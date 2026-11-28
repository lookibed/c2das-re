options gen2

module pp_oracle public

require strings
require math
require daslib/strings_boost
require daslib/fio
require daslib/clargs
require ../../frontend/pp_lexer.das
require ../../frontend/pp_directives.das
require ../../frontend/pp_expand.das
require ../../frontend/c_defines.das
require ../../converter/cir.das
require ../../converter/dumper_a.das
require pp_features

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

//! Whether `unit`, which the reference failed on with `error` ("" when it did not), is a reference
//! failure: counted into `totals` and printed, listed with its reason or unlisted with `error`. A
//! listed unit the reference preprocessed is counted and printed as stale, and compared.
[arch(at="ARCHITECTURE.md#reference-failures")]
def reference_failure(listed : array<ReferenceFailure>; unit, error : string; var totals : OracleTotals) : bool {
    let reason = listed_reason(listed, unit)
    if (!empty(error)) {
        if (empty(reason)) {
            totals.unlisted++
            print("{unit}: reference failure (unlisted): {error}\n")
        } else {
            totals.listed++
            print("{unit}: reference failure (listed): {reason}\n")
        }
        return true
    }
    if (!empty(reason)) {
        totals.stale++
        print("{unit}: listed as a reference failure ({reason}), preprocessed: drop its line\n")
    }
    return false
}

