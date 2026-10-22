options gen2
// the pipeline parses clang's JSON dump below its own frames: a deep expression tree overflows
// the default 16 KB context stack
options stack = 1048576

require strings
require daslib/strings_boost
require daslib/fio
require daslib/clargs
require ../converter/pipeline.das
require ../converter/tiers.das
require ../converter/dumper_a.das

//! The Lua harness: `lua/fetch.sh`'s release composed into one C file per program,
//! `lua/work/lua_all.c` (the interpreter) and `lua/work/luac_all.c` (the compiler), each
//! converted with `lua/lua.c2das` through `converter/pipeline.das`, its compile check
//! included, and timed. `--native` builds the native oracle of each, `--run` runs the converted
//! interpreter under the interpreter tier against it. Run from the repository root.

let SOURCES = "lua/fetch/lua-5.4.8/src"
let WORK = "lua/work"
let SIDECAR = "lua/lua.c2das"
let NATIVE_FLAGS <- ["-O0", "-funsigned-char", "-w"]

// the sources of the Makefile's `CORE_O`, in its order, then the auxiliary library of its `LIB_O`
let CORE <- ["lapi", "lcode", "lctype", "ldebug", "ldo", "ldump", "lfunc", "lgc", "llex", "lmem", "lobject", "lopcodes", "lparser", "lstate", "lstring", "ltable", "ltm", "lundump", "lvm", "lzio", "lauxlib"]

// the rest of `LIB_O`, the standard libraries: the interpreter links them, the compiler does not
// (its `writer` would clash with `lstrlib.c`'s in one translation unit)
let STANDARD <- ["lbaselib", "lcorolib", "ldblib", "liolib", "lmathlib", "loadlib", "loslib", "lstrlib", "ltablib", "lutf8lib", "linit"]

// the program each composed file builds: its stem, the source holding its `main`, and whether it
// links the standard libraries
let PROGRAMS <- [("lua_all", "lua", true), ("luac_all", "luac", false)]

[CommandLineArgs]
struct Args {
    @clarg_doc = "also build the native oracle of each program into lua/work/<stem>_native"
    native : bool
    @clarg_doc = "also run the converted interpreter under --tier with each --arg and compare with the native oracle"
    run : bool
    @clarg_doc = "the tier --run takes: interp or jit"
    tier : string = "interp"
    @clarg_doc = "an argument the interpreter gets under --run, one per --arg, in order (default -e \"print(1+1)\")"
    arg : array<string>
    @clarg_doc = "convert only the programs whose stem contains this text"
    filter : string = ""
    @clarg_doc = "dialect: linux (this host, the native oracle's) or msvc"
    target : string = "linux"
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
}

// the headers copied beside the composed files, so the quoted includes resolve to them: a
// header under the main file's folder is part of the program the converter dumps
def private copy_headers : bool {
    var copied = true
    dir(SOURCES) $(name) {
        if (name |> ends_with(".h")) {
            copied = fwrite(path_join(WORK, name), fread(path_join(SOURCES, name))) && copied
        }
    }
    return copied
}

// `lua/work/<stem>.c`: the macros every source of the program sees, then the library's sources
// and `main_source` concatenated, each under a line naming it; the file's path
[arch(at="ARCHITECTURE.md#composition")]
def private compose(stem, main_source : string; standard : bool) : string {
    let c_path = path_join(WORK, "{stem}.c")
    let text = build_string() $(var w) {
        w |> write("/* {stem}: lua 5.4.8 as one translation unit, composed by lua/run.das */\n")
        w |> write("#define LUA_CORE\n#define LUA_LIB\n#define {main_source}_c\n")
        var sources <- clone_to_move(CORE)
        if (standard) {
            sources |> push_from(STANDARD)
        }
        sources |> push(main_source)
        for (source in sources) {
            w |> write("/* ==== {source}.c ==== */\n")
            w |> write(fread(path_join(SOURCES, "{source}.c")))
        }
    }
    return fwrite(c_path, text) ? c_path : ""
}

// the Lua source and line that line `line` of the composed file `c_path` comes from, as
// `lobject.c:267`, by the `/* ==== name.c ==== */` line above it; "" for a line above them all
def private lua_line(c_path : string; line : int) : string {
    let banner = "/* ==== "
    var source = ""
    var first = 0
    for (idx, text in count(1), split(fread(c_path), "\n")) {
        if (idx > line) {
            break
        }
        if (text |> starts_with(banner)) {
            source = slice(text, length(banner), find(text, " ====", length(banner)))
            first = idx
        }
    }
    return empty(source) ? "" : "{source}:{line - first}"
}

// `error` with the Lua source and line beside the composed file's location it names
def private located(error, c_path : string) : string {
    let at = find(error, "{base_name(c_path)}:")
    if (at < 0) {
        return error
    }
    let digits = slice(error, at + length(base_name(c_path)) + 1)
    var line = 0
    for (ch in digits) {
        break if (!is_number(ch))
        line = line * 10 + (ch - '0')
    }
    let source = lua_line(c_path, line)
    return empty(source) ? error : "{error} (lua {source})"
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

// the native oracle of `c_path` at `bin`; false with the compiler's text logged when it fails
def private build_native(c_path, bin : string) : bool {
    var args <- [default_clang()]
    args |> push_from(NATIVE_FLAGS, ["-o", bin, c_path, "-lm"])
    var output : string
    if (run_and_capture(args, output, 300.0) != 0) {
        to_log(LOG_ERROR, "lua: native build of {c_path} failed:\n{output}\n")
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

// one program composed, converted and reported; with `--native` its oracle built, with `--run`
// both run
def private build_program(stem, main_source : string; standard : bool; args : Args) : bool {
    let c_path = compose(stem, main_source, standard)
    if (empty(c_path)) {
        to_log(LOG_ERROR, "lua: cannot write {WORK}/{stem}.c\n")
        return false
    }
    let bin = path_join(WORK, "{stem}_native")
    if ((args.native || args.run) && !build_native(c_path, bin)) {
        return false
    }
    let res <- convert(c_path, path_join(WORK, stem), args.target, "", SIDECAR)
    to_log(LOG_INFO, "lua: {stem}: dumper {fmt(":.1f", res.dump_seconds)} s, JSON {res.json_bytes} bytes\n")
    if (!res.ok) {
        to_log(LOG_ERROR, "lua: {stem}: {located(res.error, c_path)}\n")
        return false
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
    if ((!mkdir_rec(WORK) && !stat(WORK).is_dir) || !copy_headers()) {
        to_log(LOG_ERROR, "lua: cannot write the headers into {WORK}\n")
        return 1
    }
    var ok = true
    for (program in PROGRAMS) {
        if (empty(args.filter) || program._0 |> contains(args.filter)) {
            ok = build_program(program._0, program._1, program._2, args) && ok
        }
    }
    return ok ? 0 : 1
}
