options gen2
require dastest/testing_boost public
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
        if (!empty(dir)) {
            rmdir_rec(dir)
        }
    }
}
