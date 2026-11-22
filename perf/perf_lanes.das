options gen2

module perf_lanes public

require strings
require daslib/strings_boost
require daslib/strings_convert
require daslib/fio
require ../converter/tiers.das
require ../converter/dumper_a.das
require samples public

//! The lanes and the sample arithmetic every timing harness shares: `perf/run.das` over the
//! kernels and `ports/publish.das` over a ported program's workloads. Each lane is built here
//! once (perf/ARCHITECTURE.md section 2), so both harnesses time the same native build, the same
//! daslang invocations and the same exe and AOT builds. A cell is the median of its samples
//! (`samples.das`), each a `timed` process pinned to one core.

//! the native lane's flags: dasProfile's Release build gives its C++ kernels `-O3`
let NATIVE_FLAGS <- ["-O3", "-w", "-funsigned-char"]
//! the seconds each step of an `exe` or `aot` build may take, and the run it ends with
let BUILD_TIMEOUT = 3600.0

//! The native lane's build of the program's `c_paths` into `bin` by the pinned clang, `libs`
//! linked last.
def native_build_command(c_paths : array<string>; bin : string; libs : array<string>) : array<string> {
    var argv <- [default_clang()]
    argv |> push_from(NATIVE_FLAGS, ["-o", bin], c_paths, libs)
    return <- argv
}

//! The interpreter (`flag` empty) or JIT (`flag` `-jit`) lane over the converted `das_path`, the
//! module folders loaded; the program's own arguments follow after `--`.
def das_lane_command(das_path, flag : string; module_dirs : array<string>) : array<string> {
    var argv <- daslang_cmd(module_dirs)
    if (!empty(flag)) {
        argv |> push(flag)
    }
    argv |> push(das_path)
    return <- argv
}

//! the names of the signals 1 to 15 by number, Linux's
let SIGNAL_NAMES <- ["", "HUP", "INT", "QUIT", "ILL", "TRAP", "ABRT", "BUS", "FPE", "KILL", "USR1", "SEGV", "USR2", "PIPE", "ALRM", "TERM"]

//! `argv` as a guarded run starts it (`ARCHITECTURE_SAMPLES.md`): under `prlimit` with a core limit
//! of one byte, which writes no core file even to a pipe handler, and, when `address_space` is
//! above 0, that many bytes of address space, inside `sh`, which waits for it and so reports a
//! death by signal N as the exit code 128 + N.
def guarded(argv : array<string>; address_space : int64) : array<string> {
    var full <- ["sh", "-c", "\"$@\"; exit $?", "sh", "prlimit", "--core=1"]
    full |> reserve(length(full) + 2 + length(argv))
    if (address_space > 0l) {
        full |> push("--as={address_space}")
    }
    full |> push("--")
    full |> push_from(argv)
    return <- full
}

//! the variable naming the core a timed sample runs on (`ARCHITECTURE_SAMPLES.md` section 4), `off`
//! for none
let TIMING_CORE_VARIABLE = "C2DAS_TIMING_CORE"
//! the core a timed sample runs on when the variable is unset
let DEFAULT_TIMING_CORE = 3

//! How a timed sample is pinned: the `taskset` prefix its command takes (empty for none) and the
//! line saying so.
struct TimingPin {
    prefix : array<string>
    note : string
}

//! The cores a `Cpus_allowed_list` value names (`0-3,8`), in order; none for a value it cannot read.
def cpu_list(list : string) : array<int> {
    var cores : array<int>
    var inscope parts <- split(strip(list), ",")
    for (part in parts) {
        var inscope bounds <- split(part, "-")
        let lo = try_to_int(bounds[0]) ?? -1
        let hi = length(bounds) == 2 ? try_to_int(bounds[1]) ?? -1 : lo
        if (length(bounds) > 2 || lo < 0 || hi < lo) {
            delete cores
            return <- cores
        }
        cores |> reserve(length(cores) + hi - lo + 1)
        for (core in range(lo, hi + 1)) {
            cores |> push(core)
        }
    }
    return <- cores
}

