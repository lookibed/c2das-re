options gen2

module pipeline public

require strings
require daslib/strings_boost
require daslib/fio
require daslib/rtti
require daslib/ast
require daslib/clargs
require daslib/das_source_formatter
require cir
require dumper_a
require emit
require sidecar

//! One C file through the whole chain: clang dump, C-IR (written, read back, rewritten and
//! compared byte for byte), das emission, the formatter, a compile check. Nothing is
//! hand-edited between the steps and every artifact lands under `out_dir`.

struct ConvertResult {
    ok : bool
    error : string
    cir_path : string
    das_path : string
    cir_text : string
    das_text : string
    // the port-progress metric of docs/lowering-examples.md "Pointers": how many
    // function bodies needed [c_function], out of all the unit defines
    c_functions : int
    function_count : int
}


// `as_written` keeps every `unsafe` scope and every symbol and turns optimization off
def private compile_with(das_path : string; as_written : bool; blk : block<(ok : bool; program : ProgramPtr; output : string) : void>) {
    var inscope access <- make_file_access("")
    using() $(var mg : ModuleGroup) {
        using() $(var cop : CodeOfPolicies) {
            cop.no_fold_unsafe = as_written
            cop.no_optimizations = as_written
            cop.export_all = as_written
            compile_file(das_path, access, unsafe(addr(mg)), cop) $(ok, program, output) {
                invoke(blk, ok, program, ok || !empty(output) ? string(output) : "compile failed without a message")
            }
        }
    }
}

//! `das_path` compiled with the default policies, as the compile check runs it; `blk` sees
//! whether it compiled, the program and the compiler's output, never empty on a failure.
def compile_checked(das_path : string; blk : block<(ok : bool; program : ProgramPtr; output : string) : void>) {
    compile_with(das_path, false, blk)
}

//! `das_path` compiled with every `unsafe` scope kept, no optimization and no unused symbol
//! removed, so the program's AST is the text's own; `blk` sees what `compile_checked`'s does.
def compile_as_written(das_path : string; blk : block<(ok : bool; program : ProgramPtr; output : string) : void>) {
    compile_with(das_path, true, blk)
}

def private compile_errors(das_path : string) : string {
    var report = ""
    compile_checked(das_path) $(ok, _program, output) {
        if (!ok) {
            report = output
        }
    }
    return report
}

//! The file name of `c_path` up to its first dot: the stem every artifact of the file is named by.
def file_stem(c_path : string) : string {
    let name = base_name(c_path)
    let dot = find(name, ".")
    return dot < 0 ? name : slice(name, 0, dot)
}

def convert(c_path : string; out_dir : string; target_name : string; clang : string = ""; sidecar_path : string = ""; param_writes : string = "") : ConvertResult {
    var res : ConvertResult
    if (!empty(param_writes) && !is_param_writes(param_writes)) {
        res.error = "--param-writes is in-place or copy, not `{param_writes}`"
        return <- res
    }
    if (!mkdir_rec(out_dir) && !stat(out_dir).is_dir) {
        res.error = "cannot create {out_dir}"
        return <- res
    }
    var side_error : string
    var side <- read_sidecar(find_sidecar(c_path, sidecar_path), side_error)
    if (!empty(side_error)) {
        res.error = "sidecar: {side_error}"
        return <- res
    }
    if (!empty(param_writes)) {
        side.param_writes = param_writes
    }
    var d <- dump_tu(c_path, target_by_name(target_name), empty(clang) ? default_clang() : clang, side.defines)
    if (!empty(d.error)) {
        res.error = "dumper: {d.error}"
        delete_tu(d.tu)
        return <- res
    }
    res.cir_text = write_cir(d.tu)
    res.cir_path = path_join(out_dir, "{file_stem(c_path)}.cir.json")
    if (!fwrite(res.cir_path, res.cir_text)) {
        res.error = "cannot write {res.cir_path}"
        delete_tu(d.tu)
        return <- res
    }
    var read_error : string
    var reread <- read_cir(res.cir_text, read_error)
    if (!empty(read_error)) {
        res.error = "reader: {read_error}"
        delete_tu(d.tu)
        return <- res
    }
    let rewritten = write_cir(reread)
    delete_tu(reread)
    if (rewritten != res.cir_text) {
        res.error = "reader and writer disagree on {res.cir_path}"
        delete_tu(d.tu)
        return <- res
    }
    let em <- emit_tu(d.tu, side)
    delete_tu(d.tu)
    if (!empty(em.error)) {
        res.error = "emitter: {em.error}"
        return <- res
    }
    res.c_functions = em.c_functions
    res.function_count = em.function_count
    res.das_text = format_source_string(em.text)
    res.das_path = path_join(out_dir, "{file_stem(c_path)}.das")
    if (!fwrite(res.das_path, res.das_text)) {
        res.error = "cannot write {res.das_path}"
        return <- res
    }
    let errors = compile_errors(res.das_path)
    if (!empty(errors)) {
        res.error = "compile check: {errors}"
        return <- res
    }
    res.ok = true
    return <- res
}

//! The opening every command-line main shares: `args` parsed for `prog`, the help printed under
//! `-?`; the exit code to return at once, or -1 to go on.
def cli_prologue(var args : auto(ArgsT); prog : string) : int {
    let parsed = _::parse_args_with_help(args, prog)
    if (parsed >= 0) {
        return parsed
    }
    if (args.show_help) {
        print_help(_::get_command_info(type<ArgsT>), prog)
        return 0
    }
    return -1
}