//! The totals of `units`, each unit with differences printed with its first `show` ones, each
//! reference failure with its listed reason or its error, then a line of the totals headed `name`.
def run_set(name : string; units : array<string>; work : string; flags : array<string>; listed : array<ReferenceFailure>;
            show : int; raw : bool = false) : OracleTotals {
    var totals : OracleTotals
    for (unit in units) {
        let r <- compare_unit(unit, work, flags, show, raw)
        continue if (reference_failure(listed, unit, r.error, totals))
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
//! folder's own units as `suites/gcc_torture/fetch.sh` fetches it; `pp2`, the `.c` units of
//! `compare/pp/fixtures/pp2/`. Sorted, so a run is stable. `error` names an unknown corpus or a
//! corpus folder that is missing, a suite not fetched among them: no corpus is ever empty by absence.
def corpus_units(root, corpus : string; var error : string&) : array<string> {
    var units : array<string>
    let folders <- {"frontend" => "frontend/include", "pp2" => "compare/pp/fixtures/pp2", "pp3" => "compare/pp/fixtures/pp3", "pp4" => "compare/pp/fixtures/pp4",
                    "c-testsuite" => "suites/c_testsuite/fetch/c-testsuite/tests/single-exec",
                    "gcc-torture" => "suites/gcc_torture/fetch/gcc/gcc/testsuite/gcc.c-torture/execute"}
    let relative = folders?[corpus] ?? ""
    if (empty(relative)) {
        error = "unknown corpus '{corpus}': frontend, c-testsuite, gcc-torture, pp2, pp3 or pp4"
        return <- units
    }
    let folder = path_join(root, relative)
    if (!stat(folder).is_dir) {
        let fetches <- {"c-testsuite" => "suites/c_testsuite/fetch.sh", "gcc-torture" => "suites/gcc_torture/fetch.sh"}
        let fetch = fetches?[corpus] ?? ""
        let hint = empty(fetch) ? "" : " (fetch it with {fetch})"
        error = "corpus {corpus}: {folder} is missing{hint}"
        return <- units
    }
    if (corpus == "frontend") {
        dir_rec(folder) $(name, is_dir) {
            if (!is_dir && ends_with(name, ".h")) {
                units |> push(path_join(folder, name))
            }
        }
    } else {
        dir(folder) $(name) {
            if (ends_with(name, ".c")) {
                units |> push(path_join(folder, name))
            }
        }
    }
    sort(units)
    return <- units
}

//! Every dialect's feature-query table (`pp_features.das`) regenerated into `frontend/predefined/`,
//! the clang runs' units under `work`; 0 when each was written.
def write_features(work : string) : int {
    var error = ""
    mkdir_rec(work)
    let headers = has_env_variable("DAS_CLANG_INCLUDE") ? get_env_variable("DAS_CLANG_INCLUDE") : path_join(dir_name(dir_name(default_clang())), "include")
    let candidates <- feature_candidates(headers, error)
    for (dialect in DIALECTS) {
        var inscope flags <- dialect_flags(dialect, error)
        let text = empty(error) ? generate_features(dialect, flags, candidates, work, error) : ""
        if (!empty(error)) {
            to_log(LOG_ERROR, "{error}\n")
            return 1
        }
        fwrite(features_path(dialect), text)
        to_log(LOG_INFO, "{features_path(dialect)}: written\n")
    }
    return 0
}

//! The command line of `run.das`.
[CommandLineArgs]
struct OracleArgs {
    @clarg_doc = "a corpus to compare: frontend, c-testsuite, gcc-torture, pp2, pp3 or pp4 (repeatable)"
    corpus : array<string>
    @clarg_doc = "the differences shown per unit"
    show : int = 3
    @clarg_doc = "the folder the preprocessed units are written to"
    work : string = "compare/work/pp"
    @clarg_doc = "compare the units themselves, not clang -E's output of them (units with no directive and no macro)"
    raw : bool
    @clarg_doc = "compare the directive layer, frontend/pp_directives.das, not the lexer: units with directives and no macro use (corpus pp2 is the fixture set)"
    pp2 : bool
    @clarg_doc = "compare the macro expansion, frontend/pp_expand.das, over the directive layer (corpus pp3 is the fixture set)"
    pp3 : bool
    @clarg_doc = "compare the whole preprocessor, the #if evaluator included, with clang: the expansion oracle under its PP.4 name (corpus pp4 is the fixture set)"
    pp4 : bool
    @clarg_doc = "regenerate the feature-query tables of frontend/predefined/ from the pinned clang, then exit"
    features : bool
    @clarg_doc = "a corpus list for --pp2, --pp3 and --pp4: a unit a line, its path then its -I, -D and -x flags (repeatable)"
    list : array<string>
    @clarg_positional
    @clarg_doc = "units compared besides the corpora"
    units : array<string>
}

//! The corpora and units `args` names compared, from the repository root, each set's line and the
//! total printed; 0 when no unit differs, 1 when one does, a corpus is unknown or missing, or the
//! flags or the list cannot be read.
//! With `pp2` the directive oracle runs them, with `pp3` or `pp4` the expansion oracle (`run_pp2`).
def run_oracle(args : OracleArgs) : int {
    var error : string
    return write_features(args.work) if (args.features)
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
    return run_pp2(args, root, flags, listed) if (args.pp2 || args.pp3 || args.pp4)
    var total : OracleTotals
    for (corpus in args.corpus) {
        var inscope units <- corpus_units(root, corpus, error)
        if (!empty(error)) {
            to_log(LOG_ERROR, "{error}\n")
            return 1
        }
        total += run_set(corpus, units, args.work, flags, listed, args.show)
    }
    if (!empty(args.units)) {
        total += run_set("units", args.units, args.work, flags, listed, args.show, args.raw)
    }
    let line = describe_totals("total", total)
    print("{line}\n")
    return total.diffs == 0 ? 0 : 1
}

// The directive oracle of `frontend/pp_directives.das` (`ARCHITECTURE.md#pp2`)

//! The class of a difference, and of a unit by the latest its differences wait for: equal to clang,
//! waiting for PP.3's expansion, or different where the preprocessor answers.
enum Pp2Class {
    clean
    needs_pp3
    differs
}

//! A token PP.2 handed out, with what a difference is classed by: whether it names a macro PP.2 has
//! defined where it stands, and whether it stands in the parenthesized arguments of a function-like
//! macro PP.2 has defined.
struct Pp2Token {
    tok : OracleToken
    macro : bool
    in_call : bool
}

//! One difference: `clang_count` clang tokens from `clang_at` stand where PP.2 has `pp_count`
//! tokens from `pp_at`, with no token of either side matched between them.
struct Pp2Difference {
    clang_at : int
    clang_count : int
    pp_at : int
    pp_count : int
    cls : Pp2Class
}

//! A unit through PP.2 and clang: every difference with its class, and what PP.2 left to the later
//! items. A place in PP.2's stream is the count of tokens it handed out before it.
struct Pp2Result {
    unit : string
    expanded : bool         //!< PP.3's expanded stream, not PP.2's: no difference waits for PP.3
    clang_tokens : int
    pp_tokens : int
    differences : array<Pp2Difference>
    pp3_at : array<int>     //!< the places of the `#include`s and `#line`s left to PP.3
    clang_pragmas : int
    pp_pragmas : int
    clang_pragma_at : array<int>    //!< the place of each `#pragma` and `#ident` line of clang's output, in order
    pp_pragma_at : array<int>       //!< the place of each pragma and pack entry, in order
    errors : array<string>  //!< the preprocessor's errors, past those naming PP.3 and those met past `pp3_from`
    pp3_from : int = -1     //!< PP.2's stream alone: the place of the first directive line that names a macro only PP.3 reads (`Preprocessor.unexpanded`)
    gave_up : bool          //!< the alignment passed its limit: the streams past their common ends are one difference
    error : string          //!< clang failed on the unit: nothing compared
    shown : array<string>
    cls : Pp2Class
}

//! The edits the alignment of two streams searches before it gives up.
let PP2_ALIGN_LIMIT = 2000

//! clang's builtin macros (`Preprocessor::RegisterBuiltinMacros`): no `#define` makes them, `-dM`
//! lists none of them, and PP.3 expands them.
let private CLANG_BUILTIN_MACROS <- {
    "__LINE__", "__FILE__", "__BASE_FILE__", "__FILE_NAME__", "__COUNTER__", "__INCLUDE_LEVEL__", "__TIMESTAMP__",
    "__DATE__", "__TIME__", "_Pragma", "__has_feature", "__has_extension", "__has_builtin", "__has_constexpr_builtin",
    "__has_attribute", "__has_c_attribute", "__has_declspec_attribute", "__has_cpp_attribute", "__has_include",
    "__has_include_next", "__has_embed", "__has_warning", "__is_identifier", "__is_target_arch", "__is_target_vendor",
    "__is_target_os", "__is_target_environment", "__is_target_variant_os", "__is_target_variant_environment",
    "__building_module", "__MODULE__"
}

//! The predefined-macro entries and the include path of PP.2 under Dumper A's `linux` dialect: the
//! table's entries and the own headers' folder, canonical, as `frontend_flags` hands them to clang.
def pp2_setup(var error : string&) : tuple<entries : array<string>; search : array<string>> {
    var setup : tuple<entries : array<string>; search : array<string>>
    setup.entries <- read_predefined(predefined_table(target_lp64_linux()), error)
    setup.search |> push(get_full_file_name(own_include_dir()))
    return <- setup
}

//! The `#pragma` and `#ident` lines of clang's `-E` output `text`: clang prints each pragma it
//! keeps and each `#ident` as a line, and its token dump of that output takes them as directives,
//! not tokens, as PP.2 keeps them in its pragma and pack ledgers instead of its stream.
[arch(at="ARCHITECTURE.md#pp2")]
def pragma_lines(text : string) : int => length(pragma_line_numbers(text))

// the numbers, from 1, of the `#pragma` and `#ident` lines of `text`
def private pragma_line_numbers(text : string) : array<int> {
    var numbers : array<int>
    for (line, n in split(text, "\n"), count(1)) {
        let s = strip(line)
        if (starts_with(s, "#")) {
            let directive = strip(slice(s, 1))
            if (starts_with(directive, "pragma") || starts_with(directive, "ident")) {
                numbers |> push(n)
            }
        }
    }
    return <- numbers
}

//! The place of each `#pragma` and `#ident` line of clang's `-E` output `text` in its token stream
//! `clang`, the tokens of that output: the count of tokens on the lines before it.
[arch(at="ARCHITECTURE.md#pp2")]
def pragma_places(text : string; clang : array<OracleToken>) : array<int> {
    let numbers <- pragma_line_numbers(text)
    var places : array<int>
    places |> reserve(length(numbers))
    var before = 0
    for (n in numbers) {
        while (before < length(clang) && clang[before].line < n) {
            before++
        }
        places |> push(before)
    }
    return <- places
}

//! The tokens PP.2 hands out for `unit` read through `fio`, the `linux` feature table answering
//! the `#if` queries, and what it left to PP.3, into `result`. A diagnostic is placed at the tokens
//! handed out before it; an error counts as the preprocessor's own unless it names PP.3. With
//! `result.expanded`, PP.3's expanded tokens, the time builtins at `ORACLE_EPOCH`, none marked as
//! a macro's.
[arch(at="ARCHITECTURE.md#pp2")]
def pp2_tokens(unit : string; entries, search : array<string>; var result : Pp2Result) : array<Pp2Token> {
    var tokens : array<Pp2Token>
    var pp : Preprocessor
    let started = (result.expanded ? pp_expand_start(pp, new PpFioProvider(), unit, entries, search, ORACLE_EPOCH)
                                   : pp_start(pp, new PpFioProvider(), unit, entries, search))
    if (!started) {
        result.errors |> push("cannot read {unit}")
        return <- tokens
    }
    var table_error = ""
    pp.eval.features <- read_features(features_path("linux"), table_error)
    if (!empty(table_error)) {
        result.errors |> push(table_error)
    }
    var seen = 0
    var more = true
    var called = false
    var depth = 0
    while (more) {
        more = pp_next_token(pp)
        if (result.pp3_from < 0 && !empty(pp.unexpanded)) {
            result.pp3_from = pp.unexpanded[0]
        }
        for (i in range(seen, length(pp.diags))) {
            let what = pp.diags[i].what
            if (find(what, "PP.3") >= 0 || (result.pp3_from >= 0 && pp.diags[i].severity != PpSeverity.warning)) {
                result.pp3_at |> push(length(tokens))
            } elif (pp.diags[i].severity != PpSeverity.warning) {
                result.errors |> push("{pp.diags[i].line}:{pp.diags[i].col} {what}")
            }
        }
        seen = length(pp.diags)
        if (more) {
            let kind = pp.tok.tok.kind
            let macro = !result.expanded && kind == int(PpTok.IDENTIFIER) && pp_defined(pp, pp.tok.tok.sym)
            var in_call = false
            if (depth > 0) {
                in_call = true
                depth += kind == int(PpTok.LPAREN) ? 1 : kind == int(PpTok.RPAREN) ? -1 : 0
            } elif (called && kind == int(PpTok.LPAREN)) {
                in_call = true
                depth = 1
            }
            called = macro && pp.macros[pp.macro_of?[pp.tok.tok.sym] ?? -1].function_like
            tokens |> push(Pp2Token(tok = OracleToken(kind = kind, spelling = pp_token_spelling(pp), at_bol = pp.tok.tok.at_bol),
                                    macro = macro, in_call = in_call))
        }
    }
    result.pp_pragmas = length(pp.pragmas) + length(pp.packs)
    result.pp_pragma_at |> reserve(result.pp_pragmas)
    for (p in pp.pragmas) {
        result.pp_pragma_at |> push(p.emitted)
    }
    for (p in pp.packs) {
        result.pp_pragma_at |> push(p.emitted)
    }
    sort(result.pp_pragma_at)
    return <- tokens
}

//! Whether two tokens are the same to the directive oracle: kind, spelling and `at_bol`, since
//! `-P` output has lines and columns of its own.
def same_pp2_token(a, b : OracleToken) : bool => a.kind == b.kind && a.at_bol == b.at_bol && a.spelling == b.spelling

// Myers' greedy search for the shortest edit script of `clang` and `ours` from `lo`, `n` and `m`
// tokens long: its edit count, -1 past `limit`; before each edit count `d`, the furthest x of the
// diagonals -d-1 .. d+1 lies in `trace` from `trace_at[d]`
def private myers_search(clang : array<OracleToken>; ours : array<Pp2Token>; lo, n, m, limit : int;
                         var trace, trace_at : array<int>) : int {
    let offset = limit + 1
    var v : array<int>
    v |> resize(2 * limit + 3)
    trace_at |> reserve(limit + 1)
    for (d in range(limit + 1)) {
        let at = length(trace)
        let need = at + 2 * d + 3
        if (capacity(trace) < need) {
            trace |> reserve(2 * need)
        }
        trace |> resize(need)
        trace_at |> push(at)
        for (k in range(-d - 1, d + 2)) {
            trace[at + k + d + 1] = v[offset + k]
        }
        for (step in range(d + 1)) {
            let k = 2 * step - d
            var x = k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]) ? v[offset + k + 1] : v[offset + k - 1] + 1
            var y = x - k
            while (x < n && y < m && same_pp2_token(clang[lo + x], ours[lo + y].tok)) {
                x++
                y++
            }
            v[offset + k] = x
            return d if (x >= n && y >= m)
        }
    }
    return -1
}

