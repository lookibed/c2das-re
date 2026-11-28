options gen2
options stack = 8388608

require parse_oracle

//! The parse oracle's command line, run from the repository root:
//! `das compare/parse/run.das -- --corpus fixtures --corpus c-testsuite [--quiet] [unit.c ...]`.
//! Exit 0 when no unit differs and the parser refused none. The stack holds the parser's 256
//! levels and the reductions' recursion over a long flat expression.

[export]
def main : int {
    var args = ParseOracleArgs()
    let rc = parse_args_with_help(args, "parse_oracle")
    return rc if (rc >= 0)
    return run_parse_oracle(args)
}
