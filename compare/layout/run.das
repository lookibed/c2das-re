options gen2

require layout_oracle

//! The layout oracle's command line, run from the repository root:
//! `das compare/layout/run.das -- --corpus rules --corpus c-testsuite --root /path/to/fetch/trees`.
//! Exit 0 when no record differs.

[export]
def main : int {
    var args = LayoutArgs()
    let rc = parse_args_with_help(args, "layout_oracle")
    return rc if (rc >= 0)
    return run_layout_oracle(args)
}
