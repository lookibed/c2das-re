options gen2
// the pipeline parses clang's JSON dump below its own frames: a deep expression tree overflows
// the default 16 KB context stack, and dastest gives its tests this much
options stack = 1048576

require ../suite_runner.das

//! The GCC c-torture `execute` runner (`scripts/run_suite.sh gcc_torture`): a test passes when
//! its module exits 0, the harness's own contract (a failing test calls `abort`); its output
//! is not judged, as gcc's harness does not judge it.

def verdict(id : string; _c_path : string; rc : int; output : string) : Outcome =>
    rc != 0 ? Outcome(id = id, status = "exit", reason = "exited {rc}: {first_line(output)}") : Outcome(id = id, status = "pass", reason = "")

[export]
def main : int {
    let spec = SuiteSpec(name = "gcc_torture", tests_dir = GCC_TORTURE_TESTS, work_dir = "suites/gcc_torture/work", expected_pass = "suites/gcc_torture/expected_pass.txt", skip_ledger = "suites/gcc_torture/skip.txt", run_timeout = 20.0)
    return run_suite_main(spec, @@verdict)
}
