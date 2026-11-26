options gen2
options indenting = 4
// clang's JSON dump nests deeply: the reader recurses per level
options stack = 8388608

// The probe's correctness run: `-- <inputs.txt> <out_dir> [--no-clang]`. For every unit of
// `inputs.txt` (`name<TAB>path.i` lines, `prep.das` writes them): lex once per candidate, parse with
// RD and with LR, compare the two dumps byte for byte (locations included), and, unless
// `--no-clang`, reduce clang's JSON dump of the unit and each tree to the `c1_clang` line form and
// compare. Writes `<out_dir>/correctness.tsv` (one row per unit) and, per unit that differs, the two
// dumps or the first clang mismatches beside it; prints the totals.

require daslib/fio
require strings
require math
require daslib/strings_boost
require c1_lexer
require c1_rd
require c1_lr
require c1_clang

//! The clang flags of Dumper A's frontend that still matter on preprocessed input.
let CLANG_FLAGS <- ["-target", "x86_64-unknown-linux-gnu", "-funsigned-char", "-w", "-fsyntax-only", "-Xclang", "-ast-dump=json"]

def clang_binary : string => has_env_variable("PATH_TO_LIBCLANG") ? get_env_variable("PATH_TO_LIBCLANG") + "/bin/clang" : "clang"

struct ClangResult {
    compared : int
    wildcards : int
    mismatches : int
    first : string
}

def compare_with_clang(path : string; ast : Ast; src : Source) : ClangResult {
    var res : ClangResult
    var out : string
    var argv <- [clang_binary()]
    argv |> push_from(CLANG_FLAGS, [path])
    let rc = run_and_capture(argv, out, 300.0)
    if (rc != 0) {
        res.mismatches = -1
        res.first = "clang exited {rc}"
        return res
    }
    // the main file: the one the first line marker names
    let main_file = length(src.files) > 1 ? src.files[1] : src.files[0]
    var error : string
    let theirs <- clang_lines(out, main_file, error)
    if (!empty(error)) {
        res.mismatches = -1
        res.first = "json: {error}"
        return res
    }
    let ours <- ast_lines(ast, src, main_file)
    let count = max(length(ours), length(theirs))
    let aligned = length(ours) == length(theirs)
    for (i in range(count)) {
        let a = i < length(ours) ? ours[i] : "<none>"
        let b = i < length(theirs) ? theirs[i] : "<none>"
        res.compared++
        if (find(a, " ? ") >= 0 || find(a, "@?") >= 0) {
            res.wildcards++
        }
        if (!line_matches(a, b)) {
            res.mismatches++
            if (empty(res.first)) {
                res.first = "line {i + 1}: ours `{a}` clang `{b}`"
            }
            if (!aligned) {
                // a missing or extra line shifts every later one: the first is the finding
                break
            }
        }
    }
    return res
}

[export]
def main() {
    let args <- get_command_line_arguments()
    let at = find_index(args, "--")
    if (at < 0 || at + 2 >= length(args)) {
        print("usage: c1_compare.das -- <inputs.txt> <out_dir> [--no-clang]\n")
        unsafe(fio::exit(2))
    }
    let out_dir = args[at + 2]
    let use_clang = find_index(args, "--no-clang") < 0
    var rows : array<string>
    rows |> push("unit\ttokens\trd\tlr\trd_eq_lr\tclang_lines\tclang_wildcards\tclang_mismatch\tnote")
    var n_units = 0
    var rd_ok = 0
    var lr_ok = 0
    var same = 0
    var clang_ok = 0
    var clang_lines_total = 0
    var clang_wild_total = 0
    for (line in split(fread(args[at + 1]), "\n")) {
        if (empty(line)) {
            continue
        }
        let parts <- split(line, "\t")
        let name = parts[0]
        let path = parts[1]
        let text = fread(path)
        n_units++
        var r : Rd
        lex(r.src, text, path)
        let ntok = length(r.src.toks)
        rd_parse(r)
        var l : LrParser
        lex(l.lexer.src, text, path)
        lr_parse(l)
        let rd_err = r.failed ? r.err : r.src.err
        let lr_err = l.failed ? l.err : l.lexer.src.err
        if (empty(rd_err)) {
            rd_ok++
        }
        if (empty(lr_err)) {
            lr_ok++
        }
        var eq = "-"
        var note = ""
        if (empty(rd_err) && empty(lr_err)) {
            let a = dump_ast(r.ast, r.src, true)
            let b = dump_ast(l.lexer.ast, l.lexer.src, true)
            eq = a == b ? "yes" : "no"
            if (a == b) {
                same++
            } else {
                fwrite("{out_dir}/{name}.rd.txt", a)
                fwrite("{out_dir}/{name}.lr.txt", b)
            }
        } else {
            note = "rd: {rd_err} | lr: {lr_err}"
        }
        var cl = "-"
        var cw = "-"
        var cm = "-"
        if (use_clang && empty(rd_err)) {
            let res = compare_with_clang(path, r.ast, r.src)
            cl = "{res.compared}"
            cw = "{res.wildcards}"
            cm = "{res.mismatches}"
            if (res.mismatches == 0) {
                clang_ok++
                clang_lines_total += res.compared
                clang_wild_total += res.wildcards
            } else {
                note = res.first
            }
        }
        rows |> push("{name}\t{ntok}\t{empty(rd_err) ? "ok" : "refused"}\t{empty(lr_err) ? "ok" : "refused"}\t{eq}\t{cl}\t{cw}\t{cm}\t{replace(note, "\t", " ")}")
    }
    fwrite("{out_dir}/correctness.tsv", join(rows, "\n") + "\n")
    print("{n_units} units: RD parsed {rd_ok}, LR parsed {lr_ok}, RD tree == LR tree on {same}")
    if (use_clang) {
        print("; clang-equal {clang_ok} ({clang_lines_total} lines compared, {clang_wild_total} with a wildcard)")
    }
    print("\n")
}
