options gen2

require strings
require daslib/strings_boost
require daslib/fio
require daslib/clargs
require ../../converter/pipeline.das
require ../../converter/tiers.das

//! The c-testsuite single-exec runner and its ratchet. Run from the repository root through
//! `scripts/run_suite.sh c_testsuite`: every test under fetch/ is converted into work/<id>/,
//! run under the interpreter, and its merged output and exit code compared with the suite's
//! expectation. `expected_pass.txt` is the ratchet: a listed test that stops passing fails the
//! run; a newly passing test is reported, and `--update` writes it into the list. `skip.txt`
//! names the tests never run, one ledger line each.

let SUITE_DIR = "suites/c_testsuite"
let TESTS_DIR = "suites/c_testsuite/fetch/c-testsuite/tests/single-exec"
let WORK_DIR = "suites/c_testsuite/work"
let EXPECTED_PASS = "suites/c_testsuite/expected_pass.txt"
let SKIP_LEDGER = "suites/c_testsuite/skip.txt"

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

def skip_ids : table<string>
{
    var ids : table<string>
    for (line in read_lines(SKIP_LEDGER)) {
        ids |> insert(split(line, "\t")[0])
    }
    return <- ids
}

def test_ids(filter : string) : array<string> {
    var ids : array<string>
    dir(TESTS_DIR) $(name) {
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

def run_one(id : string; target : string) : Outcome {
    let c_path = "{TESTS_DIR}/{id}.c"
    let work = "{WORK_DIR}/{id}"
    let res <- convert(c_path, work, target)
    if (!res.ok) {
        return Outcome(id = id, status = "convert", reason = first_line(res.error))
    }
    var output : string
    let rc = run_tier(res.das_path, "interp", work, output, ["c_runtime", "dasCRuntime"])
    if (rc != 0) {
        return Outcome(id = id, status = "exit", reason = "exited {rc}: {first_line(output)}")
    }
    let expected = fread_text("{c_path}.expected")
    if (output != expected) {
        return Outcome(id = id, status = "output", reason = "got `{first_line(output)}`, expected `{first_line(expected)}`")
    }
    return Outcome(id = id, status = "pass", reason = "")
}

[export]
def main : int {
    var args = Args()
    let parsed = parse_args_with_help(args, "run_suite c_testsuite")
    if (parsed >= 0) {
        return parsed
    }
    if (!fexist(TESTS_DIR)) {
        to_log(LOG_ERROR, "{TESTS_DIR} is missing: run {SUITE_DIR}/fetch.sh\n")
        return 2
    }
    let skips <- skip_ids()
    let expected <- read_lines(EXPECTED_PASS)
    var expected_set : table<string>
    for (id in expected) {
        expected_set |> insert(id)
    }
    var passed : array<string>
    var counts : table<string; int>
    var regressions : array<string>
    var gained : array<string>
    for (id in test_ids(args.filter)) {
        if (key_exists(skips, id)) {
            counts["skip"] = (counts?["skip"] ?? 0) + 1
            continue
        }
        let out = run_one(id, args.target)
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
    to_log(LOG_INFO, "c_testsuite: {summary}\n")
    if (!empty(gained)) {
        to_log(LOG_INFO, "newly passing: {join(gained, " ")}{args.update ? " (recorded)" : " (run with --update to record)"}\n")
    }
    if (args.update && empty(args.filter)) {
        fopen(EXPECTED_PASS, "wb") $(f) {
            if (f != null) {
                fwrite(f, "# c-testsuite single-exec tests that pass under the interpreter; the ratchet, kept sorted\n")
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
