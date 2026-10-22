options gen2
// the pipeline parses clang's JSON dump below its own frames: a deep expression tree overflows
// the default 16 KB context stack, and dastest gives its tests this much
options stack = 1048576

require strings
require daslib/strings_boost
require daslib/fio
require daslib/clargs
require daslib/json_boost
require crt
require ../converter/pipeline.das
require ../converter/tiers.das
require ../converter/sidecar.das
require perf_tables
require ../suites/suite_files.das
require perf_cli
require perf_compose
require perf_lanes

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
    @clarg_doc = "the results file a run writes and --table reads (default perf/results_linux.json)"
    out : string = RESULTS
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

// one das lane of kernel `name` measured over `argv`, which it logs at `info`, into `cells`, or a line in `errors`
def measure_lane(var cells : table<string; Cell>; var errors : array<string>; name, lane : string; argv : array<string>; samples, oracle : int) {
    to_log(LOG_INFO, "{name}/{lane}: {join(argv, " ")}\n")
    var err : string
    var cell <- measure(argv, samples, err)
    accept_lane(cells, lane, cell, oracle, err)
    if (!empty(err)) {
        errors |> push("{name}/{lane}: {err}")
    }
}

//! Every lane of one kernel: the native build, the four converter tiers, and the interpreter
//! over the conversion under `--param-writes copy`.
def run_kernel(name : string; samples : int; var errors : array<string>) : table<string; Cell> {
    var cells : table<string; Cell>
    let work = path_join(WORK, name)
    let c_path = write_composed(name, work)
    let native_bin = path_join(work, "{name}_native")
    var build_out : string
    let no_libs : array<string>
    if (run_and_capture(native_build_command(c_path, native_bin, no_libs), build_out, 600.0) != 0) {
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
    measure_lane(cells, errors, name, "interp", das_lane_command(res.das_path, "", CONVERTED_MODULES), samples, oracle)
    // the same lane over the conversion under `--param-writes copy`, in its own folder
    let copied <- convert(c_path, path_join(work, "copy"), "linux", "", "", "copy")
    if (copied.ok) {
        measure_lane(cells, errors, name, "interp-copy", das_lane_command(copied.das_path, "", CONVERTED_MODULES), samples, oracle)
    } else {
        errors |> push("{name}/interp-copy: convert: {first_line(copied.error)}")
    }
    measure_lane(cells, errors, name, "jit", das_lane_command(res.das_path, "-jit", CONVERTED_MODULES), samples, oracle)
    let no_args : array<string>
    for (lane in ["exe", "aot"]) {
        var build_error : string
        let bin = lane == "exe" ? build_exe(res.das_path, work, no_args, build_error) : build_aot(res.das_path, work, no_args, build_error)
        if (empty(bin)) {
            errors |> push("{name}/{lane}: {build_error}")
        } else {
            measure_lane(cells, errors, name, lane, [bin], samples, oracle)
        }
    }
    return <- cells
}

def lane_text(cells : table<string; Cell>; lane : string) : string {
    var text = "-"
    cells |> get(lane) $(c) {
        text = cell_text(c.time, c.spread)
    }
    return text
}

def update_readme(rendered : string) : bool {
    let text = fread(README)
    let b = find(text, README_BEGIN)
    let e = find(text, README_END)
    if (b < 0 || e < 0 || e < b) {
        return false
    }
    fwrite(README, slice(text, 0, b + length(README_BEGIN)) + "\n" + rendered + slice(text, e))
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
        let js = read_json_file(args.out, error)
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
    var clang_version, daslang_version : string
    tool_versions(clang_version, daslang_version)
    var root <- {
        "cpu" => JV(cpu_name()),
        "platform" => JV("{get_platform_name()} {strip(captured(["uname", "-m"]))}"),
        "timestamp" => JV(strip(captured(["date", "-u", "+%Y-%m-%d %H:%M UTC"]))),
        "samples" => JV(args.samples),
        "versions" => JV({"clang" => JV(clang_version), "daslang" => JV(daslang_version)}),
        "lanes" => JV(LANES),
        "tests" => JV(tests)
    }
    let js = JV(root)
    fwrite(args.out, write_json(js) + "\n")
    print(show_tables(js, baseline, baseline_name, args.ratios, args.report))
    if (args.readme && !update_readme(render_results(js))) {
        to_log(LOG_ERROR, "{README} has no perf-table markers\n")
    }
    for (e in errors) {
        to_log(LOG_ERROR, "{e}\n")
    }
    return empty(errors) ? 0 : 1
}
