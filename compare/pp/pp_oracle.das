options gen2

module pp_oracle public

require strings
require daslib/strings_boost
require daslib/fio
require daslib/clargs
require ../../frontend/pp_lexer.das
require ../../converter/cir.das
require ../../converter/dumper_a.das

//! The pp-token oracle of `frontend/pp_lexer.das` (`compare/pp/ARCHITECTURE.md`): a unit
//! preprocessed by clang under the dialect's flags, its output lexed by clang (`-dump-tokens`) and by
//! the pp lexer, the two token streams compared token by token.

//! One token as either side reports it: its PpTok kind, spelling, line, column and flags. For the
//! clang side `has_space` already folds `[StartOfLine]` in (`ARCHITECTURE.md#flags`).
struct OracleToken {
    kind : int
    spelling : string
    line : int
    col : int
    at_bol : bool
    has_space : bool
}

//! A unit's comparison: the tokens of each side, the differing positions and the first ones shown.
struct UnitResult {
    unit : string
    clang_tokens : int
    pp_tokens : int
    diffs : int
    error : string          //!< clang failed on the unit: nothing compared
    shown : array<string>
}

// clang's punctuator kinds (`clang/Basic/TokenKinds.def`) and the PpTok each is
let private CLANG_PUNCTS <- {
    "l_square" => int(PpTok.LBRACKET), "r_square" => int(PpTok.RBRACKET), "l_paren" => int(PpTok.LPAREN),
    "r_paren" => int(PpTok.RPAREN), "l_brace" => int(PpTok.LBRACE), "r_brace" => int(PpTok.RBRACE),
    "period" => int(PpTok.PERIOD), "ellipsis" => int(PpTok.ELLIPSIS), "amp" => int(PpTok.AMP),
    "ampamp" => int(PpTok.AND_AND), "ampequal" => int(PpTok.AND_ASSIGN), "star" => int(PpTok.STAR),
    "starequal" => int(PpTok.MUL_ASSIGN), "plus" => int(PpTok.PLUS), "plusplus" => int(PpTok.INC),
    "plusequal" => int(PpTok.ADD_ASSIGN), "minus" => int(PpTok.MINUS), "arrow" => int(PpTok.ARROW),
    "minusminus" => int(PpTok.DEC), "minusequal" => int(PpTok.SUB_ASSIGN), "tilde" => int(PpTok.TILDE),
    "exclaim" => int(PpTok.EXCLAIM), "exclaimequal" => int(PpTok.NE), "slash" => int(PpTok.SLASH),
    "slashequal" => int(PpTok.DIV_ASSIGN), "percent" => int(PpTok.PERCENT), "percentequal" => int(PpTok.MOD_ASSIGN),
    "less" => int(PpTok.LESS), "lessless" => int(PpTok.SHL), "lessequal" => int(PpTok.LE),
    "lesslessequal" => int(PpTok.SHL_ASSIGN), "greater" => int(PpTok.GREATER), "greatergreater" => int(PpTok.SHR),
    "greaterequal" => int(PpTok.GE), "greatergreaterequal" => int(PpTok.SHR_ASSIGN), "caret" => int(PpTok.CARET),
    "caretequal" => int(PpTok.XOR_ASSIGN), "pipe" => int(PpTok.PIPE), "pipepipe" => int(PpTok.OR_OR),
    "pipeequal" => int(PpTok.OR_ASSIGN), "question" => int(PpTok.QUESTION), "colon" => int(PpTok.COLON),
    "semi" => int(PpTok.SEMI), "coloncolon" => int(PpTok.COLONCOLON), "equal" => int(PpTok.ASSIGN), "equalequal" => int(PpTok.EQ),
    "comma" => int(PpTok.COMMA), "hash" => int(PpTok.HASH), "hashhash" => int(PpTok.HASHHASH),
    "numeric_constant" => int(PpTok.PP_NUMBER), "unknown" => int(PpTok.OTHER)
}

//! The PpTok kind of a clang token kind: a punctuator, a literal class, `unknown`, and any other
//! name - `identifier` or a keyword, whose kind clang names by its spelling - an IDENTIFIER.
def clang_kind(kind : string) : int {
    let punct = CLANG_PUNCTS?[kind] ?? -1
    return punct if (punct >= 0)
    return int(PpTok.CHAR_CONSTANT) if (ends_with(kind, "char_constant"))
    return int(PpTok.STRING_LITERAL) if (ends_with(kind, "string_literal"))
    return int(PpTok.IDENTIFIER)
}

