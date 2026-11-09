options gen2

module suite_runner public

require daslib/cmp
require strings
require daslib/strings_boost
require daslib/fio
require daslib/clargs
require math
require ../converter/pipeline.das
require ../converter/tiers.das
require suite_files public

//! The runner every suite shares: each `<id>.c` of the suite is converted into `work/<id>/`
//! under the `linux` dialect, run under `--tier` (the interpreter unless given), and judged by
//! the suite's own verdict; `expected_pass.txt` is the ratchet (a listed id that stops passing
//! fails the run, a newly passing one is reported and `--update` records it) and `skip.txt` the
//! ledger of the ids never run. A suite is a `SuiteSpec` and a verdict function.

[CommandLineArgs]
struct Args {
    @clarg_doc = "run only the tests whose id contains this text"
    filter : string = ""
    @clarg_doc = "rewrite expected_pass.txt with every test that passed"
    update : bool
    @clarg_doc = "print the reason of every non-passing test"
    verbose : bool
    @clarg_doc = "dialect for the conversion: linux (this host's baseline) or msvc"
    target : string = "linux"
    @clarg_doc = "tier the converted tests run under: interp (default), jit or exe; the ratchet is the interpreter's, so --update needs interp"
    tier : string = "interp"
    @clarg_doc = "run only the ids skip.txt lists, writing work/skip_audit.tsv; the ratchet is not judged, and only --update writes it, adding the audited ids that pass"
    audit_skips : bool
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
}

//! The tiers a suite runs under (`--tier`).
let SUITE_TIERS <- ["interp", "jit", "exe"]

//! Why a run under `tier` is refused, "" when it is not: a tier outside `SUITE_TIERS`, or
//! `update` under any tier but the interpreter's, whose ratchet `expected_pass.txt` is.
def tier_refusal(tier : string; update : bool) : string {
    if (!has_value(SUITE_TIERS, tier)) {
        return "unknown tier `{tier}`: one of {join(SUITE_TIERS, ", ")}"
    }
    return update && tier != "interp" ? "--update records the interpreter's ratchet; run it under --tier interp" : ""
}

//! the folder each file-based suite's tests sit in, from the repository root
let C_TESTSUITE_TESTS = "suites/c_testsuite/fetch/c-testsuite/tests/single-exec"
let GCC_TORTURE_TESTS = "suites/gcc_torture/fetch/gcc/gcc/testsuite/gcc.c-torture/execute"

struct Outcome {
    id : string
    status : string
    reason : string
}

struct SuiteSpec {
    name : string
    tests_dir : string
    work_dir : string
    expected_pass : string
    skip_ledger : string
    // seconds a converted test may run before it counts as `timeout`
    run_timeout : float
}

//! What a run found: the ids that passed, the count per status, the listed ids that stopped
//! passing and the unlisted ones that pass.
struct Tally {
    passed : array<string>
    counts : table<string; int>
    regressions : array<string>
    gained : array<string>
}

def count_status(var tally : Tally; status : string) {
    tally.counts[status] = (tally.counts?[status] ?? 0) + 1
}

//! One outcome against the ratchet; the reason of a listed id that does not pass is logged, and
//! under `verbose` that of every id that does not pass.
def record(var tally : Tally; ratchet : Ratchet; out : Outcome; verbose : bool) {
    count_status(tally, out.status)
    if (out.status == "pass") {
        tally.passed |> push(out.id)
        if (!key_exists(ratchet.expected_set, out.id)) {
            tally.gained |> push(out.id)
        }
        return
    }
    if (key_exists(ratchet.expected_set, out.id)) {
        tally.regressions |> push(out.id)
    }
    if (verbose || key_exists(ratchet.expected_set, out.id)) {
        to_log(LOG_INFO, "{out.id}: {out.status}: {out.reason}\n")
    }
}

//! The end of a run: the summary and the newly passing ids are logged, `ratchet_ids` (which
//! arrive sorted) become `expected_pass` under `update` unless the run was `filtered`, and the
//! exit code is 1 when a listed id stopped passing.
def finish_run(name, expected_pass : string; tally : Tally; update, filtered : bool; ratchet_ids : array<string>) : int {
    let summary = join([for (k, v in keys(tally.counts), values(tally.counts)); "{k} {v}"], ", ")
    to_log(LOG_INFO, "{name}: {summary}\n")
    let write = update && !filtered
    if (!empty(tally.gained)) {
        let how = write ? "recorded" : update ? "a --filter run does not record" : "run with --update to record"
        to_log(LOG_INFO, "newly passing: {join(tally.gained, " ")} ({how})\n")
    }
    if (write) {
        write_ratchet(name, expected_pass, ratchet_ids)
    }
    if (!empty(tally.regressions)) {
        to_log(LOG_ERROR, "ratchet broken, these passed before: {join(tally.regressions, " ")}\n")
        return 1
    }
    return 0
}

