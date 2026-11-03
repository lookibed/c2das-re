options gen2
// the pipeline parses clang's JSON dump below its own frames: a deep expression tree overflows
// the default 16 KB context stack, and dastest gives its tests this much
options stack = 1048576

require strings
require daslib/strings_boost
require daslib/fio
require daslib/clargs
require daslib/json_boost
require ../converter/pipeline.das
require ../converter/tiers.das
require ../converter/sidecar.das
require perf_tables
require boxes
require ../suites/suite_files.das
require perf_cli
require perf_compose
require perf_lanes
require perf_measure

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
//! the dasProfile method's capture, and dasProfile's own capture from this machine beside it
let METHOD_RESULTS = "perf/results_method_linux.json"
let DASPROFILE_RESULTS = "perf/dasprofile_linux.json"
let README = "README.md"
//! the methods a run measures by: this tree's (`composed_source`) and dasProfile's
//! (`composed_method_source`), over the kernels both repositories share
let METHODS <- ["default", "dasprofile"]

[CommandLineArgs]
struct Args {
    @clarg_doc = "run only the kernels whose name contains this text"
    filter : string = ""
    @clarg_doc = "samples per lane, each its own process (default 5)"
    samples : int = 5
    @clarg_name = "table"
    @clarg_doc = "render the table from the stored results instead of measuring"
    show_table : bool
    @clarg_doc = "rewrite the method's section of README.md from the run, or under --table from the stored capture"
    readme : bool
    @clarg_doc = "print the lane time / native table after the results"
    ratios : bool
    @clarg_doc = "the capture the delta compares against (default: the method's committed capture at HEAD)"
    baseline : string = ""
    @clarg_doc = "write the results, ratio and delta tables as one markdown block to this file"
    report : string = ""
    @clarg_doc = "the results file a run writes and --table reads (default perf/results_linux.json, under --method dasprofile perf/results_method_linux.json)"
    out : string = ""
    @clarg_doc = "default (this tree's harness, every kernel) or dasprofile (dasProfile's harness and its kernels in C, perf/kernels/dasprofile: noinline kernel functions, volatile sink, steady clock)"
    method : string = "default"
    @clarg_doc = "the box the run measures on, bench, PC or fx (default: the box of the CPU model, none for another CPU)"
    box : string = ""
    @clarg_doc = "exit 1 when a cell drifts from the baseline past --tolerance either way, or one capture lacks a cell the other has"
    check : bool
    @clarg_doc = "the --check bar in percent (default 10, the FLAG rule's)"
    tolerance : int = 10
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
}

//! Every lane of one kernel under the default method: the native build, the four converter tiers,
//! and the interpreter over the conversions under `--param-writes copy`, `--loops while` and
//! `--first-member reinterpret`.
def run_kernel(name : string; samples : int; var errors : array<string>) : table<string; Cell> {
    var cells : table<string; Cell>
    let work = path_join(WORK, name)
    let c_path = write_composed(name, work)
    let no_libs : array<string>
    var oracle = 0
    if (!measure_native(cells, errors, name, c_path, work, no_libs, samples, oracle)) {
        return <- cells
    }
    let res <- convert(c_path, work, "linux")
    if (!res.ok) {
        errors |> push("{name}/convert: {first_line(res.error)}")
        return <- cells
    }
    measure_lane(cells, errors, name, "interp", das_lane_command(res.das_path, "", CONVERTED_MODULES), samples, oracle)
    // the same lane over the conversions under the non-default options, each in its own folder
    for (lane, sub, param_writes, loops, first_member in ["interp-copy", "interp-while", "interp-reinterpret"], ["copy", "while", "reinterpret"], ["copy", "", ""], ["", "while", ""], ["", "", "reinterpret"]) {
        let other <- convert(c_path, path_join(work, sub), "linux", "", "", param_writes, loops, first_member)
        if (other.ok) {
            measure_lane(cells, errors, name, lane, das_lane_command(other.das_path, "", CONVERTED_MODULES), samples, oracle)
        } else {
            errors |> push("{name}/{lane}: convert: {first_line(other.error)}")
        }
    }
    measure_tiers(cells, errors, name, res.das_path, work, samples, oracle)
    return <- cells
}

//! Every lane of one kernel under the dasProfile method: the method's program built natively with
//! its clock's C body, and its conversion under the four tiers, in `work/<kernel>/method`.
def run_method_kernel(name : string; samples : int; var errors : array<string>) : table<string; Cell> {
    var cells : table<string; Cell>
    let work = path_join(path_join(WORK, name), "method")
    let c_path = write_method_composed(name, work)
    var oracle = 0
    if (!measure_native(cells, errors, name, c_path, work, [METHOD_NATIVE_DEFINE], samples, oracle)) {
        return <- cells
    }
    let res <- convert(c_path, work, "linux")
    if (!res.ok) {
        errors |> push("{name}/convert: {first_line(res.error)}")
        return <- cells
    }
    measure_lane(cells, errors, name, "interp", das_lane_command(res.das_path, "", CONVERTED_MODULES), samples, oracle)
    measure_tiers(cells, errors, name, res.das_path, work, samples, oracle)
    return <- cells
}