//! The tokens of clang's `-dump-tokens` text, each record `kind 'spelling'\t[flags]\tLoc=<file:line:col>`,
//! more than one line when its spelling holds a newline (a raw string) or its `[UnClean='...']` flag
//! spells a line splice; the `eof` record ends them. `has_space` is `[LeadingSpace]`, or `[StartOfLine]` past the first line: clang leaves
//! `[LeadingSpace]` off a token right after a newline.
[arch(at="ARCHITECTURE.md#flags")]
def clang_tokens(dump : string) : array<OracleToken> {
    var tokens : array<OracleToken>
    var pending = ""
    for (part in split(dump, "\n")) {
        let line = empty(pending) ? part : "{pending}\n{part}"
        let loc_at = find(line, "\tLoc=<")
        if (loc_at < 0) {
            pending = find(line, "'") >= 0 ? line : ""
            continue
        }
        pending = ""
        let first_quote = find(line, "'")
        let unclean_at = find(line, " [UnClean='")
        let head = slice(line, 0, unclean_at >= 0 ? unclean_at : loc_at)
        let last_quote = rfind(head, "'")
        continue if (first_quote < 0 || last_quote <= first_quote)
        let kind = slice(line, 0, first_quote - 1)
        break if (kind == "eof")
        let flags = slice(head, last_quote + 1)
        let loc = slice(line, loc_at + 6, length(line) - 1)
        let col_at = rfind(loc, ":")
        let line_at = rfind(slice(loc, 0, col_at), ":")
        let sol = find(flags, "[StartOfLine]") >= 0
        let ls = find(flags, "[LeadingSpace]") >= 0
        let at_line = to_int(slice(loc, line_at + 1, col_at))
        let at_col = to_int(slice(loc, col_at + 1))
        tokens |> push(OracleToken(kind = clang_kind(kind), spelling = slice(line, first_quote + 1, last_quote),
                                   line = at_line, col = at_col, at_bol = sol, has_space = ls || (sol && at_line > 1)))
    }
    return <- tokens
}

//! The tokens `pp_lexer.das` reads from `bytes`; the first has no space unless text precedes it.
def lexed_tokens(var bytes : array<uint8>) : array<OracleToken> {
    var lx : PpLexer
    pp_open(lx, bytes, 0)
    var tokens : array<OracleToken>
    while (pp_next(lx)) {
        tokens |> push(OracleToken(kind = lx.tok.kind, spelling = pp_spelling(lx), line = lx.tok.line, col = lx.tok.col,
                                   at_bol = lx.tok.at_bol, has_space = lx.tok.has_space))
    }
    return <- tokens
}

def private describe(t : OracleToken) : string =>
    "{t.kind} '{t.spelling}' {t.line}:{t.col}{t.at_bol ? " bol" : ""}{t.has_space ? " space" : ""}"

//! `line`, `col` of `t` ordered against those of `u`: -1 before, 0 at, 1 after
def private place_order(t, u : OracleToken) : int {
    return t.line < u.line ? -1 : 1 if (t.line != u.line)
    return t.col < u.col ? -1 : t.col > u.col ? 1 : 0
}

//! The differences of `clang` and `ours`, walked together by position: a token both sides place
//! at one line and column differs when its kind, spelling or a flag does, a token only one side
//! places there is one difference, and so is each token one side has past the other's end; the
//! first `show` of them described in `shown`.
[arch(at="ARCHITECTURE.md#flags")]
def compare_tokens(clang, ours : array<OracleToken>; show : int; var shown : array<string>) : int {
    var diffs = 0
    var i = 0
    var j = 0
    while (i < length(clang) && j < length(ours)) {
        let order = place_order(clang[i], ours[j])
        var seen = ""
        if (order < 0) {
            seen = "#{i}: clang only {describe(clang[i])}"
            i++
        } elif (order > 0) {
            seen = "#{j}: pp only {describe(ours[j])}"
            j++
        } else {
            let c = clang[i]
            let o = ours[j]
            if (c.kind != o.kind || c.spelling != o.spelling || c.at_bol != o.at_bol || c.has_space != o.has_space) {
                seen = "#{i}: clang {describe(c)} | pp {describe(o)}"
            }
            i++
            j++
        }
        continue if (empty(seen))
        diffs++
        if (length(shown) < show) {
            shown |> push(seen)
        }
    }
    let extra = length(clang) - i + length(ours) - j
    if (extra > 0 && length(shown) < show) {
        shown |> push("{extra} tokens past the other side's end ({length(clang)} clang, {length(ours)} pp)")
    }
    return diffs + extra
}