//! `ids`, sorted, written as the ratchet `expected_pass` of suite `name`.
def write_ratchet(name, expected_pass : string; ids : array<string>) {
    let lines <- [for (id in ids); "{id}\n"]
    fwrite(expected_pass, "# {name} tests that pass under the interpreter; the ratchet, kept sorted\n{join(lines, "")}")
}

//! A C file converted into `work` under `target` and, when it converts, run under `tier` (one of
//! `SUITE_TIERS`) with both module folders loaded: `converted` false with the error's first
//! line, or the exit code and merged output of the run.
struct ConvertedRun {
    converted : bool
    error : string
    rc : int
    output : string
}

//! `flags` go to the interpreter or the JIT before the module (`-no-module-cache`). The run's
//! children log at `warning`: the JIT and the exe build report themselves at `info`, which
//! `scripts/env.sh` sets, and those lines would land in the output a verdict judges.
def convert_and_run(c_path, work, target, tier : string; timeout : float; flags : array<string>) : ConvertedRun {
    var run : ConvertedRun
    let res <- convert(c_path, work, target)
    if (!res.ok) {
        run.error = first_line(res.error)
        return run
    }
    run.converted = true
    let level = get_env_variable("DAS_LOG_LEVEL")
    set_env_variable("DAS_LOG_LEVEL", "warning")
    run.rc = run_tier(res.das_path, tier, work, run.output, CONVERTED_MODULES, timeout, flags)
    set_env_variable("DAS_LOG_LEVEL", level)
    return run
}

//! A run's verdict against the output it must give: `exit` for a non-zero exit, `output` for
//! any other output, `pass` otherwise.
def compare_output(id : string; rc : int; output, expected : string) : Outcome {
    if (rc != 0) {
        return Outcome(id = id, status = "exit", reason = "exited {rc}: {first_line(output)}")
    }
    if (output != expected) {
        return Outcome(id = id, status = "output", reason = "got `{first_line(output)}`, expected `{first_line(expected)}`")
    }
    return Outcome(id = id, status = "pass", reason = "")
}

// convert and run one test under `tier`; the suite's verdict judges a module that ran within the timeout
def private run_one(spec : SuiteSpec; id : string; target, tier : string; verdict : function<(id : string; c_path : string; rc : int; output : string) : Outcome>) : Outcome {
    let c_path = "{spec.tests_dir}/{id}.c"
    let no_flags : array<string>
    let run = convert_and_run(c_path, "{spec.work_dir}/{id}", target, tier, spec.run_timeout, no_flags)
    if (!run.converted) {
        return Outcome(id = id, status = "convert", reason = run.error)
    }
    if (run.rc == popen_timed_out) {
        return Outcome(id = id, status = "timeout", reason = "ran longer than {int(spec.run_timeout)} s")
    }
    return invoke(verdict, id, c_path, run.rc, run.output)
}

//! A `skip.txt` line as the skip audit reads it: the id and the feature it names.
struct SkipLine {
    id : string
    feature : string
}

def skip_line(line : string) : SkipLine {
    var inscope fields <- split(line, "\t")
    return SkipLine(id = fields[0], feature = length(fields) > 1 ? fields[1] : "")
}

def read_skip_lines(skip_ledger : string) : array<SkipLine> => [for (line in read_lines(skip_ledger)); skip_line(line)]

//! The ledger lines an audit judges: each id once, the first line naming it, those whose id holds
//! `filter` (all for ""), sorted by id.
def audited_lines(lines : array<SkipLine>; filter : string) : array<SkipLine> {
    var seen : table<string>
    var kept : array<SkipLine>
    for (line in lines) {
        if (!key_exists(seen, line.id) && (empty(filter) || find(line.id, filter) >= 0)) {
            seen |> insert(line.id)
            kept |> push(line)
        }
    }
    kept |> sort() <| cmp_by(_.id)
    return <- kept
}

//! One ledgered id's outcome in the skip audit.
struct AuditRow {
    id : string
    feature : string
    status : string
    reason : string
}