// the token pairs the shortest script of `found` edits matches, last first, walked back from
// (`n`, `m`) through `myers_search`'s trace
def private myers_matches(found, n, m : int; trace, trace_at : array<int>) : array<int2> {
    var matched : array<int2>
    matched |> reserve(min(n, m))
    var x = n
    var y = m
    for (step in range(found)) {
        let d = found - step
        let before = trace_at[d] + d + 1
        let k = x - y
        let prev_k = k == -d || (k != d && trace[before + k - 1] < trace[before + k + 1]) ? k + 1 : k - 1
        let px = trace[before + prev_k]
        while (x > px && y > px - prev_k) {
            x--
            y--
            matched |> push(int2(x, y))
        }
        x = px
        y = px - prev_k
    }
    while (x > 0 && y > 0) {
        x--
        y--
        matched |> push(int2(x, y))
    }
    return <- matched
}

//! The differences of `clang` and `ours`: the runs between the tokens Myers' shortest edit script
//! matches. Past `limit` edits it gives up (`gave_up`), the streams past their common ends then one
//! difference.
[arch(at="ARCHITECTURE.md#pp2")]
def pp2_differences(clang : array<OracleToken>; ours : array<Pp2Token>; limit : int; var gave_up : bool&) : array<Pp2Difference> {
    var differences : array<Pp2Difference>
    var lo = 0
    while (lo < length(clang) && lo < length(ours) && same_pp2_token(clang[lo], ours[lo].tok)) {
        lo++
    }
    var n = length(clang) - lo
    var m = length(ours) - lo
    while (n > 0 && m > 0 && same_pp2_token(clang[lo + n - 1], ours[lo + m - 1].tok)) {
        n--
        m--
    }
    return <- differences if (n == 0 && m == 0)
    var trace, trace_at : array<int>
    let found = myers_search(clang, ours, lo, n, m, limit, trace, trace_at)
    if (found < 0) {
        gave_up = true
        differences |> push(Pp2Difference(clang_at = lo, clang_count = n, pp_at = lo, pp_count = m))
        return <- differences
    }
    let matched <- myers_matches(found, n, m, trace, trace_at)
    var prev = int2(-1, -1)
    for (i in range(length(matched) + 1)) {
        let at = i < length(matched) ? matched[length(matched) - 1 - i] : int2(n, m)
        if (prev.x + 1 < at.x || prev.y + 1 < at.y) {
            differences |> push(Pp2Difference(clang_at = lo + prev.x + 1, clang_count = at.x - prev.x - 1, pp_at = lo + prev.y + 1,
                                              pp_count = at.y - prev.y - 1))
        }
        prev = at
    }
    return <- differences
}

