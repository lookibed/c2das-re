options gen2
// the pipeline parses clang's JSON dump below its own frames: a deep expression tree overflows
// the default 16 KB context stack
options stack = 1048576

require strings
require daslib/strings_boost
require daslib/fio
require daslib/clargs
require daslib/json_boost
require ../converter/pipeline.das
require ../converter/cir.das
require ../converter/tiers.das
require ../converter/dumper_a.das
require ../converter/sidecar.das
require sources

//! The Lua harness: `lua/fetch.sh`'s release converted as its Makefile builds it, the interpreter
//! `lua` and the compiler `luac`, each from its separate C files through a program manifest
//! `lua/work/<stem>.program.json` and `converter/pipeline.das`'s `convert_program` with
//! `lua/lua.c2das`, its compile check included, and timed, in the source layout into
//! `lua/work/<stem>/`, in the scc layout into `lua/work/scc/<stem>/` and in the single layout into
//! `lua/work/single/<stem>/`. `--native` builds the
//! native oracle of each, `--run` runs the converted interpreter against it, `--luac-check` the
//! converted compiler's `-o` over a folder of scripts. Run from the repository root.

let WORK = "lua/work"
let NATIVE_FLAGS <- ["-O0", "-funsigned-char", "-w"]



[CommandLineArgs]
struct Args {
    @clarg_doc = "also build the native oracle of each program from its sources into lua/work/<stem>_native"
    native : bool
    @clarg_doc = "also run the converted interpreter under --tier with each --arg and compare with the native oracle"
    run : bool
    @clarg_doc = "the tier --run takes: interp or jit"
    tier : string = "interp"
    @clarg_doc = "an argument the interpreter gets under --run, one per --arg, in order (default -e \"print(1+1)\")"
    arg : array<string>
    @clarg_doc = "convert only the program of this stem: lua or luac"
    filter : string = ""
    @clarg_doc = "the layouts to convert: source (a module per C file, the cycles cut, into lua/work/<stem>/), scc (every cycle one module, into lua/work/scc/<stem>/), single (one module, into lua/work/single/<stem>/) or all, the default"
    layout : string = "all"
    @clarg_name = "luac-check"
    @clarg_doc = "a folder of Lua scripts: the converted luac compiles each with -o under --tier, and its bytes must be the native luac's"
    luac_check : string = ""
    @clarg_doc = "dialect: linux (this host, the native oracle's) or msvc"
    target : string = "linux"
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
}

// `lua/work/<stem>.program.json`: the program's sources in link order (`program_sources`), each by
// its full path; the manifest's path, "" when it cannot be written
[arch(at="ARCHITECTURE.md#program")]
def private write_manifest(stem : string) : string {
    let path = path_join(WORK, "{stem}.program.json")
    let tus = join([for (c_path in program_sources(stem)); write_json(JV(c_path))], ", ")
    return fwrite(path, "\{\n \"tus\": [{tus}],\n \"entry\": \"main\"\n\}\n") ? path : ""
}

def private line_count(text : string) : int {
    var lines = 0
    for (ch in text) {
        if (ch == '\n') {
            lines++
        }
    }
    return lines
}

// the native oracle of the program's `c_paths` at `bin`; false with the compiler's text logged
// when it fails
def private build_native(c_paths : array<string>; bin : string) : bool {
    var args <- [default_clang()]
    args |> push_from(NATIVE_FLAGS, ["-o", bin], c_paths, ["-lm"])
    var output : string
    if (run_and_capture(args, output, 300.0) != 0) {
        to_log(LOG_ERROR, "lua: native build of {bin} failed:\n{output}\n")
        return false
    }
    to_log(LOG_INFO, "lua: {bin}: {int64(stat(bin).size)} bytes\n")
    return true
}

