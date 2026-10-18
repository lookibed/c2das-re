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
    for (line in split(fread_text(path), "\n")) {
        let trimmed = strip(line)
        if (!empty(trimmed) && !(trimmed |> starts_with("#"))) {
            lines |> push(trimmed)
        }
    }
    return <- lines
}

def fread_text(path : string) : string {
    var text = ""
    fopen(path, "rb") $(f) {
        if (f != null) {
            text = fread(f)
        }
    }
    return text
}

def private skip_ids(spec : SuiteSpec) : table<string> {
    var ids : table<string>
    for (line in read_lines(spec.skip_ledger)) {
        ids |> insert(split(line, "\t")[0])
    }
    return <- ids
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
    let work = "{spec.work_dir}/{id}"
    let res <- convert(c_path, work, target)
    if (!res.ok) {
        return Outcome(id = id, status = "convert", reason = first_line(res.error))
    }
    var output : string
    let rc = run_tier(res.das_path, "interp", work, output, ["c_runtime", "dasCRuntime"], spec.run_timeout)
    return invoke(verdict, id, c_path, rc, output)
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
    let skips <- skip_ids(spec)
    let expected <- read_lines(spec.expected_pass)
    var expected_set : table<string>
    for (id in expected) {
        expected_set |> insert(id)
    }
    var passed : array<string>
    var counts : table<string; int>
    var regressions, gained : array<string>
    for (id in test_ids(spec, args.filter)) {
        if (key_exists(skips, id)) {
            counts["skip"] = (counts?["skip"] ?? 0) + 1
            continue
        }
        let out = run_one(spec, id, args.target, verdict)
        counts[out.status] = (counts?[out.status] ?? 0) + 1
        if (out.status == "pass") {
            passed |> push(id)
            if (!key_exists(expected_set, id)) {
                gained |> push(id)
            }
        } else {
            if (key_exists(expected_set, id)) {
                regressions |> push(id)
            }
            if (args.verbose || key_exists(expected_set, id)) {
                to_log(LOG_INFO, "{id}: {out.status}: {out.reason}\n")
            }
        }
    }
    let summary = join([for (k, v in keys(counts), values(counts)); "{k} {v}"], ", ")
    to_log(LOG_INFO, "{spec.name}: {summary}\n")
    if (!empty(gained)) {
        to_log(LOG_INFO, "newly passing: {join(gained, " ")}{args.update ? " (recorded)" : " (run with --update to record)"}\n")
    }
    if (args.update && empty(args.filter)) {
        fopen(spec.expected_pass, "wb") $(f) {
            if (f != null) {
                fwrite(f, "# {spec.name} tests that pass under the interpreter; the ratchet, kept sorted\n")
                for (id in passed) {
                    fwrite(f, "{id}\n")
                }
            }
        }
    }
    if (!empty(regressions)) {
        to_log(LOG_ERROR, "ratchet broken, these passed before: {join(regressions, " ")}\n")
        return 1
    }
    return 0
}
