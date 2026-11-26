options gen2
require dastest/testing_boost public
require strings
require daslib/fio

//! `frontend/REVIEW.das` run as a review round runs it, a child daslang started in a root folder:
//! `main` gates that folder's `frontend/`, and the exit code is the verdict. The test lives here
//! because the gate bans every process start under `frontend/`.

// the gate run with `root` as its working folder, its output in `out`
def private run_gate(root : string; var out : string&) : int {
    var inscope no_env : array<string>
    return run_and_capture([path_join(get_das_root(), "bin/daslang"), path_join(getcwd(), "frontend/REVIEW.das")], root, no_env, out, 300.0)
}

[test(description = "the frontend gate passes on this tree and fails on a root whose frontend/ requires the clang binding", timeout = 1200)]
def test_frontend_gate_runs(t : T?) {
    t |> run("the gate is green on the repository") @(t : T?) {
        var out : string
        t |> equal(run_gate(getcwd(), out), 0, out)
    }
    t |> run("the gate is red on a root whose frontend/ holds a file that requires cbind") @(t : T?) {
        let root = path_join(test_temp_dir(), "gate_root")
        mkdir_rec(path_join(root, "frontend/sub"))
        fwrite(path_join(root, "frontend/sub/x.das"), "options gen2\nrequire cbind\n")
        var out : string
        t |> equal(run_gate(root, out), 1, out)
        t |> success(find(out, "frontend/sub/x.das:2: requires `cbind`: nothing under frontend/ needs clang") >= 0, out)
    }
}
