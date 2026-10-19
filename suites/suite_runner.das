options gen2

module suite_runner public

require strings
require daslib/strings_boost
require daslib/fio
require daslib/clargs
require ../converter/pipeline.das
require ../converter/tiers.das

//! The runner every suite shares: each `<id>.c` of the suite is converted into `work/<id>/`
//! under the `linux` dialect, run under the interpreter, and judged by the suite's own
//! verdict; `expected_pass.txt` is the ratchet (a listed id that stops passing fails the run, a
//! newly passing one is reported and `--update` records it) and `skip.txt` the ledger of the
//! ids never run. A suite is a `SuiteSpec` and a verdict function.

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
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
}

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
    // seconds a converted test may run before it counts as `exit`
    run_timeout : float
}

def read_lines(path : string) : array<string> {
    var lines : array<string>
    if (!fexist(path)) {
        return <- lines
    }
    for (line in split(fread(path), "\n")) {
        let trimmed = strip(line)
        if (!empty(trimmed) && !(trimmed |> starts_with("#"))) {
            lines |> push(trimmed)
        }
    }
    return <- lines
}

//! The ratchet and the ledger as a run reads them: the ids `expected_pass.txt` lists, as read and
//! as a set, and the ids `skip.txt` lists.
struct Ratchet {
    expected : array<string>
    expected_set : table<string>
    skips : table<string>
}

def read_ratchet(expected_pass, skip_ledger : string) : Ratchet {
    var r : Ratchet
    for (line in read_lines(skip_ledger)) {
        r.skips |> insert(split(line, "\t")[0])
    }
    r.expected <- read_lines(expected_pass)
    for (id in r.expected) {
        r.expected_set |> insert(id)
    }
    return <- r
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
        let lines <- [for (id in ratchet_ids); "{id}\n"]
        fwrite(expected_pass, "# {name} tests that pass under the interpreter; the ratchet, kept sorted\n{join(lines, "")}")
    }
    if (!empty(tally.regressions)) {
        to_log(LOG_ERROR, "ratchet broken, these passed before: {join(tally.regressions, " ")}\n")
        return 1
    }
    return 0
}

//! A C file converted into `work` under `target` and, when it converts, run under the
//! interpreter with both module folders loaded: `converted` false with the error's first line,
//! or the exit code and merged output of the run.
struct ConvertedRun {
    converted : bool
    error : string
    rc : int
    output : string
}

def convert_and_run(c_path, work, target : string; timeout : float) : ConvertedRun {
    let no_flags : array<string>
    return convert_and_run(c_path, work, target, timeout, no_flags)
}

//! `flags` go to the interpreter before the module (`-no-module-cache`).
def convert_and_run(c_path, work, target : string; timeout : float; flags : array<string>) : ConvertedRun {
    var run : ConvertedRun
    let res <- convert(c_path, work, target)
    if (!res.ok) {
        run.error = first_line(res.error)
        return run
    }
    run.converted = true
    run.rc = run_tier(res.das_path, "interp", work, run.output, CONVERTED_MODULES, timeout, flags)
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

// the `.c` files directly under the tests folder, by id, sorted
def private test_ids(spec : SuiteSpec; filter : string) : array<string> {
    var ids : array<string>
    dir(spec.tests_dir) $(name) {
        if (name |> ends_with(".c") && (empty(filter) || find(name, filter) >= 0)) {
            ids |> push(slice(name, 0, length(name) - 2))
        }
    }
    ids |> sort()
    return <- ids
}

def first_line(text : string) : string {
    let nl = find(text, "\n")
    return nl < 0 ? text : slice(text, 0, nl)
}

// convert and run one test; the suite's verdict judges a module that ran
def private run_one(spec : SuiteSpec; id : string; target : string; verdict : function<(id : string; c_path : string; rc : int; output : string) : Outcome>) : Outcome {
    let c_path = "{spec.tests_dir}/{id}.c"
    let run = convert_and_run(c_path, "{spec.work_dir}/{id}", target, spec.run_timeout)
    if (!run.converted) {
        return Outcome(id = id, status = "convert", reason = run.error)
    }
    return invoke(verdict, id, c_path, run.rc, run.output)
}

//! The whole run from the command line: exit 0 when the ratchet holds, 1 when a listed id
//! stopped passing, 2 when the suite is not fetched.
def run_suite_main(spec : SuiteSpec; verdict : function<(id : string; c_path : string; rc : int; output : string) : Outcome>) : int {
    var args = Args()
    let parsed = parse_args_with_help(args, "run_suite {spec.name}")
    if (parsed >= 0) {
        return parsed
    }
    if (args.show_help) {
        print_help(get_command_info(type<Args>), "run_suite {spec.name}")
        return 0
    }
    if (!fexist(spec.tests_dir)) {
        to_log(LOG_ERROR, "{spec.tests_dir} is missing: run suites/{spec.name}/fetch.sh\n")
        return 2
    }
    let ratchet <- read_ratchet(spec.expected_pass, spec.skip_ledger)
    var tally : Tally
    for (id in test_ids(spec, args.filter)) {
        if (key_exists(ratchet.skips, id)) {
            count_status(tally, "skip")
            continue
        }
        record(tally, ratchet, run_one(spec, id, args.target, verdict), args.verbose)
    }
    return finish_run(spec.name, spec.expected_pass, tally, args.update, !empty(args.filter), tally.passed)
}
