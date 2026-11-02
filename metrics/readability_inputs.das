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
require ../converter/sidecar.das
require ../lua/sources.das
require readability_file

//! One input key converted the way the readability metric and the criteria measure it
//! (`metrics/ARCHITECTURE.md` section 2): the C files it came from and the das files emitted.

//! A converted input: `error` when it did not generate or convert, else the C files in link
//! order, the sidecar they converted under ("" for none), the emitted modules (`.das`) and the
//! cluster fragments (`.das.inc`), each by its path.
struct ConvertedInput {
    error : string
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
//! `lua/<program>[@source-cut|@single]` key names.
def lua_key_parts(key : string; var layout : string&) : string {
    let id = slice(key, length("lua/"))
    for (suffix in [SINGLE_KEY_SUFFIX, CUT_KEY_SUFFIX]) {
        if (id |> ends_with(suffix)) {
            layout = slice(suffix, 1)
            return slice(id, 0, length(id) - length(suffix))
        }
    }
    layout = "source"
    return id
}

//! Input `key` converted into `<dir>/das/` under the `linux` dialect: a `perf/<kernel>@copy` key
//! under `--param-writes copy`, a `perf/<kernel>@while` key under `--loops while`, a
//! `perf/<kernel>@reinterpret` key under `--first-member reinterpret`, a Lua key from
//! the release's files in the layout it names.
def convert_input(key, dir : string) : ConvertedInput {
    var out : ConvertedInput
    let das_dir = path_join(dir, "das")
    if (group_of(key) == "lua") {
        var layout : string
        let stem = lua_key_parts(key, layout)
        out.c_paths <- program_sources(stem)
        out.sidecar = SIDECAR
        let res <- convert_program(out.c_paths, das_dir, "linux", "", SIDECAR, "", "", "main", layout)
        if (!res.ok) {
            out.error = "convert: {headline(res.error)}"
        } elif (layout == "single") {
            out.das_paths |> push(res.das_path)
        } else {
            for (f in res.files) {
                if (f |> ends_with(".das")) {
                    out.das_paths |> push(path_join(das_dir, f))
                } elif (f |> ends_with(".das.inc")) {
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
    out.sidecar = find_sidecar(c_path, "")
    let res <- convert(c_path, das_dir, "linux", "", "", key |> ends_with(COPY_KEY_SUFFIX) ? "copy" : "", key |> ends_with(WHILE_KEY_SUFFIX) ? "while" : "", key |> ends_with(REINTERPRET_KEY_SUFFIX) ? "reinterpret" : "")
    if (!res.ok) {
        out.error = "convert: {headline(res.error)}"
    } else {
        out.das_paths |> push(res.das_path)
    }
    return <- out
}
