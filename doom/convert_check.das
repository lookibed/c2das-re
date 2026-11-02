options gen2

module convert_check public

require strings
require daslib/fio
require daslib/strings_boost
require ../converter/pipeline.das
require ../converter/tiers.das
require ../converter/cir.das
require ../converter/dumper_a.das
require ../converter/emit.das
require ../converter/sidecar.das

//! The conversion checks `run.das --convert` and `--compile-check` apply (`ARCHITECTURE.md`
//! section 7): the program staged into one folder, each unit converted alone, the program
//! converted in a layout, every module it emits compiled alone, and each failure's first line
//! classified by the construct that blocks it.

//! The target the program converts for.
let TARGET = "linux"

//! One unit's or module's verdict: `error` the first line of its refusal, "" when it passed.
struct Verdict {
    name : string
    error : string
}

//! The first line of `text` that names an error, else its first non-empty line, else "".
def first_error_line(text : string) : string {
    var first = ""
    for (line in split(text, "\n")) {
        let trimmed = strip(line)
        continue if (empty(trimmed))
        if (trimmed |> contains("error")) {
            return trimmed
        }
        if (empty(first)) {
            first = trimmed
        }
    }
    return first
}

//! The program copied into `dir` as one folder, so the dumper takes every header as the
//! program's: every file of `sources`, then `host` with its `#include` of `DOOM.h` by a path into
//! `sources` spelled bare; the C files of the program in link order, `units` then the host, empty
//! with `error` set when a copy fails.
def stage_program(sources, host, dir : string; units : array<string>; var error : string&) : array<string> {
    var c_paths : array<string>
    if (!mkdir_rec(dir) && !stat(dir).is_dir) {
        error = "cannot create {dir}"
        return <- c_paths
    }
    dir(sources) $(name) {
        let path = path_join(sources, name)
        if (stat(path).is_reg && !fwrite(path_join(dir, name), fread(path))) {
            error = "cannot copy {path} into {dir}"
        }
    }
    let host_text = fread(host)
    let host_copy = path_join(dir, base_name(host))
    let lines <- [for (line in split(host_text, "\n")); line |> starts_with("#include \"") && line |> ends_with("/DOOM.h\"") ? "#include \"DOOM.h\"" : line]
    if (empty(host_text) || !fwrite(host_copy, join(lines, "\n"))) {
        error = "cannot copy {host} into {dir}"
    }
    if (empty(error)) {
        c_paths <- [for (unit in units); get_full_file_name(path_join(dir, "{unit}.c"))]
        c_paths |> push(get_full_file_name(host_copy))
    }
    return <- c_paths
}

// whether `tu` declares a record of the tag or typedef `name`
def private declares(tu : CirTu; name : string) : bool {
    for (d in tu.decls) {
        if ((d.k == "record" && tu.types[d.t].name == name) || (d.k == "typedefdecl" && d.name == name)) {
            return true
        }
    }
    return false
}

//! The prefix of a unit's emitter error naming a function another unit defines: alone the unit
//! has no binding for it, which the program's link gives.
let LINK_BOUND = "link-bound: "

// the function `error` names as `external function `<name>``, "" when it names none
def private external_function(error : string) : string {
    let at = find(error, "external function `")
    if (at < 0) {
        return ""
    }
    let rest = slice(error, at + length("external function `"))
    let close = find(rest, "`")
    return close < 0 ? "" : slice(rest, 0, close)
}