// the places in PP.2's stream a difference spans, widened over every place an insertion or a
// deletion of one side can slide to among equal tokens: a diff puts such a run at one of them
def private pp2_span(d : Pp2Difference; clang : array<OracleToken>; ours : array<Pp2Token>) : int2 {
    var span = int2(d.pp_at, d.pp_at + d.pp_count)
    if (d.pp_count == 0 && d.clang_count > 0) {
        var at = d.clang_at
        while (at > 0 && span.x > 0 && same_pp2_token(clang[at - 1], clang[at + d.clang_count - 1])) {
            at--
            span.x--
        }
        at = d.clang_at
        while (at + d.clang_count < length(clang) && same_pp2_token(clang[at + d.clang_count], clang[at])) {
            at++
            span.y++
        }
    } elif (d.clang_count == 0 && d.pp_count > 0) {
        while (span.x > 0 && same_pp2_token(ours[span.x - 1].tok, ours[span.x + d.pp_count - 1].tok)) {
            span.x--
        }
        var at = d.pp_at
        while (at + d.pp_count < length(ours) && same_pp2_token(ours[at + d.pp_count].tok, ours[at].tok)) {
            at++
            span.y++
        }
    }
    return span
}

//! The class of difference `d`: needs PP.3 when it ends past a directive line naming a macro PP.2
//! alone read as a name (`pp3_from`), or when PP.2's side, or the token either side of it,
//! names a macro PP.2 defined or one of clang's builtin macros or stands in a function-like macro's
//! call, or a place left to PP.3 lies in its span - never in PP.3's expanded stream; else it differs.
[arch(at="ARCHITECTURE.md#pp2")]
def pp2_difference_class(r : Pp2Result; d : Pp2Difference; clang : array<OracleToken>; ours : array<Pp2Token>) : Pp2Class {
    let span = pp2_span(d, clang, ours)
    return Pp2Class.differs if (r.expanded)
    return Pp2Class.needs_pp3 if (r.pp3_from >= 0 && span.y >= r.pp3_from)
    let near = int2(max(span.x - 1, 0), min(span.y + 1, length(ours)))
    for (j in range(near.x, near.y)) {
        return Pp2Class.needs_pp3 if (ours[j].macro || ours[j].in_call || key_exists(CLANG_BUILTIN_MACROS, ours[j].tok.spelling))
    }
    for (p in r.pp3_at) {
        return Pp2Class.needs_pp3 if (span.x <= p && p <= span.y)
    }
    return Pp2Class.differs
}