// the converted interpreter at `das_path` under `tier` and the native one at `bin`, each run with
// `program_args`: true when the exit codes and the outputs agree
def private run_both(das_path, bin, tier : string; program_args : array<string>) : bool {
    var native_args <- [bin]
    native_args |> push_from(program_args)
    var native_out : string
    let native_rc = run_and_capture(native_args, native_out, 60.0)
    var das_out : string
    let no_flags : array<string>
    let das_rc = run_tier(das_path, tier, WORK, das_out, CONVERTED_MODULES, 600.0, no_flags, program_args)
    // the JIT reports its compilation on `info` lines among the program's output
    das_out = join([for (ln in split(das_out, "\n")); ln; where !(ln |> starts_with("[I] "))], "\n")
    to_log(LOG_INFO, "lua: native exited {native_rc}: {native_out}\n")
    to_log(LOG_INFO, "lua: {tier} exited {das_rc}: {das_out}\n")
    return native_rc == das_rc && native_out == das_out
}

// the bytes of the file at `path`, none when it cannot be read; a das string would stop at the
// first zero byte, which bytecode holds
def private file_bytes(path : string) : array<uint8> {
    var bytes : array<uint8>
    fopen(path, "rb") $(f) {
        if (f != null) {
            fload(f, int64(stat(path).size)) $(data) {
                bytes := data
            }
        }
    }
    return <- bytes
}

// whether the files at `a` and `b` hold the same bytes
def private same_bytes(a, b : string) : bool {
    let left <- file_bytes(a)
    let right <- file_bytes(b)
    if (length(left) != length(right)) {
        return false
    }
    for (x, y in left, right) {
        if (x != y) {
            return false
        }
    }
    return true
}

// every `.lua` file of `dir` compiled by the native compiler `bin` and by the converted one at
// `das_path` under `tier`, each with `-o` into its own file under `out_dir`: true when every pair of
// exit codes agrees and every pair of outputs is byte for byte the same
def private luac_check(das_path, bin, tier, dir, out_dir : string) : bool {
    var scripts : array<string>
    dir(dir) $(name) {
        if (name |> ends_with(".lua")) {
            scripts |> push(path_join(dir, name))
        }
    }
    if (empty(scripts)) {
        to_log(LOG_ERROR, "lua: luac -o: no .lua file in {dir}\n")
        return false
    }
    sort(scripts)
    mkdir_rec(out_dir)
    var same = 0
    for (script in scripts) {
        let stem = file_stem(script)
        let native_out = path_join(out_dir, "{stem}.native.luac")
        let das_out = path_join(out_dir, "{stem}.{tier}.luac")
        var native_text, das_text : string
        let native_rc = run_and_capture([bin, "-o", native_out, script], native_text, 60.0)
        var inscope no_flags : array<string>
        let das_rc = run_tier(das_path, tier, WORK, das_text, CONVERTED_MODULES, 600.0, no_flags, ["-o", das_out, script])
        let agree = native_rc == das_rc && fexist(native_out) && same_bytes(native_out, das_out)
        if (agree) {
            same++
        } else {
            to_log(LOG_ERROR, "lua: luac -o {base_name(script)}: native exited {native_rc}, {tier} {das_rc}; the bytes differ\n")
        }
    }
    to_log(LOG_INFO, "lua: luac -o under {tier}: {same} of {length(scripts)} files byte for byte the native compiler's\n")
    return same == length(scripts)
}

// the folder a program's conversion in `layout` lands in: `lua/work/<stem>/` for the source layout,
// `lua/work/<layout>/<stem>/` for the scc and the single ones
def private layout_dir(stem, layout : string) : string =>
    layout == "source" ? path_join(WORK, stem) : path_join(path_join(WORK, layout), stem)

// the layouts `--layout` names
def private layouts_of(args : Args) : array<string> => <- args.layout == "all" ? ["source", "scc", "single"] : [args.layout]

// the lines of every das file a conversion wrote, a fragment's included
def private das_lines(res : ConvertResult; dir : string) : int {
    if (empty(res.files)) {
        return line_count(res.das_text)
    }
    var lines = 0
    for (f in res.files) {
        lines += line_count(fread(path_join(dir, f)))
    }
    return lines
}