//! Each of `c_paths` dumped alone under the sidecar `side`, then each the dumper takes emitted
//! alone, its `over_indexed` entries narrowed to the records the unit declares: the unit passes
//! when the dumper and the emitter take it. An emitter error naming a function another unit
//! defines is marked `LINK_BOUND`. Nothing is written and nothing compiled, since the rest of the
//! program is missing.
def convert_units(c_paths : array<string>; side : Sidecar) : array<Verdict> {
    var verdicts : array<Verdict>
    var tus : array<CirTu>
    var defined : table<string>
    verdicts |> reserve(length(c_paths))
    tus |> reserve(length(c_paths))
    for (c_path in c_paths) {
        var d <- dump_tu(c_path, target_by_name(TARGET), default_clang(), dump_inputs(side))
        verdicts |> push(Verdict(name = file_stem(c_path), error = empty(d.error) ? "" : first_error_line("dumper: {d.error}")))
        for (decl in d.tu.decls) {
            if (decl.k == "func" && decl.body != null) {
                defined |> insert(decl.name)
            }
        }
        tus |> emplace(d.tu)
    }
    for (v, tu in verdicts, tus) {
        if (empty(v.error)) {
            var unit_side := side
            unit_side.over_indexed <- [for (entry in side.over_indexed); entry; where declares(tu, slice(entry, 0, find(entry, ".")))]
            let em <- emit_tu(tu, unit_side)
            if (!empty(em.error)) {
                let error = first_error_line("emitter: {em.error}")
                v.error = key_exists(defined, external_function(error)) ? LINK_BOUND + error : error
            }
        }
        delete_tu(tu)
    }
    return <- verdicts
}

//! Every module `out_dir`'s module list names (its fragments left out) compiled alone by
//! `daslang -compile-only` with the converted program's module folders (`module_dirs`), each a
//! verdict with the compiler's first error line.
def compile_modules(out_dir : string; module_dirs : array<string>; timeout : float) : array<Verdict> {
    var verdicts : array<Verdict>
    let list = path_join(out_dir, MODULE_LIST)
    if (!fexist(list)) {
        return <- verdicts
    }
    for (rel in split(fread(list), "\n")) {
        continue if (empty(rel) || !(rel |> ends_with(".das")))
        var inscope argv <- daslang_cmd(module_dirs)
        argv |> push_from(["-compile-only", get_full_file_name(path_join(out_dir, rel))])
        var output : string
        let rc = run_and_capture(argv, output, timeout)
        verdicts |> push(Verdict(name = rel, error = rc == 0 ? "" : (empty(output) ? "exit {rc}" : first_error_line(output))))
    }
    return <- verdicts
}

//! The constructs a refusal or a compile failure is classified by: a fragment of its first line
//! and the construct's name, the first match winning; the numbered findings are P6.1's
//! (`ARCHITECTURE.md` section 7).
let BLOCKERS <- [
    (LINK_BOUND, "a function another unit defines, which only the link binds (the unit alone)"),
    ("before a definition gives its array a length", "an `extern T a[];` referenced before the definition giving its length"),
    ("block-scope `extern` declaration", "a block-scope `extern` with no file-scope declaration before it"),
    ("unsupported local declaration `FunctionDecl`", "a block-scope function prototype"),
    ("of a marshal-only record is a record or an array of records", "a record or an array of records in a marshal record (finding 2)"),
    ("an array of the marshal-only record", "an array of a marshal record, `maptexture_t.patches` (finding 2)"),
    ("sidecar `over_indexed`", "an over-indexed trailing array in a marshal record (finding 3)")
]

//! `error` without its stage and its source locations: each `: `-separated part naming a `.c`,
//! `.h` or `.das` line dropped.
def unlocated(error : string) : string {
    var parts <- [for (part in split(error, ": ")); part; where !(part |> contains(".c:") || part |> contains(".h:") || part |> contains(".das:"))]
    if (!empty(parts) && (parts[0] == "dumper" || parts[0] == "emitter")) {
        parts |> erase(0)
    }
    return join(parts, ": ")
}

//! The construct `error` is blocked by, `new: <error unlocated>` when no fragment matches.
def classify(error : string) : string {
    for (blocker in BLOCKERS) {
        if (error |> contains(blocker._0)) {
            return blocker._1
        }
    }
    return "new: {unlocated(error)}"
}

//! The classification table: per construct, `<count>  <construct>  (<names>)`, the largest first,
//! the passed verdicts left out.
def blocker_table(verdicts : array<Verdict>) : array<string> {
    var names : table<string; array<string>>
    for (v in verdicts) {
        if (!empty(v.error)) {
            names[classify(v.error)] |> push(v.name)
        }
    }
    var rows <- [for (construct, blocked in keys(names), values(names)); Verdict(name = "{length(blocked)}", error = "{length(blocked)}  {construct}  ({join(blocked, " ")})")]
    sort(rows) $(a, b) => to_int(a.name) > to_int(b.name) || (a.name == b.name && a.error < b.error)
    return <- [for (row in rows); row.error]
}