// the error prefix of each conversion stage `convert` writes, and the audit's status for it
let private CONVERT_STAGES = fixed_array((prefix = "dumper: ", stage = "dumper"), (prefix = "emitter: ", stage = "emitter"), (prefix = "compile check: ", stage = "compile"))

//! The audit's status of an outcome: `convert` as the stage its error names (`dumper`,
//! `emitter`, `compile`; `convert` for any other), `output` as `mismatch`, any other as it is.
def audit_status(out : Outcome) : string {
    if (out.status == "output") {
        return "mismatch"
    }
    if (out.status != "convert") {
        return out.status
    }
    for (s in CONVERT_STAGES) {
        if (out.reason |> starts_with(s.prefix)) {
            return s.stage
        }
    }
    return "convert"
}

def audit_row(feature : string; out : Outcome) : AuditRow =>
    AuditRow(id = out.id, feature = feature, status = audit_status(out), reason = replace(first_line(out.reason), "\t", " "))

//! The skip audit's tally: one line per feature, sorted, with its count per status, sorted.
def audit_tally(rows : array<AuditRow>) : array<string> {
    var per_feature : table<string; table<string; int>>
    for (row in rows) {
        per_feature[row.feature][row.status] = (per_feature?[row.feature]?[row.status] ?? 0) + 1
    }
    var features <- [for (f in keys(per_feature)); f]
    features |> sort()
    return <- [for (f in features); "{f}: {status_counts(per_feature[f])}"]
}

// a feature's count per status, sorted by status
def private status_counts(counts : table<string; int>) : string {
    var inscope statuses <- [for (s in keys(counts)); s]
    statuses |> sort()
    return join([for (s in statuses); "{s} {counts?[s] ?? 0}"], ", ")
}

//! The end of a skip audit: the rows, sorted by id, written to `<work_dir>/skip_audit.tsv` (id,
//! feature, status, the reason's first line) and the per-feature tally logged.
def finish_audit(name, work_dir : string; rows : array<AuditRow>) {
    var sorted := rows
    sorted |> sort() <| cmp_by(_.id)
    mkdir_rec(work_dir)
    let path = "{work_dir}/skip_audit.tsv"
    let text = build_string() $(writer) {
        writer |> write("# {name} skip audit: id, feature, status, reason\n")
        for (row in sorted) {
            writer |> write("{row.id}\t{row.feature}\t{row.status}\t{row.reason}\n")
        }
    }
    fwrite(path, text)
    to_log(LOG_INFO, "{name} skip audit: {length(rows)} ids, written to {path}\n")
    for (line in audit_tally(rows)) {
        to_log(LOG_INFO, "  {line}\n")
    }
}

//! The skip audit of a file-based suite: every id `skip.txt` lists whose name holds `filter`
//! is converted and run under `tier` as an unlisted id would be, and a listed id with no `.c` file
//! is `missing`; the rows, which `finish_audit` wrote too.
def audit_suite(spec : SuiteSpec; filter, target, tier : string; verdict : function<(id : string; c_path : string; rc : int; output : string) : Outcome>) : array<AuditRow> {
    var present : table<string>
    for (id in c_file_ids(spec.tests_dir, filter)) {
        present |> insert(id)
    }
    var rows : array<AuditRow>
    for (line in audited_lines(read_skip_lines(spec.skip_ledger), filter)) {
        if (key_exists(present, line.id)) {
            rows |> push(audit_row(line.feature, run_one(spec, line.id, target, tier, verdict)))
        } else {
            rows |> push(AuditRow(id = line.id, feature = line.feature, status = "missing", reason = "no {line.id}.c in {spec.tests_dir}"))
        }
    }
    finish_audit(spec.name, spec.work_dir, rows)
    return <- rows
}

//! `--audit-skips --update`: the audited ids that passed join the ratchet `expected_pass` of suite
//! `name`, which only grows (a failure, a timeout or a missing file joins nothing, and no listed id
//! leaves); the count that joined. Their `skip.txt` lines stay until the ledger is rewritten
//! (`gcc_torture/filter.das` for the torture suite).
def join_audit_passes(name, expected_pass : string; rows : array<AuditRow>) : int {
    var ids <- read_lines(expected_pass)
    var listed : table<string>
    for (id in ids) {
        listed |> insert(id)
    }
    var joined = 0
    for (row in rows) {
        if (row.status == "pass" && !key_exists(listed, row.id)) {
            listed |> insert(row.id)
            ids |> push(row.id)
            joined++
        }
    }
    ids |> sort()
    write_ratchet(name, expected_pass, ids)
    to_log(LOG_INFO, "{name} skip audit: {joined} passing ids joined {expected_pass}; rewrite skip.txt so their lines go\n")
    return joined
}

