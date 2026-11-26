options gen2

require daslib/fio
require daslib/clargs
require pp_oracle

//! The pp-token oracle's command line, run from the repository root:
//! `das compare/pp/run.das -- --corpus frontend --corpus c-testsuite [--show N] [--raw] [unit.c ...]`.
//! Exit 0 when no unit differs.

[CommandLineArgs]
struct OracleArgs {
    @clarg_doc = "a corpus to compare: frontend or c-testsuite (repeatable)"
    corpus : array<string>
    @clarg_doc = "the differences shown per unit"
    show : int = 3
    @clarg_doc = "the folder the preprocessed units are written to"
    work : string = "compare/work/pp"
    @clarg_doc = "compare the units themselves, not clang -E's output of them (units with no directive and no macro)"
    raw : bool
    @clarg_positional
    @clarg_doc = "units compared besides the corpora"
    units : array<string>
}

[export]
def main : int {
    var args = OracleArgs()
    let rc = parse_args_with_help(args, "pp_oracle")
    return rc if (rc >= 0)
    let root = getcwd()
    var error : string
    let flags <- preprocess_flags(error)
    if (!empty(error)) {
        to_log(LOG_ERROR, "{error}\n")
        return 1
    }
    mkdir_rec(args.work)
    var total : int3
    for (corpus in args.corpus) {
        total += run_set(corpus, corpus_units(root, corpus), args.work, flags, args.show)
    }
    if (!empty(args.units)) {
        total += run_set("units", args.units, args.work, flags, args.show, args.raw)
    }
    print("total: {total.x} tokens, {total.y} diffs, {total.z} clang failures\n")
    return total.y == 0 ? 0 : 1
}