//! The pin of a timed sample from `setting` (the variable's value), `taskset` (its path, "" when
//! not on `PATH`) and `allowed` (the cores this process may run on, none when unknown): the core
//! `setting` names, `DEFAULT_TIMING_CORE` when it is empty, else the last allowed core when that one
//! is not allowed; no pin under `off`, without taskset, or for a core not allowed.
def timing_pin(setting, taskset : string; allowed : array<int>) : TimingPin {
    if (setting == "off") {
        return <- TimingPin(note = "{TIMING_CORE_VARIABLE}=off: timed samples run unpinned")
    }
    if (empty(taskset)) {
        return <- TimingPin(note = "no taskset on PATH: timed samples run unpinned")
    }
    var core = DEFAULT_TIMING_CORE
    if (!empty(setting)) {
        core = try_to_int(setting) ?? -1
    } elif (!empty(allowed) && !has_value(allowed, core)) {
        core = allowed[length(allowed) - 1]
    }
    if (core < 0 || (!empty(allowed) && !has_value(allowed, core))) {
        return <- TimingPin(note = "{TIMING_CORE_VARIABLE}={setting} names no core this process may run on: timed samples run unpinned")
    }
    return <- TimingPin(prefix <- [taskset, "-c", "{core}"], note = "timed samples run on core {core} (taskset)")
}

//! The first folder of `$PATH` holding the program `name`, as its path; "" when none does.
def on_path(name : string) : string {
    for (dir in split(get_env_variable("PATH"), ":")) {
        let candidate = path_join(empty(dir) ? "." : dir, name)
        if (stat(candidate).is_reg) {
            return candidate
        }
    }
    return ""
}

// the cores this process may run on, its `Cpus_allowed_list`; none when unread
def private allowed_cores : array<int> {
    for (line in split(fread("/proc/self/status"), "\n")) {
        if (line |> starts_with("Cpus_allowed_list:")) {
            return <- cpu_list(slice(line, length("Cpus_allowed_list:")))
        }
    }
    return <- array<int>()
}

// this process's pin, read once and logged, a missing pin as a warning
var private PROCESS_PIN : TimingPin
var private PROCESS_PIN_READ = false

//! The prefix of a timed sample on this machine (`timing_pin` of `$C2DAS_TIMING_CORE`, taskset on
//! `PATH` and this process's `Cpus_allowed_list`), its note logged on the first call.
def timing_prefix : array<string> {
    if (!PROCESS_PIN_READ) {
        var inscope allowed <- allowed_cores()
        delete PROCESS_PIN
        PROCESS_PIN <- timing_pin(get_env_variable(TIMING_CORE_VARIABLE), on_path("taskset"), allowed)
        PROCESS_PIN_READ = true
        to_log(empty(PROCESS_PIN.prefix) ? LOG_WARNING : LOG_INFO, "{PROCESS_PIN.note}\n")
    }
    return <- clone_to_move(PROCESS_PIN.prefix)
}

//! `argv` as a timed sample starts it: `pinned` by `pin`, then `guarded` under `address_space`.
def timed(argv : array<string>; address_space : int64; pin : array<string>) : array<string> {
    var full := pin
    full |> push_from(guarded(argv, address_space))
    return <- full
}

//! `timed` with this process's `timing_prefix`.
def timed(argv : array<string>; address_space : int64) : array<string> => <- timed(argv, address_space, timing_prefix())

//! The death the exit code `rc` of a guarded run reports: `signal N (<name>)` for a code from 129
//! to 192, the shell's report of a death by signal N, else "".
def signal_text(rc : int) : string {
    let signal = rc - 128
    if (signal < 1 || signal > 64) {
        return ""
    }
    return signal < length(SIGNAL_NAMES) ? "signal {signal} ({SIGNAL_NAMES[signal]})" : "signal {signal}"
}

//! The exit code `rc` of a guarded run in words: its `signal_text`, else `exited <rc>`.
def exit_text(rc : int) : string {
    let signal = signal_text(rc)
    return empty(signal) ? "exited {rc}" : signal
}

//! A failed guarded run's error: its exit in words and the first line it reported, or `no output`.
def run_error(rc : int; output : string) : string {
    let line = first_reported_line(output)
    return empty(line) ? "{exit_text(rc)}, no output" : "{exit_text(rc)}: {line}"
}

