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
//! clang under Dumper A's flags, its declarations, record and enum bodies and function bodies as
//! clang reads them and as the parser reads them, both reduced to lines and compared line by line.

//! A line where the two sides differ: its number, both lines (`(none)` for a line one side
//! lacks), and the cause clang's semantics give for it, "" when none is named.
struct Difference {
    line : int
    ours : string
    theirs : string
    cause : string
}

//! What a unit gave: `same`, `differs` (its differences), `construct refused` (the parser refused
//! a construct it does not take, which ends the unit), `parser refused` (any other located error
//! of the parser) or `clang refused` (clang's error); the lines compared, and the construct refused.
struct ParseResult {
    unit : string
    verdict : string
    message : string
    differences : array<Difference>
    lines : int
    skipped : array<string>
    not_compared : array<string>    //!< one reason per thing the oracle cannot compare (`ARCHITECTURE.md#compared`)
    parser_lines : array<string>    //!< the parser's side, whole
    clang_lines : array<string>     //!< clang's side, whole
}

// the ends of the runs of `b` from `j` that a `?` may stand for: an array size's (the `?` right
// after `[`) is any text up to the `]` that closes it; any other is one part of a type, a run with
// its parentheses and brackets balanced and none of `,`, `*`, `[`, `]`, `)` outside them; never a
// `"`, never empty
def private wildcard_ends(b : array<uint8>#; j : int; size : bool) : array<int> {
    var ends : array<int>
    var depth = 0
    var at = j
    while (at < length(b)) {
        let c = int(b[at])
        break if (c == '"' || (depth == 0 && (c == ']' || c == ')' || (!size && (c == ',' || c == '*' || c == '[')))))
        depth += (c == '(' || c == '[') ? 1 : (c == ')' || c == ']') ? -1 : 0
        at++
        if (depth == 0) {
            ends |> push(at)
        }
    }
    return <- ends
}

def private match_from(a, b : array<uint8>#; i0, j0 : int) : bool {
    var i = i0
    var j = j0
    while (i < length(a)) {
        if (a[i] == uint8('?')) {
            let size = i > 0 && a[i - 1] == uint8('[')
            for (stop in wildcard_ends(b, j, size)) {
                return true if (match_from(a, b, i + 1, stop))
            }
            return false
        }
        return false if (j >= length(b) || a[i] != b[j])
        i++
        j++
    }
    return j == length(b)
}

//! Whether line `ours` (the parser's) matches `theirs` (clang's): equal, where each `?` of `ours`
//! stands for one part of a type the tree alone cannot spell - a run of `theirs` with balanced
//! parentheses and none of `,`, `*`, `[`, `]`, `)` outside them - or, right after `[`, for an
//! array's size (`ARCHITECTURE.md#compared`).
[arch(at="ARCHITECTURE.md#compared")]
def lines_match(ours, theirs : string) : bool {
    var matched = false
    peek_data(ours) $(a) {
        peek_data(theirs) $(b) {
            matched = match_from(a, b, 0, 0)
        }
    }
    return matched
}

// a line's parts: up to its first type, the type, and the rest; a line with no type is its head
def private type_parts(line : string) : tuple<head : string; spelled : string; rest : string> {
    let open = find(line, "\"")
    let close = open < 0 ? -1 : find(line, "\"", open + 1)
    return (head = line, spelled = "", rest = "") if (close < 0)
    return (head = slice(line, 0, open), spelled = slice(line, open + 1, close), rest = slice(line, close + 1))
}

//! A library builtin's type as written, from clang's own (`ARCHITECTURE.md#causes`): `restrict`
//! dropped, `__size_t` spelled `size_t`, the decayed `va_list` and `jmp_buf` spelled by their
//! typedef names, and the names of `va_list`'s typedef chain (`__gnuc_va_list`,
//! `__builtin_va_list`) read as `va_list`.
def builtin_as_written(spelled : string) : string {
    var t = replace(replace(spelled, "restrict ", ""), " restrict", "")
    t = replace(t, "*restrict", "*")
    t = replace(t, "__size_t", "size_t")
    t = replace(t, "struct __va_list_tag *", "va_list")
    t = replace(t, "__builtin_va_list", "va_list")
    t = replace(t, "__gnuc_va_list", "va_list")
    return replace(t, "struct __jmp_buf_tag *", "jmp_buf")
}

