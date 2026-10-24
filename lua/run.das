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
require ../converter/tiers.das
require ../converter/dumper_a.das

//! The Lua harness: `lua/fetch.sh`'s release converted as its Makefile builds it, the interpreter
//! `lua` and the compiler `luac`, each from its separate C files through a program manifest
//! `lua/work/<stem>.program.json` and `converter/pipeline.das`'s `convert_program` with
//! `lua/lua.c2das`, its compile check included, and timed. `--native` builds the native oracle of
//! each, `--run` runs the converted interpreter under the interpreter tier against it. Run from the
//! repository root.

let SOURCES = "lua/fetch/lua-5.4.8/src"
let WORK = "lua/work"
let SIDECAR = "lua/lua.c2das"
let NATIVE_FLAGS <- ["-O0", "-funsigned-char", "-w"]

// the sources of the Makefile's `CORE_O`, in its order, then the auxiliary library of its `LIB_O`
let CORE <- ["lapi", "lcode", "lctype", "ldebug", "ldo", "ldump", "lfunc", "lgc", "llex", "lmem", "lobject", "lopcodes", "lparser", "lstate", "lstring", "ltable", "ltm", "lundump", "lvm", "lzio", "lauxlib"]

// the rest of `LIB_O`, the standard libraries: the interpreter links them; the compiler, which
// calls none of them, does not, as the Makefile's archive link pulls none into it
let STANDARD <- ["lbaselib", "lcorolib", "ldblib", "liolib", "lmathlib", "loadlib", "loslib", "lstrlib", "ltablib", "lutf8lib", "linit"]

// the program each manifest builds: its stem, the source holding its `main`, and whether it links
// the standard libraries
let PROGRAMS <- [("lua", "lua", true), ("luac", "luac", false)]

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
    @clarg_doc = "dialect: linux (this host, the native oracle's) or msvc"
    target : string = "linux"
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
}

// `lua/work/<stem>.program.json`: the program's sources in link order, the core, the standard
// libraries when it links them, then `main_source`, each by its full path; the manifest's path, ""
// when it cannot be written
[arch(at="ARCHITECTURE.md#program")]
def private write_manifest(stem, main_source : string; standard : bool) : string {
    var sources <- clone_to_move(CORE)
    if (standard) {
        sources |> push_from(STANDARD)
    }
    sources |> push(main_source)
    let path = path_join(WORK, "{stem}.program.json")
    let tus = join([for (source in sources); write_json(JV(get_full_file_name(path_join(SOURCES, "{source}.c"))))], ", ")
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

// one program's manifest written, the program converted and reported; with `--native` its
// oracle built, with `--run` both run
def private build_program(stem, main_source : string; standard : bool; args : Args) : bool {
    let manifest = write_manifest(stem, main_source, standard)
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
    if ((args.native || args.run) && !build_native(input.c_paths, bin)) {
        return false
    }
    let res <- convert_program(input.c_paths, path_join(WORK, stem), args.target, "", SIDECAR, "", "", input.entry)
    to_log(LOG_INFO, "lua: {stem}: {length(input.c_paths)} files, dumper {fmt(":.1f", res.dump_seconds)} s, JSON {res.json_bytes} bytes\n")
    if (!res.ok) {
        to_log(LOG_ERROR, "lua: {stem}: {res.error}\n")
        return false
    }
    to_log(LOG_INFO, "lua: {stem}: link {fmt(":.1f", res.link_seconds)} s, {length(res.bound)} declarations bound to another file's definition, {length(res.renamed)} statics renamed, {length(res.deduplicated)} header functions kept once\n")
    for (line in res.renamed) {
        to_log(LOG_INFO, "lua: {stem}: renamed {line}\n")
    }
    to_log(LOG_INFO, "lua: {stem}: emitter {fmt(":.1f", res.emit_seconds)} s, compile check {fmt(":.1f", res.check_seconds)} s, {line_count(res.das_text)} lines of das, [c_function] on {res.c_functions} of {res.function_count} functions\n")
    if (!args.run || main_source != "lua") {
        return true
    }
    var program_args <- ["-e", "print(1+1)"]
    if (!empty(args.arg)) {
        program_args := args.arg
    }
    return run_both(res.das_path, bin, args.tier, program_args)
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
            ok = build_program(program._0, program._1, program._2, args) && ok
        }
    }
    return ok ? 0 : 1
}
