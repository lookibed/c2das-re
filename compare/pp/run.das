options gen2

require pp_oracle

//! The pp-token oracle's command line, run from the repository root:
//! `das compare/pp/run.das -- --corpus frontend --corpus c-testsuite [--show N] [--raw] [unit.c ...]`.
//! Exit 0 when no unit differs.

[export]
def main : int {
    var args = OracleArgs()
    let rc = parse_args_with_help(args, "pp_oracle")
    return rc if (rc >= 0)
    return run_oracle(args)
}
