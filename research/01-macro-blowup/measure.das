options gen2
options stack = 1048576

require strings
require daslib/strings_boost
require daslib/fio
require daslib/clargs
require daslib/json_boost
require ../../converter/pipeline.das
require ../../converter/tiers.das
require ../../perf/perf_compose.das
require ../../perf/perf_lanes.das
require ../../perf/perf_measure.das

//! research 01 (macro blowup): one kernel of `kernels/` composed by the dasProfile method, built
//! natively, converted, and timed under the interpreter and the JIT as converted and as the
//! hand-edited helper-call module `<name>_helper.das` beside this script spells it. Run from the
//! repository root with both module folders loaded.

let KERNELS = "research/01-macro-blowup/kernels"
let WORK = "out/research01"
let HELPERS = "research/01-macro-blowup"
let TIMEOUT = 120.0

[CommandLineArgs]
struct Args {
    @clarg_doc = "the kernel to measure (a file stem of kernels/)"
    kernel : string = ""
    @clarg_doc = "samples per lane (default 5)"
    samples : int = 5
    @clarg_doc = "only compose and convert, print the converted module's path"
    convert_only : bool
    @clarg_doc = "the hand-edited spellings to time, `<kernel>_<suffix>.das` beside this script (comma list)"
    variants : string = "helper,outer,expr,inline"
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
}

def private lane(name, lane : string; argv : array<string>; samples, oracle : int) : string {
    var inscope cells : table<string; Cell>
    var errors : array<string>
    measure_lane(cells, errors, name, lane, argv, samples, oracle, TIMEOUT)
    var out = empty(errors) ? "" : "error: {errors[0]}"
    cells |> get(lane) $(c) {
        out = "{c.time}"
    }
    return out
}

def private tiers(name, das_path : string; samples, oracle : int) : string {
    var out = ""
    for (ln, flag in ["interp", "jit"], ["", "-jit"]) {
        out += "{name} {ln} {lane(name, ln, das_lane_command(das_path, flag, CONVERTED_MODULES), samples, oracle)}\n"
    }
    return out
}

[export]
def main : int {
    var args = Args()
    let parsed = cli_prologue(args, "measure")
    if (parsed >= 0) {
        return parsed
    }
    let work = path_join(WORK, args.kernel)
    mkdir(WORK)
    let c_path = write_method_composed(KERNELS, args.kernel, work)
    let res <- convert(c_path, work, "linux")
    if (!res.ok) {
        print("convert failed: {res.error}\n")
        return 1
    }
    print("converted: {res.das_path}\n")
    if (args.convert_only) {
        return 0
    }
    var inscope native_cells : table<string; Cell>
    var errors : array<string>
    var oracle = 0
    if (!measure_native(native_cells, errors, args.kernel, c_path, work, [METHOD_NATIVE_DEFINE], args.samples, oracle)) {
        print("native failed: {errors[0]}\n")
        return 1
    }
    print("{args.kernel} native {native_cells["native"].time} result {oracle}\n")
    print(tiers("{args.kernel} converted", res.das_path, args.samples, oracle))
    for (suffix in split(args.variants, ",")) {
        let alt = path_join(HELPERS, "{args.kernel}_{suffix}.das")
        if (stat(alt).is_valid) {
            print(tiers("{args.kernel} {suffix}", alt, args.samples, oracle))
        }
    }
    return 0
}
