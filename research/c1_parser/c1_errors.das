options gen2
options indenting = 4

// The probe's error run: `-- <file.c>...`: each deliberately broken input through RD, LR and clang
// (`-fsyntax-only`, its first error), one row each, printed as a markdown table.

require daslib/fio
require strings
require daslib/strings_boost
require c1_lexer
require c1_rd
require c1_lr

def first_clang_error(path : string) : string {
    var out : string
    let clang = has_env_variable("PATH_TO_LIBCLANG") ? get_env_variable("PATH_TO_LIBCLANG") + "/bin/clang" : "clang"
    run_and_capture([clang, "-fsyntax-only", "-w", path], out, 60.0)
    for (line in split(out, "\n")) {
        if (find(line, "error:") >= 0) {
            return line
        }
    }
    return "(no error)"
}

def short(path, msg : string) : string {
    let s = replace(msg, path, base_name(path))
    // dasBison lists the whole expected set: keep its head
    let cut = find(s, ", expected one of: ")
    if (cut >= 0) {
        let rest = slice(s, cut + 19)
        let names <- split(rest, ", ")
        let head = join([for (n in names) ; n], ", ")
        return length(names) > 4 ? "{slice(s, 0, cut)}, expected one of: {join([for (i in range(4)); names[i]], ", ")}, ... ({length(names)} names)" : "{slice(s, 0, cut)}, expected one of: {head}"
    }
    return s
}

[export]
def main() {
    let args <- get_command_line_arguments()
    let at = find_index(args, "--")
    print("| input | clang | RD | LR |\n|---|---|---|---|\n")
    for (i in range(at + 1, length(args))) {
        let path = args[i]
        let text = fread(path)
        var r : Rd
        lex(r.src, text, path)
        rd_parse(r)
        var l : LrParser
        lex(l.lexer.src, text, path)
        lr_parse(l)
        let rd_msg = r.failed ? r.err : "(accepted)"
        let lr_msg = l.failed ? l.err : "(accepted)"
        print("| {base_name(path)} | {short(path, first_clang_error(path))} | {short(path, rd_msg)} | {short(path, lr_msg)} |\n")
    }
}
