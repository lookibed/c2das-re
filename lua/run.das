options gen2
// the pipeline parses clang's JSON dump below its own frames: a deep expression tree overflows
// the default 16 KB context stack
options stack = 1048576

require strings
require math
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
//! native oracle of each, `--run` runs the converted interpreter against it, `--error-check` the
//! interpreter's error-recovery checks against it, `--luac-check` the
//! converted compiler's `-o` over a folder of scripts, `--suite-check` the release's test suite file
//! by file against it. Run from the repository root.

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
    @clarg_name = "error-check"
    @clarg_doc = "also run the converted interpreter under --tier with each of Lua's error-recovery checks and compare each with the native oracle"
    error_check : bool
    @clarg_doc = "convert only the program of this stem: lua or luac"
    filter : string = ""
    @clarg_doc = "the layouts to convert: source (a module per C file, the cycles cut, into lua/work/<stem>/), scc (every cycle one module, into lua/work/scc/<stem>/), single (one module, into lua/work/single/<stem>/) or all, the default"
    layout : string = "all"
    @clarg_name = "luac-check"
    @clarg_doc = "a folder of Lua scripts: the converted luac compiles each with -o under --tier, and its bytes must be the native luac's"
    luac_check : string = ""
    @clarg_name = "suite-check"
    @clarg_doc = "also run each file of the release's test suite with the converted interpreter under --tier and with the native oracle, each capped, and write the verdicts to lua/work/<layout>/suite.txt"
    suite_check : bool
    @clarg_name = "suite-filter"
    @clarg_doc = "run only this file of the test suite under --suite-check"
    suite_filter : string = ""
    @clarg_name = "suite-timeout"
    @clarg_doc = "the seconds each run of a test file gets under --suite-check"
    suite_timeout : float = 1800.0
    @clarg_name = "suite-memory"
    @clarg_doc = "the memory each run of a test file gets under --suite-check, as systemd's MemoryMax takes it"
    suite_memory : string = "4G"
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

// the JIT reports its compilation on `info` lines among the program's output: `output` without them
def private program_output(output : string) : string =>
    join([for (ln in split(output, "\n")); ln; where !(ln |> starts_with("[I] "))], "\n")

// the converted interpreter at `das_path` under `tier` and the native one at `bin`, each run with
// `program_args`: true when the exit codes and the outputs agree. The native one runs under the
// name `stem`, the `argv[0]` the converted program gets, which Lua's messages quote
def private run_both(das_path, bin, stem, tier : string; program_args : array<string>) : bool {
    var native_args <- ["bash", "-c", "exec -a \"$0\" \"$@\"", stem, bin]
    native_args |> push_from(program_args)
    var native_out : string
    let native_rc = run_and_capture(native_args, native_out, 60.0)
    var das_out : string
    let no_flags : array<string>
    let das_rc = run_tier(das_path, tier, WORK, das_out, CONVERTED_MODULES, 600.0, no_flags, program_args)
    das_out = program_output(das_out)
    to_log(LOG_INFO, "lua: native exited {native_rc}: {native_out}\n")
    to_log(LOG_INFO, "lua: {tier} exited {das_rc}: {das_out}\n")
    return native_rc == das_rc && native_out == das_out
}

// the interpreter's arguments of each error-recovery check: an error caught by `pcall`, one
// uncaught (exit 1, the message on stderr), nested protected calls, an error the VM raises, an
// error object that is a table, an error inside a coroutine, `xpcall`'s handler and a memory error
let ERROR_CHECKS <- [
    ["-e", "print(pcall(error, 'boom'))"],
    ["-e", "error('x')"],
    ["-e", "print(pcall(function() print(pcall(error, 'in')); error('out') end))"],
    ["-e", "print(pcall(function() return 1 + \{\} end))"],
    ["-e", "print(select(2, pcall(error, \{code = 7\})).code)"],
    ["-e", "print(coroutine.resume(coroutine.create(function() error('c') end)))"],
    ["-e", "print(xpcall(function() error('h') end, function(m) return 'handled: ' .. m end))"],
    ["-e", "print(pcall(string.rep, 'x', 1 << 40))"]
]

