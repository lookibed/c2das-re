options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require daslib/fio
require ../../suites/csmith/nightly.das
require ../../suites/csmith/verdict.das
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
    t |> run("the nights of consecutive starts share no seed and no bits: a seed's low half is not the previous night's high half") @(t : T?) {
        let night_a <- nightly_seeds(20261122, 1000)
        let night_b <- nightly_seeds(20261123, 1000)
        var in_a : table<string>
        for (s in night_a) {
            in_a |> insert(s)
        }
        t |> equal(length([for (s in night_b); s; where key_exists(in_a, s)]), 0)
        // under `random_seed(start)` all 1000 pairs match; unrelated nights match one in 32768
        var shared_halves = 0
        for (idx in range(1000)) {
            let low_b = (to_int(night_b[idx]) - 1) & 0x7fff
            let high_a = ((to_int(night_a[idx]) - 1) >> 15) & 0x7fff
            shared_halves += low_b == high_a ? 1 : 0
        }
        t |> success(shared_halves < 5, "{shared_halves} of 1000 seeds share the halves")
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
    NightlyRun(date = "2026-11-22", start = 20261122, count = 6, tier = "interp", compiler = "gcc-14", csmith_commit = "c0", csmith_options = "--no-argc", repo_commit = "r0", das_commit = "d0", replay = "CC=gcc-14 scripts/run_suite.sh csmith --nightly --start 20261122 --seeds 6 --tier interp")

// the seeds 1.. with these statuses, finished in reverse draw order
def finished_of(statuses : array<string>) : table<string; Outcome> {
    var out : table<string; Outcome>
    for (idx in range(length(statuses))) {
        let back = length(statuses) - 1 - idx
        out["{back + 1}"] = Outcome(id = "{back + 1}", status = statuses[back], reason = "why {back + 1}\nmore")
    }
    return <- out
}

def drawn_of(count : int) : array<string> => [for (idx in range(count)); "{idx + 1}"]

def outcomes_of(statuses : array<string>) : array<Outcome> => [for (idx, status in count(), statuses); Outcome(id = "{idx + 1}", status = status, reason = "")]

[test]
def test_nightly_result(t : T?) {
    t |> run("the result file counts judged seeds apart from the reference side's, lists each verdict in draw order, and gives a failure its files") @(t : T?) {
        let statuses <- ["pass", "output", "convert", "native", "timeout", "exit", "native-timeout", "crash", "pass"]
        let drawn <- drawn_of(10)
        let text = nightly_report(night(), "suites/csmith/work", drawn, finished_of(statuses), 61.5)
        let lines <- split(text, "\n")
        t |> success(lines[0] |> starts_with("# csmith nightly 2026-11-22: start seed 20261122, 6 seeds asked, tier interp"), text)
        t |> equal(lines[1], "# csmith c0, options --no-argc; c2das-re r0; daScript d0")
        t |> equal(lines[2], "# replay: CC=gcc-14 scripts/run_suite.sh csmith --nightly --start 20261122 --seeds 6 --tier interp")
        t |> equal(lines[3], "judged 7 of 6 asked, drew 10, native-timeout 1")
        t |> equal(lines[4], "draw cap 9")
        for (want in fixed_array("wall 61 s", "pass 2", "differs 2", "refused 1", "timeout 1", "crash 1", "native 1", "native-timeout 1",
                "seeds differs: 2 6", "seeds refused: 3", "seeds native: 4", "seeds timeout: 5", "seeds native-timeout: 7", "seeds crash: 8", "seeds pass: 1 9",
                "differs 2: output: why 2", "  reduce: CC=gcc-14 suites/csmith/reduce.sh 2", "timeout 5: timeout: why 5", "crash 8: crash: why 8",
                "  files: suites/csmith/work/6/", "  outputs: suites/csmith/work/6/6.native.out suites/csmith/work/6/6.das.out", "  files: suites/csmith/work/5/")) {
            t |> success(lines |> has_value(want), "no line `{want}` in:\n{text}")
        }
        t |> success(!(text |> contains("reduce.sh 5")), "a timeout gets no reducer line: {text}")
        t |> success(!(text |> contains("files: suites/csmith/work/3/")), "a refused seed keeps no files: {text}")
        t |> success(!(text |> contains("files: suites/csmith/work/7/")), "a native timeout keeps no files: {text}")
        t |> success(find(text, "differs 2:") < find(text, "timeout 5:") && find(text, "timeout 5:") < find(text, "differs 6:"), "failures in draw order: {text}")
    }
    t |> run("a night that drew its cap short of N says so") @(t : T?) {
        let statuses <- ["pass", "native-timeout", "native-timeout", "pass", "native", "native-timeout", "pass", "native-timeout", "pass"]
        let text = nightly_report(night(), "w", drawn_of(9), finished_of(statuses), 1.0)
        t |> success(text |> contains("judged 4 of 6 asked, drew 9, native-timeout 4\ndraw cap 9 hit: the night judged 4 seeds, not 6\n"), text)
    }
    t |> run("the result file is dated and named by its start, a tier but the interpreter's named too") @(t : T?) {
        t |> equal(nightly_result_path("w", night()), "w/nightly/2026-11-22-20261122.txt")
        var jit = night()
        jit.tier = "jit"
        t |> equal(nightly_result_path("w", jit), "w/nightly/2026-11-22-20261122-jit.txt")
    }
    t |> run("the result file is replaced whole, through a temporary file") @(t : T?) {
        let path = path_join(test_temp_dir(), "night.txt")
        t |> equal(write_atomically(path, "one\n"), true)
        t |> equal(write_atomically(path, "two\n"), true)
        t |> equal(fread(path), "two\n")
        t |> equal(fexist("{path}.tmp"), false)
    }
    t |> run("a timeout of csmith or the native run is the reference side's, any other timeout the converter's") @(t : T?) {
        t |> equal(night_status(Verdict(status = "timeout", signature = "timeout {CSMITH_STAGE}")), "native-timeout")
        t |> equal(night_status(Verdict(status = "timeout", signature = "timeout {NATIVE_STAGE}")), "native-timeout")
        t |> equal(night_status(Verdict(status = "timeout", signature = "timeout the converted run")), "timeout")
        t |> equal(night_status(Verdict(status = "native", signature = "timeout {NATIVE_STAGE}")), "native")
        for (status in fixed_array("pass", "output", "exit", "convert", "timeout", "crash")) {
            t |> equal(is_judged(status), true, status)
        }
        t |> equal(is_judged("native"), false)
        t |> equal(is_judged("native-timeout"), false)
        t |> equal(draw_cap(1000), 1500)
    }
    t |> run("a seed keeps its work folder only when it diverged, timed out on the converter's side or crashed") @(t : T?) {
        for (status in fixed_array("output", "exit", "timeout", "crash")) {
            t |> equal(keeps_files(status), true, status)
        }
        for (status in fixed_array("pass", "convert", "native", "native-timeout")) {
            t |> equal(keeps_files(status), false, status)
        }
    }
    t |> run("the night exits 1 on any divergence or converter-side timeout, 0 otherwise") @(t : T?) {
        t |> equal(nightly_exit_code(outcomes_of(["pass", "convert", "native", "native-timeout", "crash"])), 0)
        t |> equal(nightly_exit_code(outcomes_of(["pass", "exit"])), 1)
        t |> equal(nightly_exit_code(outcomes_of(["output", "pass"])), 1)
        t |> equal(nightly_exit_code(outcomes_of(["pass", "timeout"])), 1)
    }
    t |> run("a night runs once per date and start: refused while one runs, and over its result file unless forced") @(t : T?) {
        t |> success(night_refusal("r.txt", false, "77", false) |> contains("is running (pid 77)"))
        t |> success(night_refusal("r.txt", true, "77", true) |> contains("is running (pid 77)"))
        t |> success(night_refusal("r.txt", true, "", false) |> contains("r.txt exists"))
        t |> equal(night_refusal("r.txt", true, "", true), "")
        t |> equal(night_refusal("r.txt", false, "", false), "")
    }
}

[test(timeout = 1200)]
def test_nightly_refusals(t : T?) {
    t |> run("a bad start, no seeds, or another mode beside --nightly exits 2 before any seed") @(t : T?) {
        let cases <- [("--nightly --start 12x", "--start `12x` is not a decimal"), ("--nightly --update", "--nightly judges fresh seeds alone"),
            ("--nightly --one 5", "--nightly judges fresh seeds alone"), ("--nightly --check x.c", "--nightly judges fresh seeds alone"),
            ("--nightly --seeds 0", "--nightly --seeds 0 judges nothing")]
        for (c in cases) {
            var out : string
            let rc = run_and_capture(["bash", "-c", "\"$1\" -load_module dasCRuntime -load_module c_runtime suites/csmith/run.das -- $2", "csmith", get_das_root() + "/bin/daslang", c._0], out, 120.0)
            t |> equal(rc, 2, out)
            t |> success(out |> contains(c._1), out)
        }
    }
}