//! The `exe` or `aot` binary of `das_path` built in `work` with `module_dirs` loaded and run once
//! with `program_args`; "" with `error` set when the build leaves none. The binary is
//! `build_tier`'s: an earlier build's while its key stands, else built again; a failed build is the
//! lane's error, never an earlier binary's run. The build and the run it ends with each get
//! `timeout` seconds; a timed-out run leaves a binary but no lane. The run is `guarded` under
//! `address_space` bytes, so a program that crashes there dumps no core either.
def lane_binary(das_path, tier, work : string; module_dirs, program_args : array<string>; var error : string&; timeout : float; address_space : int64 = 0l) : string {
    var out : string
    let no_flags, no_program : array<string>
    let built = build_tier(das_path, tier, work, out, module_dirs, timeout, no_flags)
    if (built.rc == popen_timed_out) {
        error = "the build or its run took longer than {int(timeout)} s"
        return ""
    }
    if (built.rc != 0 || !fexist(built.bin)) {
        let line = tier == "exe" ? exe_build_line(out) : aot_build_line(out)
        error = "the build exited {built.rc} and left no binary: {line}"
        return ""
    }
    var argv <- guarded(no_program, address_space)
    argv |> push_from(binary_argv(tier, built.bin, program_args))
    if (run_and_capture(argv, out, timeout) == popen_timed_out) {
        error = "the build or its run took longer than {int(timeout)} s"
        return ""
    }
    return built.bin
}

//! The line that says why the `aot` build failed: the context generation's `out of heap memory`
//! line (its `error[...]` line only names the exception), else the first `error[` line of the
//! context generation or `: error:` line of the host compiler, else the last reported line.
def aot_build_line(text : string) : string {
    let lines <- [for (l in split(text, "\n")); strip(l); where !empty(strip(l)) && !(strip(l) |> starts_with("[I] "))]
    for (line in lines) {
        if (line |> starts_with("out of heap memory")) {
            return line
        }
    }
    for (line in lines) {
        if (line |> starts_with("error[") || find(line, ": error: ") >= 0) {
            return line
        }
    }
    return empty(lines) ? "" : lines[length(lines) - 1]
}

//! The line that says why daslang's `-exe` build failed: the first reported line after its
//! `Output:` line (the linker's own message), else the first reported line.
def exe_build_line(text : string) : string {
    let at = find(text, "\nOutput:\n")
    let line = at < 0 ? "" : first_reported_line(slice(text, at + length("\nOutput:\n")))
    return empty(line) ? first_reported_line(text) : line
}

//! The `exe` lane's binary of `das_path`, built in `work` by daslang's `-exe` and run once with
//! `program_args`; "" with `error` set when the build leaves none.
def build_exe(das_path, work : string; program_args : array<string>; var error : string&) : string => build_exe(das_path, work, program_args, error, BUILD_TIMEOUT)

//! `build_exe` with `timeout` seconds for the build and for the run it ends with.
def build_exe(das_path, work : string; program_args : array<string>; var error : string&; timeout : float) : string => lane_binary(das_path, "exe", work, CONVERTED_MODULES, program_args, error, timeout)

//! The `aot` lane's binary of `das_path`: the `-ctx` context and the host `converter/tiers.das`
//! writes, compiled by the pinned clang++ at `-O3` in `work/ctx`, and run once with
//! `program_args`; "" with `error` set when the build leaves none.
def build_aot(das_path, work : string; program_args : array<string>; var error : string&) : string => build_aot(das_path, work, program_args, error, BUILD_TIMEOUT)

//! `build_aot` with `timeout` seconds for each build step and for the run it ends with.
def build_aot(das_path, work : string; program_args : array<string>; var error : string&; timeout : float) : string => lane_binary(das_path, "aot", work, CONVERTED_MODULES, program_args, error, timeout)

//! The merged stdout and stderr of `args`, whatever its exit code.
def captured(args : array<string>) : string {
    var out : string
    run_and_capture(args, out, 600.0)
    return out
}

//! the texts a shell prints when a child dies of a signal, dash's and bash's alike
let SHELL_SIGNAL_LINES <- ["Hangup", "Quit", "Illegal instruction", "Trace/breakpoint trap", "Aborted", "Bus error", "Floating point exception", "Killed", "Segmentation fault", "Terminated"]

//! True when `line` is a shell's report of a child's death by signal (`Segmentation fault (core
//! dumped)`), which a guarded run's shell prints after the program's own output.
def shell_signal_line(line : string) : bool {
    let text = line |> ends_with(" (core dumped)") ? slice(line, 0, length(line) - length(" (core dumped)")) : line
    return has_value(SHELL_SIGNAL_LINES, text)
}

