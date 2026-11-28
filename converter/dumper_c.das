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
//! own preprocessor under Dumper A's predefined macros, feature tables and own headers, and the C-IR
//! built over its tokens by the frontend's clang-free parser and builder, `frontend/c_ir.das`, which
//! place each node by its own tokens. No clang runs.

//! Dumper C's C-IR of `c_path` under `target` into `tu`: the frontend's preprocessor over the file
//! (the predefined-macro and feature tables of `target`, the own headers' folder searched), then
//! the parser and the builder, which leaves out the declarations of files outside the program root
//! (the sidecar's `program_root`, else the file's folder) and of the own headers, as Dumper A does;
//! `error` names the step that failed. `clang` is Dumper A's, which Dumper C does not run. A
//! sidecar's `defines`, `include_dirs` and `include_files` are refused: the builder takes none yet.
[arch(at="ARCHITECTURE_DUMPER_C.md#dumper-c"), unused_argument(clang)]
def dumper_c_tu(c_path : string; target : CirTarget; clang : string; inputs : DumpInputs; var tu : CirTu; var error : string&) {
    if (!empty(inputs.defines) || !empty(inputs.include_dirs) || !empty(inputs.include_files)) {
        error = "Dumper C takes no sidecar defines, include folders or include files yet"
        return
    }
    let predefines <- read_predefined(predefined_table(target), error)
    return if (!empty(error))
    let headers = get_full_file_name(own_include_dir())
    let root = empty(inputs.program_root) ? dir_name(get_full_file_name(c_path)) : get_full_file_name(inputs.program_root)
    let program_dir = ends_with(root, "/") ? root : root + "/"
    let main = get_full_file_name(c_path)
    if (!starts_with(main, program_dir) || starts_with(main, headers + "/")) {
        error = "the main file {main} is no file of the program: it lies outside the program root {program_dir} or under the own libc headers' folder {headers}/"
        return
    }
    var p = new CParser
    var provider = new PpFioProvider()
    c_parser_open_source(*p, provider, c_path, predefines, [headers], is_msvc(target), -1l, features_path(is_msvc(target) ? "msvc" : "linux"))
    let u = c_unit(*p)
    if (p.failed) {
        error = "parser: {p.err}"
    } else {
        var r = new CIr
        c_ir_open(*r, target, headers + "/", program_dir)
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
