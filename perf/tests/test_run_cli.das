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
    t |> run("the interp-while lane times the --loops while conversion and reproduces the native result") @(t : T?) {
        let blit = js?["tests"]?["blit"]
        t |> success((blit?["interp-while"]?["time"] ?? 0.0lf) > 0.0lf, out)
        t |> equal(blit?["interp-while"]?["result"] ?? -1l, blit?["native"]?["result"] ?? -2l, out)
        t |> success(lane_argv(out, "blit/interp-while") |> ends_with(" perf/work/blit/while/blit.das"), out)
        // the harness's own counting loop is the one canonical `for` of the program
        t |> success(fread("perf/work/blit/blit.das") |> contains(" in range64(reps)"))
        t |> success(!(fread("perf/work/blit/while/blit.das") |> contains(" in range")))
    }
    t |> run("the interp-reinterpret lane times the --first-member reinterpret conversion and reproduces the native result") @(t : T?) {
        let blit = js?["tests"]?["blit"]
        t |> success((blit?["interp-reinterpret"]?["time"] ?? 0.0lf) > 0.0lf, out)
        t |> equal(blit?["interp-reinterpret"]?["result"] ?? -1l, blit?["native"]?["result"] ?? -2l, out)
        t |> success(lane_argv(out, "blit/interp-reinterpret") |> ends_with(" perf/work/blit/reinterpret/blit.das"), out)
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

[test]
def test_run_method(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_perf_method", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    t |> run("--method nope is a usage error") @(t : T?) {
        var out : string
        t |> equal(run_and_capture(["bash", "scripts/run_perf.sh", "--method", "nope"], out, 60.0), 2, out)
        t |> success(out |> contains("--method is default or dasprofile, not `nope`"), out)
    }
    let results = path_join(dir, "method.json")
    let baseline = path_join(dir, "baseline.json")
    // a baseline whose every time is far off, so --check finds every cell drifted
    fwrite(baseline, "\{\"cpu\": \"{cpu_name_line()}\", \"lanes\": [\"native\", \"interp\"], \"tests\": \{\"fib_recursive\": \{\"native\": \{\"time\": 100.0\}, \"interp\": \{\"time\": 100.0\}\}\}\}\n")
    var out : string
    let rc = run_and_capture(["bash", "scripts/run_perf.sh", "--method", "dasprofile", "--filter", "fib", "--samples", "1", "--out", results, "--baseline", baseline, "--check"], out, 1800.0)
    var error : string
    let js = read_json(fread(results), error)
    t |> run("the dasprofile method measures the shared kernels' five lanes on the method's program") @(t : T?) {
        t |> equal(error, "", "{results}: {out}")
        t |> equal(js?["method"] ?? "", "dasprofile", out)
        t |> equal(join([for (lane in (js?["lanes"]).value as _array); lane ?? ""], " "), "native interp jit exe aot", out)
        for (kernel in ["fib_loop", "fib_recursive"]) {
            let row = js?["tests"]?[kernel]
            for (lane in ["native", "interp", "jit", "exe", "aot"]) {
                t |> success((row?[lane]?["time"] ?? 0.0lf) > 0.0lf, "{kernel}/{lane}: {out}")
            }
            t |> equal(row?["interp"]?["result"] ?? -1l, row?["native"]?["result"] ?? -2l, out)
        }
        t |> equal(length((js?["tests"]).value as _object), 2, out)
        t |> success(fread("perf/work/fib_loop/method/fib_loop.das") |> contains("c_volatile_store(fib_loop__c2das_sink, fib_loop__kernel_result())"))
    }
    t |> run("--check exits 1 naming each cell past the tolerance and each cell one capture lacks") @(t : T?) {
        t |> equal(rc, 1, out)
        t |> success(out |> contains("--check: fib_recursive/native -"), out)
        t |> success(out |> contains("--check: fib_loop/native missing"), out)
    }
    t |> run("--table under the method renders the committed capture, its delta against HEAD's and the comparison with dasProfile's") @(t : T?) {
        var shown : string
        t |> equal(run_and_capture(["bash", "scripts/run_perf.sh", "--method", "dasprofile", "--table"], shown, 120.0), 0, shown)
        t |> success(shown |> contains("Delta against HEAD:perf/results_method_linux.json"), shown)
        t |> success(shown |> contains("The dasProfile method on "), shown)
        t |> success(shown |> contains("| primes "), shown)
    }
    rmdir_rec(dir)
}

// the CPU model the harness records, so a fixture baseline compares times on this machine
def cpu_name_line : string {
    for (line in split(fread("/proc/cpuinfo"), "\n")) {
        if (line |> starts_with("model name")) {
            return strip(slice(line, find(line, ":") + 1))
        }
    }
    return "unknown cpu"
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

// `perf/dasprofile_capture.das` run with `args` through the repository's module setup: its exit code
def capture_run(args : string; var out : string&) : int => run_and_capture(["bash", "-c", ". scripts/env.sh && das perf/dasprofile_capture.das -- {args}"], out, 120.0)

[test]
def test_dasprofile_capture(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_dasprofile_capture", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    let input = path_join(dir, "in.json")
    let written = path_join(dir, "out.json")
    t |> run("without --input and --commit the help is printed and the exit is 2") @(t : T?) {
        var out : string
        t |> equal(capture_run("--out {written}", out), 2, out)
        t |> success(out |> contains("the dasProfile commit the capture ran"), out)
    }
    t |> run("an input that is no JSON object is an error naming the file") @(t : T?) {
        fwrite(input, "[1, 2]\n")
        var out : string
        t |> equal(capture_run("--input {input} --commit abc --out {written}", out), 1, out)
        t |> success(out |> contains("{input}: not a JSON object"), out)
    }
    t |> run("the capture is copied with the commit and the toolchain line stamped on") @(t : T?) {
        fwrite(input, "\{\"versions\": \{\"cpp_compiler\": \"Clang 22\", \"daslang\": \"0.6.4\", \"llvm\": \"22.1.5\"\}, \"cpu\": \"C\"\}\n")
        var out : string
        t |> equal(capture_run("--input {input} --commit abc --out {written}", out), 0, out)
        var error : string
        let js = read_json(fread(written), error)
        t |> equal(error, "", fread(written))
        t |> equal(js?["dasprofile_commit"] ?? "", "abc")
        t |> equal(js?["toolchain"] ?? "", "Clang 22, daslang 0.6.4, LLVM 22.1.5")
        t |> equal(js?["cpu"] ?? "", "C")
    }
    rmdir_rec(dir)
}
