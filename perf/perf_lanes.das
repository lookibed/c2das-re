options gen2

module perf_lanes public

require math
require strings
require daslib/strings_boost
require daslib/fio
require ../converter/cir.das
require ../converter/tiers.das
require ../converter/dumper_a.das

//! The lanes and the sample arithmetic every timing harness shares: `perf/run.das` over the
//! kernels and `ports/publish.das` over a ported program's workloads. Each lane is built here
//! once (perf/ARCHITECTURE.md section 2), so both harnesses time the same native build, the same
//! daslang invocations and the same exe and AOT builds. A cell is the median of its samples, with
//! the spread as half the sample range over that median.

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
//! with `program_args`; "" with `error` set when the build leaves none. The tiers return the
//! build's exit code when the build fails, which passes for a run's, so a lane stands only on the
//! binary its build left; an earlier run's goes first. The build and the run it ends with each get
//! `timeout` seconds; a timed-out run leaves a binary but no lane. The run is `guarded` under
//! `address_space` bytes, so a program that crashes there dumps no core either.
def lane_binary(das_path, tier, work : string; module_dirs, program_args : array<string>; var error : string&; timeout : float; address_space : int64 = 0l) : string {
    let bin = tier == "aot" ? aot_binary(das_path, work) : path_join(work, "{file_stem(das_path)}_exe")
    remove(bin)
    remove(bin + ".exe")
    var out : string
    let no_flags, no_program : array<string>
    let rc = run_tier(das_path, tier, work, out, module_dirs, timeout, no_flags, program_args, guarded(no_program, address_space))
    if (rc == popen_timed_out) {
        error = "the build or its run took longer than {int(timeout)} s"
        return ""
    }
    let built = fexist(bin + ".exe") ? bin + ".exe" : bin
    if (rc >= 0 && fexist(built)) {
        return built
    }
    // the tier refused before any build ran: its text is the reason
    if (rc == -1) {
        error = first_reported_line(out)
        return ""
    }
    let line = tier == "exe" ? exe_build_line(out) : aot_build_line(out)
    error = "the build exited {rc} and left no binary: {line}"
    return ""
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

//! The last line of `text` that is not empty.
def last_line(text : string) : string {
    let lines <- [for (l in split(text, "\n")); strip(l); where !empty(strip(l))]
    return empty(lines) ? "" : lines[length(lines) - 1]
}

//! The median of `values`, 0 for none.
def median_of(values : array<double>) : double {
    var sorted := values
    sorted |> sort()
    let n = length(sorted)
    return n == 0 ? 0.0lf : (n & 1) == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) * 0.5lf
}

//! Half the range of `samples` as a share of `median`, 0 when there are none or the median is 0.
def spread_of(samples : array<double>; median : double) : double {
    if (empty(samples) || median <= 0.0lf) {
        return 0.0lf
    }
    var lo = samples[0]
    var hi = samples[0]
    for (s in samples) {
        lo = min(lo, s)
        hi = max(hi, s)
    }
    return (hi - lo) * 0.5lf / median
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