// one program converted in `layout` and reported; with `--run` the interpreter run against the
// native oracle `bin`, with `--luac-check` the compiler over the folder it names
def private convert_layout(stem, main_source : string; input : ProgramInput; bin, layout : string; args : Args) : bool {
    let dir = layout_dir(stem, layout)
    let res <- convert_program(input.c_paths, dir, args.target, "", SIDECAR, "", "", input.entry, layout)
    let head = "lua: {stem} ({layout})"
    to_log(LOG_INFO, "{head}: {length(input.c_paths)} files, dumper {fmt(":.1f", res.dump_seconds)} s, JSON {res.json_bytes} bytes\n")
    if (!res.ok) {
        to_log(LOG_ERROR, "{head}: {res.error}\n")
        return false
    }
    to_log(LOG_INFO, "{head}: link {fmt(":.1f", res.link_seconds)} s, {length(res.bound)} declarations bound to another file's definition, {length(res.renamed)} statics renamed, {length(res.deduplicated)} header functions kept once\n")
    for (line in res.renamed) {
        to_log(LOG_INFO, "{head}: renamed {line}\n")
    }
    if (!empty(res.files)) {
        let fragments = length([for (f in res.files); f; where f |> ends_with(".das.inc")])
        to_log(LOG_INFO, "{head}: {length(res.files) - fragments} modules, {fragments} fragments\n")
        // the modules belong to the conversion's report; the edges that tie each cluster are
        // logged apart, outside the lines the ports README quotes
        for (line in res.partition) {
            to_log(LOG_INFO, line |> contains(" -> ") ? "partition {stem} ({layout}): {line}\n" : "{head}: module {line}\n")
        }
    }
    to_log(LOG_INFO, "{head}: emitter {fmt(":.1f", res.emit_seconds)} s, compile check {fmt(":.1f", res.check_seconds)} s, {das_lines(res, dir)} lines of das, [c_function] on {res.c_functions} of {res.function_count} functions\n")
    if (args.run && main_source == "lua") {
        var program_args <- ["-e", "print(1+1)"]
        if (!empty(args.arg)) {
            program_args := args.arg
        }
        return run_both(res.das_path, bin, args.tier, program_args)
    }
    if (!empty(args.luac_check) && main_source == "luac") {
        return luac_check(res.das_path, bin, args.tier, args.luac_check, path_join(dir, "luac_check"))
    }
    return true
}

// one program's manifest written, the program converted in each layout `--layout` names and
// reported; with `--native`, `--run` or `--luac-check` its oracle built first
def private build_program(stem, main_source : string; args : Args) : bool {
    let manifest = write_manifest(stem)
    if (empty(manifest)) {
        to_log(LOG_ERROR, "lua: cannot write {WORK}/{stem}.program.json\n")
        return false
    }
    var error : string
    let input <- read_program_input(manifest, args.target, error)
    if (!empty(error)) {
        to_log(LOG_ERROR, "lua: {stem}: {error}\n")
        return false
    }
    let bin = path_join(WORK, "{stem}_native")
    if ((args.native || args.run || !empty(args.luac_check)) && !build_native(input.c_paths, bin)) {
        return false
    }
    var ok = true
    for (layout in layouts_of(args)) {
        ok = convert_layout(stem, main_source, input, bin, layout, args) && ok
    }
    return ok
}

[export]
def main : int {
    var args = Args()
    let early = cli_prologue(args, "lua/run.das")
    if (early >= 0) {
        return early
    }
    if (args.tier != "interp" && args.tier != "jit") {
        to_log(LOG_ERROR, "lua: --tier is interp or jit, not `{args.tier}`\n")
        return 1
    }
    if (args.layout != "all" && !is_layout(args.layout)) {
        to_log(LOG_ERROR, "lua: --layout is source, scc, single or all, not `{args.layout}`\n")
        return 1
    }
    if (!stat(SOURCES).is_dir) {
        to_log(LOG_ERROR, "lua: no {SOURCES}; run lua/fetch.sh first\n")
        return 1
    }
    if (!mkdir_rec(WORK) && !stat(WORK).is_dir) {
        to_log(LOG_ERROR, "lua: cannot create {WORK}\n")
        return 1
    }
    var ok = true
    for (program in PROGRAMS) {
        if (empty(args.filter) || program._0 == args.filter) {
            ok = build_program(program._0, program._1, args) && ok
        }
    }
    return ok ? 0 : 1
}