//! The flags of a unit's preprocessing: Dumper A's, under the `linux` dialect - its triple, clang's
//! own macros dropped and the table's set, plain `char` unsigned, the own headers the only system
//! folder; `error` names what is missing.
def preprocess_flags(var error : string&) : array<string> => <- dumper_frontend_flags(target_lp64_linux(), error)

//! A unit the reference cannot preprocess by decision: `clang -E` under the dumper's flags fails on
//! it, for `reason`. `suffix` is the end of the unit's path.
struct ReferenceFailure {
    suffix : string
    reason : string
}

//! The list the runner reads, from the repository root.
let REFERENCE_FAILURES = "compare/pp/reference_failures.txt"

//! The reference failures listed in the text `list`: a line `<unit path suffix>\t<reason>`, a line
//! starting `#` a comment.
[arch(at="ARCHITECTURE.md#reference-failures")]
def reference_failures(list : string) : array<ReferenceFailure> {
    var listed : array<ReferenceFailure>
    for (line in split(list, "\n")) {
        let tab = find(line, "\t")
        continue if (tab <= 0 || starts_with(line, "#"))
        listed |> push(ReferenceFailure(suffix = slice(line, 0, tab), reason = slice(line, tab + 1)))
    }
    return <- listed
}

//! The reason `unit` is listed for, "" when no entry's suffix ends its path.
def listed_reason(listed : array<ReferenceFailure>; unit : string) : string {
    for (f in listed) {
        return f.reason if (unit == f.suffix || ends_with(unit, "/{f.suffix}"))
    }
    return ""
}

//! What a set of units gave: the tokens and differences of the units compared, the reference
//! failures listed and unlisted, and the listed units the reference preprocessed after all.
struct OracleTotals {
    tokens : int
    diffs : int
    listed : int
    unlisted : int
    stale : int
}

def operator +=(var a : OracleTotals; b : OracleTotals) {
    a.tokens += b.tokens
    a.diffs += b.diffs
    a.listed += b.listed
    a.unlisted += b.unlisted
    a.stale += b.stale
}

//! The totals line of `t` headed `name`.
def describe_totals(name : string; t : OracleTotals) : string =>
    "{name}: {t.tokens} tokens, {t.diffs} diffs, {t.listed} reference failures (listed), {t.unlisted} reference failures (unlisted), {t.stale} listed units preprocessed"

//! The totals of `units`, each unit with differences printed with its first `show` ones, each
//! reference failure with its listed reason or its error, then a line of the totals headed `name`.
def run_set(name : string; units : array<string>; work : string; flags : array<string>; listed : array<ReferenceFailure>;
            show : int; raw : bool = false) : OracleTotals {
    var totals : OracleTotals
    for (unit in units) {
        let r <- compare_unit(unit, work, flags, show, raw)
        let reason = listed_reason(listed, unit)
        if (!empty(r.error)) {
            if (empty(reason)) {
                totals.unlisted++
                print("{unit}: reference failure (unlisted): {r.error}\n")
            } else {
                totals.listed++
                print("{unit}: reference failure (listed): {reason}\n")
            }
            continue
        }
        if (!empty(reason)) {
            totals.stale++
            print("{unit}: listed as a reference failure ({reason}), preprocessed: drop its line\n")
        }
        totals.tokens += r.clang_tokens
        totals.diffs += r.diffs
        if (r.diffs > 0) {
            print("{unit}: {r.clang_tokens} tokens, {r.diffs} diffs\n")
            for (line in r.shown) {
                print("    {line}\n")
            }
        }
    }
    let head = "{name}: {length(units)} units"
    print("{describe_totals(head, totals)}\n")
    return totals
}

