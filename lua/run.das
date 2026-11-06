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
require ../perf/perf_lanes.das
require sources

//! The Lua harness: `lua/fetch.sh`'s release converted as its Makefile builds it, the interpreter
//! `lua` and the compiler `luac`, each from its separate C files through a program manifest
//! `lua/work/<stem>.program.json` and `converter/pipeline.das`'s `convert_program` with
//! `lua/lua.c2das`, its compile check included, and timed, in the source layout into
//! `lua/work/<stem>/`, in the source-cut layout into `lua/work/source-cut/<stem>/` and in the
//! single layout into `lua/work/single/<stem>/`, each under `lua/work/goto/` with
//! `--switch-dispatch goto`. `--native` builds the
//! native oracle of each, `--run` runs the converted interpreter against it, `--error-check` the
//! interpreter's error-recovery checks against it, `--luac-check` the
//! converted compiler's `-o` over a folder of scripts, `--suite-check` the release's test suite file
//! by file against it. Run from the repository root.

let WORK = "lua/work"
let ORACLE_FLAGS <- ["-O0", "-funsigned-char", "-w"]



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
    @clarg_doc = "the layouts to convert: source (a module per C file, every cycle one module, into lua/work/<stem>/), source-cut (the cycles cut by late binding, into lua/work/source-cut/<stem>/), single (one module, into lua/work/single/<stem>/) or all, the default"
    layout : string = "all"
    @clarg_name = "switch-dispatch"
    @clarg_doc = "the converter's --switch-dispatch: chain or goto (a dense switch as a jump table, lvm's dispatch among them, each layout's folder then under lua/work/goto/); default the sidecar's, which is chain"
    switch_dispatch : string = ""
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
    @clarg_name = "suite-port"
    @clarg_doc = "the value of the global `_port` each test file gets under --suite-check: true skips the tests that assume a POSIX build, false runs them"
    suite_port : string = "true"
    @clarg_name = "suite-memory"
    @clarg_doc = "the memory each run of a test file gets under --suite-check: anything systemd's MemoryMax takes; the prlimit fallback needs bytes with K, M, G or T"
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

// the native oracle of the program's `c_paths` at `bin`; false with the compiler's text logged
// when it fails
def private build_native(c_paths : array<string>; bin : string) : bool {
    var args <- [default_clang()]
    args |> push_from(ORACLE_FLAGS, ["-o", bin], c_paths, ["-lm"])
    var output : string
    if (run_and_capture(args, output, 300.0) != 0) {
        to_log(LOG_ERROR, "lua: native build of {bin} failed:\n{output}\n")
        return false
    }
    to_log(LOG_INFO, "lua: {bin}: {int64(stat(bin).size)} bytes\n")
    return true
}

struct Streams {
    out : string
    err : string
}

// `argv` run with its stderr sent to a file of its own under `lua/work`, read and removed after the
// run, and its stdin a pipe whose writer has exited, which reads at its end at once and does not
// seek, where `run_and_capture` alone gives the `/dev/null` that seeks: its exit code, the two
// streams in `streams`. `path_dir`, unless empty, leads its `PATH`. Each `exec` keeps `argv`'s
// program the direct child the timeout and the cap kill
def private run_split(argv : array<string>; timeout : float; path_dir : string; var streams : Streams) : int {
    let err_path = full_path(path_join(WORK, "run.stderr"))
    var cmd <- ["bash", "-c", "exec 2>\"$0\" 0< <(:); [ -z \"$1\" ] || PATH=\"$1:$PATH\"; shift; exec \"$@\"", err_path, path_dir]
    cmd |> push_from(argv)
    let rc = run_and_capture(cmd, streams.out, timeout)
    streams.err = fexist(err_path) ? fread(err_path) : ""
    remove(err_path)
    return rc
}

// the converted interpreter at `das_path` under `tier`, `interp` or `jit`, with `program_args`
def private das_argv(das_path, tier : string; program_args : array<string>) : array<string> {
    var argv <- daslang_cmd([for (m in CONVERTED_MODULES); full_path(m)])
    if (tier == "jit") {
        argv |> push("-jit")
    }
    argv |> push_from([full_path(das_path), "--"], program_args)
    return <- argv
}

// the streams of the native run and the converted run that differ, "" when both agree
def private stream_difference(native, das : Streams) : string {
    if (native.out != das.out && native.err != das.err) {
        return "stdout and stderr differ"
    }
    return native.out != das.out ? "stdout differs" : native.err != das.err ? "stderr differs" : ""
}