//! The class of a compared unit: it differs when PP.2 has an error of its own, a difference
//! differs, the pragma counts disagree with nothing left to PP.3 to explain them, or the
//! streams are equal and a pragma stands at another place; else it needs the latest item a
//! difference or a place left over waits for; else it is clean.
[arch(at="ARCHITECTURE.md#pp2")]
def pp2_class(r : Pp2Result) : Pp2Class {
    return Pp2Class.differs if (!empty(r.errors))
    var cls = Pp2Class.clean
    for (d in r.differences) {
        cls = int(d.cls) > int(cls) ? d.cls : cls
    }
    if (!empty(r.pp3_at) && cls == Pp2Class.clean) {
        cls = Pp2Class.needs_pp3
    }
    if (r.clang_pragmas != r.pp_pragmas) {
        let explained = cls == Pp2Class.needs_pp3 && r.clang_pragmas > r.pp_pragmas
        return Pp2Class.differs if (!explained)
    } elif (cls == Pp2Class.clean && length(r.clang_pragma_at) == length(r.pp_pragma_at)) {
        for (a, b in r.clang_pragma_at, r.pp_pragma_at) {
            return Pp2Class.differs if (a != b)
        }
    }
    return cls
}

// the spellings of `count` tokens from `at`, at most six of them
def private pp2_spellings(toks : array<OracleToken>; at, count : int) : string {
    let parts <- [for (i in range(at, at + min(count, 6))); toks[i].spelling]
    return "{join(parts, " ")}{count > 6 ? " ..." : ""}"
}

