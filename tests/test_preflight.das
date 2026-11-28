options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require daslib/fio

//! `scripts/preflight.sh --only tests` over stand-in suites in a scratch folder: `PREFLIGHT_TEST_GROUPS`
//! replaces the lane's groups, so the lane's scheduling, its output order and its verdict are the
//! script's own, the suites small

// a stand-in suite `name` under `dir`: one test file whose test runs `body`
def private stand_in(dir, name, body : string) {
    mkdir_rec(path_join(dir, name))
    fwrite(path_join(dir, "{name}/test_{name}.das"), "options gen2\nrequire dastest/testing_boost public\nrequire daslib/fio\n\n[test]\ndef test_{name}(t : T?) \{\n{body}\}\n")
}

// the scratch suites: `slow` sleeps, prints a marker and leaves `slow_done`; `fast` records whether
// `slow_done` was there when it ran and where its stdout goes (a pipe stays `/proc/self/fd/1`, a
// buffered suite's log resolves to that file); `red` fails with a marker; `iso` holds two files
def private stand_ins(dir : string) {
    let done = path_join(dir, "slow_done")
    let saw = path_join(dir, "fast_saw")
    let fd1 = path_join(dir, "fast_fd1")
    stand_in(dir, "slow", "    sleep(3000u)\n    print(\"SLOW-AFTER-SLEEP\\n\")\n    fwrite(\"{done}\", \"\")\n    t |> success(true)\n")
    stand_in(dir, "fast", "    fwrite(\"{saw}\", fexist(\"{done}\") ? \"done\" : \"running\")\n    fwrite(\"{fd1}\", get_full_file_name(\"/proc/self/fd/1\"))\n    t |> success(true)\n")
    stand_in(dir, "red", "    t |> failure(\"STAND-IN-RED: the deliberately red suite\")\n")
    stand_in(dir, "iso", "    t |> success(true)\n")
    fwrite(path_join(dir, "iso/test_iso2.das"), fread(path_join(dir, "iso/test_iso.das")) |> replace("test_iso(", "test_iso2("))
}

// the tests lane over `groups` (`;` between groups, a space between the suites of one) with `jobs`,
// `isolated` naming the suites that run under dastest's isolated mode
def private lane(groups, jobs, isolated : string; var out : string&) : int {
    let cmd = "PREFLIGHT_TEST_GROUPS=\"$1\" PREFLIGHT_ISOLATED_SUITES=\"$3\" exec bash scripts/preflight.sh --only tests --jobs \"$2\" 2>&1"
    return run_and_capture(["bash", "-c", cmd, "lane", groups, jobs, isolated], out, 300.0)
}

def private lane(groups : string; jobs : int; var out : string&) : int => lane(groups, "{jobs}", "", out)

// the tests lane over `groups` with `jobs`, `timeouts` the suites' whole-run budgets (`suite=seconds`, a space between)
def private budgeted_lane(groups, jobs, timeouts : string; var out : string&) : int {
    let cmd = "PREFLIGHT_TEST_GROUPS=\"$1\" PREFLIGHT_ISOLATED_SUITES= PREFLIGHT_SUITE_TIMEOUTS=\"$3\" exec bash scripts/preflight.sh --only tests --jobs \"$2\" 2>&1"
    return run_and_capture(["bash", "-c", cmd, "lane", groups, jobs, timeouts], out, 300.0)
}

// whether `first` appears in `out` before `second`, both present
def private before(out, first, second : string) : bool {
    let a = find(out, first)
    let b = find(out, second)
    return a >= 0 && b >= 0 && a < b
}