//! The first line of `text` that is not empty, not an `info` line (`[I] `) and not a shell's
//! report of a signal death (`shell_signal_line`).
def first_reported_line(text : string) : string {
    for (l in split(text, "\n")) {
        let line = strip(l)
        if (!empty(line) && !(line |> starts_with("[I] ")) && !shell_signal_line(line)) {
            return line
        }
    }
    return ""
}

//! The lines of `text` that do not start with `prefix`.
def lines_without(text, prefix : string) : array<string> => <- [for (ln in split(text, "\n")); ln; where !(ln |> starts_with(prefix))]

//! `text` without the `info` lines (`[I] `) the JIT reports its compilation on among a program's
//! output.
def program_output(text : string) : string => join(lines_without(text, "[I] "), "\n")

//! `argv` run in the folder `cwd` through `sh`, so the folder needs no process API; `argv` itself
//! for an empty `cwd`.
def in_folder(cwd : string; argv : array<string>) : array<string> {
    var full : array<string>
    if (!empty(cwd)) {
        full |> push_from(["sh", "-c", "cd \"$0\" && exec \"$@\"", cwd])
    }
    full |> push_from(argv)
    return <- full
}

//! The folder a program's conversion in `layout` lands in under `work`: `<work>/<stem>/` for the
//! source layout, `<work>/<layout>/<stem>/` for the source-cut and the single ones.
def layout_dir(work, stem, layout : string) : string => layout == "source" ? path_join(work, stem) : path_join(path_join(work, layout), stem)

//! `text` as one word of a POSIX shell's command line: single-quoted, each quote of its own closed,
//! escaped and reopened.
def shell_word(text : string) : string => "'" + replace(text, "'", "'\\''") + "'"

//! The shell command that runs a script again as `argv` (its `get_command_line_arguments`) ran it,
//! with `extra` last among the script's arguments, so each of them wins; a `--` opens the script's
//! arguments when `argv` has none. The shell `exec`s it, so a signal that ends the process shows in
//! the status `system` returns (`process_ended`).
def rerun_command(argv, extra : array<string>) : string {
    var words <- [for (word in argv); shell_word(word)]
    if (!has_value(argv, "--")) {
        words |> push("--")
    }
    words |> push_from([for (word in extra); shell_word(word)])
    return "exec " + join(words, " ")
}

//! How a process `system` ran ended, from the wait status it returns: "" when it exited 0.
def process_ended(status : int) : string {
    if (status == -1) {
        return "could not start"
    }
    let signal = status & 0x7f
    return signal != 0 ? "was killed by signal {signal}" : (status >> 8) != 0 ? "exited {status >> 8}" : ""
}

//! The last line of `text` that is not empty.
def last_line(text : string) : string {
    let lines <- [for (l in split(text, "\n")); strip(l); where !empty(strip(l))]
    return empty(lines) ? "" : lines[length(lines) - 1]
}

//! The CPU model `/proc/cpuinfo` names, "unknown cpu" without one; `$C2DAS_CPU_NAME` when set, a
//! test's stand-in for a machine no box names, with a warning, since it changes a capture's stamps.
def cpu_name : string {
    let forced = get_env_variable("C2DAS_CPU_NAME")
    if (!empty(forced)) {
        to_log(LOG_WARNING, "C2DAS_CPU_NAME is set: the CPU is `{forced}`, not this machine's\n")
        return forced
    }
    for (line in split(fread("/proc/cpuinfo"), "\n")) {
        if (line |> starts_with("model name")) {
            let colon = find(line, ":")
            return colon < 0 ? line : strip(slice(line, colon + 1))
        }
    }
    return "unknown cpu"
}

//! The first line of the pinned clang's `--version` and of daslang's `-version`.
def tool_versions(var clang, daslang : string&) {
    clang = first_reported_line(captured([default_clang(), "--version"]))
    daslang = first_reported_line(captured([get_das_root() + "/bin/daslang", "-version"]))
}

//! The order `count` lanes, the first the native one, take their sample of the round `round` (from 0)
//! when the samples of a workload interleave, as indexes: native first (its first sample is the
//! oracle a converted lane is held to), then the other lanes forward in an even round and backward
//! in an odd one, so a drift of the machine over the rounds weighs on every converted lane alike.
def sample_order(count, round : int) : array<int> {
    var order <- [0]
    order |> reserve(count)
    for (i in range(1, count)) {
        order |> push(round % 2 == 0 ? i : count - i)
    }
    return <- order
}