//! The whole run from the command line: exit 0 when the ratchet holds, 1 when a listed id
//! stopped passing, 2 when the suite is not fetched; under `--audit-skips` the skip audit,
//! exit 0, its passing ids joining the ratchet under `--update`.
def run_suite_main(spec : SuiteSpec; verdict : function<(id : string; c_path : string; rc : int; output : string) : Outcome>) : int {
    var args = Args()
    let parsed = cli_prologue(args, "run_suite {spec.name}")
    if (parsed >= 0) {
        return parsed
    }
    let refusal = tier_refusal(args.tier, args.update)
    if (!empty(refusal)) {
        to_log(LOG_ERROR, "{refusal}\n")
        return 2
    }
    if (!fexist(spec.tests_dir)) {
        to_log(LOG_ERROR, "{spec.tests_dir} is missing: run suites/{spec.name}/fetch.sh\n")
        return 2
    }
    if (args.audit_skips) {
        let rows <- audit_suite(spec, args.filter, args.target, args.tier, verdict)
        if (args.update) {
            join_audit_passes(spec.name, spec.expected_pass, rows)
        }
        return 0
    }
    let ratchet <- read_ratchet(spec.expected_pass, spec.skip_ledger)
    var tally : Tally
    for (id in c_file_ids(spec.tests_dir, args.filter)) {
        if (key_exists(ratchet.skips, id)) {
            count_status(tally, "skip")
            continue
        }
        record(tally, ratchet, run_one(spec, id, args.target, args.tier, verdict), args.verbose)
    }
    return finish_run(spec.name, spec.expected_pass, tally, args.update, !empty(args.filter), tally.passed)
}

//! The seconds since `t0`, a `ref_time_ticks` reading.
def seconds_since(t0 : int64) : float => float(double(get_time_nsec(t0)) / 1000000000.0lf)

struct private RunningWorker {
    index : int
    proc : process
    started : int64
    output : string
}

// true once `w` ended, by itself or killed past `timeout` seconds, and `done` took it
def private reap_worker(var w : RunningWorker; timeout : float; done : block<(index : int; killed : bool; rc : int; output : string) : void>) : bool {
    var rc = unsafe(process_poll(w.proc))
    let killed = rc == process_running && seconds_since(w.started) >= timeout
    unsafe(process_drain(w.proc) $(line) {
        w.output += line
    })
    if (rc == process_running && !killed) {
        return false
    }
    if (killed) {
        unsafe(process_kill(w.proc))
        rc = unsafe(process_wait(w.proc, 10.0))
    }
    invoke(done, w.index, killed, rc, w.output)
    unsafe(close_process(w.proc))
    return true
}

//! Indices 0 to `count - 1` through worker processes, at most `jobs` running at once: `start`
//! spawns an index's worker, and `done` takes it with what it printed once it exited, or once
//! it was killed past `timeout` seconds.
def run_workers(count, jobs : int; timeout : float; start : block<(index : int) : process>; done : block<(index : int; killed : bool; rc : int; output : string) : void>) {
    var running : array<RunningWorker>
    var next = 0
    while (next < count || !empty(running)) {
        while (next < count && length(running) < max(jobs, 1)) {
            running |> push(RunningWorker(index = next, proc = invoke(start, next), started = ref_time_ticks()))
            next++
        }
        var idx = 0
        while (idx < length(running)) {
            if (reap_worker(running[idx], timeout, done)) {
                running |> erase(idx)
            } else {
                idx++
            }
        }
        sleep(200u)
    }
}

//! A worker of `script`: the script run with both module folders loaded and `--one <id>`, the
//! file `stale` it writes removed first, so a worker that dies leaves none behind.
def spawn_one(script, id, stale : string) : process {
    let no_args : array<string>
    return spawn_one(script, id, stale, no_args)
}

//! `worker_args` follow `--one <id>` on the worker's command line (`--tier jit`).
def spawn_one(script, id, stale : string; worker_args : array<string>) : process {
    var argv <- daslang_cmd(CONVERTED_MODULES)
    argv |> push_from([script, "--", "--one", id], worker_args)
    let noenv : array<string>
    remove(stale)
    return unsafe(spawn_process(argv, "", noenv))
}