//! The time the expansion oracle's units are preprocessed at, seconds since 1970: clang reads it
//! from `SOURCE_DATE_EPOCH`, PP.3 from `pp_expand_start`, so `__DATE__`, `__TIME__` and
//! `__TIMESTAMP__` agree.
let ORACLE_EPOCH = 1000000000l

//! A unit of a corpus and the flags of its own: `-I<dir>`, `-D<entry>` and `-x <language>`.
struct OracleUnit {
    path : string
    flags : array<string>
}

//! The units at `paths`, with no flags of their own.
def oracle_units(paths : array<string>) : array<OracleUnit> =>
    <- [for (path in paths); OracleUnit(path = path)]

//! The units of the corpus list `list`: a line each, the unit's path then its flags, blank-separated.
[arch(at="ARCHITECTURE.md#pp3")]
def list_units(list : string) : array<OracleUnit> {
    var units : array<OracleUnit>
    for (line in split(fread(list), "\n")) {
        var inscope words <- [for (w in split(strip(line), " ")); w; where !empty(w)]
        continue if (empty(words))
        var unit = OracleUnit(path = words[0])
        unit.flags |> reserve(length(words) - 1)
        for (i in range(1, length(words))) {
            unit.flags |> push(words[i])
        }
        units |> emplace(unit)
    }
    return <- units
}

