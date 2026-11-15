options gen2
// the pipeline parses clang's JSON dump below its own frames: a deep expression tree overflows
// the default 16 KB context stack, and dastest gives its tests this much
options stack = 1048576

require daslib/fio
require daslib/clargs
require pipeline
require sidecar
require tiers

//! c2das: `daslang converter/main.das -- <file.c>... | --program <p.json> [--out <dir>] [--target msvc|linux] [--run <tier>] [--arg <a>]... [--sidecar <file>] [--param-writes in-place|copy] [--loops range|while] [--first-member addr|reinterpret] [--switch-dispatch chain|goto|table] [--layout source|source-cut|single] [--edge-census] [--no-solid-context] [--checks safe|off] [--past-end call|inline] [--inline-helpers] [--fn-macros fold|expand] [--forms-off pointer_steps,ranged_loops,c_switch]`.
//! Converts one C file into `<dir>/<stem>.das` (default `out/`), several or a manifest's as one
//! program: by default a module per C file under `<dir>` as the files lie under their common
//! folder, mutually dependent files one module of fragments (`--layout source`), the cycles among
//! them cut by late binding through `<entry>_link.das` (`--layout source-cut`), or one module
//! named by the unit holding `main` (`--layout single`); with `--run` executes the result under a tier, `--arg` each argument of its C `argv`
//! in order, and exits with the program's exit code.

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
    @clarg_name = "first-member"
    @clarg_doc = "the address of a member at offset 0 (a struct's first member, a union's member, nested ones): addr (addr(p.f), the default) or reinterpret (the containing pointer reinterpreted, reinterpret<F?>(p), faster under the interpreter); overrides the sidecar's first_member"
    first_member : string = ""
    @clarg_name = "switch-dispatch"
    @clarg_doc = "a dense switch (8 or more case values filling at least half of their range, no case falling into the next): chain (its cases tested in turn, the default) or goto (a jump table, `goto int(_cond) + base` past a bounds guard, faster under the interpreter and the JIT; a switch a goto from another case re-dispatches is then a flat label CFG, by a table where its values fill half their range) or table (such a switch, one falling through too, flat: a jump to one das label per case, `goto int(_cond) + base` past a bounds guard, or through a module-level table of label numbers when its range has values no case holds, no loop and no case test); overrides the sidecar's switch_dispatch"
    switch_dispatch : string = ""
    @clarg_doc = "a program of several files: source (the default: a module per C file under --out as the files lie under their common folder, a header's types <header>_h.das, the entry module the one holding main, every cycle among files one module <first stem>_cluster.das of <stem>.das.inc fragments; program.layout.txt reports the partition), source-cut (the same with the cycles cut by late binding through <entry>_link.das, as the sidecar's layout object directs; program.layout.txt reports the cut) or single (one module named by the file holding main); one file is one module in each; overrides the sidecar's layout"
    layout : string = ""
    @clarg_name = "edge-census"
    @clarg_doc = "a program in a source layout: also write program.edges.txt, the edges of each cycle among its files by kind (call, address, global, type) and the cycles left were every function, then every function and object, forward-declared; changes no converted text"
    edge_census : bool
    @clarg_name = "no-solid-context"
    @clarg_doc = "write no `options solid_context` in the modules (by default each carries it: a global and a function are reached by index, never looked up by name: Doom under the JIT 3.2-3.9x -> 1.3-1.4x native); only for a module that runs in another context or is patched or reloaded, which the option forbids; overrides the sidecar's solid_context"
    no_solid_context : bool
    @clarg_doc = "das's checks in the converted functions: safe (the default: a null dereference or an index past its array panics naming the access) or off (every converted function carries `unsafe_deref` and `hint(unsafe_range_check)`, dropping the checks: faster where they are hot, Doom 3-7% and Lua 2-11% under the interpreter and the JIT, not on every kernel; a wrong C program then reads garbage or dies by SIGSEGV instead of panicking, and the AOT host keeps its range checks); overrides the sidecar's checks"
    checks : string = ""
    @clarg_name = "past-end"
    @clarg_doc = "`&a[k]` of an array whose index is a plain load (a variable or a field), which C may take one past the end: call (`addr(a[0]) + end_index(k, N)`, the default) or inline (`k == N ? addr(a[0]) + N : addr(a[k])`, das's own index with no call per access: faster under the interpreter, the index and the array spelled twice); overrides the sidecar's past_end"
    past_end : string = ""
    @clarg_name = "inline-helpers"
    @clarg_doc = "a direct call of a pure `static` helper (its body `return <expr>` or the clamp shape `if (n > hi) n = hi; else if (n < lo) n = lo; return n;`, its parameters and result integers or floating) spelled as the helper's expression at the call site, an argument with an effect or read twice bound to a temporary first: no call per use under the interpreter, the helper's name gone from the site; by default the call stays; sets the sidecar's inline_helpers"
    inline_helpers : bool
    @clarg_name = "fn-macros"
    @clarg_doc = "an expansion of a function-like macro of the program: fold (the default: a call of the macro's private `[c_macro] def`, printed under its `#define`, where every argument is evaluated as C evaluates it and the body reads only its parameters) or expand (the expansion's C spelled at every site); overrides the sidecar's fn_macros"
    fn_macros : string = ""
    @clarg_name = "forms-off"
    @clarg_doc = "the forms spelled as before they were introduced, comma-separated: pointer_steps (a pointer step and compound store `p = p + n`, not `p++`, `p += n`), ranged_loops (a range loop only for `<` over locals and constants, not `<=` or a global or member bound), c_switch (a switch spelled as its if-chain or matched-flag loop, not the `c_switch` macro); by default none; sets the sidecar's forms_off"
    forms_off : string = ""
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
    if (!empty(args.first_member) && !is_first_member(args.first_member)) {
        to_log(LOG_ERROR, "c2das: --first-member is addr or reinterpret, not `{args.first_member}`; -? for help\n")
        return 2
    }
    if (!empty(args.switch_dispatch) && !is_switch_dispatch(args.switch_dispatch)) {
        to_log(LOG_ERROR, "c2das: --switch-dispatch is chain, goto or table, not `{args.switch_dispatch}`; -? for help\n")
        return 2
    }
    if (!empty(args.checks) && !is_checks(args.checks)) {
        to_log(LOG_ERROR, "c2das: --checks is safe or off, not `{args.checks}`; -? for help\n")
        return 2
    }
    if (!empty(args.past_end) && !is_past_end(args.past_end)) {
        to_log(LOG_ERROR, "c2das: --past-end is call or inline, not `{args.past_end}`; -? for help\n")
        return 2
    }
    if (!empty(args.fn_macros) && !is_fn_macros(args.fn_macros)) {
        to_log(LOG_ERROR, "c2das: --fn-macros is fold or expand, not `{args.fn_macros}`; -? for help\n")
        return 2
    }
    if (!empty(forms_off_error(args.forms_off))) {
        to_log(LOG_ERROR, "c2das: {forms_off_error(args.forms_off)}; -? for help\n")
        return 2
    }
    if (!empty(args.layout) && !is_layout(args.layout)) {
        to_log(LOG_ERROR, "c2das: --layout is source, source-cut or single, not `{args.layout}`; -? for help\n")
        return 2
    }
    var error : string
    let input <- !empty(args.program) ? read_program_input(args.program, args.target, error) : ProgramInput(c_paths <- clone_to_move(args.input), entry = "main")
    if (!empty(error)) {
        to_log(LOG_ERROR, "c2das: {error}\n")
        return 1
    }
    let res <- convert_program(input.c_paths, args.out, args.target, "", args.sidecar, args.param_writes, args.loops, input.entry, args.layout, args.edge_census, args.first_member, args.switch_dispatch, args.no_solid_context, args.checks, args.past_end, args.inline_helpers, args.fn_macros, args.forms_off)
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