// the converted interpreter at `das_path` under `tier` and the native one at `bin`, each run with
// `program_args`: "" when the exit codes and both streams agree, else what differs. The native one
// runs under the name `stem`, the `argv[0]` the converted program gets, which Lua's messages quote
def private run_both(das_path, bin, stem, tier : string; program_args : array<string>) : string {
    var native_args <- ["bash", "-c", "exec -a \"$0\" \"$@\"", stem, bin]
    native_args |> push_from(program_args)
    var native, das : Streams
    let native_rc = run_split(native_args, 60.0, "", native)
    let das_rc = run_split(das_argv(das_path, tier, program_args), 600.0, "", das)
    das.out = program_output(das.out)
    to_log(LOG_INFO, "lua: native exited {native_rc}: {native.out}\n")
    to_log(LOG_INFO, "lua: native stderr: {native.err}\n")
    to_log(LOG_INFO, "lua: {tier} exited {das_rc}: {das.out}\n")
    to_log(LOG_INFO, "lua: {tier} stderr: {das.err}\n")
    return native_rc != das_rc ? "native exited {native_rc}, {tier} {das_rc}" : stream_difference(native, das)
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
        let difference = run_both(das_path, bin, stem, tier, check)
        if (empty(difference)) {
            agree++
        } else {
            to_log(LOG_ERROR, "lua: error check `{join(check, " ")}` under {tier} differs from the native build: {difference}\n")
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

// the interpreter's arguments for the test file `file`, with the globals `all.lua` sets for it and
// `_port` as `--suite-port` names it
def private suite_args(file, port : string) : array<string> =>
    <- file == "big.lua" ? ["-e", "_port={port}", "-e", BIG_LUA] : ["-e", "_port={port}", file]

// a run's memory cap: the words that run a command under it, and whether the kernel kills the
// command past it (a cgroup cap, which `run_and_capture` reports as the signal's number) or its
// allocations fail there (an address-space cap, which `lua.c` reports as `not enough memory`)
struct Cap {
    prefix : array<string>
    kills : bool
}

// the most digits every count of which fits an int64, whose largest value has 19
let MAX_INT64_DIGITS = 18

// `memory` as systemd's MemoryMax takes it, in bytes: digits with K, M, G or T; -1 for any other
// spelling, and for a count past int64
def private memory_bytes(memory : string) : int64 {
    let last = empty(memory) ? "" : slice(memory, length(memory) - 1)
    let scale = last == "K" ? 1024l : last == "M" ? 1048576l : last == "G" ? 1073741824l : last == "T" ? 1099511627776l : 1l
    let digits = scale == 1l ? memory : slice(memory, 0, length(memory) - 1)
    if (empty(digits)) {
        return -1l
    }
    for (ch in digits) {
        if (!is_number(ch)) {
            return -1l
        }
    }
    if (length(digits) > MAX_INT64_DIGITS) {
        return -1l
    }
    let count = to_int64(digits)
    return count > 9223372036854775807l / scale ? -1l : count * scale
}

// the caps `--suite-check` can apply, in the order it tries them: a scope of the system manager
// (root's), a scope of the user's own manager (a user with one running), and `prlimit`'s
// address-space limit (any user); a scope's `MemoryMax` is `memory` as given, the limit `memory` in
// bytes, which `unparsed` says when it has none
def private cap_candidates(memory : string; var unparsed : string&) : array<Cap> {
    let scope <- ["--scope", "--collect", "-p", "MemoryMax={memory}", "-p", "MemorySwapMax=0", "--quiet"]
    var candidates : array<Cap>
    candidates |> reserve(3)
    for (manager in [["systemd-run"], ["systemd-run", "--user"]]) {
        var inscope prefix := manager
        prefix |> push_from(scope)
        candidates |> emplace(Cap(prefix <- prefix, kills = true))
    }
    let bytes = memory_bytes(memory)
    if (bytes < 0l) {
        unparsed = "`prlimit --as` takes bytes with K, M, G or T, not `{memory}`"
    } else {
        candidates |> emplace(Cap(prefix <- ["prlimit", "--as={bytes}", "--"]))
    }
    return <- candidates
}

// the first of `cap_candidates` for `--suite-memory` under which `true` runs, in `cap`: false when
// none does, each probe and why it failed logged
def private choose_cap(args : Args; var cap : Cap&) : bool {
    var unparsed : string
    var candidates <- cap_candidates(args.suite_memory, unparsed)
    var attempts : array<string>
    attempts |> reserve(length(candidates) + 1)
    for (candidate in candidates) {
        var inscope probe := candidate.prefix
        probe |> push("true")
        var out : string
        if (run_and_capture(probe, out, 60.0) == 0) {
            cap := candidate
            return true
        }
        attempts |> push("`{join(probe, " ")}`, which fails: {first_reported_line(out)}")
    }
    if (!empty(unparsed)) {
        attempts |> push(unparsed)
    }
    to_log(LOG_ERROR, "lua: --suite-check caps each run with {join(attempts, "; ")}\n")
    return false
}

// `path` from the repository root, the runs entering the suite's folder
def private full_path(path : string) : string => path_join(getcwd(), path)

// whether the character at `i` of `text` is a digit; false past its end
def private digit_at(text : array<int>; i : int) : bool => i < length(text) && is_number(text[i])

def private sign_at(text : array<int>; i : int) : bool => i < length(text) && (text[i] == '+' || text[i] == '-')

// the end of the number starting at `i` of `text`: a sign, digits and points, an exponent
def private number_end(text : array<int>; i : int) : int {
    var j = sign_at(text, i) ? i + 1 : i
    while (j < length(text)) {
        let ch = text[j]
        if (is_number(ch) || ch == '.') {
            j++
        } elif ((ch == 'e' || ch == 'E') && (digit_at(text, j + 1) || (sign_at(text, j + 1) && digit_at(text, j + 2)))) {
            j += 2
        } else {
            break
        }
    }
    return j
}

// the end of the run of dots starting at `i` of `text`, short of a dot a number starts with
def private dots_end(text : array<int>; i : int) : int {
    var j = i
    while (j < length(text) && text[j] == '.' && !digit_at(text, j + 1)) {
        j++
    }
    return j
}

// `line` with every number one `#`, whatever its sign, digits or notation: the suite prints seeds,
// timings and dates, `%g` choosing the notation by the value; and every run of dots one dot, the
// progress dots `all.lua`'s collections print running as many as the collector's timing makes
def private masked(line : string) : string {
    let text <- [for (ch in line); ch]
    return build_string() $(var w) {
        var i = 0
        while (i < length(text)) {
            let ch = text[i]
            if (is_number(ch) || ((ch == '.' || ch == '+' || ch == '-') && digit_at(text, i + 1))) {
                w |> write("#")
                i = number_end(text, i)
            } elif (ch == '.') {
                w |> write(".")
                i = dots_end(text, i)
            } else {
                w |> write_char(ch)
                i++
            }
        }
    }
}

// the warning `all.lua` prints when its time differs from the one the previous run left
let TIME_WARNING = "Lua warning: #time difference from previous test"

// `line` without `TIME_WARNING`, its text to the end of the line: all.lua prints the warning
// mid-line after its progress dots, which stay
def private without_time_warning(line : string) : string {
    let at = find(line, TIME_WARNING)
    return at < 0 ? line : slice(line, 0, at)
}

// the lines of a run's output the comparison reads, each without `TIME_WARNING` and a line it held
// alone gone, since the previous run in the suite's folder is the other build's
def private compared_lines(output : string) : array<string> => <- [for (line in split(output, "\n")); without_time_warning(line); where !(line |> starts_with(TIME_WARNING))]

// the first line of `stream` where `native` and `das` differ once masked, quoted from each
def private first_line_difference(stream, native, das, tier : string) : string {
    let native_lines <- compared_lines(native)
    let converted_lines <- compared_lines(das)
    for (i in range(max(length(native_lines), length(converted_lines)))) {
        let native_line = i < length(native_lines) ? native_lines[i] : "<end>"
        let das_line = i < length(converted_lines) ? converted_lines[i] : "<end>"
        if (masked(native_line) != masked(das_line)) {
            return "{stream} line {i + 1}: native `{slice(native_line, 0, 120)}`, {tier} `{slice(das_line, 0, 120)}`"
        }
    }
    return ""
}

// the first line where the native run and the converted run differ, stdout before stderr
def private first_difference(native, das : Streams; tier : string) : string {
    let out = first_line_difference("stdout", native.out, das.out, tier)
    return empty(out) ? first_line_difference("stderr", native.err, das.err, tier) : out
}

// the signal a cgroup cap kills a run with, which `run_and_capture` returns as its exit code
let SIGKILL = 9

// one run's verdict when the cap or the timeout ended it: `memory`, `timeout`, or "" when it
// exited; a cap that kills ended the run with `SIGKILL`, one that fails allocations with the
// `not enough memory` of `lua.c` on stderr `err`
def private limit_verdict(rc : int; cap : Cap; err, side, memory : string; timeout : float) : string {
    if (rc == popen_timed_out) {
        return "timeout {side} past {timeout} s"
    }
    let over = cap.kills ? rc == SIGKILL : rc != 0 && err |> contains("not enough memory")
    return over ? "memory {side} over {memory}" : ""
}

// the seconds since `t0`, a `ref_time_ticks` reading; `suites/suite_runner.das` holds a public
// float one, which a public one in `converter/pipeline.das` would make ambiguous there
def private run_seconds(t0 : int64) : double => double(get_time_usec(t0)) / 1000000.0lf

// one run of a test file under the cap: its exit code, its streams, its seconds and its
// `limit_verdict`
struct CappedRun {
    rc : int
    streams : Streams
    seconds : double
    limit : string
}

// `argv` run under `cap` and timed, `path_dir` leading its `PATH`, the run named `side` in its
// limit verdict
def private capped_run(argv : array<string>; side, path_dir : string; cap : Cap; args : Args) : CappedRun {
    var full := cap.prefix
    full |> push_from(argv)
    var run : CappedRun
    let started = ref_time_ticks()
    run.rc = run_split(full, args.suite_timeout, path_dir, run.streams)
    run.seconds = run_seconds(started)
    run.limit = limit_verdict(run.rc, cap, run.streams.err, side, args.suite_memory, args.suite_timeout)
    return run
}

// the verdict line of a run the cap or the timeout ended: `memory` or `timeout`, its seconds, why
def private limit_line(file : string; run : CappedRun) : string => "{file} {split(run.limit, " ")[0]} {run.seconds:.1f} {run.limit}"

// the verdict line of one test file: the native oracle `bin` run first, then the converted
// interpreter at `das_path` under `tier`, each in the suite's folder with the `lua` of
// `launchers` on its `PATH` (`suite_launchers`), under `cap` and timed; a run the
// cap or the timeout ends is `memory` or `timeout`, and an oracle that fails on its own is `oracle`
// with the first line of its stderr: in both the converted one is skipped
def private suite_file(file, das_path, bin, tier : string; launchers : Launchers; cap : Cap; args : Args) : string {
    let dir = full_path(SUITE_DIR)
    if (!fexist(path_join(dir, file))) {
        return "{file} missing 0.0"
    }
    var native_argv <- ["bash", "-c", "cd \"$1\" && exec -a \"$0\" \"$\{@:2\}\"", "lua", dir, full_path(bin)]
    native_argv |> push_from(suite_args(file, args.suite_port))
    let native = capped_run(native_argv, "native", launchers.native, cap, args)
    to_log(LOG_INFO, "lua: suite {file}: native exited {native.rc} in {native.seconds:.1f} s\n")
    if (!empty(native.limit)) {
        return limit_line(file, native)
    }
    if (native.rc != 0) {
        let said = first_reported_line(native.streams.err)
        let quoted = empty(said) ? "" : ": " + slice(said, 0, 160)
        return "{file} oracle {native.seconds:.1f} native exited {native.rc}{quoted}"
    }
    var das = capped_run(in_folder(dir, das_argv(das_path, tier, suite_args(file, args.suite_port))), tier, launchers.das, cap, args)
    if (!empty(das.limit)) {
        return limit_line(file, das)
    }
    das.streams.out = program_output(das.streams.out)
    let difference = first_difference(native.streams, das.streams, tier)
    if (native.rc != das.rc) {
        return "{file} fail {das.seconds:.1f} native exited {native.rc}, {tier} {das.rc}; {difference}"
    }
    return empty(difference) ? "{file} pass {das.seconds:.1f}" : "{file} fail {das.seconds:.1f} {difference}"
}

// the folders whose `lua` each side's runs find on their `PATH`, as `main.lua` runs the interpreter
struct Launchers {
    native : string
    das : string
}

// `lua/work/native_bin/lua`, a link named `lua` to the native oracle `bin` (the nested runs look
// `lua` up on `PATH`), and `lua/work/<layout>/bin/lua`, a script running the converted interpreter
// at `das_path` under `tier` with its arguments, each word quoted for `sh`: their folders, empty
// when one cannot be written
def private suite_launchers(das_path, bin, tier, layout : string) : Launchers {
    let native_dir = full_path(path_join(WORK, "native_bin"))
    let das_dir = full_path(path_join(path_join(WORK, layout), "bin"))
    mkdir_rec(native_dir)
    mkdir_rec(das_dir)
    let das_lua = path_join(das_dir, "lua")
    let command = join([for (word in das_argv(das_path, tier, array<string>())); "'{replace(word, "'", "'\\''")}'"], " ")
    var out : string
    let linked = run_and_capture(["ln", "-sfn", full_path(bin), path_join(native_dir, "lua")], out, 60.0) == 0
    let written = fwrite(das_lua, "#!/bin/sh\nexec {command} \"$@\"\n") && run_and_capture(["chmod", "+x", das_lua], out, 60.0) == 0
    return linked && written ? Launchers(native = native_dir, das = das_dir) : Launchers()
}

// every file of `SUITE` (the one `--suite-filter` names) run by `suite_file` in `layout` under the
// cap `choose_cap` finds (probed again here: `Args` stays the command line), its verdicts written
// to `lua/work/<layout>/suite.txt` and counted: true when every file passes
def private suite_check(das_path, bin, layout : string; args : Args) : bool {
    let files <- empty(args.suite_filter) ? clone_to_move(SUITE) : [args.suite_filter]
    let launchers = suite_launchers(das_path, bin, args.tier, layout)
    if (empty(launchers.native)) {
        to_log(LOG_ERROR, "lua: cannot write the suite's `lua` launchers under {WORK}\n")
        return false
    }
    var cap : Cap
    if (!choose_cap(args, cap)) {
        return false
    }
    to_log(LOG_INFO, "lua: suite ({layout}, {args.tier}) caps each run with `{join(cap.prefix, " ")}`\n")
    let started = ref_time_ticks()
    var lines : array<string>
    lines |> reserve(length(files))
    var counts : table<string; int>
    for (file in files) {
        let line = suite_file(file, das_path, bin, args.tier, launchers, cap, args)
        to_log(LOG_INFO, "lua: suite ({layout}, {args.tier}): {line}\n")
        lines |> push(line)
        counts[split(line, " ")[1]]++
    }
    let out_dir = path_join(WORK, layout)
    mkdir_rec(out_dir)
    fwrite(path_join(out_dir, "suite.txt"), join(lines, "\n") + "\n")
    let totals = join([for (verdict in ["pass", "fail", "timeout", "memory", "oracle", "missing"]); "{counts?[verdict] ?? 0} {verdict}"], ", ")
    to_log(LOG_INFO, "lua: suite under {args.tier} ({layout}): {totals} of {length(files)} files in {fmt(":.0f", run_seconds(started))} s\n")
    return (counts?["pass"] ?? 0) == length(files)
}

// the layouts `--layout` names
def private layouts_of(args : Args) : array<string> => <- args.layout == "all" ? ["source", "source-cut", "single"] : [args.layout]

// the lines of every das file a conversion wrote, a fragment's included
def private das_lines(res : ConvertResult; dir : string) : int {
    if (empty(res.files)) {
        return count(res.das_text, "\n")
    }
    var lines = 0
    for (f in res.files) {
        lines += count(fread(path_join(dir, f)), "\n")
    }
    return lines
}

// the folder the layouts' folders sit in: `WORK`, or under `--switch-dispatch goto` its `goto/`, so
// the goto conversion's trees and module caches stay apart from the default ones
def private work_of(args : Args) : string => args.switch_dispatch == "goto" ? path_join(WORK, "goto") : WORK

// one program converted in `layout` and reported; with `--error-check`, `--suite-check` and `--run`
// the interpreter run against the native oracle `bin`, with `--luac-check` the compiler over the folder it names
def private convert_layout(stem, main_source : string; input : ProgramInput; bin, layout : string; args : Args) : bool {
    let dir = layout_dir(work_of(args), stem, layout)
    let res <- convert_program(input.c_paths, dir, args.target, "", SIDECAR, "", "", input.entry, layout, false, "", args.switch_dispatch)
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
        let difference = run_both(res.das_path, bin, stem, args.tier, program_args)
        if (!empty(difference)) {
            to_log(LOG_ERROR, "lua: --run under {args.tier} differs from the native build: {difference}\n")
        }
        return empty(difference)
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
        to_log(LOG_ERROR, "lua: --layout is source, source-cut, single or all, not `{args.layout}`\n")
        return 1
    }
    if (!empty(args.suite_filter) && !has_value(SUITE, args.suite_filter)) {
        to_log(LOG_ERROR, "lua: --suite-filter names a file of the suite, not `{args.suite_filter}`\n")
        return 1
    }
    if (args.suite_port != "true" && args.suite_port != "false") {
        to_log(LOG_ERROR, "lua: --suite-port is true or false, not `{args.suite_port}`\n")
        return 1
    }
    var cap : Cap
    if (args.suite_check && !choose_cap(args, cap)) {
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
