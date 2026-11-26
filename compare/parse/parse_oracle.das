options gen2
options indenting = 4

module parse_oracle public

require strings
require math
require daslib/strings_boost
require daslib/fio
require daslib/clargs
require daslib/cmp
require clang_side public
require parser_side public
require ../../frontend/c_parser.das
require ../../converter/cir.das
require ../../converter/dumper_a.das

//! The parse oracle of Dumper C's parser (`compare/parse/ARCHITECTURE.md`): a unit preprocessed by
//! clang under Dumper A's flags, its file-scope declarations as clang reads them and as the parser
//! reads them, both reduced to one line per declared entity and compared line by line.

//! What a unit gave: `same`, `differs` (the first differing line of each side), `parser refused`
//! (the parser's located error) or `clang refused` (clang's error); the lines compared, and the
//! constructs skipped and left uncompared on the way.
struct ParseResult {
    unit : string
    verdict : string
    message : string
    ours : string
    theirs : string
    lines : int
    skipped : array<string>
    not_compared : array<string>
    parser_lines : array<string>    //!< the parser's side, whole
    clang_lines : array<string>     //!< clang's side, whole
}

//! Whether line `ours` (the parser's) matches `theirs` (clang's): equal, where each `?` of `ours`
//! stands for any run of characters with no `"` in `theirs` - a type, or a part of one, the tree
//! alone cannot spell (`ARCHITECTURE.md#compared`).
[arch(at="ARCHITECTURE.md#compared")]
def lines_match(ours, theirs : string) : bool {
    var matched = false
    peek_data(ours) $(a) {
        peek_data(theirs) $(b) {
            var i = 0
            var j = 0
            var star = -1
            var star_j = 0
            let n = length(a)
            let m = length(b)
            while (j < m) {
                if (i < n && a[i] == uint8('?')) {
                    star = i
                    star_j = j
                    i++
                } elif (i < n && a[i] == b[j]) {
                    i++
                    j++
                } elif (star >= 0 && b[star_j] != uint8('"')) {
                    star_j++
                    i = star + 1
                    j = star_j
                } else {
                    return
                }
            }
            while (i < n && a[i] == uint8('?')) {
                i++
            }
            matched = i == n
        }
    }
    return matched
}

// the lines of a side with a `(file <name>)` line before each run of lines in one file
def private with_files(lines : array<tuple<file : string; text : string>>) : array<string> {
    var out : array<string>
    out |> reserve(length(lines) + 1)
    var file = ""
    for (l in lines) {
        if (empty(out) || l.file != file) {
            file = l.file
            out |> push("(file {file})")
        }
        out |> push(l.text)
    }
    return <- out
}

//! The comparison of the preprocessed text `text`, named `name`, with clang's JSON dump `json` of
//! it: the parser reads the text declaration by declaration, the declarations it skips are left
//! out of clang's side, and the two sides' lines are compared in order.
[arch(at="ARCHITECTURE.md#verdicts")]
def compare_texts(unit, text, json : string) : ParseResult {
    var result = ParseResult(unit = unit)
    let clang <- clang_unit(json, text, unit)
    if (!empty(clang.error)) {
        result.verdict = "clang refused"
        result.message = clang.error
        return <- result
    }
    var p : CParser
    let parsed <- parse_unit(p, text, unit, clang.tops)
    result.skipped <- [for (s in parsed.skipped); s.construct]
    if (!empty(parsed.error)) {
        result.verdict = "parser refused"
        result.message = parsed.error
        return <- result
    }
    var ours_lines : array<tuple<file : string; text : string>>
    for (n in parsed.items) {
        var inscope lines <- parser_lines(p, n)
        ours_lines |> push_from(lines)
    }
    var theirs_lines : array<tuple<file : string; text : string>>
    for (top in clang.tops) {
        continue if (parsed.skipped_places |> key_exists(top.key))
        theirs_lines |> push_from(top.lines)
        result.not_compared |> push_from(top.not_compared)
    }
    result.parser_lines <- with_files(ours_lines)
    result.clang_lines <- with_files(theirs_lines)
    let ours & = unsafe(result.parser_lines)
    let theirs & = unsafe(result.clang_lines)
    let common = min(length(ours), length(theirs))
    for (i in range(common)) {
        if (!lines_match(ours[i], theirs[i])) {
            result.verdict = "differs"
            result.message = "line {i + 1}"
            result.ours = ours[i]
            result.theirs = theirs[i]
            result.lines = i
            return <- result
        }
    }
    result.lines = common
    if (length(ours) != length(theirs)) {
        result.verdict = "differs"
        result.message = "line {common + 1}"
        result.ours = common < length(ours) ? ours[common] : "(none)"
        result.theirs = common < length(theirs) ? theirs[common] : "(none)"
        return <- result
    }
    result.verdict = "same"
    return <- result
}