// the stored capture `out` rendered, by `--table`; under the dasProfile method the comparison
// too; with `--readme` the method's README.md section rewritten from it
def show_stored(args : Args; out : string; baseline : JsonValue?; baseline_name : string) : int {
    var error : string
    let js = read_json_file(out, error)
    if (js == null) {
        to_log(LOG_ERROR, "{error}\n")
        return 1
    }
    print(show_tables(js, baseline, baseline_name, args.ratios, args.report))
    if (args.method == "dasprofile") {
        let section = readme_section(js, args.method, DASPROFILE_RESULTS, error)
        print(empty(section) ? "{error}\n" : "\n{section}")
    }
    if (args.readme) {
        log_error(write_readme(README, DASPROFILE_RESULTS, js, args.method))
    }
    return 0
}

// every kernel the run names measured by the method's lanes, one JSON row per kernel
def measure_kernels(args : Args; lanes : array<string>; var errors : array<string>) : table<string; JsonValue?> {
    let by_dasprofile = args.method == "dasprofile"
    let names <- kernel_ids(args.method, args.filter)
    var tests : table<string; JsonValue?>
    for (name in names) {
        var inscope cells <- by_dasprofile ? run_method_kernel(name, args.samples, errors) : run_kernel(name, args.samples, errors)
        var row <- {for (lane, cell in keys(cells), values(cells)); lane => JV((time = cell.time, spread = cell.spread, count = cell.count, result = cell.result, samples = JV(cell.samples)))}
        tests[name] = JV(row)
        to_log(LOG_INFO, "{name}: " + join([for (lane in lanes); "{lane} {lane_text(cells, lane)}"], ", ") + "\n")
    }
    return <- tests
}

// the capture of a run: the machine and its box, the versions, the method, its lanes and the rows
def capture_of(args : Args; lanes : array<string>; var tests : table<string; JsonValue?>) : JsonValue? {
    var clang_version, daslang_version : string
    tool_versions(clang_version, daslang_version)
    let cpu = cpu_name()
    var root <- {
        "cpu" => JV(cpu),
        "box" => JV(capture_box(args.box, cpu)),
        "platform" => JV("{get_platform_name()} {strip(captured(["uname", "-m"]))}"),
        "timestamp" => JV(strip(captured(["date", "-u", "+%Y-%m-%d %H:%M UTC"]))),
        "samples" => JV(args.samples),
        "method" => JV(args.method),
        "versions" => JV({"clang" => JV(clang_version), "daslang" => JV(daslang_version)}),
        "lanes" => JV(lanes),
        "tests" => JV(tests)
    }
    return JV(root)
}

// `error` logged, when there is one
def log_error(error : string) {
    if (!empty(error)) {
        to_log(LOG_ERROR, "{error}\n")
    }
}

[export]
def main : int {
    var args = Args()
    let parsed = cli_prologue(args, "run_perf")
    if (parsed >= 0) {
        return parsed
    }
    if (!has_value(METHODS, args.method)) {
        to_log(LOG_ERROR, "--method is default or dasprofile, not `{args.method}`\n")
        return 2
    }
    let refusal = box_refusal(args.box)
    if (!empty(refusal)) {
        to_log(LOG_ERROR, "{refusal}\n")
        return 2
    }
    let committed = args.method == "dasprofile" ? METHOD_RESULTS : RESULTS
    let out = empty(args.out) ? committed : args.out
    var baseline_name, error : string
    let baseline = baseline_capture(args.baseline, committed, baseline_name, error)
    if (!empty(error)) {
        to_log(LOG_ERROR, "{error}\n")
        return 1
    }
    if (args.show_table) {
        return show_stored(args, out, baseline, baseline_name)
    }
    let lanes <- args.method == "dasprofile" ? [for (lane in METHOD_LANES); lane] : [for (lane in LANES); lane]
    var errors : array<string>
    var tests <- measure_kernels(args, lanes, errors)
    let js = capture_of(args, lanes, tests)
    fwrite(out, write_json(js) + "\n")
    print(show_tables(js, baseline, baseline_name, args.ratios, args.report))
    if (args.readme) {
        log_error(write_readme(README, DASPROFILE_RESULTS, js, args.method))
    }
    for (e in errors) {
        to_log(LOG_ERROR, "{e}\n")
    }
    // `--check` asks whether the run reproduces the baseline: a lane error the baseline shares
    // (a cell both lack) reproduces it, a new one is a missing cell
    if (args.check) {
        return check_drift(js, baseline, baseline_name, args.tolerance) ? 0 : 1
    }
    return empty(errors) ? 0 : 1
}
