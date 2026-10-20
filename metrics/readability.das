options gen2
// the pipeline parses clang's JSON dump below its own frames: a deep expression tree overflows
// the default 16 KB context stack, and dastest gives its tests this much
options stack = 1048576

require strings
require daslib/strings_boost
require daslib/fio
require daslib/clargs
require ../suites/suite_runner.das
require ../suites/csmith/generate.das
require ../perf/perf_compose.das
require ../converter/pipeline.das
require readability_file
require readability_count

//! The readability metric (`scripts/run_readability.sh`): every input key `expected_input_keys`
//! names, converted under the `linux` dialect and counted by `readability_count`, one worker
//! process per input, `--jobs` at a time. The totals ratchet against the committed
//! `readability_linux.json`: a run exits 1 when one went up, and `--update` records the run.

let CAPTURE = "metrics/readability_linux.json"
let WORK = "metrics/work"

// seconds a worker may live before the driver kills it: a csmith seed converts in up to a minute
let WORKER_TIMEOUT = 900.0

[CommandLineArgs]
struct ReadabilityArgs {
    @clarg_doc = "record the run in metrics/readability_linux.json"
    update : bool
    @clarg_doc = "count only the inputs whose input key (<group>/<id>) contains this text"
    filter : string = ""
    @clarg_doc = "list every counted site, with the name a named literal could use"
    verbose : bool
    @clarg_doc = "inputs converted at once, one worker process each"
    jobs : int = 4
    @clarg_doc = "worker: convert and count the input with this input key, writing work/<key>/counts.txt"
    one : string = ""
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
}

// the C file of an input, written under `dir` when it is generated or composed
def private c_file_of(key, dir : string; var error : string&) : string {
    let group = group_of(key)
    let id = slice(key, length(group) + 1)
    if (group == "c_testsuite") {
        return "{C_TESTSUITE_TESTS}/{id}.c"
    } elif (group == "gcc_torture") {
        return "{GCC_TORTURE_TESTS}/{id}.c"
    } elif (group == "perf") {
        return write_composed(id, dir)
    }
    let prog = csmith_program(id, dir, CSMITH_TIMEOUT)
    error = prog.timed_out ? "csmith took longer than {int(CSMITH_TIMEOUT)} s" : prog.error
    return prog.c_path
}

def private counts_path(key : string) : string => "{WORK}/{key}/counts.txt"

// an error's first line, and when that line only names the stage (`dumper: clang exited 1:`)
// the first non-empty line after it
def private headline(error : string) : string {
    let lines <- [for (l in split(error, "\n")); strip(l); where !empty(strip(l))]
    if (empty(lines)) {
        return error
    }
    return lines[0] |> ends_with(":") && length(lines) > 1 ? "{lines[0]} {lines[1]}" : lines[0]
}

// the worker: one input converted into work/<key>/ and counted
def private measure_one(key : string) : ModuleCount {
    let dir = "{WORK}/{key}"
    var error : string
    let c_path = c_file_of(key, dir, error)
    if (!empty(error)) {
        return ModuleCount(error = error)
    }
    let res <- convert(c_path, path_join(dir, "das"), "linux")
    if (!res.ok) {
        return ModuleCount(error = "convert: {headline(res.error)}")
    }
    return <- count_module(res.das_path)
}

// the committed capture, empty when there is none
def private committed_capture : Capture {
    var error : string
    var cap <- read_capture(fexist(CAPTURE) ? fread(CAPTURE) : "\{\}", error)
    if (!empty(error)) {
        to_log(LOG_ERROR, "{CAPTURE}: {error}\n")
    }
    return <- cap
}

// what the workers measured: the capture, a line per input that failed, and every site
struct Measured {
    cap : Capture
    failures : array<string>
    sites : array<tuple<key : string; line : int; text : string>>
}

