options gen2
// the pipeline parses clang's JSON dump below its own frames: a deep expression tree overflows
// the default 16 KB context stack, and dastest gives its tests this much
options stack = 1048576

require strings
require math
require daslib/strings_boost
require daslib/fio
require daslib/clargs
require daslib/json_boost
require crt
require ../converter/pipeline.das
require ../converter/tiers.das
require ../converter/dumper_a.das
require ../converter/sidecar.das
require perf_tables
require ../suites/suite_files.das
require perf_cli
require perf_compose

//! The performance comparison of docs/very-detailed-plan.md section 2, measured the way
//! borisbat/dasProfile measures: every kernel under perf/kernels/<name>.c is composed with
//! the profile prologue and epilogue into one C file, built natively by the pinned clang at
//! -O3, the optimization dasProfile's Release build gives its C++ kernels, and converted by the pipeline, and each lane runs it as its own process SAMPLES times;
//! the program itself runs the kernel as many times as fit the budget and prints the per-run
//! seconds, so startup never enters a cell, and its result, which the native lane sets as the
//! oracle every das lane must reproduce. A cell is the median, ± half the range as a share
//! of it. Run from the repository root through scripts/run_perf.sh.

let WORK = "perf/work"
let RESULTS = "perf/results_linux.json"
let README = "README.md"
let README_BEGIN = "<!-- perf-table:begin -->"
let README_END = "<!-- perf-table:end -->"

[CommandLineArgs]
struct Args {
    @clarg_doc = "run only the kernels whose name contains this text"
    filter : string = ""
    @clarg_doc = "samples per lane, each its own process (default 5)"
    samples : int = 5
    @clarg_name = "table"
    @clarg_doc = "render the table from the stored results instead of measuring"
    show_table : bool
    @clarg_doc = "rewrite the perf table section of README.md after measuring"
    readme : bool
    @clarg_doc = "print the lane time / native table after the results"
    ratios : bool
    @clarg_doc = "the capture the delta compares against (default: perf/results_linux.json at HEAD)"
    baseline : string = ""
    @clarg_doc = "write the results, ratio and delta tables as one markdown block to this file"
    report : string = ""
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
}

struct Cell {
    time : double
    spread : double
    count : int64
    result : int
    samples : array<double>
}

def first_line(text : string) : string {
    let nl = find(text, "\n")
    return nl < 0 ? text : slice(text, 0, nl)
}

def captured(args : array<string>) : string {
    var out : string
    run_and_capture(args, out, 600.0)
    return out
}

// the kernel's line is the last one: a tier may log before the program runs
def last_line(text : string) : string {
    let lines <- [for (l in split(text, "\n")); strip(l); where !empty(strip(l))]
    return empty(lines) ? "" : lines[length(lines) - 1]
}

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

def median_of(values : array<double>) : double {
    var sorted := values
    sorted |> sort()
    let n = length(sorted)
    return n == 0 ? 0.0lf : (n & 1) == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) * 0.5lf
}

def cell_of(samples : array<double>; count : int64; result : int) : Cell {
    var c = Cell(time = median_of(samples), count = count, result = result)
    if (!empty(samples)) {
        var lo = samples[0]
        var hi = samples[0]
        for (s in samples) {
            lo = min(lo, s)
            hi = max(hi, s)
        }
        c.spread = c.time > 0.0lf ? (hi - lo) * 0.5lf / c.time : 0.0lf
    }
    c.samples := samples
    return <- c
}

