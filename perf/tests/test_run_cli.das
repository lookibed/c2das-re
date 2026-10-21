options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require daslib/json_boost
require ../perf_cli.das

[test]
def test_run_help(t : T?) {
    t |> run("-? prints the help and exits before any kernel runs") @(t : T?) {
        var out : string
        let rc = run_and_capture(["bash", "scripts/run_perf.sh", "-?"], out, 60.0)
        t |> equal(rc, 0, out)
        t |> success(out |> contains("show this help and exit"), out)
        t |> success(!(out |> contains("Captured on")), out)
    }
}

// the argv the run logged for `kernel/lane`, "" when it logged none
def lane_argv(out, lane : string) : string {
    for (line in split(out, "\n")) {
        let at = find(line, "{lane}: ")
        if (at >= 0) {
            return strip(slice(line, at + length(lane) + 2))
        }
    }
    return ""
}

[test]
def test_run_blit_lanes(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_perf", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    let results = path_join(dir, "results.json")
    let committed = fread_text("perf/results_linux.json")
    var out : string
    // each das lane logs its argv at `info`
    let level = get_env_variable("DAS_LOG_LEVEL")
    set_env_variable("DAS_LOG_LEVEL", "info")
    let rc = run_and_capture(["bash", "scripts/run_perf.sh", "--filter", "blit", "--samples", "1", "--out", results], out, 1200.0)
    set_env_variable("DAS_LOG_LEVEL", level)
    var error : string
    let js = read_json(fread_text(results), error)
    t |> run("one blit sample runs every lane and writes the --out file, not the committed one") @(t : T?) {
        t |> equal(rc, 0, out)
        t |> equal(error, "", "{results}: {out}")
        t |> equal(js?["samples"] ?? 0l, 1l)
        t |> success(fread_text("perf/results_linux.json") == committed, "the run rewrote perf/results_linux.json")
    }
    t |> run("the interp-copy lane times the copy conversion and reproduces the native result") @(t : T?) {
        let blit = js?["tests"]?["blit"]
        t |> success((blit?["interp-copy"]?["time"] ?? 0.0lf) > 0.0lf, out)
        t |> equal(blit?["interp-copy"]?["result"] ?? -1l, blit?["native"]?["result"] ?? -2l, out)
        t |> success(lane_argv(out, "blit/interp-copy") |> ends_with(" perf/work/blit/copy/blit.das"), out)
        t |> success(lane_argv(out, "blit/interp") |> ends_with(" perf/work/blit/blit.das"), out)
    }
    t |> run("the copy lane's module copies blit's parameters, the in-place one does not") @(t : T?) {
        t |> success(fread_text("perf/work/blit/copy/blit.das") |> contains("src_in"))
        t |> success(!(fread_text("perf/work/blit/blit.das") |> contains("src_in")))
    }
    rmdir_rec(dir)
}
