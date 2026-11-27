options gen2
options stack = 1048576

require daslib/fio
require cir
require dumper_a
require dumper_c

//! The child `pipeline.das` runs for `--dumper c` (`ARCHITECTURE_DUMPER_C.md`):
//! `daslang -load_module dasCRuntime -load_module c_runtime -load_module fetch/dasFlex
//! converter/dumper_c_main.das -- <file.c> <linux|msvc> <clang> <out.cir.json>` writes the unit's
//! C-IR text to the last file and exits 0, or prints why it failed and exits 1.

[export]
def main : int {
    let args <- get_command_line_arguments()
    var at = 0
    while (at < length(args) && args[at] != "--") {
        at++
    }
    if (at + 4 >= length(args)) {
        print("usage: dumper_c_main.das -- <file.c> <linux|msvc> <clang> <out.cir.json>\n")
        return 1
    }
    var tu : CirTu
    var error : string
    dumper_c_tu(args[at + 1], target_by_name(args[at + 2]), args[at + 3], DumpInputs(), tu, error)
    if (!empty(error)) {
        print("dumper C: {error}\n")
        delete_tu(tu)
        return 1
    }
    let written = fwrite(args[at + 4], write_cir(tu))
    delete_tu(tu)
    if (!written) {
        print("dumper C: cannot write {args[at + 4]}\n")
    }
    return written ? 0 : 1
}
