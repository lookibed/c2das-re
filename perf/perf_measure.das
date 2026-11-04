options gen2

module perf_measure public

require strings
require daslib/strings_boost
require daslib/fio
require crt
require ../converter/tiers.das
require ../suites/suite_files.das
require perf_tables
require perf_lanes

//! A timed lane's samples and its cell: each sample is one process whose last line is the
//! kernel's `<seconds per run> <runs> <result>`, a cell their median with the spread, and a das
//! lane's cell stands only with the native lane's result (perf/ARCHITECTURE.md section 2).

struct Cell {
    time : double
    spread : double
    count : int64
    result : int
    samples : array<double>
}

//! the seconds a sample may take
let SAMPLE_TIMEOUT = 600.0

//! The seconds a das lane's sample and its `exe` or `aot` build (with the run it ends with) may take,
//! and the bytes of address space a guarded run of it may map, 0 for no cap.
struct LaneLimits {
    sample : float
    build : float
    address_space : int64
}

//! the perf harness's limits
let PERF_LIMITS = LaneLimits(sample = SAMPLE_TIMEOUT, build = BUILD_TIMEOUT)

// the kernel's line is the last one: a tier may log before the program runs
def parse_sample(out : string; var seconds : double&; var reps : int64&; var result : int&) : bool {
    let fields <- split(last_line(out), " ")
    if (length(fields) != 3) {
        return false
    }
    let digits = unsafe(reinterpret<uint8?>(fields[0]))
    seconds = unsafe(crt::strtod(digits, null))
    reps = to_int64(fields[1], false)
    result = to_int(fields[2], false)
    return seconds > 0.0lf
}

def cell_of(samples : array<double>; count : int64; result : int) : Cell {
    var c = Cell(time = median_of(samples), count = count, result = result)
    c.spread = spread_of(samples, c.time)
    c.samples := samples
    return <- c
}

//! `samples` launches of `argv`, each a process; the kernel's own line gives the per-run time.
def measure(argv : array<string>; samples : int; var error : string&) : Cell => measure(argv, samples, error, SAMPLE_TIMEOUT)

//! `measure` with `timeout` seconds per sample, each sample `guarded` with no address-space cap; a
//! sample past the timeout is the error, as is one that fails (`run_error`).
def measure(argv : array<string>; samples : int; var error : string&; timeout : float) : Cell {
    var times : array<double>
    var count = 0l
    var result = 0
    times |> reserve(samples)
    for (_s in range(samples)) {
        var out : string
        let rc = run_and_capture(guarded(argv, 0l), out, timeout)
        var seconds = 0.0lf
        var sample_result = 0
        if (rc == popen_timed_out) {
            error = "a sample took longer than {int(timeout)} s"
            break
        }
        if (rc != 0 || !parse_sample(out, seconds, count, sample_result)) {
            error = run_error(rc, out)
            break
        }
        if (!empty(times) && sample_result != result) {
            error = "result {sample_result} differs from the first sample's {result}"
            break
        }
        result = sample_result
        times |> push(seconds)
    }
    return <- cell_of(times, count, result)
}

// a das lane's cell stands only with the native result: a kernel that computes something
// else measures something else
def accept_lane(var cells : table<string; Cell>; lane : string; var cell : Cell; oracle : int; var err : string&) {
    if (empty(err) && cell.result != oracle) {
        err = "result {cell.result} differs from the native {oracle}"
    }
    if (empty(err)) {
        cells[lane] <- cell
    }
}

// one das lane of kernel `name` measured over `argv`, which it logs at `info`, into `cells`, or a line in `errors`
def measure_lane(var cells : table<string; Cell>; var errors : array<string>; name, lane : string; argv : array<string>; samples, oracle : int) {
    measure_lane(cells, errors, name, lane, argv, samples, oracle, SAMPLE_TIMEOUT)
}

//! `measure_lane` with `timeout` seconds per sample.
def measure_lane(var cells : table<string; Cell>; var errors : array<string>; name, lane : string; argv : array<string>; samples, oracle : int; timeout : float) {
    to_log(LOG_INFO, "{name}/{lane}: {join(argv, " ")}\n")
    var err : string
    var cell <- measure(argv, samples, err, timeout)
    accept_lane(cells, lane, cell, oracle, err)
    if (!empty(err)) {
        errors |> push("{name}/{lane}: {err}")
    }
}

// the native lane of `c_path` built into `work` with `extra` after the file, its result the
// `oracle` every das lane must reproduce: false, with the line in `errors`, when the build or a
// sample fails
def measure_native(var cells : table<string; Cell>; var errors : array<string>; name, c_path, work : string; extra : array<string>; samples : int; var oracle : int&) : bool {
    let native_bin = path_join(work, "{name}_native")
    var build_out : string
    if (run_and_capture(native_build_command([c_path], native_bin, extra), build_out, 600.0) != 0) {
        errors |> push("{name}/native: {first_line(build_out)}")
        return false
    }
    var native_err : string
    var native <- measure([native_bin], samples, native_err)
    if (!empty(native_err)) {
        errors |> push("{name}/native: {native_err}")
        return false
    }
    oracle = native.result
    cells["native"] <- native
    return true
}

// the JIT, exe and AOT lanes of the converted `das_path`
def measure_tiers(var cells : table<string; Cell>; var errors : array<string>; name, das_path, work : string; samples, oracle : int) {
    measure_tiers(cells, errors, name, das_path, work, CONVERTED_MODULES, samples, oracle, PERF_LIMITS)
}

//! The JIT lane with `module_dirs` loaded, and the exe and AOT lanes, of `das_path`, under `limits`.
def measure_tiers(var cells : table<string; Cell>; var errors : array<string>; name, das_path, work : string; module_dirs : array<string>; samples, oracle : int; limits : LaneLimits) {
    measure_lane(cells, errors, name, "jit", das_lane_command(das_path, "-jit", module_dirs), samples, oracle, limits.sample)
    let no_args : array<string>
    for (lane in ["exe", "aot"]) {
        var build_error : string
        let bin = lane == "exe" ? build_exe(das_path, work, no_args, build_error, limits.build) : build_aot(das_path, work, no_args, build_error, limits.build)
        if (empty(bin)) {
            errors |> push("{name}/{lane}: {build_error}")
        } else {
            measure_lane(cells, errors, name, lane, [bin], samples, oracle, limits.sample)
        }
    }
}

def lane_text(cells : table<string; Cell>; lane : string) : string {
    var text = "-"
    cells |> get(lane) $(c) {
        text = cell_text(c.time, c.spread)
    }
    return text
}