//! The cause that explains the difference of the parser's line `ours` from clang's `theirs`, "" for
//! none (`ARCHITECTURE.md#causes`): a named cause explains only a difference of the declaration's
//! type, every other part of the lines equal, and only a difference of its shape - a library
//! builtin's type equal to the written one once `builtin_as_written`, a redeclaration's type equal
//! to the earlier declaration's (`prior`).
[arch(at="ARCHITECTURE.md#causes")]
def explained_by(ours : string; theirs : FormLine) : string {
    let mine = type_parts(ours)
    let clang = type_parts(theirs.text)
    return "" if (mine.head != clang.head || !lines_match(mine.rest, clang.rest))
    if (theirs.cause == LIBRARY_BUILTIN && lines_match(builtin_as_written(mine.spelled), builtin_as_written(clang.spelled))) {
        return LIBRARY_BUILTIN
    }
    if (theirs.cause == MERGED_REDECLARATION && clang.spelled == theirs.prior) {
        return MERGED_REDECLARATION
    }
    return ""
}

// the lines of a side with a `(file <name>)` line before each run of lines in one file
def private with_files(lines : array<FormLine>) : array<FormLine> {
    var out : array<FormLine>
    out |> reserve(length(lines) + 1)
    var file = ""
    for (l in lines) {
        if (empty(out) || l.file != file) {
            file = l.file
            out |> push(FormLine(file = file, text = "(file {file})"))
        }
        out |> push(l)
    }
    return <- out
}

// a line up to its first type: what names the entity, or the whole line
def private head_of(line : string) : string {
    let quote = find(line, "\"")
    return quote < 0 ? line : slice(line, 0, quote)
}

//! The differences of the parser's lines `ours` and clang's `theirs`, walked together: a line pair
//! that names one entity and differs is a difference, and the walk goes on; a pair that names two
//! entities, or a line past the other side's end, is the last difference, as the sides no longer
//! align. `compared` is the count of line pairs read.
[arch(at="ARCHITECTURE.md#verdicts")]
def line_differences(ours, theirs : array<FormLine>; var compared : int&) : array<Difference> {
    var out : array<Difference>
    let common = min(length(ours), length(theirs))
    compared = common
    for (i in range(common)) {
        continue if (lines_match(ours[i].text, theirs[i].text))
        out |> push(Difference(line = i + 1, ours = ours[i].text, theirs = theirs[i].text, cause = explained_by(ours[i].text, theirs[i])))
        if (head_of(ours[i].text) != head_of(theirs[i].text)) {
            compared = i
            return <- out
        }
    }
    if (length(ours) != length(theirs)) {
        let mine = common < length(ours) ? ours[common].text : "(none)"
        let clang = common < length(theirs) ? theirs[common].text : "(none)"
        out |> push(Difference(line = common + 1, ours = mine, theirs = clang))
    }
    return <- out
}

//! The comparison of the preprocessed text `text`, named `unit`, with clang's JSON dump `json` of
//! it: the parser reads the whole unit, and the two sides' lines are compared in order.
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
    let parsed <- parse_unit(p, text, unit)
    if (!empty(parsed.error)) {
        result.verdict = empty(parsed.construct) ? "parser refused" : "construct refused"
        result.message = parsed.error
        if (!empty(parsed.construct)) {
            result.skipped |> push(parsed.construct)
        }
        return <- result
    }
    var ours_lines : array<FormLine>
    for (n in parsed.items) {
        var inscope lines <- parser_lines(p, n)
        for (l in lines) {
            if (empty(l.note)) {
                ours_lines |> push(l)
            } else {
                result.not_compared |> push(l.note)
            }
        }
    }
    var theirs_lines : array<FormLine>
    for (top in clang.tops) {
        theirs_lines |> push_from(top.lines)
    }
    let ours <- with_files(ours_lines)
    let theirs <- with_files(theirs_lines)
    result.parser_lines <- [for (l in ours); l.text]
    result.clang_lines <- [for (l in theirs); l.text]
    result.differences <- line_differences(ours, theirs, result.lines)
    result.verdict = empty(result.differences) ? "same" : "differs"
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

