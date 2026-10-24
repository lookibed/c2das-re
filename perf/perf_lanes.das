options gen2

module perf_lanes public

require math
require strings
require daslib/strings_boost
require daslib/fio
require ../converter/pipeline.das
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

// the `exe` and `aot` tiers return the build's exit code when the build fails, which passes for a
// run's, so a lane stands only on the binary its build left; an earlier run's goes first. The
// build and the run it ends with each get `BUILD_TIMEOUT` seconds
def private built_binary(das_path, tier, work, bin : string; program_args : array<string>; var error : string&) : string {
    remove(bin)
    remove(bin + ".exe")
    var out : string
    let no_flags : array<string>
    let rc = run_tier(das_path, tier, work, out, CONVERTED_MODULES, BUILD_TIMEOUT, no_flags, program_args)
    let built = fexist(bin + ".exe") ? bin + ".exe" : bin
    if (rc >= 0 && fexist(built)) {
        return built
    }
    // the tier refused before any build ran: its text is the reason
    if (rc == -1) {
        error = first_reported_line(out)
        return ""
    }
    // the exe build's linker message follows daslang's `Output:` line; the AOT host build's ends
    // the output
    let line = tier == "exe" ? exe_build_line(out) : last_line(out)
    error = "the build exited {rc} and left no binary: {line}"
    return ""
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
def build_exe(das_path, work : string; program_args : array<string>; var error : string&) : string => built_binary(das_path, "exe", work, path_join(work, "{file_stem(das_path)}_exe"), program_args, error)

//! The `aot` lane's binary of `das_path`: the `-ctx` context and the host `converter/tiers.das`
//! writes, compiled by the pinned clang++ at `-O3` in `work/ctx`; "" with `error` set when the
//! build leaves none or the tier refuses `program_args`.
def build_aot(das_path, work : string; program_args : array<string>; var error : string&) : string => built_binary(das_path, "aot", work, aot_binary(das_path, work), program_args, error)

//! The merged stdout and stderr of `args`, whatever its exit code.
def captured(args : array<string>) : string {
    var out : string
    run_and_capture(args, out, 600.0)
    return out
}

//! The first line of `text` that is not empty and not an `info` line (`[I] `).
def first_reported_line(text : string) : string {
    for (l in split(text, "\n")) {
        let line = strip(l)
        if (!empty(line) && !(line |> starts_with("[I] "))) {
            return line
        }
    }
    return ""
}

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

//! The CPU model `/proc/cpuinfo` names, "unknown cpu" without one.
def cpu_name : string {
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
