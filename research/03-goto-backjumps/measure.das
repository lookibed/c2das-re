options gen2
// the pipeline parses clang's JSON dump below its own frames (perf/audit_lua.das)
options stack = 1048576
require strings
require daslib/fio
require daslib/clargs
require daslib/json_boost
require ../../converter/pipeline.das
require ../../converter/tiers.das
require ../../converter/cir.das
require ../../perf/perf_compose.das
require ../../perf/perf_lanes.das
require ../../perf/perf_measure.das

//! research 03: one kernel composed by the dasProfile method, built natively (the oracle),
//! converted and timed under the interpreter and the JIT; then every hand-written `.das`
//! named by --hand timed the same way against the oracle. Run from the repository root.

let KERNELS = "research/03-goto-backjumps/kernels"
let WORK = "research/03-goto-backjumps/work"
let LANE_TIMEOUT = 120.0

[CommandLineArgs]
struct Args {
    @clarg_doc = "the kernel under kernels/ (default exec_backjump)"
    kernel : string = "exec_backjump"
    @clarg_doc = "samples per lane (default 5)"
    samples : int = 5
    @clarg_doc = "a hand-written module to time beside the conversion; repeatable"
    hand : array<string>
    @clarg_doc = "skip the native build and the conversion: --oracle gives the result"
    oracle : int = 0
    @clarg_doc = "where the capture goes (default work/<kernel>.json)"
    out : string = ""
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
}

def cell_json(cell : Cell) : JsonValue? => JV((time = cell.time, spread = cell.spread, count = cell.count, result = cell.result, samples = JV(cell.samples)))

def tier_cells(name, das_path : string; samples, oracle : int) : table<string; JsonValue?> {
    var out : table<string; JsonValue?>
    for (lane, flag in ["interp", "jit"], ["", "-jit"]) {
        var inscope cells : table<string; Cell>
        var errors : array<string>
        measure_lane(cells, errors, name, lane, das_lane_command(das_path, flag, CONVERTED_MODULES), samples, oracle, LANE_TIMEOUT)
        var entry : JsonValue?
        cells |> get(lane) $(c) {
            entry = cell_json(c)
        }
        out[lane] = entry != null ? entry : JV({"error" => JV(empty(errors) ? "not measured" : errors[0])})
        let shown = entry != null ? "{cells[lane].time}" : errors[0]
        to_log(LOG_INFO, "{name} {lane}: {shown}\n")
    }
    return <- out
}

[export]
def main : int {
    var args = Args()
    let parsed = cli_prologue(args, "measure")
    if (parsed >= 0) {
        return parsed
    }
    let work = path_join(WORK, args.kernel)
    var entry : table<string; JsonValue?>
    var oracle = args.oracle
    if (oracle == 0) {
        mkdir_rec(work)
        let c_path = write_method_composed(KERNELS, args.kernel, work)
        var inscope native_cells : table<string; Cell>
        var errors : array<string>
        if (!measure_native(native_cells, errors, args.kernel, c_path, work, [METHOD_NATIVE_DEFINE], args.samples, oracle)) {
            to_log(LOG_ERROR, "native: {errors[0]}\n")
            return 1
        }
        entry["native"] = cell_json(native_cells["native"])
        to_log(LOG_INFO, "native: {native_cells["native"].time} result {oracle}\n")
        let res <- convert(c_path, work, "linux")
        if (!res.ok) {
            to_log(LOG_ERROR, "convert: {res.error}\n")
            return 1
        }
        to_log(LOG_INFO, "converted: {res.das_path}\n")
        entry["converted"] = JV(tier_cells(args.kernel, res.das_path, args.samples, oracle))
    }
    for (h in args.hand) {
        entry[file_stem(h)] = JV(tier_cells(file_stem(h), h, args.samples, oracle))
    }
    let out = empty(args.out) ? path_join(WORK, args.kernel + ".json") : args.out
    fwrite(out, write_json(JV(entry)))
    to_log(LOG_INFO, "written {out}\n")
    return 0
}