//! The flags of a unit's preprocessing: Dumper A's, under the `linux` dialect; `error` names what
//! is missing.
def parse_flags(var error : string&) : array<string> => <- dumper_frontend_flags(target_lp64_linux(), error)

//! A unit through clang: `clang -E` under `flags` into `work`, then clang's JSON dump of that
//! output; the preprocessed text and the dump, or `error`, clang's own, when either run fails.
[arch(at="ARCHITECTURE.md#flags")]
def clang_dump(unit, work : string; flags : array<string>) : tuple<error : string; text : string; json : string> {
    let preprocessed = path_join(work, "{base_name(unit)}.i")
    var argv <- [default_clang(), "-E"]
    argv |> push_from(flags, [unit, "-o", preprocessed])
    var out : string
    if (run_and_capture(argv, out, 300.0) != 0) {
        return (error = "clang -E: {first_line(out)}", text = "", json = "")
    }
    var dump_argv <- [default_clang(), "-target", target_lp64_linux().triple, "-undef"]
    dump_argv |> push_from(DUMPER_FLAGS, ["-x", "c", "-fsyntax-only", "-Xclang", "-ast-dump=json", preprocessed])
    var json : string
    if (run_and_capture(dump_argv, json, 300.0) != 0) {
        return (error = "clang -ast-dump: {first_line(json)}", text = "", json = "")
    }
    return (error = "", text = fread(preprocessed), json = json)
}

//! One unit through both sides: `clang_dump`, then `compare_texts`.
def compare_unit(unit, work : string; flags : array<string>) : ParseResult {
    let dumped = clang_dump(unit, work, flags)
    return ParseResult(unit = unit, verdict = "clang refused", message = dumped.error) if (!empty(dumped.error))
    return <- compare_texts(unit, dumped.text, dumped.json)
}

// the first line of `text` holding `error:`, or its first line
def private first_line(text : string) : string {
    for (line in split(text, "\n")) {
        return line if (find(line, "error:") >= 0)
    }
    let stop = find(text, "\n")
    return stop >= 0 ? slice(text, 0, stop) : text
}

//! The totals of a set of units: the units per verdict, the lines compared, the constructs skipped
//! and those left uncompared, each by its name.
struct ParseTotals {
    verdicts : table<string; int>
    lines : int
    skipped : table<string; int>
    not_compared : table<string; int>
}

def private count_into(var counts : table<string; int>; key : string) {
    counts[key] = (counts?[key] ?? 0) + 1
}

def private merge_counts(var into : table<string; int>; counts : table<string; int>) {
    for (key, n in keys(counts), values(counts)) {
        into[key] = (into?[key] ?? 0) + n
    }
}

def operator +=(var a : ParseTotals; b : ParseTotals) {
    merge_counts(a.verdicts, b.verdicts)
    a.lines += b.lines
    merge_counts(a.skipped, b.skipped)
    merge_counts(a.not_compared, b.not_compared)
}

//! `r` added to `totals`.
def add_result(var totals : ParseTotals; r : ParseResult) {
    count_into(totals.verdicts, r.verdict)
    totals.lines += r.lines
    for (s in r.skipped) {
        count_into(totals.skipped, s)
    }
    for (s in r.not_compared) {
        count_into(totals.not_compared, s)
    }
}

// a table's entries as `name N`, the largest first
def private counted(counts : table<string; int>) : string {
    var entries <- [for (name, n in keys(counts), values(counts)); (n = n, name = name)]
    sort(entries) <| cmp_by(-_.n, _.name)
    return join([for (e in entries); "{e.name} {e.n}"], ", ")
}

//! The lines that describe `totals`, headed `name`.
def describe_totals(name : string; totals : ParseTotals) : string {
    let verdicts <- ["same", "differs", "parser refused", "clang refused"]
    let counts = join([for (v in verdicts); "{totals.verdicts?[v] ?? 0} {v}"], ", ")
    return build_string() $(var w) {
        w |> write("{name}: {counts}; {totals.lines} lines compared\n")
        w |> write("  skipped (parser refusals by construct): {counted(totals.skipped)}\n")
        w |> write("  not compared yet (by construct): {counted(totals.not_compared)}\n")
    }
}