//! One unit through clang (`-E -P`, then `-dump-tokens` of its output, the `#pragma` and `#ident`
//! lines counted apart) and through PP.2 with the same macros and include path; aligned by kind,
//! spelling and `at_bol`, and every difference classed. Every difference that differs is shown,
//! and `show` of each other class. With `expand`, through PP.3 at `ORACLE_EPOCH`, and the unit's
//! own flags (`OracleUnit`) given to both sides: `-I` before `search`, `-D` after `entries`.
[arch(at="ARCHITECTURE.md#pp2")]
def compare_unit_pp2(unit, work : string; flags : array<string>; entries, search : array<string>; show : int; expand : bool = false;
                     unit_flags : array<string> = array<string>()) : Pp2Result {
    var result = Pp2Result(unit = unit, expanded = expand)
    var our_search : array<string>
    var our_entries := entries
    var clang_flags := flags
    var i = 0
    while (i < length(unit_flags)) {
        let f = unit_flags[i]
        if (starts_with(f, "-I")) {
            our_search |> push(slice(f, 2))
        } elif (starts_with(f, "-D")) {
            our_entries |> push(slice(f, 2))
        } elif (f == "-x" && i + 1 < length(unit_flags)) {
            clang_flags |> push(f)
            i++
        } else {
            result.error = "unsupported unit flag {f}"
            return <- result
        }
        clang_flags |> push(unit_flags[i])
        i++
    }
    our_search |> push_from(search)
    let preprocessed = path_join(work, "{base_name(unit)}.{expand ? "pp3" : "pp2"}.i")
    var argv <- [default_clang(), "-E", "-P"]
    argv |> push_from(clang_flags, [unit, "-o", preprocessed])
    var out : string
    let env <- ["SOURCE_DATE_EPOCH={ORACLE_EPOCH}"]
    if (run_and_capture(argv, "", env, out, 300.0) != 0) {
        result.error = "clang -E: {out}"
        return <- result
    }
    var dump : string
    var dump_argv <- [default_clang(), "-target", target_lp64_linux().triple, "-undef"]
    dump_argv |> push_from(DUMPER_FLAGS, ["-x", "c", "-fsyntax-only", "-Xclang", "-dump-tokens", preprocessed])
    if (run_and_capture(dump_argv, dump, 300.0) != 0) {
        result.error = "clang -dump-tokens: {slice(dump, 0, 400)}"
        return <- result
    }
    let clang <- clang_tokens(dump)
    let text = fread(preprocessed)
    result.clang_pragmas = pragma_lines(text)
    result.clang_pragma_at <- pragma_places(text, clang)
    let ours <- pp2_tokens(unit, our_entries, our_search, result)
    result.clang_tokens = length(clang)
    result.pp_tokens = length(ours)
    result.differences <- pp2_differences(clang, ours, PP2_ALIGN_LIMIT, result.gave_up)
    if (!empty(result.differences)) {
        let pp_side <- [for (o in ours); o.tok]
        let classes <- [for (d in result.differences); pp2_difference_class(result, d, clang, ours)]
        var shown_of <- [0, 0, 0]
        for (d, cls in result.differences, classes) {
            d.cls = cls
            if (d.cls == Pp2Class.differs || shown_of[int(d.cls)] < show) {
                shown_of[int(d.cls)]++
                result.shown |> push("{d.cls} at pp #{d.pp_at}: clang [{pp2_spellings(clang, d.clang_at, d.clang_count)}] | pp [{pp2_spellings(pp_side, d.pp_at, d.pp_count)}]")
            }
        }
    }
    result.cls = pp2_class(result)
    return <- result
}

//! The differences of `r` of class `cls`.
def pp2_count(r : Pp2Result; cls : Pp2Class) : int => length([for (d in r.differences); d; where d.cls == cls])

//! What a set of units gave the directive oracle: the units of each class and the differences of
//! each class, in `Pp2Class` order, and the tokens and reference failures as `OracleTotals` counts them.
struct Pp2Totals {
    units : int3
    differences : int3
    oracle : OracleTotals
}

def operator +=(var a : Pp2Totals; b : Pp2Totals) {
    a.units += b.units
    a.differences += b.differences
    a.oracle += b.oracle
}

