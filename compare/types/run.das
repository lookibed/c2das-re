options gen2
options stack = 262144

require types_compare

//! The type-table comparison's command line, run from the repository root:
//! `das compare/types/run.das -- [--c-testsuite] [--dialect linux|msvc] [unit.c ...]`.
//! Exit 0 when every scalar-only unit's declaration order agrees.

[export]
def main : int {
    var args = TypesArgs()
    let rc = parse_args_with_help(args, "types_compare")
    return rc if (rc >= 0)
    return run_types(args)
}
