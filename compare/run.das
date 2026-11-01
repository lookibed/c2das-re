options gen2

require strings
require daslib/strings_boost
require daslib/clargs
require daslib/json_boost
require ../converter/pipeline.das
require ../perf/perf_lanes.das
require ../suites/suite_runner.das
require rust_translator
require suite_compare

//! The head-to-head with the Rust translator from the repository root: `--suites` runs it over
//! the three suites' inputs and writes the `suites` section of `compare/results_linux.json`
//! (`compare/ARCHITECTURE.md`).

[CommandLineArgs]
struct CompareArgs {
    @clarg_doc = "run the Rust translator over all three suites"
    suites : bool
    @clarg_doc = "run it over one suite: c_testsuite, gcc_torture or csmith"
    suite : string = ""
    @clarg_doc = "run only the ids that contain this text; a filtered run writes no capture"
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
    var c <- suite_capture(ratchet, outcomes, seconds_since(started))
    let counts = join([for (s in STATUSES); "{s} {c.rust?[s] ?? 0}"], ", ")
    to_log(LOG_INFO, "{spec.name}: rust {counts} of {c.ids} (ours {c.ours_pass}, skipped {c.ours_skipped}; rust passes of ours {c.rust_pass_of_ours}, of skipped {c.rust_pass_of_skipped}, of unlisted {c.rust_pass_of_unlisted})\n")
    return <- c
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
    let all <- compare_suites()
    let specs <- [for (s in all); s; where args.suites || s.name == args.suite]
    if (empty(specs)) {
        to_log(LOG_ERROR, "name what to run: --suites, or --suite c_testsuite, gcc_torture or csmith\n")
        return 1
    }
    let missing = missing_inputs(specs)
    if (!empty(missing)) {
        to_log(LOG_ERROR, "{missing}\n")
        return 2
    }
    var entries <- {for (spec in specs); spec.name => JV(run_suite(spec, args))}
    if (!empty(args.filter)) {
        return 0
    }
    var reason, clang_version, daslang_version : string
    tool_versions(clang_version, daslang_version)
    let stamps <- {"rust_commit" => rust_version(rust_binary(), reason), "daslang" => daslang_version, "date" => strip(captured(["date", "-u", "+%Y-%m-%d %H:%M UTC"]))}
    let out = empty(args.out) ? CAPTURE : args.out
    let error = write_capture(out, entries, stamps)
    if (!empty(error)) {
        to_log(LOG_ERROR, "{error}\n")
        return 1
    }
    to_log(LOG_INFO, "written to {out}\n")
    return 0
}