//! The totals line of `t` headed `name`, which ends in its own separator.
def describe_pp2_totals(name : string; t : Pp2Totals) : string {
    let u = t.units
    let d = t.differences
    let o = t.oracle
    return "{name} {u.x} clean, {u.y} need PP.3, {u.z} differ, {o.listed} reference failures (listed), {o.unlisted} reference failures (unlisted), {o.stale} listed units preprocessed; {o.tokens} tokens, differences {d.z} differ, {d.y} need PP.3"
}

//! The directive oracle over `units`, or with `expand` the expansion oracle: each unit not clean
//! printed with its class, the count of its differences of each class, the differences shown and
//! PP.2's errors, each reference failure as `run_set` prints it, then a line of the totals headed
//! `name`.
def run_set_pp2(name : string; units : array<OracleUnit>; work : string; flags : array<string>; listed : array<ReferenceFailure>;
                entries, search : array<string>; show : int; expand : bool = false; mode : string = "") : Pp2Totals {
    var totals : Pp2Totals
    for (u in units) {
        let unit = u.path
        let r <- compare_unit_pp2(unit, work, flags, entries, search, show, expand, u.flags)
        continue if (reference_failure(listed, unit, r.error, totals.oracle))
        totals.units[int(r.cls)]++
        totals.oracle.tokens += r.clang_tokens
        for (d in r.differences) {
            totals.differences[int(d.cls)]++
        }
        continue if (r.cls == Pp2Class.clean)
        print("{unit}: {r.cls}, {r.clang_tokens} clang / {r.pp_tokens} pp tokens, differences {pp2_count(r, Pp2Class.differs)} differ, {pp2_count(r, Pp2Class.needs_pp3)} need PP.3{r.gave_up ? " (alignment gave up)" : ""}, places left {length(r.pp3_at)} to PP.3, pragmas {r.clang_pragmas} clang / {r.pp_pragmas} pp\n")
        for (line in r.shown) {
            print("    {line}\n")
        }
        for (line in r.errors) {
            print("    pp: {line}\n")
        }
    }
    let head = "{name} ({empty(mode) ? (expand ? "pp3" : "pp2") : mode}): {length(units)} units,"
    let line = describe_pp2_totals(head, totals)
    print("{line}\n")
    return totals
}

//! The directive oracle, or with `args.pp3` the expansion oracle, over the corpora, the corpus lists
//! and the units `args` names, from `root`, each set's line and the total printed; 0 when no unit
//! differs where PP.2 (and PP.3) answer and the reference fails only on listed units, 1 when a unit
//! differs, a unit the list does not name fails in the reference, a corpus is unknown or missing, or
//! PP.2's setup fails.
def run_pp2(args : OracleArgs; root : string; flags : array<string>; listed : array<ReferenceFailure>) : int {
    var error : string
    let setup <- pp2_setup(error)
    if (!empty(error)) {
        to_log(LOG_ERROR, "{error}\n")
        return 1
    }
    let expand = args.pp3 || args.pp4
    let mode = args.pp4 ? "pp4" : expand ? "pp3" : "pp2"
    var total : Pp2Totals
    for (corpus in args.corpus) {
        var inscope units <- corpus_units(root, corpus, error)
        if (!empty(error)) {
            to_log(LOG_ERROR, "{error}\n")
            return 1
        }
        total += run_set_pp2(corpus, oracle_units(units), args.work, flags, listed, setup.entries, setup.search, args.show, expand, mode)
    }
    for (list in args.list) {
        if (!stat(list).is_reg) {
            to_log(LOG_ERROR, "corpus list {list} is missing\n")
            return 1
        }
        total += run_set_pp2(base_name(list), list_units(list), args.work, flags, listed, setup.entries, setup.search, args.show, expand, mode)
    }
    if (!empty(args.units)) {
        total += run_set_pp2("units", oracle_units(args.units), args.work, flags, listed, setup.entries, setup.search, args.show, expand, mode)
    }
    let line = describe_pp2_totals("total ({mode}):", total)
    print("{line}\n")
    return total.units.z == 0 && total.oracle.unlisted == 0 ? 0 : 1
}
