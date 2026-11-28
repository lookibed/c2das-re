options gen2
options indenting = 4

module dumper_c public

require strings
require daslib/strings_boost
require daslib/fio
require cir
require dumper_a
require ../frontend/c_ir.das
require ../frontend/c_defines.das

//! Dumper C behind `--dumper c` (`ARCHITECTURE_DUMPER_C.md`): a unit preprocessed by the frontend's
//! own preprocessor under Dumper A's predefined macros and own headers, and the C-IR built over its
//! tokens by the frontend's clang-free parser and builder, `frontend/c_ir.das`, which place each node
//! by its own tokens. Where an `#if` needs the evaluator PP.4 brings, clang's `-E` text stands in.

//! The text of `c_path` as `clang -E` under Dumper A's flags `flags` prints it, the line markers
//! kept; "" with `error` naming the step that failed.
def private clang_text(c_path, clang : string; flags : array<string>; var error : string&) : string {
    var argv <- [clang, "-E"]
    argv |> push_from(flags, [c_path])
    var text : string
    if (run_and_capture(argv, text, 300.0) != 0) {
        error = "clang -E: {slice(text, 0, 400)}"
        return ""
    }
    return text
}

//! Whether parser error `err` is the preprocessor's for an `#if` only PP.4 evaluates.
def dumper_c_needs_evaluator(err : string) : bool => find(err, "needs the PP.4 evaluator") >= 0

//! Dumper C's C-IR of `c_path` under `target` into `tu`: the frontend's preprocessor over the file
//! (the predefined-macro table of `target`, the own headers' folder searched) or, where an `#if`
//! needs PP.4, `clang -E` under Dumper A's flags, then the parser and the builder, the own headers'
//! folder as the library; `error` names the step that failed. A sidecar's `defines`,
//! `include_dirs` and `include_files` are refused: the builder takes none yet.
[arch(at="ARCHITECTURE_DUMPER_C.md#dumper-c")]
def dumper_c_tu(c_path : string; target : CirTarget; clang : string; inputs : DumpInputs; var tu : CirTu; var error : string&) {
    if (!empty(inputs.defines) || !empty(inputs.include_dirs) || !empty(inputs.include_files)) {
        error = "Dumper C takes no sidecar defines, include folders or include files yet"
        return
    }
    let flags <- dumper_frontend_flags(target, error)
    return if (!empty(error))
    let predefines <- read_predefined(predefined_table(target), error)
    return if (!empty(error))
    let headers = get_full_file_name(own_include_dir())
    var p = new CParser
    var provider = new PpFioProvider()
    if (!c_parser_open_source(*p, provider, c_path, predefines, [headers], is_msvc(target)) && dumper_c_needs_evaluator(p.err)) {
        let text = clang_text(c_path, clang, flags, error)
        if (!empty(error)) {
            unsafe {
                delete p
            }
            return
        }
        c_parser_open_text(*p, text, c_path, is_msvc(target))
    }
    let u = c_unit(*p)
    if (p.failed) {
        error = "parser: {p.err}"
    } else {
        var r = new CIr
        c_ir_open(*r, target, headers + "/")
        if (!c_ir_unit(*r, *p, u)) {
            error = "builder: {r.err}"
        }
        swap(tu, r.tu)
        unsafe {
            delete r
        }
    }
    unsafe {
        delete p
    }
}
