options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require ../pp/pp_oracle.das
require ../../frontend/pp_lexer.das

//! `compare/pp/pp_oracle.das`: clang's `-dump-tokens` read, its kinds mapped, two token streams
//! compared, and the edge-case unit through the pinned clang with no difference.

// two `-dump-tokens` records and the `eof` one: a keyword at the start of the first line, a token
// after a newline (no `[LeadingSpace]` from clang), a char constant holding a quote, and a token
// whose `[UnClean='...']` spells a line splice over two lines
let DUMP = "int 'int'\t [StartOfLine]\tLoc=<a.i:1:1>\nidentifier 'x'\t [LeadingSpace]\tLoc=<a.i:1:5>\nsemi ';'\t\tLoc=<a.i:1:6>\nchar_constant ''\\'''\t [StartOfLine]\tLoc=<a.i:2:1>\nidentifier 'ab'\t [LeadingSpace] [UnClean='a\\\nb']\tLoc=<a.i:2:6>\neof ''\t\tLoc=<a.i:3:2>\nidentifier 'z'\t\tLoc=<a.i:3:2>\n"

[test(description = "clang's -dump-tokens records read as tokens, a [StartOfLine] past the first byte counting as a space, an UnClean record over two lines one token, the eof record the end")]
def test_clang_tokens(t : T?) {
    let toks <- clang_tokens(DUMP)
    t |> equal(length(toks), 5)
    t |> equal(toks[0].kind, int(PpTok.IDENTIFIER))
    t |> success(toks[0].at_bol && !toks[0].has_space)
    t |> equal("{toks[1].spelling} {toks[1].line}:{toks[1].col} {toks[1].has_space}", "x 1:5 true")
    t |> equal(toks[2].kind, int(PpTok.SEMI))
    t |> equal(toks[3].kind, int(PpTok.CHAR_CONSTANT))
    t |> equal(toks[3].spelling, "'\\''")
    t |> success(toks[3].at_bol && toks[3].has_space)
    t |> equal("{toks[4].spelling} {toks[4].line}:{toks[4].col}", "ab 2:6")
    t |> equal(length(clang_tokens("junk\tLoc=<a.i:1:1>\nsemi ';'\t\tLoc=<a.i:1:2>\n")), 1)
    let raw <- clang_tokens("string_literal 'R\"(a\nb)\"'\t [StartOfLine]\tLoc=<a.i:1:1>\nsemi ';'\t\tLoc=<a.i:2:4>\n")
    t |> equal(length(raw), 2)
    t |> equal(raw[0].spelling, "R\"(a\nb)\"")
}

[test(description = "a token at the start of the file's first line has a space only from [LeadingSpace]: a byte order mark before it is none")]
def test_first_line_space(t : T?) {
    let toks <- clang_tokens("int 'int'\t [StartOfLine]\tLoc=<a.i:1:4>\nidentifier 'y'\t [StartOfLine] [LeadingSpace]\tLoc=<a.i:1:3>\n")
    t |> success(!toks[0].has_space)
    t |> success(toks[1].has_space)
}

[test(description = "a clang kind maps to its PpTok: punctuators, every literal class, unknown, and identifiers and keywords alike")]
def test_clang_kind(t : T?) {
    t |> equal(clang_kind("hashhash"), int(PpTok.HASHHASH))
    t |> equal(clang_kind("coloncolon"), int(PpTok.COLONCOLON))
    t |> equal(clang_kind("lesslessequal"), int(PpTok.SHL_ASSIGN))
    t |> equal(clang_kind("numeric_constant"), int(PpTok.PP_NUMBER))
    t |> equal(clang_kind("wide_char_constant"), int(PpTok.CHAR_CONSTANT))
    t |> equal(clang_kind("utf8_string_literal"), int(PpTok.STRING_LITERAL))
    t |> equal(clang_kind("unknown"), int(PpTok.OTHER))
    t |> equal(clang_kind("identifier"), int(PpTok.IDENTIFIER))
    t |> equal(clang_kind("typedef"), int(PpTok.IDENTIFIER))
}

