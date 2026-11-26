options gen2

module pp_oracle public

require strings
require math
require daslib/strings_boost
require daslib/fio
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
    "semi" => int(PpTok.SEMI), "equal" => int(PpTok.ASSIGN), "equalequal" => int(PpTok.EQ),
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
//! more than one line when its `[UnClean='...']` flag spells a line splice; the `eof` record ends them. `has_space` is `[LeadingSpace]`, or `[StartOfLine]` past the file's
//! first byte: clang leaves `[LeadingSpace]` off a token right after a newline.
[arch(at="ARCHITECTURE.md#flags")]
def clang_tokens(dump : string) : array<OracleToken> {
    var tokens : array<OracleToken>
    var pending = ""
    for (part in split(dump, "\n")) {
        let line = empty(pending) ? part : "{pending}\n{part}"
        let loc_at = find(line, "\tLoc=<")
        if (loc_at < 0) {
            pending = find(line, "[UnClean='") >= 0 ? line : ""
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
                                   line = at_line, col = at_col, at_bol = sol, has_space = ls || (sol && (at_line > 1 || at_col > 1))))
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

//! The positions where `clang` and `ours` differ in kind, spelling, line, column or a flag, plus
//! the tokens one side has past the other's end; the first `show` of them described in `shown`.
def compare_tokens(clang, ours : array<OracleToken>; show : int; var shown : array<string>) : int {
    var diffs = 0
    let common = min(length(clang), length(ours))
    for (i, c, o in count(), clang, ours) {
        if (c.kind != o.kind || c.spelling != o.spelling || c.line != o.line || c.col != o.col || c.at_bol != o.at_bol || c.has_space != o.has_space) {
            diffs++
            if (length(shown) < show) {
                shown |> push("#{i}: clang {describe(c)} | pp {describe(o)}")
            }
        }
    }
    let extra = max(length(clang), length(ours)) - common
    if (extra > 0 && length(shown) < show) {
        shown |> push("{extra} tokens past the shorter side's end ({length(clang)} clang, {length(ours)} pp)")
    }
    return diffs + extra
}

//! The flags of a unit's preprocessing: Dumper A's, under the `linux` dialect - its triple, clang's
//! own macros dropped and the table's set, plain `char` unsigned, the own headers the only system
//! folder; `error` names what is missing.
def preprocess_flags(var error : string&) : array<string> => <- dumper_frontend_flags(target_lp64_linux(), error)

//! The tokens, differences and clang failures of `units`, each unit with differences printed with
//! its first `show` ones, then a line of the totals headed `name`.
def run_set(name : string; units : array<string>; work : string; flags : array<string>; show : int; raw : bool = false) : int3 {
    var totals : int3
    for (unit in units) {
        let r <- compare_unit(unit, work, flags, show, raw)
        if (!empty(r.error)) {
            totals.z++
            print("{unit}: {r.error}\n")
            continue
        }
        totals.x += r.clang_tokens
        totals.y += r.diffs
        if (r.diffs > 0) {
            print("{unit}: {r.clang_tokens} tokens, {r.diffs} diffs\n")
            for (line in r.shown) {
                print("    {line}\n")
            }
        }
    }
    print("{name}: {length(units)} units, {totals.z} clang failures, {totals.x} tokens, {totals.y} diffs\n")
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
//! the single-exec suite as `suites/c_testsuite/fetch.sh` fetches it. Sorted, so a run is stable.
def corpus_units(root, corpus : string) : array<string> {
    var units : array<string>
    if (corpus == "frontend") {
        let folder = path_join(root, "frontend/include")
        dir_rec(folder) $(name, is_dir) {
            if (!is_dir && ends_with(name, ".h")) {
                units |> push(path_join(folder, name))
            }
        }
    } elif (corpus == "c-testsuite") {
        let folder = path_join(root, "suites/c_testsuite/fetch/c-testsuite/tests/single-exec")
        dir(folder) $(name) {
            if (ends_with(name, ".c")) {
                units |> push(path_join(folder, name))
            }
        }
    }
    sort(units)
    return <- units
}