//! `samples` launches of `argv`, each a process; the kernel's own line gives the per-run time.
def measure(argv : array<string>; samples : int; var error : string&) : Cell {
    var times : array<double>
    var count = 0l
    var result = 0
    times |> reserve(samples)
    for (_s in range(samples)) {
        var out : string
        let rc = run_and_capture(argv, out, 600.0)
        var seconds = 0.0lf
        var sample_result = 0
        if (rc != 0 || !parse_sample(out, seconds, count, sample_result)) {
            error = "exited {rc}: {first_line(out)}"
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

//! Every lane of one kernel: the native build and the four converter tiers.
def run_kernel(name : string; samples : int; var errors : array<string>) : table<string; Cell> {
    var cells : table<string; Cell>
    let work = path_join(WORK, name)
    let c_path = write_composed(name, work)
    let native_bin = path_join(work, "{name}_native")
    var build_out : string
    if (run_and_capture([default_clang(), "-O3", "-w", "-funsigned-char", "-o", native_bin, c_path], build_out, 600.0) != 0) {
        errors |> push("{name}/native: {first_line(build_out)}")
        return <- cells
    }
    var native_err : string
    var native <- measure([native_bin], samples, native_err)
    if (!empty(native_err)) {
        errors |> push("{name}/native: {native_err}")
        return <- cells
    }
    let oracle = native.result
    cells["native"] <- native
    let res <- convert(c_path, work, "linux")
    if (!res.ok) {
        errors |> push("{name}/convert: {first_line(res.error)}")
        return <- cells
    }
    let daslang = get_das_root() + "/bin/daslang"
    var loader : array<string>
    loader |> reserve(2 * length(CONVERTED_MODULES))
    for (dir in CONVERTED_MODULES) {
        loader |> push("-load_module")
        loader |> push(dir)
    }
    var err : string
    var interp <- measure(with_binary_first(daslang, loader, "", res.das_path), samples, err)
    accept_lane(cells, "interp", interp, oracle, err)
    if (!empty(err)) {
        errors |> push("{name}/interp: {err}")
    }
    err = ""
    var jit <- measure(with_binary_first(daslang, loader, "-jit", res.das_path), samples, err)
    accept_lane(cells, "jit", jit, oracle, err)
    if (!empty(err)) {
        errors |> push("{name}/jit: {err}")
    }
    var tier_out : string
    if (run_tier(res.das_path, "exe", work, tier_out, CONVERTED_MODULES) >= 0) {
        let exe = path_join(work, "{name}_exe")
        let built = fexist(exe + ".exe") ? exe + ".exe" : exe
        err = ""
        var exe_cell <- measure([built], samples, err)
        accept_lane(cells, "exe", exe_cell, oracle, err)
        if (!empty(err)) {
            errors |> push("{name}/exe: {err}")
        }
    } else {
        errors |> push("{name}/exe: {first_line(tier_out)}")
    }
    tier_out = ""
    if (run_tier(res.das_path, "aot", work, tier_out, CONVERTED_MODULES) >= 0) {
        let bin = path_join(path_join(work, "ctx"), "{name}_aot")
        err = ""
        var aot_cell <- measure([bin], samples, err)
        accept_lane(cells, "aot", aot_cell, oracle, err)
        if (!empty(err)) {
            errors |> push("{name}/aot: {err}")
        }
    } else {
        errors |> push("{name}/aot: {first_line(tier_out)}")
    }
    return <- cells
}

def with_binary_first(daslang : string; loader : array<string>; flag : string; script : string) : array<string> {
    var argv <- [daslang]
    let tail <- empty(flag) ? [script] : [flag, script]
    argv |> push_from(loader, tail)
    return <- argv
}

def cpu_name : string {
    for (line in split(fread_text("/proc/cpuinfo"), "\n")) {
        if (line |> starts_with("model name")) {
            let colon = find(line, ":")
            return colon < 0 ? line : strip(slice(line, colon + 1))
        }
    }
    return "unknown cpu"
}

def lane_text(cells : table<string; Cell>; lane : string) : string {
    var text = "-"
    cells |> get(lane) $(c) {
        text = cell_text(c.time, c.spread)
    }
    return text
}

def update_readme(rendered : string) : bool {
    let text = fread_text(README)
    let b = find(text, README_BEGIN)
    let e = find(text, README_END)
    if (b < 0 || e < 0 || e < b) {
        return false
    }
    write_text(README, slice(text, 0, b + length(README_BEGIN)) + "\n" + rendered + slice(text, e))
    return true
}

[export]
def main : int {
    var args = Args()
    let parsed = cli_prologue(args, "run_perf")
    if (parsed >= 0) {
        return parsed
    }
    var baseline_name, error : string
    let baseline = baseline_capture(args.baseline, RESULTS, baseline_name, error)
    if (!empty(error)) {
        to_log(LOG_ERROR, "{error}\n")
        return 1
    }
    if (args.show_table) {
        let js = read_json_file(RESULTS, error)
        if (js == null) {
            to_log(LOG_ERROR, "{error}\n")
            return 1
        }
        print(show_tables(js, baseline, baseline_name, args.ratios, args.report))
        return 0
    }
    let names <- c_file_ids(KERNELS, args.filter)
    var errors : array<string>
    var tests : table<string; JsonValue?>
    for (name in names) {
        var inscope cells <- run_kernel(name, args.samples, errors)
        var row <- {for (lane, cell in keys(cells), values(cells)); lane => JV((time = cell.time, spread = cell.spread, count = cell.count, result = cell.result, samples = JV(cell.samples)))}
        tests[name] = JV(row)
        to_log(LOG_INFO, "{name}: " + join([for (lane in LANES); "{lane} {lane_text(cells, lane)}"], ", ") + "\n")
    }
    var root <- {
        "cpu" => JV(cpu_name()),
        "platform" => JV("{get_platform_name()} {strip(captured(["uname", "-m"]))}"),
        "timestamp" => JV(strip(captured(["date", "-u", "+%Y-%m-%d %H:%M UTC"]))),
        "samples" => JV(args.samples),
        "versions" => JV({"clang" => JV(first_line(captured([default_clang(), "--version"]))), "daslang" => JV(first_line(captured([get_das_root() + "/bin/daslang", "-version"])))}),
        "lanes" => JV(LANES),
        "tests" => JV(tests)
    }
    let js = JV(root)
    write_text(RESULTS, write_json(js) + "\n")
    print(show_tables(js, baseline, baseline_name, args.ratios, args.report))
    if (args.readme && !update_readme(render_results(js))) {
        to_log(LOG_ERROR, "{README} has no perf-table markers\n")
    }
    for (e in errors) {
        to_log(LOG_ERROR, "{e}\n")
    }
    return empty(errors) ? 0 : 1
}