[test(description = "the comparison counts every differing position and every token past the shorter side, showing the first ones")]
def test_compare_tokens(t : T?) {
    let a <- [OracleToken(kind = 1, spelling = "a", line = 1, col = 1), OracleToken(kind = 2, spelling = "b", line = 1, col = 3)]
    let b <- [OracleToken(kind = 1, spelling = "a", line = 1, col = 1), OracleToken(kind = 2, spelling = "b", line = 1, col = 3, has_space = true),
              OracleToken(kind = 3, spelling = "c", line = 2, col = 1)]
    var shown : array<string>
    t |> equal(compare_tokens(a, a, 5, shown), 0)
    t |> equal(compare_tokens(a, b, 5, shown), 2)
    t |> equal(length(shown), 2)
    t |> success(starts_with(shown[0], "#1: "), shown[0])
    var few : array<string>
    t |> equal(compare_tokens(a, b, 1, few), 2)
    t |> equal(length(few), 1)
}

[test(description = "each compared field alone makes a difference: kind, spelling, at_bol and has_space one, a line or a column one unmatched token on each side")]
def test_each_field(t : T?) {
    let base = OracleToken(kind = 1, spelling = "a", line = 1, col = 1)
    var kind = base
    kind.kind = 2
    var spelling = base
    spelling.spelling = "b"
    var line = base
    line.line = 2
    var col = base
    col.col = 2
    var bol = base
    bol.at_bol = true
    var space = base
    space.has_space = true
    let names = fixed_array("kind", "spelling", "at_bol", "has_space", "line", "col")
    for (name, other, expected in names, fixed_array(kind, spelling, bol, space, line, col), fixed_array(1, 1, 1, 1, 2, 2)) {
        var inscope shown : array<string>
        var inscope clang <- [base]
        var inscope ours <- [other]
        t |> equal(compare_tokens(clang, ours, 0, shown), expected, name)
    }
}

[test(description = "a token split in two costs its own differences and no more: the comparison resyncs on the position")]
def test_compare_resyncs(t : T?) {
    let clang <- [OracleToken(kind = 1, spelling = "::", line = 1, col = 1), OracleToken(kind = 2, spelling = "x", line = 1, col = 3),
                  OracleToken(kind = 2, spelling = "y", line = 2, col = 1)]
    let ours <- [OracleToken(kind = 3, spelling = ":", line = 1, col = 1), OracleToken(kind = 3, spelling = ":", line = 1, col = 2),
                 OracleToken(kind = 2, spelling = "x", line = 1, col = 3), OracleToken(kind = 2, spelling = "y", line = 2, col = 1)]
    var shown : array<string>
    t |> equal(compare_tokens(clang, ours, 5, shown), 2)
    t |> equal(length(shown), 2)
    t |> equal(shown[1], "#1: pp only 3 ':' 1:2")
}

[test(description = "only the first `show` differences are described, each as both sides' kind, spelling, place and flags")]
def test_show_cap(t : T?) {
    let clang <- [OracleToken(kind = 1, spelling = "a", line = 1, col = 1), OracleToken(kind = 1, spelling = "b", line = 1, col = 3)]
    let ours <- [OracleToken(kind = 1, spelling = "x", line = 1, col = 1, at_bol = true), OracleToken(kind = 1, spelling = "y", line = 1, col = 3)]
    var shown : array<string>
    t |> equal(compare_tokens(clang, ours, 1, shown), 2)
    t |> equal(length(shown), 1)
    t |> equal(shown[0], "#0: clang 1 'a' 1:1 | pp 1 'x' 1:1 bol")
}

[test(description = "the edge-case unit gives clang's tokens through the pp lexer, lexed raw and after clang -E", timeout = 1200)]
def test_edge_unit_against_clang(t : T?) {
    var error : string
    let flags <- preprocess_flags(error)
    t |> equal(error, "")
    let unit = "compare/pp/fixtures/edge_tokens.c"
    let work = path_join(test_temp_dir(), "pp_oracle")
    mkdir_rec(work)
    let preprocessed = path_join(work, "edge_tokens.c.i")
    for (raw in fixed_array(true, false)) {
        let r <- compare_unit(unit, work, flags, 5, raw)
        t |> equal(r.error, "", "raw {raw}")
        t |> success(r.clang_tokens > 150, "raw {raw}: {r.clang_tokens} tokens")
        t |> equal(r.diffs, 0, "raw {raw}: {r.shown}")
        t |> equal(fexist(preprocessed), !raw, "raw {raw}: {preprocessed}")
    }
}

