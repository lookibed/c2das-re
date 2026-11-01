options gen2
// `--perf` converts in this process: the pipeline parses clang's JSON dump below its own frames,
// and a deep expression tree overflows the default 16 KB context stack
options stack = 1048576

require strings
require daslib/strings_boost
require daslib/clargs
require daslib/json_boost
require ../converter/pipeline.das
require ../suites/suite_runner.das
require rust_translator
require suite_compare
require perf_compare

//! The head-to-head with the Rust translator from the repository root: `--suites` runs it over
//! the three suites' inputs and writes the `suites` section of `compare/results_linux.json`,
//! `--perf` times the perf kernels through both translators and writes its `perf` section
//! (`compare/ARCHITECTURE.md`).

[CommandLineArgs]
struct CompareArgs {
    @clarg_doc = "run the Rust translator over all three suites"
    suites : bool
    @clarg_doc = "run it over one suite: c_testsuite, gcc_torture or csmith"
    suite : string = ""
    @clarg_doc = "time the perf kernels through both translators under every lane"
    perf : bool
    @clarg_doc = "samples per perf lane, each its own process (default 5)"
    samples : int = 5
    @clarg_doc = "run only the ids (perf: the kernels) that contain this text; a filtered run writes no capture"
    filter : string = ""
    @clarg_doc = "cases judged at once, one worker process each"
    jobs : int = 4
    @clarg_doc = "the capture a run writes (default compare/results_linux.json)"
    out : string = ""
    @clarg_doc = "log the reason of every case that does not pass"
    verbose : bool
    @clarg_doc = "worker: judge this case, <suite>/<id>, writing compare/work/<suite>/<id>/verdict"
    one : string = ""
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
}

// the worker of `--one`: 0 once the verdict is written, 2 for an argument naming no case
def run_worker(text : string) : int {
    var suite, id : string
    let specs <- compare_suites()
    let found = split_worker_id(text, suite, id) ? find_index_if(specs, $(s) => s.name == suite) : -1
    if (found < 0) {
        to_log(LOG_ERROR, "--one takes <suite>/<id> of c_testsuite, gcc_torture or csmith, not `{text}`\n")
        return 2
    }
    judge_case(specs[found], id, rust_binary())
    return 0
}

// one suite through the workers, its summary logged; its capture entry
def run_suite(spec : SuiteSpec; args : CompareArgs) : SuiteCapture {
    let started = ref_time_ticks()
    let ratchet <- read_ratchet(spec.expected_pass, spec.skip_ledger)
    var outcomes <- drive_suite(spec, suite_ids(spec, ratchet, args.filter), ratchet, args.jobs)
    for (o in outcomes) {
        if (args.verbose && o.status != "pass") {
            to_log(LOG_INFO, "{spec.name}/{o.id} ({o.tag}): {o.status}: {o.reason}\n")
        }
    }
    var c <- suite_capture(ratchet, outcomes, seconds_since(started), run_stamps(rust_binary()))
    let counts = join([for (s in STATUSES); "{s} {c.rust?[s] ?? 0}"], ", ")
    to_log(LOG_INFO, "{spec.name}: rust {counts} of {c.ids} (ours {c.ours_pass}, skipped {c.ours_skipped}; rust passes of ours {c.rust_pass_of_ours}, of skipped {c.rust_pass_of_skipped}, of unlisted {c.rust_pass_of_unlisted})\n")
    return <- c
}

// the perf comparison over the kernels `--filter` names, the geometric means logged; the capture's
// `perf` section written
def run_perf(args : CompareArgs) : int {
    var reason : string
    if (!rust_available(reason)) {
        to_log(LOG_ERROR, "{reason}\n")
        return 2
    }
    let bin = rust_binary()
    var entries : table<string; JsonValue?>
    for (k in perf_kernels(args.filter)) {
        var entry = compare_kernel(k, bin, args.samples)
        to_log(LOG_INFO, "{kernel_line(k.key, entry)}\n")
        entries[k.key] = entry
    }
    var section = perf_section(run_stamps(bin), args.samples, entries)
    for (line in geomean_lines(section)) {
        to_log(LOG_INFO, "{line}\n")
    }
    return record_run(empty(args.out) ? CAPTURE : args.out, args.filter) $(path) => write_capture_section(path, "perf", section)
}

[export]
def main : int {
    var args = CompareArgs()
    let parsed = cli_prologue(args, "compare")
    if (parsed >= 0) {
        return parsed
    }
    if (!empty(args.one)) {
        return run_worker(args.one)
    }
    if (args.perf) {
        if (args.suites || !empty(args.suite)) {
            to_log(LOG_ERROR, "--perf runs alone: run the suites in a run of their own\n")
            return 1
        }
        if (args.samples < 1) {
            to_log(LOG_ERROR, "--samples takes a count of at least 1, not {args.samples}\n")
            return 1
        }
        return run_perf(args)
    }
    let all <- compare_suites()
    let specs <- [for (s in all); s; where args.suites || s.name == args.suite]
    if (empty(specs)) {
        to_log(LOG_ERROR, "name what to run: --suites, --suite c_testsuite, gcc_torture or csmith, or --perf\n")
        return 1
    }
    let missing = missing_inputs(specs)
    if (!empty(missing)) {
        to_log(LOG_ERROR, "{missing}\n")
        return 2
    }
    var entries <- {for (spec in specs); spec.name => JV(run_suite(spec, args))}
    return record_run(empty(args.out) ? CAPTURE : args.out, args.filter, entries)
}
