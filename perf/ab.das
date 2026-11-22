options gen2

require daslib/fio
require daslib/clargs
require ../converter/pipeline.das
require ab_band

//! The A/B decision of `ab_band.das` over a batch file (perf/ARCHITECTURE_SAMPLES.md section 6):
//! `daslang perf/ab.das -- --file <batch> --arm <arm> --base <arm> [--value work_s] [--cells]`.

[CommandLineArgs]
struct AbArgs {
    @clarg_doc = "the batch: one line per run with bench=, lane=, arm= and the value's key=value fields"
    file : string = ""
    @clarg_doc = "the arm whose knob is decided"
    arm : string = ""
    @clarg_doc = "the arm it is measured against"
    base : string = ""
    @clarg_doc = "the key of the timed value, in seconds (default work_s)"
    value : string = "work_s"
    @clarg_doc = "also print each cell's median, its spreads and its left-out sample"
    cells : bool
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
}

[export]
def main : int {
    var args = AbArgs()
    let parsed = cli_prologue(args, "ab")
    if (parsed >= 0) {
        return parsed
    }
    if (empty(args.file) || empty(args.arm) || empty(args.base)) {
        to_log(LOG_ERROR, "ab: --file, --arm and --base are required\n")
        return 2
    }
    if (!fexist(args.file)) {
        to_log(LOG_ERROR, "ab: no file {args.file}\n")
        return 2
    }
    var inscope batch <- read_batch(fread(args.file), args.value)
    if (args.cells) {
        print(render_cells(batch))
    }
    print(render_ab(batch, args.arm, args.base))
    return 0
}
