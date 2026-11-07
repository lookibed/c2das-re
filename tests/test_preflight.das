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

// the scratch suites: `slow` sleeps, then leaves `slow_done`; `fast` records whether `slow_done`
// was there when it ran; `red` fails with a marker
def private stand_ins(dir : string) {
    let done = path_join(dir, "slow_done")
    let saw = path_join(dir, "fast_saw")
    stand_in(dir, "slow", "    sleep(3000u)\n    fwrite(\"{done}\", \"\")\n    t |> success(true)\n")
    stand_in(dir, "fast", "    fwrite(\"{saw}\", fexist(\"{done}\") ? \"done\" : \"running\")\n    t |> success(true)\n")
    stand_in(dir, "red", "    t |> failure(\"STAND-IN-RED: the deliberately red suite\")\n")
}

// the tests lane over `groups` (`;` between groups, a space between the suites of one) with `jobs`
def private lane(groups : string; jobs : int; var out : string&) : int => run_and_capture(["bash", "-c", "PREFLIGHT_TEST_GROUPS=\"$1\" exec bash scripts/preflight.sh --only tests --jobs \"$2\" 2>&1", "lane", groups, "{jobs}"], out, 300.0)

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
        t |> success(before(out, "slow/test_slow.das", "fast/test_fast.das"), out)
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
        t |> success(before(out, "slow/test_slow.das", "red/test_red.das") && before(out, "red/test_red.das", "fast/test_fast.das"), out)
        t |> equal(fread(saw), "running", out)
    }
    t |> run("--jobs 1 runs the suites one after another in the listed order, the red one still red") @(t : T?) {
        remove(done)
        var out : string
        t |> equal(lane("{slow};{red};{fast}", 1, out), 1, out)
        t |> equal(fread(saw), "done", out)
        t |> success(out |> contains("STAND-IN-RED: the deliberately red suite"), out)
        t |> success(before(out, "slow/test_slow.das", "red/test_red.das") && before(out, "red/test_red.das", "fast/test_fast.das"), out)
    }
    t |> run("a --jobs that is not a positive count is refused") @(t : T?) {
        var out : string
        t |> equal(lane(fast, 0, out), 2, out)
        t |> success(out |> contains("--jobs takes a positive count"), out)
    }
    rmdir_rec(dir)
}
