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

//! Dumper C behind `--dumper c` (`ARCHITECTURE_DUMPER_C.md`): a unit preprocessed by clang under
//! Dumper A's flags and the C-IR built over that text by the frontend's clang-free parser and
//! builder, `frontend/c_ir.das`, which place each node by its own tokens. Clang stands in here for
//! Dumper C's own preprocessor until it expands macros.

//! Dumper C's C-IR of `c_path` under `target` into `tu`: `clang -E` under Dumper A's flags (the
//! line markers kept), then the parser and the builder over the text, the own headers' folder as
//! the library; `error` names the step that failed. A sidecar's `defines`, `include_dirs` and
//! `include_files` are refused: the builder takes none yet.
[arch(at="ARCHITECTURE_DUMPER_C.md#dumper-c")]
def dumper_c_tu(c_path : string; target : CirTarget; clang : string; inputs : DumpInputs; var tu : CirTu; var error : string&) {
    if (!empty(inputs.defines) || !empty(inputs.include_dirs) || !empty(inputs.include_files)) {
        error = "Dumper C takes no sidecar defines, include folders or include files yet"
        return
    }
    let flags <- dumper_frontend_flags(target, error)
    return if (!empty(error))
    var argv <- [clang, "-E"]
    argv |> push_from(flags, [c_path])
    var text : string
    if (run_and_capture(argv, text, 300.0) != 0) {
        error = "clang -E: {slice(text, 0, 400)}"
        return
    }
    var p = new CParser
    c_parser_open_text(*p, text, c_path, is_msvc(target))
    let u = c_unit(*p)
    if (p.failed) {
        error = "parser: {p.err}"
    } else {
        var r = new CIr
        c_ir_open(*r, target, get_full_file_name(own_include_dir()) + "/")
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
