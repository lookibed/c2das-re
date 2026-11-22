options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require daslib/fio
require ../../suites/csmith/nightly.das
require ../../suites/suite_runner.das

//! The csmith nightly (`run.das --nightly`): the seeds a start draws, the start a date or a flag
//! names, the dated result file and the exit code; the driver's refusal of a bad start runs the
//! script itself, since its exit code is what is judged.

// a decimal from 1 to 2^30, csmith's seed range as the draw makes it
def is_seed(s : string) : bool {
    for (ch in s) {
        if (!is_number(ch)) {
            return false
        }
    }
    return !empty(s) && length(s) <= 10 && !(s |> starts_with("0")) && to_int64(s) <= 1073741824l
}

[test]
def test_nightly_seeds(t : T?) {
    t |> run("a start draws the same distinct decimal seeds on every run, another start others") @(t : T?) {
        let first <- nightly_seeds(20261122, 50)
        let again <- nightly_seeds(20261122, 50)
        let other <- nightly_seeds(20261123, 50)
        t |> equal(length(first), 50)
        t |> equal(join(first, " "), join(again, " "))
        t |> success(join(first, " ") != join(other, " "))
        var seen : table<string>
        for (s in first) {
            t |> success(is_seed(s), s)
            seen |> insert(s)
        }
        t |> equal(length(seen), 50)
        // a longer night starts with the shorter one's seeds, so a cut night replays as a prefix
        let longer <- nightly_seeds(20261122, 60)
        t |> equal(join([for (idx in range(50)); longer[idx]], " "), join(first, " "))
    }
    t |> run("the start is the date's digits, or a decimal of one to nine digits") @(t : T?) {
        t |> equal(date_start("2026-11-22"), 20261122)
        t |> equal(date_start("2026-11"), -1)
        t |> equal(date_start("26-11-22"), -1)
        t |> equal(parse_start("7"), 7)
        t |> equal(parse_start("123456789"), 123456789)
        t |> equal(parse_start("1234567890"), -1)
        t |> equal(parse_start("12a"), -1)
        t |> equal(parse_start(""), -1)
    }
}

def night() : NightlyRun =>
    NightlyRun(date = "2026-11-22", start = 20261122, count = 6, tier = "interp", compiler = "gcc-14", replay = "CC=gcc-14 scripts/run_suite.sh csmith --nightly --start 20261122 --seeds 6 --tier interp")

def outcomes_of(statuses : array<string>) : array<Outcome> {
    var out <- [for (idx, status in count(), statuses); Outcome(id = "{idx + 1}", status = status, reason = "why {idx + 1}\nmore")]
    return <- out
}

[test]
def test_nightly_result(t : T?) {
    t |> run("the result file counts each verdict, lists its seeds, and gives a divergence its files and reducer line") @(t : T?) {
        let outcomes <- outcomes_of(["pass", "output", "convert", "native", "timeout", "exit"])
        let text = nightly_report(night(), "suites/csmith/work", outcomes, 61.5)
        let lines <- split(text, "\n")
        t |> success(lines[0] |> starts_with("# csmith nightly 2026-11-22: start seed 20261122, 6 seeds, tier interp"), text)
        t |> equal(lines[1], "# replay: CC=gcc-14 scripts/run_suite.sh csmith --nightly --start 20261122 --seeds 6 --tier interp")
        for (want in fixed_array("judged 6 of 6", "wall 61 s", "pass 1", "differs 2", "refused 1", "native 1", "timeout 1", "crash 0",
                "seeds differs: 2 6", "seeds refused: 3", "seeds native: 4", "seeds timeout: 5", "seeds crash: ", "seeds pass: 1",
                "differs 2: output: why 2", "  reduce: CC=gcc-14 suites/csmith/reduce.sh 2", "timeout 5: timeout: why 5",
                "  files: suites/csmith/work/6/", "  outputs: suites/csmith/work/6/6.native.out suites/csmith/work/6/6.das.out", "  files: suites/csmith/work/5/")) {
            t |> success(lines |> has_value(want), "no line `{want}` in:\n{text}")
        }
        t |> success(!(text |> contains("reduce.sh 5")), "a timeout gets no reducer line: {text}")
        t |> success(!(text |> contains("files: suites/csmith/work/3/")), "a refused seed keeps no files: {text}")
    }
    t |> run("the result file is dated and named by its start, a tier but the interpreter's named too") @(t : T?) {
        t |> equal(nightly_result_path("w", night()), "w/nightly/2026-11-22-20261122.txt")
        var jit = night()
        jit.tier = "jit"
        t |> equal(nightly_result_path("w", jit), "w/nightly/2026-11-22-20261122-jit.txt")
    }
    t |> run("a seed keeps its work folder only when it diverged, timed out or crashed") @(t : T?) {
        for (status in fixed_array("output", "exit", "timeout", "crash")) {
            t |> equal(keeps_files(status), true, status)
        }
        for (status in fixed_array("pass", "convert", "native")) {
            t |> equal(keeps_files(status), false, status)
        }
    }
    t |> run("the night exits 1 on any divergence, 0 otherwise") @(t : T?) {
        t |> equal(nightly_exit_code(outcomes_of(["pass", "convert", "native", "timeout", "crash"])), 0)
        t |> equal(nightly_exit_code(outcomes_of(["pass", "exit"])), 1)
        t |> equal(nightly_exit_code(outcomes_of(["output", "pass"])), 1)
    }
}

[test(timeout = 1200)]
def test_nightly_refusals(t : T?) {
    t |> run("a bad start or another mode beside --nightly exits 2 before any seed") @(t : T?) {
        for (flags in fixed_array("--nightly --start 12x", "--nightly --update")) {
            var out : string
            let rc = run_and_capture(["bash", "-c", "\"$1\" -load_module dasCRuntime -load_module c_runtime suites/csmith/run.das -- $2", "csmith", get_das_root() + "/bin/daslang", flags], out, 120.0)
            t |> equal(rc, 2, out)
            t |> success(out |> contains(flags == "--nightly --update" ? "--nightly judges fresh seeds alone" : "--start `12x` is not a decimal"), out)
        }
    }
}