// every check of `ERROR_CHECKS` run by the converted interpreter at `das_path` under `tier` and by
// the native one at `bin` named `stem`: true when each agrees
def private error_check(das_path, bin, stem, tier : string) : bool {
    var agree = 0
    for (check in ERROR_CHECKS) {
        if (run_both(das_path, bin, stem, tier, check)) {
            agree++
        } else {
            to_log(LOG_ERROR, "lua: error check `{join(check, " ")}` under {tier} differs from the native build\n")
        }
    }
    to_log(LOG_INFO, "lua: error checks under {tier}: {agree} of {length(ERROR_CHECKS)} agree with the native build\n")
    return agree == length(ERROR_CHECKS)
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

// the release's test suite, beside its `src/`
let SUITE_DIR = "{dir_name(SOURCES)}-tests"

// the files `all.lua` runs under `_port=true`, in its order, then `all.lua` itself
let SUITE <- ["main.lua", "gc.lua", "db.lua", "calls.lua", "strings.lua", "literals.lua", "tpack.lua", "attrib.lua", "gengc.lua", "locals.lua", "constructs.lua", "code.lua", "big.lua", "cstack.lua", "nextvar.lua", "pm.lua", "utf8.lua", "api.lua", "events.lua", "vararg.lua", "closure.lua", "coroutine.lua", "goto.lua", "errors.lua", "math.lua", "sort.lua", "bitwise.lua", "verybig.lua", "files.lua", "all.lua"]

// `big.lua` yields at its top level: `all.lua` runs it as a coroutine and checks what it yields
let BIG_LUA = "local f = coroutine.wrap(assert(loadfile('big.lua'))) assert(f() == 'b') assert(f() == 'a')"

// the interpreter's arguments for the test file `file`, with the globals `all.lua` sets for it
def private suite_args(file : string) : array<string> =>
    <- file == "big.lua" ? ["-e", "_port=true", "-e", BIG_LUA] : ["-e", "_port=true", file]

// the prefix that runs a command in a scope of its own whose memory systemd caps at `memory`; the
// kernel kills the command past it, which `run_and_capture` reports as the signal's number
def private capped(memory : string) : array<string> =>
    <- ["systemd-run", "--scope", "-p", "MemoryMax={memory}", "--quiet"]

// `path` from the repository root, the runs entering the suite's folder
def private full_path(path : string) : string => path_join(getcwd(), path)

// `text` with every run of digits one `#`: the suite prints seeds, timings and dates
def private masked(text : string) : string {
    return build_string() $(var w) {
        var in_digits = false
        for (ch in text) {
            if (!is_number(ch)) {
                w |> write_char(ch)
            } elif (!in_digits) {
                w |> write("#")
            }
            in_digits = is_number(ch)
        }
    }
}

// the first line where `native` and `das` differ once masked, quoted from each
def private first_difference(native, das, tier : string) : string {
    let left <- split(native, "\n")
    let right <- split(das, "\n")
    for (i in range(max(length(left), length(right)))) {
        let l = i < length(left) ? left[i] : "<end>"
        let r = i < length(right) ? right[i] : "<end>"
        if (masked(l) != masked(r)) {
            return "line {i + 1}: native `{slice(l, 0, 120)}`, {tier} `{slice(r, 0, 120)}`"
        }
    }
    return ""
}

// one run's verdict when the cap or the timeout ended it: `memory`, `timeout`, or "" when it exited
def private ended(rc : int; side, memory : string; timeout : float) : string {
    if (rc == popen_timed_out) {
        return "timeout {side} past {timeout} s"
    }
    return rc == 9 ? "memory {side} over {memory}" : ""
}

// the verdict line of one test file: the native oracle `bin` run first, then the converted
// interpreter at `das_path` under `tier`, each in the suite's folder, capped and timed; a run the
// cap or the timeout ends is `memory` or `timeout`, the converted one skipped when it is the oracle's
def private suite_file(file, das_path, bin, tier : string; args : Args) : string {
    let dir = full_path(SUITE_DIR)
    if (!fexist(path_join(dir, file))) {
        return "{file} missing 0.0"
    }
    var native_args <- capped(args.suite_memory)
    native_args |> push_from(["bash", "-c", "cd \"$1\" && exec -a \"$0\" \"$\{@:2\}\"", "lua", dir, full_path(bin)], suite_args(file))
    var native_out : string
    let native_started = ref_time_ticks()
    let native_rc = run_and_capture(native_args, native_out, args.suite_timeout)
    let native_seconds = double(get_time_usec(native_started)) / 1000000.0lf
    to_log(LOG_INFO, "lua: suite {file}: native exited {native_rc} in {fmt(":.1f", native_seconds)} s\n")
    let native_end = ended(native_rc, "native", args.suite_memory, args.suite_timeout)
    if (!empty(native_end)) {
        return "{file} {native_end |> starts_with("memory") ? "memory" : "timeout"} {fmt(":.1f", native_seconds)} {native_end}"
    }
    var das_args <- capped(args.suite_memory)
    das_args |> push_from(["sh", "-c", "cd \"$0\" && exec \"$@\"", dir], daslang_cmd([for (m in CONVERTED_MODULES); full_path(m)]))
    if (tier == "jit") {
        das_args |> push("-jit")
    }
    das_args |> push_from([full_path(das_path), "--"], suite_args(file))
    var das_out : string
    let das_started = ref_time_ticks()
    let das_rc = run_and_capture(das_args, das_out, args.suite_timeout)
    let seconds = fmt(":.1f", double(get_time_usec(das_started)) / 1000000.0lf)
    das_out = program_output(das_out)
    let das_end = ended(das_rc, tier, args.suite_memory, args.suite_timeout)
    if (!empty(das_end)) {
        return "{file} {das_end |> starts_with("memory") ? "memory" : "timeout"} {seconds} {das_end}"
    }
    let difference = first_difference(native_out, das_out, tier)
    if (native_rc != das_rc) {
        return "{file} fail {seconds} native exited {native_rc}, {tier} {das_rc}; {difference}"
    }
    return empty(difference) ? "{file} pass {seconds}" : "{file} fail {seconds} {difference}"
}

// every file of `SUITE` (the one `--suite-filter` names) run by `suite_file` in `layout`, its
// verdicts written to `lua/work/<layout>/suite.txt` and counted: true when every file passes
def private suite_check(das_path, bin, layout : string; args : Args) : bool {
    let files <- empty(args.suite_filter) ? clone_to_move(SUITE) : [args.suite_filter]
    let started = ref_time_ticks()
    var lines : array<string>
    lines |> reserve(length(files))
    var counts : table<string; int>
    for (file in files) {
        let line = suite_file(file, das_path, bin, args.tier, args)
        to_log(LOG_INFO, "lua: suite ({layout}, {args.tier}): {line}\n")
        lines |> push(line)
        counts[split(line, " ")[1]]++
    }
    let out_dir = path_join(WORK, layout)
    mkdir_rec(out_dir)
    fwrite(path_join(out_dir, "suite.txt"), join(lines, "\n") + "\n")
    let totals = join([for (verdict in ["pass", "fail", "timeout", "memory", "missing"]); "{counts?[verdict] ?? 0} {verdict}"], ", ")
    to_log(LOG_INFO, "lua: suite under {args.tier} ({layout}): {totals} of {length(files)} files in {fmt(":.0f", double(get_time_usec(started)) / 1000000.0lf)} s\n")
    return (counts?["pass"] ?? 0) == length(files)
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

// one program converted in `layout` and reported; with `--error-check`, `--suite-check` and `--run`
// the interpreter run against the native oracle `bin`, with `--luac-check` the compiler over the folder it names
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
    if (args.error_check && main_source == "lua" && !error_check(res.das_path, bin, stem, args.tier)) {
        return false
    }
    if (args.run && main_source == "lua") {
        var program_args <- ["-e", "print(1+1)"]
        if (!empty(args.arg)) {
            program_args := args.arg
        }
        return run_both(res.das_path, bin, stem, args.tier, program_args)
    }
    if (args.suite_check && main_source == "lua" && !suite_check(res.das_path, bin, layout, args)) {
        return false
    }
    if (!empty(args.luac_check) && main_source == "luac") {
        return luac_check(res.das_path, bin, args.tier, args.luac_check, path_join(dir, "luac_check"))
    }
    return true
}

// one program's manifest written, the program converted in each layout `--layout` names and
// reported; with `--native`, `--run`, `--error-check`, `--suite-check` or `--luac-check` its oracle
// built first
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
    if ((args.native || args.run || args.error_check || args.suite_check || !empty(args.luac_check)) && !build_native(input.c_paths, bin)) {
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
    if (!empty(args.suite_filter) && !has_value(SUITE, args.suite_filter)) {
        to_log(LOG_ERROR, "lua: --suite-filter names a file of the suite, not `{args.suite_filter}`\n")
        return 1
    }
    if (args.suite_check) {
        var probe <- capped(args.suite_memory)
        probe |> push("true")
        var out : string
        if (run_and_capture(probe, out, 60.0) != 0) {
            to_log(LOG_ERROR, "lua: --suite-check caps each run with `{join(probe, " ")}`, which fails: {out}\n")
            return 1
        }
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