//! One unit through both sides: `clang -E -P` into `work`, then `-dump-tokens` and the pp lexer
//! over that output; with `raw`, over the unit itself, which then holds no directive and names no
//! macro, so clang's tokens are its lexer's: line splices, comments and a byte order mark reach both.
def compare_unit(unit, work : string; flags : array<string>; show : int; raw : bool = false) : UnitResult {
    var result = UnitResult(unit = unit)
    let preprocessed = raw ? unit : path_join(work, "{base_name(unit)}.i")
    if (!raw) {
        var argv <- [default_clang(), "-E", "-P"]
        argv |> push_from(flags, [unit, "-o", preprocessed])
        var out : string
        if (run_and_capture(argv, out, 300.0) != 0) {
            result.error = "clang -E: {out}"
            return <- result
        }
    }
    var dump : string
    var dump_argv <- [default_clang(), "-target", target_lp64_linux().triple, "-undef"]
    dump_argv |> push_from(DUMPER_FLAGS, ["-x", "c", "-fsyntax-only", "-Xclang", "-dump-tokens", preprocessed])
    if (run_and_capture(dump_argv, dump, 300.0) != 0) {
        result.error = "clang -dump-tokens: {slice(dump, 0, 400)}"
        return <- result
    }
    var bytes : array<uint8>
    if (!pp_read_file(preprocessed, bytes)) {
        result.error = "cannot read {preprocessed}"
        return <- result
    }
    let clang <- clang_tokens(dump)
    let ours <- lexed_tokens(bytes)
    result.clang_tokens = length(clang)
    result.pp_tokens = length(ours)
    result.diffs = compare_tokens(clang, ours, show, result.shown)
    return <- result
}

//! The units of a named corpus under `root`: `frontend`, every header of the own set; `c-testsuite`,
//! the single-exec suite as `suites/c_testsuite/fetch.sh` fetches it; `gcc-torture`, the `execute`
//! folder's own units as `suites/gcc_torture/fetch.sh` fetches it. Sorted, so a run is stable.
def corpus_units(root, corpus : string) : array<string> {
    var units : array<string>
    if (corpus == "frontend") {
        let folder = path_join(root, "frontend/include")
        dir_rec(folder) $(name, is_dir) {
            if (!is_dir && ends_with(name, ".h")) {
                units |> push(path_join(folder, name))
            }
        }
    } elif (corpus == "c-testsuite" || corpus == "gcc-torture") {
        let at = corpus == "c-testsuite" ? "c_testsuite/fetch/c-testsuite/tests/single-exec" : "gcc_torture/fetch/gcc/gcc/testsuite/gcc.c-torture/execute"
        let folder = path_join(root, "suites/{at}")
        dir(folder) $(name) {
            if (ends_with(name, ".c")) {
                units |> push(path_join(folder, name))
            }
        }
    }
    sort(units)
    return <- units
}

//! The command line of `run.das`.
[CommandLineArgs]
struct OracleArgs {
    @clarg_doc = "a corpus to compare: frontend, c-testsuite or gcc-torture (repeatable)"
    corpus : array<string>
    @clarg_doc = "the differences shown per unit"
    show : int = 3
    @clarg_doc = "the folder the preprocessed units are written to"
    work : string = "compare/work/pp"
    @clarg_doc = "compare the units themselves, not clang -E's output of them (units with no directive and no macro)"
    raw : bool
    @clarg_positional
    @clarg_doc = "units compared besides the corpora"
    units : array<string>
}

//! The corpora and units `args` names compared, from the repository root, each set's line and the
//! total printed; 0 when no unit differs, 1 when one does or the flags or the list cannot be read.
def run_oracle(args : OracleArgs) : int {
    var error : string
    let flags <- preprocess_flags(error)
    if (!empty(error)) {
        to_log(LOG_ERROR, "{error}\n")
        return 1
    }
    let listed <- reference_failures(fread(REFERENCE_FAILURES))
    if (empty(listed)) {
        to_log(LOG_ERROR, "{REFERENCE_FAILURES}: no entry read\n")
        return 1
    }
    mkdir_rec(args.work)
    let root = getcwd()
    var total : OracleTotals
    for (corpus in args.corpus) {
        total += run_set(corpus, corpus_units(root, corpus), args.work, flags, listed, args.show)
    }
    if (!empty(args.units)) {
        total += run_set("units", args.units, args.work, flags, listed, args.show, args.raw)
    }
    let line = describe_totals("total", total)
    print("{line}\n")
    return total.diffs == 0 ? 0 : 1
}
