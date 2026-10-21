options gen2
// the pipeline parses clang's JSON dump below its own frames: a deep expression tree overflows
// the default 16 KB context stack, and dastest gives its tests this much
options stack = 1048576

require daslib/fio
require daslib/clargs
require pipeline
require sidecar
require tiers

//! c2das: `daslang converter/main.das -- <file.c> [--out <dir>] [--target msvc|linux] [--run <tier>] [--sidecar <file>] [--param-writes in-place|copy]`.
//! Converts one C file into `<dir>/<stem>.das` (default `out/`); with `--run` executes the
//! result under a tier and exits with the program's exit code.

[CommandLineArgs]
struct Args {
    @clarg_positional
    @clarg_doc = "the C translation unit to convert"
    input : string
    @clarg_doc = "output directory for the C-IR and the das module (default out)"
    out : string = "out"
    @clarg_doc = "dialect: msvc (LLP64, the documents' default) or linux (LP64, this host)"
    target : string = "msvc"
    @clarg_doc = "run the converted module under interp, jit, exe or aot and exit with its code"
    run : string = ""
    @clarg_doc = "the .c2das sidecar (default: <stem>.c2das beside the file, else .c2das in its folder)"
    sidecar : string = ""
    @clarg_name = "param-writes"
    @clarg_doc = "a written scalar or pointer parameter: in-place (the default) or copy (a local copy, faster under the interpreter); overrides the sidecar's param_writes"
    param_writes : string = ""
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
}

[export]
def main : int {
    var args = Args()
    let parsed = parse_args_with_help(args, "c2das")
    if (parsed >= 0) {
        return parsed
    }
    if (args.show_help) {
        print_help(get_command_info(type<Args>), "c2das")
        return 0
    }
    if (empty(args.input)) {
        to_log(LOG_ERROR, "c2das: no input file; -? for help\n")
        return 2
    }
    if (!empty(args.param_writes) && !is_param_writes(args.param_writes)) {
        to_log(LOG_ERROR, "c2das: --param-writes is in-place or copy, not `{args.param_writes}`; -? for help\n")
        return 2
    }
    let res <- convert(args.input, args.out, args.target, "", args.sidecar, args.param_writes)
    if (!res.ok) {
        to_log(LOG_ERROR, "c2das: {res.error}\n")
        return 1
    }
    to_log(LOG_INFO, "c2das: {res.cir_path}, {res.das_path}; [c_function] on {res.c_functions} of {res.function_count} functions\n")
    if (empty(args.run)) {
        return 0
    }
    var output : string
    let script = get_command_line_arguments()[1]
    let repo = dir_name(dir_name(script))
    let rc = run_tier(res.das_path, args.run, args.out, output, [path_join(repo, "c_runtime"), path_join(repo, "dasCRuntime")])
    to_log(LOG_INFO, "c2das: {args.run} exited {rc}\n{output}")
    return rc
}
