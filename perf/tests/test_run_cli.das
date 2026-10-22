options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require daslib/json_boost

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
    let committed = fread("perf/results_linux.json")
    var out : string
    // each das lane logs its argv at `info`
    let level = get_env_variable("DAS_LOG_LEVEL")
    set_env_variable("DAS_LOG_LEVEL", "info")
    let rc = run_and_capture(["bash", "scripts/run_perf.sh", "--filter", "blit", "--samples", "2", "--out", results], out, 1200.0)
    set_env_variable("DAS_LOG_LEVEL", level)
    var error : string
    let js = read_json(fread(results), error)
    t |> run("two blit samples run every lane and write the --out file, not the committed one") @(t : T?) {
        t |> equal(rc, 0, out)
        t |> equal(error, "", "{results}: {out}")
        t |> equal(js?["samples"] ?? 0l, 2l)
        t |> success(fread("perf/results_linux.json") == committed, "the run rewrote perf/results_linux.json")
    }
    t |> run("the interp-copy lane times the copy conversion and reproduces the native result") @(t : T?) {
        let blit = js?["tests"]?["blit"]
        t |> success((blit?["interp-copy"]?["time"] ?? 0.0lf) > 0.0lf, out)
        t |> equal(blit?["interp-copy"]?["result"] ?? -1l, blit?["native"]?["result"] ?? -2l, out)
        t |> success(lane_argv(out, "blit/interp-copy") |> ends_with(" perf/work/blit/copy/blit.das"), out)
        t |> success(lane_argv(out, "blit/interp") |> ends_with(" perf/work/blit/blit.das"), out)
        t |> success(lane_argv(out, "blit/jit") |> ends_with(" -jit perf/work/blit/blit.das"), out)
    }
    t |> run("a cell of two samples has their spread") @(t : T?) {
        let native = js?["tests"]?["blit"]?["native"]
        t |> success((native?["spread"] ?? 0.0lf) > 0.0lf, out)
    }
    t |> run("the copy lane's module copies blit's parameters, the in-place one does not") @(t : T?) {
        t |> success(fread("perf/work/blit/copy/blit.das") |> contains("src_in"))
        t |> success(!(fread("perf/work/blit/blit.das") |> contains("src_in")))
    }
    rmdir_rec(dir)
}

// an executable at `path` an earlier run could have left, which prints a result and succeeds: a
// lane whose build fails must not time it
def plant_stale_binary(path : string) {
    mkdir_rec(dir_name(path))
    fwrite(path, "#!/bin/sh\necho 1\nexit 0\n")
    var out : string
    run_and_capture(["chmod", "+x", path], out, 10.0)
}

// a toolchain folder for `PATH_TO_LIBCLANG` whose `clang` is the pinned one and whose `clang++`,
// the AOT host's compiler, prints a line and fails: the lane's error must carry that line
def failing_link_toolchain(dir, clang : string) : string {
    let bin = path_join(path_join(dir, "toolchain"), "bin")
    mkdir_rec(bin)
    fwrite(path_join(bin, "clang"), "#!/bin/sh\nexec {clang} \"$@\"\n")
    fwrite(path_join(bin, "clang++"), "#!/bin/sh\necho fake link failure\nexit 1\n")
    var out : string
    run_and_capture(["chmod", "+x", path_join(bin, "clang"), path_join(bin, "clang++")], out, 10.0)
    return path_join(dir, "toolchain")
}

[test]
def test_run_failed_aot_link(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_perf_link", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    let pinned = has_env_variable("PATH_TO_LIBCLANG") ? get_env_variable("PATH_TO_LIBCLANG") : ""
    let clang = empty(pinned) ? "clang" : pinned + "/bin/clang"
    var out : string
    set_env_variable("PATH_TO_LIBCLANG", failing_link_toolchain(dir, clang))
    plant_stale_binary("perf/work/fib_recursive/ctx/fib_recursive_aot")
    let rc = run_and_capture(["bash", "scripts/run_perf.sh", "--filter", "fib_recursive", "--samples", "1", "--out", path_join(dir, "results.json")], out, 1200.0)
    set_env_variable("PATH_TO_LIBCLANG", pinned)
    t |> run("a failed AOT host build is the lane's error, carrying the build's output, never an earlier binary's run") @(t : T?) {
        t |> equal(rc, 1, out)
        t |> success(out |> contains("fib_recursive/aot: the build exited 1 and left no binary: fake link failure"), out)
    }
    rmdir_rec(dir)
}

// a folder for the front of `PATH` whose `c++`, the linker daslang's `-exe` build calls, prints a
// line and fails: the exe lane's error must carry that build's diagnostic
def failing_exe_linker(dir : string) : string {
    let bin = path_join(dir, "linker")
    mkdir_rec(bin)
    fwrite(path_join(bin, "c++"), "#!/bin/sh\necho fake exe link failure\nexit 1\n")
    var out : string
    run_and_capture(["chmod", "+x", path_join(bin, "c++")], out, 10.0)
    return bin
}

[test]
def test_run_failed_exe_link(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_perf_exe", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    let path = get_env_variable("PATH")
    var out : string
    set_env_variable("PATH", "{failing_exe_linker(dir)}:{path}")
    plant_stale_binary("perf/work/fib_recursive/fib_recursive_exe")
    let rc = run_and_capture(["bash", "scripts/run_perf.sh", "--filter", "fib_recursive", "--samples", "1", "--out", path_join(dir, "results.json")], out, 1200.0)
    set_env_variable("PATH", path)
    t |> run("a failed exe build is the lane's error, carrying the build's diagnostic, never an earlier binary's run") @(t : T?) {
        t |> equal(rc, 1, out)
        t |> success(out |> contains("fib_recursive/exe: the build exited 1 and left no binary: fake exe link failure"), out)
    }
    rmdir_rec(dir)
}
