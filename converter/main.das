options gen2

require daslib/fio
require daslib/clargs
require pipeline
require tiers

//! c2das: `daslang converter/main.das -- <file.c> [--out <dir>] [--target msvc|linux] [--run <tier>]`.
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
    let res <- convert(args.input, args.out, args.target)
    if (!res.ok) {
        to_log(LOG_ERROR, "c2das: {res.error}\n")
        return 1
    }
    to_log(LOG_INFO, "c2das: {res.cir_path}, {res.das_path}\n")
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
