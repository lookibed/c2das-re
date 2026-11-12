options gen2
options stack = 1048576

module readability_inputs public

require strings
require daslib/strings_boost
require daslib/fio
require ../suites/suite_runner.das
require ../suites/csmith/generate.das
require ../perf/perf_compose.das
require ../converter/pipeline.das
require ../converter/tiers.das
require ../converter/sidecar.das
require ../lua/sources.das
require ../compare/projects.das
require ../compare/rust_translator.das
require readability_file
require criteria_file

//! One input key converted the way the readability metric and the criteria measure it
//! (`metrics/ARCHITECTURE.md` section 2): the C files it came from and the das files emitted.

//! A converted input: `error` when it did not generate or convert, else the C files in link
//! order, the sidecar they converted under ("" for none), the emitted modules (`.das`) and the
//! cluster fragments (`.das.inc`), each by its path; `c_files` counts the C files of the program,
//! more than `c_paths` holds when a project converts only file by file and some files refuse.
struct ConvertedInput {
    error : string
    c_files : int
    c_paths : array<string>
    sidecar : string
    das_paths : array<string>
    fragments : array<string>
}

//! An error's first line, and when that line only names the stage (`dumper: clang exited 1:`)
//! the first non-empty line after it.
def headline(error : string) : string {
    let lines <- [for (l in split(error, "\n")); strip(l); where !empty(strip(l))]
    if (empty(lines)) {
        return error
    }
    return lines[0] |> ends_with(":") && length(lines) > 1 ? "{lines[0]} {lines[1]}" : lines[0]
}

// the C file of a non-Lua input, written under `dir` when it is generated or composed
def private c_file_of(key, dir : string; var error : string&) : string {
    let group = group_of(key)
    let id = slice(key, length(group) + 1)
    if (group == "c_testsuite") {
        return "{C_TESTSUITE_TESTS}/{id}.c"
    } elif (group == "gcc_torture") {
        return "{GCC_TORTURE_TESTS}/{id}.c"
    } elif (group == "perf") {
        return write_composed(kernel_of_key(id), dir)
    }
    let prog = csmith_program(id, dir, CSMITH_TIMEOUT)
    error = prog.timed_out ? "csmith took longer than {int(CSMITH_TIMEOUT)} s" : prog.error
    return prog.c_path
}

//! The Lua program stem and layout (`source`, `source-cut` or `single`) a
//! `lua/<program>[@source-cut|@single|@inline|@goto|@checks-off|@past-end-inline|@fn-macros-expand]` key names (each
//! opt-in's suffix the source layout).
def lua_key_parts(key : string; var layout : string&) : string {
    let id = slice(key, length("lua/"))
    for (suffix in LUA_OPT_IN_SUFFIXES) {
        if (id |> ends_with(suffix)) {
            layout = "source"
            return slice(id, 0, length(id) - length(suffix))
        }
    }
    for (suffix in [SINGLE_KEY_SUFFIX, CUT_KEY_SUFFIX]) {
        if (id |> ends_with(suffix)) {
            layout = slice(suffix, 1)
            return slice(id, 0, length(id) - length(suffix))
        }
    }
    layout = "source"
    return id
}

// the compare project `name` of the Rust checkout converted into `dir` by `convert_project`, as the
// ports publisher converts it: the whole program's C files and modules, else the files that
// convert alone with their modules
def private convert_project_input(name, dir : string) : ConvertedInput {
    var out : ConvertedInput
    var p : Project
    if (!find_project(rust_checkout(), name, p)) {
        out.error = "no compare project {name}"
        return <- out
    }
    if (!stat(p.dir).is_dir) {
        out.error = "the Rust checkout has no {p.dir}"
        return <- out
    }
    out.error = load_expected(p)
    if (!empty(out.error)) {
        return <- out
    }
    var inscope conv <- convert_project(p, dir)
    out.sidecar = path_join(dir, "whole/{p.name}.c2das")
    let sources <- program_files(p)
    out.c_files = length(sources)
    if (empty(conv.refusal)) {
        out.c_paths <- [for (s in sources); project_path(p, s)]
        for (f in conv.files) {
            if (f |> ends_with(".das")) {
                out.das_paths |> push(f)
            } elif (f |> ends_with(".das.inc") && !is_layout_file(f)) {
                out.fragments |> push(f)
            }
        }
        return <- out
    }
    for (f in conv.per_file) {
        if (!empty(f.das_path)) {
            out.c_paths |> push(project_path(p, f.c_path))
            out.das_paths |> push(f.das_path)
        }
    }
    if (empty(out.das_paths)) {
        out.error = "convert: no file of {p.name} converts: {conv.refusal}"
    }
    return <- out
}

