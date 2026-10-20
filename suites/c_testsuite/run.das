options gen2
// the pipeline parses clang's JSON dump below its own frames: a deep expression tree overflows
// the default 16 KB context stack, and dastest gives its tests this much
options stack = 1048576

require daslib/fio
require ../suite_runner.das

//! The c-testsuite single-exec runner (`scripts/run_suite.sh c_testsuite`): a test passes when
//! its module exits 0 with the merged output `<id>.c.expected` holds, the suite's contract.

def verdict(id : string; c_path : string; rc : int; output : string) : Outcome => compare_output(id, rc, output, fread("{c_path}.expected"))

[export]
def main : int {
    let spec = SuiteSpec(name = "c_testsuite", tests_dir = C_TESTSUITE_TESTS, work_dir = "suites/c_testsuite/work", expected_pass = "suites/c_testsuite/expected_pass.txt", skip_ledger = "suites/c_testsuite/skip.txt", run_timeout = 60.0)
    return run_suite_main(spec, @@verdict)
}