[test(description = "a file opening with a byte order mark, lexed raw, gives clang's tokens and flags", timeout = 600)]
def test_bom_raw(t : T?) {
    var error : string
    let flags <- preprocess_flags(error)
    let r <- compare_unit("compare/pp/fixtures/bom_tokens.c", test_temp_dir(), flags, 5, true)
    t |> equal(r.error, "")
    t |> equal(r.clang_tokens, 5)
    t |> equal(r.diffs, 0, "{r.shown}")
}

// the file `name` under `work` holding `bytes`, its path
def private unit_of(work, name : string; bytes : array<uint8>) : string {
    let path = path_join(work, name)
    fopen(path, "wb") $(f) {
        fwrite(f, bytes)
    }
    return path
}

[test(description = "the lexer's choices that follow clang give clang's tokens raw: a lone CR, a CR splice, NUL, an empty character constant, a backslash at the end and invalid UTF-8", timeout = 600)]
def test_clang_choices_raw(t : T?) {
    var error : string
    let flags <- preprocess_flags(error)
    let work = path_join(test_temp_dir(), "pp_choices")
    mkdir_rec(work)
    let names = fixed_array("cr", "empty_char", "backslash_end", "utf8")
    let texts = fixed_array("a\rb\\\rc d\n", "'' x L''\n", "x \"ab\\",
                            "a \xed\xa0\x80 b \xe0\x80\x80 c \xf0\x80\x80\x80 d \xf4\x90\x80\x80 e\n")
    for (name, text in names, texts) {
        var inscope bytes <- [for (ch in text); uint8(ch)]
        let r <- compare_unit(unit_of(work, "{name}.c", bytes), work, flags, 5, true)
        t |> equal(r.error, "", name)
        t |> success(r.clang_tokens > 1, "{name}: {r.clang_tokens} tokens")
        t |> equal(r.diffs, 0, "{name}: {r.shown}")
    }
    let nul <- [uint8('a'), 0u8, uint8('b'), uint8('\n')]
    let r <- compare_unit(unit_of(work, "nul.c", nul), work, flags, 5, true)
    t |> equal("{r.error}{r.clang_tokens} {r.diffs}", "2 0", "{r.shown}")
}

[test(description = "a unit clang -E refuses is a clang failure, counted apart from the differences", timeout = 600)]
def test_clang_failure(t : T?) {
    var error : string
    let flags <- preprocess_flags(error)
    let r <- compare_unit("compare/pp/fixtures/no_such_unit.c", test_temp_dir(), flags, 5)
    t |> success(starts_with(r.error, "clang -E: "), r.error)
    let units <- ["compare/pp/fixtures/no_such_unit.c", "compare/pp/fixtures/bom_tokens.c"]
    let totals = run_set("missing", units, test_temp_dir(), flags, 5, true)
    t |> equal(totals, int3(5, 0, 1))
}

[test(description = "the corpora: every header of the own set, the fetched single-exec suite, and none for an unknown name")]
def test_corpus_units(t : T?) {
    let root = getcwd()
    let headers <- corpus_units(root, "frontend")
    t |> success(length(headers) > 10, "{length(headers)} headers")
    t |> equal(find_index_if(headers, $(u) => !ends_with(u, ".h")), -1)
    t |> success(find_index_if(headers, $(u) => ends_with(u, "/stdio.h")) >= 0)
    t |> equal(length(corpus_units(root, "no-such-corpus")), 0)
    let suite <- corpus_units(root, "c-testsuite")
    if (empty(suite)) {
        t |> skip("no c-testsuite fetch: suites/c_testsuite/fetch.sh")
        return
    }
    t |> success(length(suite) > 100, "{length(suite)} units")
    t |> equal(find_index_if(suite, $(u) => !ends_with(u, ".c")), -1)
}

[test(description = "the command line's run: units compared raw or after clang -E, the exit code 0 only when no unit differs", timeout = 600)]
def test_run_oracle(t : T?) {
    let work = path_join(test_temp_dir(), "pp_run")
    mkdir_rec(work)
    let unit = unit_of(work, "directive.c", [for (ch in "#define X 1\nint y = X;\n"); uint8(ch)])
    var preprocessed = OracleArgs(work = work)
    preprocessed.units |> push(unit)
    t |> equal(run_oracle(preprocessed), 0)
    var raw = OracleArgs(work = work, raw = true)
    raw.units |> push(unit)
    t |> equal(run_oracle(raw), 1)
}