//! The totals of a set of units: the units per verdict, the lines compared, the differing lines by
//! cause, and the constructs that ended a unit, each by its name.
struct ParseTotals {
    verdicts : table<string; int>
    lines : int
    named_only : int                    //!< the units that differ only by causes clang's semantics name
    differences : table<string; int>    //!< the differing lines by cause, `unnamed` for none
    skipped : table<string; int>
    not_compared : table<string; int>   //!< what the oracle cannot compare, by reason
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
    a.named_only += b.named_only
    merge_counts(a.differences, b.differences)
    merge_counts(a.skipped, b.skipped)
    merge_counts(a.not_compared, b.not_compared)
}

//! The differences of `r` that no cause of clang's semantics names.
def unnamed_differences(r : ParseResult) : int => length([for (d in r.differences); d; where empty(d.cause)])

//! `r` added to `totals`.
def add_result(var totals : ParseTotals; r : ParseResult) {
    count_into(totals.verdicts, r.verdict)
    totals.lines += r.lines
    for (d in r.differences) {
        count_into(totals.differences, empty(d.cause) ? "unnamed" : d.cause)
    }
    if (!empty(r.differences) && unnamed_differences(r) == 0) {
        totals.named_only++
    }
    for (s in r.skipped) {
        count_into(totals.skipped, s)
    }
    for (reason in r.not_compared) {
        count_into(totals.not_compared, reason)
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
    let verdicts <- ["same", "differs", "construct refused", "parser refused", "clang refused"]
    let counts = join([for (v in verdicts); "{totals.verdicts?[v] ?? 0} {v}"], ", ")
    return build_string() $(var w) {
        w |> write("{name}: {counts} ({totals.named_only} of them only by clang's named causes); {totals.lines} lines compared\n")
        w |> write("  differing lines by cause: {counted(totals.differences)}\n")
        w |> write("  units ended by a refused construct, by construct: {counted(totals.skipped)}\n")
        w |> write("  not compared, by reason: {counted(totals.not_compared)}\n")
    }
}

//! The line of a unit's result, and its first `show` differences, each with both lines and its
//! cause.
def describe_result(r : ParseResult; show : int = 3) : string {
    return build_string() $(var w) {
        w |> write("{r.unit}: {r.verdict}")
        if (r.verdict == "same") {
            w |> write(" ({r.lines} lines)")
            if (!empty(r.not_compared)) {
                w |> write(", {length(r.not_compared)} not compared")
            }
        } elif (r.verdict == "differs") {
            w |> write(" ({length(r.differences)} lines, {unnamed_differences(r)} with no named cause; {r.lines} lines compared)")
        } elif (!empty(r.message)) {
            w |> write(": {r.message}")
        }
        for (d, i in r.differences, count()) {
            break if (i >= show)
            let cause = empty(d.cause) ? "" : " [{d.cause}]"
            w |> write("\n  line {d.line}{cause}\n    parser: {d.ours}\n    clang:  {d.theirs}")
        }
    }
}

//! The totals of `units`, each unit's result printed unless it is `same` and `quiet`, then the
//! totals headed `name`.
def run_set(name : string; units : array<string>; work : string; flags : array<string>; quiet, dump : bool; show : int) : ParseTotals {
    var totals : ParseTotals
    for (unit in units) {
        let r <- compare_unit(unit, work, flags)
        add_result(totals, r)
        if (!quiet || r.verdict != "same") {
            print("{describe_result(r, show)}\n")
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
    @clarg_doc = "the differences shown per unit"
    show : int = 3
    @clarg_doc = "a macro definition `name` or `name=value` added to every unit's preprocessing (repeatable)"
    define : array<string>
    @clarg_positional
    @clarg_doc = "units compared besides the corpora"
    units : array<string>
}

//! The corpora and units `args` names compared, from the repository root, each set's totals and
//! the total printed; 0 when every unit that differs does so only by causes clang's semantics name
//! and the parser refused none, 1 otherwise or when a corpus is unknown or missing or the flags
//! cannot be made.
def run_parse_oracle(args : ParseOracleArgs) : int {
    var error : string
    var flags <- parse_flags(error)
    if (!empty(error)) {
        to_log(LOG_ERROR, "{error}\n")
        return 1
    }
    flags |> push_from([for (d in args.define); "-D{d}"])
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
        let totals <- run_set(s.name, s.units, args.work, flags, args.quiet, args.dump, args.show)
        failed += (totals.verdicts?["differs"] ?? 0) - totals.named_only + (totals.verdicts?["parser refused"] ?? 0)
        total += totals
    }
    print(describe_totals("total", total))
    return failed == 0 ? 0 : 1
}