// every input key through a worker, `jobs` at a time
def private measure_all(keys : array<string>; jobs : int) : Measured {
    var m : Measured
    run_workers(length(keys), jobs, WORKER_TIMEOUT, $(index) => spawn_one("metrics/readability.das", keys[index], counts_path(keys[index]))) $(index, killed, rc, output) {
        let key = keys[index]
        var mc <- killed ? ModuleCount(error = "killed past {int(WORKER_TIMEOUT)} s") : read_count_text(fexist(counts_path(key)) ? fread(counts_path(key)) : "")
        if (!empty(mc.error)) {
            let printed = empty(strip(output)) ? "" : "\n{strip(output)}"
            m.failures |> push("{key}: {mc.error} (worker exit {rc}){printed}")
            return
        }
        for (s in mc.sites) {
            let named = empty(s.suggested_name) ? "" : " ({s.suggested_name})"
            m.sites |> push((key = key, line = s.line, text = "{key}:{s.line}: {s.metric}{named}"))
        }
        m.cap.modules[key] <- mc.counts
    }
    for (g in INPUT_GROUPS) {
        m.cap.inputs[g] = length([for (k in keys(m.cap.modules)); k; where group_of(k) == g])
    }
    m.failures |> sort()
    m.sites |> sort() $(a, b) => a.key < b.key || (a.key == b.key && a.line < b.line)
    return <- m
}

// the recorded input keys no ratchet lists now: an input a ratchet dropped lowers the totals
// without any converter change, so it is named and, like a raised total, fails a run without
// `--update`; a `--filter` run measures a part and names none
def private dropped_keys(committed : Capture; keys : array<string>; filtered : bool) : array<string> {
    var dropped : array<string>
    if (!filtered) {
        dropped <- [for (k in keys(committed.modules)); k; where !(keys |> has_value(k))]
        dropped |> sort()
    }
    return <- dropped
}

[export]
def main : int {
    var args = ReadabilityArgs()
    let parsed = cli_prologue(args, "run_readability")
    if (parsed >= 0) {
        return parsed
    }
    if (!empty(args.one)) {
        fwrite(counts_path(args.one), count_text(measure_one(args.one)))
        return 0
    }
    for (needed in fixed_array(C_TESTSUITE_TESTS, GCC_TORTURE_TESTS, "{CSMITH_DIR}/build/src/csmith")) {
        if (!fexist(needed)) {
            to_log(LOG_ERROR, "{needed} is missing: run scripts/run_readability.sh, which fetches the suites\n")
            return 2
        }
    }
    let t0 = ref_time_ticks()
    let keys <- [for (k in expected_input_keys()); k; where empty(args.filter) || find(k, args.filter) >= 0]
    var measured <- measure_all(keys, args.jobs)
    let committed_cap <- committed_capture()
    let dropped <- dropped_keys(committed_cap, keys, !empty(args.filter))
    let committed <- committed_totals(committed_cap, [for (k in keys(measured.cap.modules)); k])
    let now <- totals_of(measured.cap.modules)
    if (args.verbose) {
        for (s in measured.sites) {
            print("{s.text}\n")
        }
    }
    let groups = join([for (g in INPUT_GROUPS); "{g} {measured.cap.inputs?[g] ?? 0}"], ", ")
    print("**Readability**\n\n{length(keys)} inputs attempted, {length(measured.failures)} failed; measured: {groups}\n\n{render_totals(committed, now)}\n")
    to_log(LOG_INFO, "{length(keys)} inputs in {int(seconds_since(t0))} s\n")
    for (f in measured.failures) {
        to_log(LOG_ERROR, "{f}\n")
    }
    let raised <- raised_metrics(committed, now)
    if (!empty(raised)) {
        to_log(LOG_ERROR, "raised: {join(raised, " ")}; a commit that raises a total says which and why\n")
    }
    for (k in dropped) {
        to_log(LOG_ERROR, "dropped: {k} is in {CAPTURE} but no ratchet lists it now\n")
    }
    let refusal = update_refusal(args.update, !empty(args.filter), !empty(measured.failures))
    if (!empty(refusal)) {
        to_log(LOG_ERROR, "not recorded: {refusal}\n")
    } elif (args.update) {
        fwrite(CAPTURE, capture_text(measured.cap))
        to_log(LOG_INFO, "recorded {CAPTURE}\n")
    }
    return run_exit_code(!empty(measured.failures), !empty(refusal), !empty(raised) || !empty(dropped), args.update)
}