[test]
def test_parallel_lane(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_preflight_lane", dir_error)
    t |> equal(dir_error, "")
    stand_ins(dir)
    let slow = path_join(dir, "slow")
    let fast = path_join(dir, "fast")
    let red = path_join(dir, "red")
    let saw = path_join(dir, "fast_saw")
    let done = path_join(dir, "slow_done")
    t |> run("groups run at once; each suite's output prints in the listed order, not the finishing one") @(t : T?) {
        remove(done)
        var out : string
        t |> equal(lane("{slow};{fast}", 2, out), 0, out)
        t |> equal(fread(saw), "running", "fast ran while slow slept: {out}")
        t |> success(before(out, "SLOW-AFTER-SLEEP", "fast/test_fast.das"), "slow's output, printed after its sleep, comes first: {out}")
        t |> success(fread(path_join(dir, "fast_fd1")) |> ends_with(".log"), "a parallel suite's output is buffered in a file")
        t |> success(out |> contains("[PASS] tests"), out)
    }
    t |> run("the suites of one group run one after another") @(t : T?) {
        remove(done)
        var out : string
        t |> equal(lane("{slow} {fast}", 2, out), 0, out)
        t |> equal(fread(saw), "done", out)
    }
    t |> run("a red suite fails the lane under parallelism, its failure text printed, the others still run") @(t : T?) {
        remove(done)
        var out : string
        t |> equal(lane("{slow};{red};{fast}", 3, out), 1, out)
        t |> success(out |> contains("STAND-IN-RED: the deliberately red suite"), out)
        t |> success(out |> contains("[FAIL] tests - a suite is red"), out)
        t |> success(before(out, "SLOW-AFTER-SLEEP", "red/test_red.das") && before(out, "red/test_red.das", "fast/test_fast.das"), out)
        t |> equal(fread(saw), "running", out)
    }
    t |> run("--jobs 1 runs the suites one after another in the listed order, the red one still red") @(t : T?) {
        remove(done)
        var out : string
        t |> equal(lane("{slow};{red};{fast}", 1, out), 1, out)
        t |> equal(fread(saw), "done", out)
        t |> equal(fread(path_join(dir, "fast_fd1")), "/proc/self/fd/1", "a sequential suite's output streams")
        t |> success(out |> contains("STAND-IN-RED: the deliberately red suite"), out)
        t |> success(before(out, "slow/test_slow.das", "red/test_red.das") && before(out, "red/test_red.das", "fast/test_fast.das"), out)
    }
    t |> run("a --jobs that is not a positive count is refused") @(t : T?) {
        for (jobs in ["0", "00", "", "abc"]) {
            var out : string
            t |> equal(lane(fast, jobs, "", out), 2, "--jobs '{jobs}': {out}")
            t |> success(out |> contains("--jobs takes a positive count"), "--jobs '{jobs}': {out}")
        }
    }
    t |> run("a named suite folder that does not exist is a red lane naming it") @(t : T?) {
        let missing = path_join(dir, "no/such/suite")
        var out : string
        t |> equal(lane("{fast};{missing}", 2, out), 1, out)
        t |> success(out |> contains("[FAIL] tests - PREFLIGHT_TEST_GROUPS names {missing}, no such suite folder"), out)
    }
    t |> run("an isolated suite runs each file in its own worker; --jobs 1 runs it single-threaded") @(t : T?) {
        let iso = path_join(dir, "iso")
        var out : string
        t |> equal(lane("{iso};{fast}", "2", iso, out), 0, out)
        t |> success(out |> contains("Running 2 tests in isolated mode"), out)
        t |> equal(lane("{iso};{fast}", "2", "", out), 0, out)
        t |> success(!(out |> contains("isolated mode")), out)
        t |> equal(lane("{iso};{fast}", "1", iso, out), 0, out)
        t |> success(!(out |> contains("isolated mode")), out)
    }
    t |> run("a suite's budget bounds its whole run, in parallel and with --jobs 1; a suite without one keeps dastest's") @(t : T?) {
        var out : string
        for (jobs in ["2", "1"]) {
            t |> equal(budgeted_lane("{slow};{fast}", jobs, "{slow}=1", out), 1, "--jobs {jobs}: {out}")
            t |> success(out |> contains("[FAIL] tests - a suite is red"), "--jobs {jobs}: {out}")
            t |> success(!(out |> contains("SLOW-AFTER-SLEEP")), "--jobs {jobs}: {out}")
            t |> equal(budgeted_lane("{slow};{fast}", jobs, "{fast}=1", out), 0, "--jobs {jobs}: {out}")
            t |> success(out |> contains("SLOW-AFTER-SLEEP"), "--jobs {jobs}: {out}")
        }
    }
    rmdir_rec(dir)
}

// `scripts/preflight.sh --only lint` over the `.das` files of `dir` alone, at env.sh's log level
def private lint_gate(dir : string; var out : string&) : int {
    let cmd = "DAS_LOG_LEVEL=info PREFLIGHT_DAS_DIRS=\"$1\" exec bash scripts/preflight.sh --only lint 2>&1"
    return run_and_capture(["bash", "-c", cmd, "lint", dir], out, 300.0)
}

[test(description = "the lint gate reads any output as findings: a compile's LOG_INFO lines never reach it, a real finding still turns it red", timeout = 600)]
def test_lint_gate(t : T?) {
    var dir_error : string
    let root = create_temp_directory("c2das_preflight_lint", dir_error)
    t |> equal(dir_error, "")
    let clean = path_join(root, "clean")
    mkdir_rec(clean)
    let scanner = path_join(clean, "scanner.das")
    fwrite(scanner, "options gen2\n\nrequire flex/flex_macro\n\n//! a stand-in scanner\n[flex]\ndef scan(var lx : FlexLexer) : bool \{\n    rule(\"a\") \{\n        lx |> emit(1)\n    \}\n\}\n")
    let red = path_join(root, "red")
    mkdir_rec(red)
    fwrite(path_join(red, "finding.das"), "options gen2\n\n//! a stand-in with one finding\ndef probe : int \{\n    var x = 1\n    return x\n\}\n")
    t |> run("the stand-in's compile logs at LOG_INFO, which env.sh's level shows") @(t : T?) {
        var out : string
        let cmd = ". scripts/env.sh && DAS_LOG_LEVEL=info das \"$DASLANG_ROOT/utils/lint/main.das\" -- \"$1\" --quiet 2>&1"
        let rc = run_and_capture(["bash", "-c", cmd, "lint", scanner], out, 300.0)
        t |> equal(rc, 0, out)
        t |> success(out |> contains("[I] [flex] scan"), out)
    }
    t |> run("a clean folder whose compile logs at LOG_INFO passes the gate, no log line in its output") @(t : T?) {
        var out : string
        let rc = lint_gate(clean, out)
        t |> equal(rc, 0, out)
        t |> success(out |> contains("[PASS] lint"), out)
        t |> success(!(out |> contains("[I] ")), out)
    }
    t |> run("a planted finding turns the gate red, the finding printed") @(t : T?) {
        var out : string
        let rc = lint_gate(red, out)
        t |> equal(rc, 1, out)
        t |> success(out |> contains("LINT003"), out)
        t |> success(out |> contains("[FAIL] lint - findings above"), out)
    }
    rmdir_rec(root)
}
