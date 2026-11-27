options gen2
options stack = 1048576

require pp_oracle

//! The pp-token oracle's command line, run from the repository root:
//! `das compare/pp/run.das -- --corpus frontend --corpus c-testsuite [--show N] [--raw] [unit.c ...]`,
//! the directive oracle `--pp2 --corpus frontend --corpus pp2`, and the expansion oracle `--pp3
//! --corpus pp3 [--list corpus.txt]`.
//! Exit 0 when no unit differs.

[export]
def main : int {
    var args = OracleArgs()
    let rc = parse_args_with_help(args, "pp_oracle")
    return rc if (rc >= 0)
    return run_oracle(args)
}
