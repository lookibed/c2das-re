options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require daslib/fio
require ../../suites/csmith/verdict.das
require ../../suites/suite_runner.das

//! The csmith driver's reading of a worker that ended: its verdict, `timeout` when killed,
//! `crash` when it exited on its own without a verdict file.

[test]
def test_csmith_verdict(t : T?) {
    t |> run("a worker that exits without a verdict is a crash, one the driver killed a timeout") @(t : T?) {
        var dir_error : string
        let dir = create_temp_directory("c2das_csmith_verdict", dir_error)
        t |> equal(dir_error, "")
        let c_path = path_join(dir, "7.c")
        let none = read_verdict(c_path)
        t |> equal(none.status, "")
        let crash = worker_outcome("7", false, 3, 900.0, none)
        t |> equal(crash.status, "crash")
        t |> equal(crash.reason, "the worker exited 3 without a verdict")
        let killed = worker_outcome("7", true, -1, 900.0, none)
        t |> equal(killed.status, "timeout")
        t |> equal(killed.reason, "the worker took longer than 900 s")
        write_verdict(c_path, Verdict(status = "output", signature = "output", reason = "got `a`"))
        let written = worker_outcome("7", false, 0, 900.0, read_verdict(c_path))
        t |> equal(written.status, "output")
        t |> equal(written.reason, "got `a`")
        if (!empty(dir)) {
            rmdir_rec(dir)
        }
    }
    t |> run("the skip audit reads a worker's verdict by its stage: a convert verdict is the stage its reason names") @(t : T?) {
        var dir_error : string
        let dir = create_temp_directory("c2das_csmith_audit", dir_error)
        t |> equal(dir_error, "")
        let c_path = path_join(dir, "9.c")
        write_verdict(c_path, Verdict(status = "convert", signature = "x", reason = "emitter: 9.c:3:1: goto into a loop, branch or switch body"))
        let row = audit_row("goto into a loop, branch or switch body", worker_outcome("9", false, 0, 900.0, read_verdict(c_path)))
        t |> equal(row.status, "emitter")
        t |> equal(row.id, "9")
        let killed = audit_row("f", worker_outcome("9", true, -1, 900.0, Verdict()))
        t |> equal(killed.status, "timeout")
        // the driver's own statuses pass through: a native side that failed, a worker with no verdict
        write_verdict(c_path, Verdict(status = "native", signature = "native", reason = "gcc exited 1"))
        t |> equal(audit_row("f", worker_outcome("9", false, 0, 900.0, read_verdict(c_path))).status, "native")
        t |> equal(audit_row("f", worker_outcome("9", false, 3, 900.0, Verdict())).status, "crash")
        if (!empty(dir)) {
            rmdir_rec(dir)
        }
    }
}

[test]
def test_csmith_tier(t : T?) {
    t |> run("a worker gets its args after `--one <id>`") @(t : T?) {
        var dir_error : string
        let dir = create_temp_directory("c2das_csmith_worker", dir_error)
        t |> equal(dir_error, "")
        let script = path_join(dir, "echo.das")
        fwrite(script, "options gen2\nrequire daslib/strings_boost\n[export]\ndef main \{\n    let args <- get_command_line_arguments()\n    print(\"\{join(args, \" \")\}\\n\")\n\}\n")
        var seen : string
        run_workers(1, 1, 120.0, $(_index) => spawn_one(script, "7", path_join(dir, "stale"), ["--tier", "jit"])) $(_index, _killed, _rc, output) {
            seen = output
        }
        t |> success(seen |> contains("-- --one 7 --tier jit"), seen)
        if (!empty(dir)) {
            rmdir_rec(dir)
        }
    }
    t |> run("the reference compiler is CC, gcc when CC is unset or empty") @(t : T?) {
        let saved = get_env_variable("CC")
        set_env_variable("CC", "gcc-14")
        t |> equal(reference_compiler(), "gcc-14")
        set_env_variable("CC", "")
        t |> equal(reference_compiler(), "gcc")
        set_env_variable("CC", saved)
    }
    t |> run("the version check runs CC: a CC that is no compiler exits 2 naming it, before any seed") @(t : T?) {
        var out : string
        let rc = run_and_capture(["bash", "-c", "CC=c2das_no_such_cc \"$1\" -load_module dasCRuntime -load_module c_runtime suites/csmith/run.das -- --seeds 1", "csmith", get_das_root() + "/bin/daslang"], out, 120.0)
        t |> equal(rc, 2, out)
        t |> success(out |> contains("c2das_no_such_cc is ``, VERSIONS.md pins gcc `"), out)
    }
    t |> run("an unknown tier exits 2 naming the tiers, --update under the exe exits 2, before any seed") @(t : T?) {
        for (flags in fixed_array("--tier aot", "--tier exe --update --seeds 0")) {
            var out : string
            let rc = run_and_capture(["bash", "-c", "\"$1\" -load_module dasCRuntime -load_module c_runtime suites/csmith/run.das -- $2", "csmith", get_das_root() + "/bin/daslang", flags], out, 120.0)
            t |> equal(rc, 2, out)
            t |> success(out |> contains(flags == "--tier aot" ? "unknown tier `aot`: one of interp, jit, exe" : "--update records the interpreter's ratchet"), out)
        }
    }
}