//! The command of the worker `script` measuring the input `key`: a project's raises its soft address-space limit to the
//! hard one, since converting doomgeneric or quakegeneric file by file in one process takes more
//! than the 3 GB a Lua input does; a run capped `prlimit --as=<soft>:<hard>` keeps the rest at soft.
def worker_argv(script, key : string) : array<string> {
    var argv <- key |> starts_with(PROJECT_PREFIX) ? ["bash", "-c", "ulimit -S -v \"$(ulimit -H -v)\" && exec \"$@\"", "worker"] : array<string>()
    argv |> push_from(daslang_cmd(CONVERTED_MODULES), [script, "--", "--one", key])
    return <- argv
}

//! The `--checks` value input `key` names: `off` for a key ending `@checks-off`, else the default.
def checks_of(key : string) : string => key |> ends_with(CHECKS_OFF_KEY_SUFFIX) ? "off" : ""

//! The `--past-end` value input `key` names: `inline` for a key ending `@past-end-inline`, else the
//! default.
def past_end_of(key : string) : string => key |> ends_with(PAST_END_KEY_SUFFIX) ? "inline" : ""

//! The `--fn-macros` value input `key` names: `expand` for a key ending `@fn-macros-expand`, else
//! the default.
def fn_macros_of(key : string) : string => key |> ends_with(FN_MACROS_EXPAND_KEY_SUFFIX) ? "expand" : ""

//! Input `key` converted into `<dir>/das/` under the `linux` dialect: a `perf/<kernel>@copy` key
//! under `--param-writes copy`, a `perf/<kernel>@while` key under `--loops while`, a
//! `perf/<kernel>@reinterpret` key under `--first-member reinterpret`, a Lua key from
//! the release's files in the layout it names; a key ending `@inline` under `--inline-helpers`, one
//! ending `@goto` under `--switch-dispatch goto`, `@checks-off` under `--checks off`,
//! `@past-end-inline` under `--past-end inline`, `@fn-macros-expand` under `--fn-macros expand`; a
//! `project/<name>` key by `convert_project` into `<dir>/` as the ports publisher converts it.
def convert_input(key, dir : string) : ConvertedInput {
    if (key |> starts_with(PROJECT_PREFIX)) {
        return <- convert_project_input(slice(key, length(PROJECT_PREFIX)), dir)
    }
    var out : ConvertedInput
    let das_dir = path_join(dir, "das")
    if (group_of(key) == "lua") {
        var layout : string
        let stem = lua_key_parts(key, layout)
        out.c_paths <- program_sources(stem)
        out.c_files = length(out.c_paths)
        out.sidecar = SIDECAR
        let res <- convert_program(out.c_paths, das_dir, "linux", "", SIDECAR, "", "", "main", layout, false, "", key |> ends_with(GOTO_KEY_SUFFIX) ? "goto" : "", false, checks_of(key), past_end_of(key), key |> ends_with(INLINE_KEY_SUFFIX), fn_macros_of(key))
        if (!res.ok) {
            out.error = "convert: {headline(res.error)}"
        } elif (layout == "single") {
            out.das_paths |> push(res.das_path)
        } else {
            for (f in res.files) {
                if (f |> ends_with(".das")) {
                    out.das_paths |> push(path_join(das_dir, f))
                } elif (f |> ends_with(".das.inc") && !is_layout_file(f)) {
                    out.fragments |> push(path_join(das_dir, f))
                }
            }
        }
        return <- out
    }
    var error : string
    let c_path = c_file_of(key, dir, error)
    if (!empty(error)) {
        out.error = error
        return <- out
    }
    out.c_paths |> push(c_path)
    out.c_files = 1
    out.sidecar = find_sidecar(c_path, "")
    let res <- convert(c_path, das_dir, "linux", "", "", key |> ends_with(COPY_KEY_SUFFIX) ? "copy" : "", key |> ends_with(WHILE_KEY_SUFFIX) ? "while" : "", key |> ends_with(REINTERPRET_KEY_SUFFIX) ? "reinterpret" : "", key |> ends_with(GOTO_KEY_SUFFIX) ? "goto" : "", false, checks_of(key), past_end_of(key), key |> ends_with(INLINE_KEY_SUFFIX), fn_macros_of(key))
    if (!res.ok) {
        out.error = "convert: {headline(res.error)}"
    } else {
        out.das_paths |> push(res.das_path)
    }
    return <- out
}