//! The line of a unit's result, and its differing lines.
def describe_result(r : ParseResult) : string {
    var text = "{r.unit}: {r.verdict}"
    if (r.verdict == "same") {
        text += " ({r.lines} lines)"
    } elif (!empty(r.message)) {
        text += ": {r.message}"
    }
    if (r.verdict == "differs") {
        text += "\n    parser: {r.ours}\n    clang:  {r.theirs}"
    }
    return text
}

//! The totals of `units`, each unit's result printed unless it is `same` and `quiet`, then the
//! totals headed `name`.
def run_set(name : string; units : array<string>; work : string; flags : array<string>; quiet, dump : bool) : ParseTotals {
    var totals : ParseTotals
    for (unit in units) {
        let r <- compare_unit(unit, work, flags)
        add_result(totals, r)
        if (!quiet || r.verdict != "same") {
            print("{describe_result(r)}\n")
        }
        if (dump) {
            for (line in r.parser_lines) {
                print("  parser {line}\n")
            }
            for (line in r.clang_lines) {
                print("  clang  {line}\n")
            }
        }
    }
    print(describe_totals("{name} ({length(units)} units)", totals))
    return <- totals
}

//! The units of a named corpus under `root`: `frontend`, every header of the own set;
//! `c-testsuite`, the single-exec suite as `suites/c_testsuite/fetch.sh` fetches it; `fixtures`,
//! the `.c` units of `compare/parse/fixtures/`. Sorted. `error` names an unknown corpus or a folder
//! that is missing: no corpus is ever empty by absence.
def corpus_units(root, corpus : string; var error : string&) : array<string> {
    var units : array<string>
    let folders <- {"frontend" => "frontend/include", "fixtures" => "compare/parse/fixtures",
                    "c-testsuite" => "suites/c_testsuite/fetch/c-testsuite/tests/single-exec"}
    let relative = folders?[corpus] ?? ""
    if (empty(relative)) {
        error = "unknown corpus '{corpus}': frontend, c-testsuite or fixtures"
        return <- units
    }
    let folder = path_join(root, relative)
    if (!stat(folder).is_dir) {
        error = "corpus {corpus}: {folder} is missing"
        return <- units
    }
    let suffix = corpus == "frontend" ? ".h" : ".c"
    dir_rec(folder) $(name, is_dir) {
        if (!is_dir && ends_with(name, suffix)) {
            units |> push(path_join(folder, name))
        }
    }
    sort(units)
    return <- units
}

//! The command line of `run.das`.
[CommandLineArgs]
struct ParseOracleArgs {
    @clarg_doc = "a corpus to compare: frontend, c-testsuite or fixtures (repeatable)"
    corpus : array<string>
    @clarg_doc = "the folder the preprocessed units are written to"
    work : string = "compare/work/parse"
    @clarg_doc = "print only the units that are not the same"
    quiet : bool
    @clarg_doc = "print both sides' lines of every unit"
    dump : bool
    @clarg_positional
    @clarg_doc = "units compared besides the corpora"
    units : array<string>
}

//! The corpora and units `args` names compared, from the repository root, each set's totals and
//! the total printed; 0 when no unit differs and the parser refused none, 1 otherwise or when a
//! corpus is unknown or missing or the flags cannot be made.
def run_parse_oracle(args : ParseOracleArgs) : int {
    var error : string
    let flags <- parse_flags(error)
    if (!empty(error)) {
        to_log(LOG_ERROR, "{error}\n")
        return 1
    }
    mkdir_rec(args.work)
    let root = getcwd()
    var sets : array<tuple<name : string; units : array<string>>>
    sets |> reserve(length(args.corpus) + 1)
    for (corpus in args.corpus) {
        var units <- corpus_units(root, corpus, error)
        if (!empty(error)) {
            to_log(LOG_ERROR, "{error}\n")
            return 1
        }
        sets |> emplace((name = corpus, units <- units))
    }
    if (!empty(args.units)) {
        sets |> emplace((name = "units", units <- clone_to_move(args.units)))
    }
    var failed = 0
    var total : ParseTotals
    for (s in sets) {
        let totals <- run_set(s.name, s.units, args.work, flags, args.quiet, args.dump)
        failed += (totals.verdicts?["differs"] ?? 0) + (totals.verdicts?["parser refused"] ?? 0)
        total += totals
    }
    print(describe_totals("total", total))
    return failed == 0 ? 0 : 1
}
