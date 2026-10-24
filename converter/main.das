options gen2
// the pipeline parses clang's JSON dump below its own frames: a deep expression tree overflows
// the default 16 KB context stack, and dastest gives its tests this much
options stack = 1048576

require daslib/fio
require daslib/clargs
require pipeline
require sidecar
require tiers

//! c2das: `daslang converter/main.das -- <file.c>... | --program <p.json> [--out <dir>] [--target msvc|linux] [--run <tier>] [--arg <a>]... [--sidecar <file>] [--param-writes in-place|copy]`.
//! Converts one C file into `<dir>/<stem>.das` (default `out/`), several or a manifest's as one
//! program into the module of the unit holding `main`; with `--run` executes the
//! result under a tier, `--arg` each argument of its C `argv` in order, and exits with the
//! program's exit code.

[CommandLineArgs]
struct Args {
    @clarg_positional
    @clarg_doc = "the C translation units to convert, one program linked in this order"
    input : array<string>
    @clarg_doc = "a program manifest (`tus`, the C files relative to it, and `entry`) in place of the files"
    program : string = ""
    @clarg_doc = "output directory for the C-IR and the das module (default out)"
    out : string = "out"
    @clarg_doc = "dialect: msvc (LLP64, the documents' default) or linux (LP64, this host)"
    target : string = "msvc"
    @clarg_doc = "run the converted module under interp, jit, exe or aot and exit with its code"
    run : string = ""
    @clarg_doc = "an argument the program run by --run gets in its C argv, one per --arg, in order"
    arg : array<string>
    @clarg_doc = "the .c2das sidecar (default: <stem>.c2das beside the file, else .c2das in its folder; of several files, the <stem>.c2das of the file holding main, else .c2das in the first file's folder)"
    sidecar : string = ""
    @clarg_name = "param-writes"
    @clarg_doc = "a written scalar or pointer parameter: in-place (the default) or copy (a local copy, faster under the interpreter); overrides the sidecar's param_writes"
    param_writes : string = ""
    @clarg_doc = "a canonical counting for loop: range (a das range loop, the default) or while (the while form every other for takes); overrides the sidecar's loops"
    loops : string = ""
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
    if (empty(args.input) && empty(args.program)) {
        to_log(LOG_ERROR, "c2das: no input file; -? for help\n")
        return 2
    }
    if (!empty(args.input) && !empty(args.program)) {
        to_log(LOG_ERROR, "c2das: --program names the files; give no file beside it; -? for help\n")
        return 2
    }
    if (!empty(args.param_writes) && !is_param_writes(args.param_writes)) {
        to_log(LOG_ERROR, "c2das: --param-writes is in-place or copy, not `{args.param_writes}`; -? for help\n")
        return 2
    }
    if (!empty(args.loops) && !is_loops(args.loops)) {
        to_log(LOG_ERROR, "c2das: --loops is range or while, not `{args.loops}`; -? for help\n")
        return 2
    }
    var error : string
    let input <- !empty(args.program) ? read_program_input(args.program, args.target, error) : ProgramInput(c_paths <- clone_to_move(args.input), entry = "main")
    if (!empty(error)) {
        to_log(LOG_ERROR, "c2das: {error}\n")
        return 1
    }
    let res <- convert_program(input.c_paths, args.out, args.target, "", args.sidecar, args.param_writes, args.loops, input.entry)
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
    let no_flags : array<string>
    let rc = run_tier(res.das_path, args.run, args.out, output, [path_join(repo, "c_runtime"), path_join(repo, "dasCRuntime")], 600.0, no_flags, args.arg)
    to_log(LOG_INFO, "c2das: {args.run} exited {rc}\n{output}")
    return rc
}
