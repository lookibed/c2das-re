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
}

[test(description = "a clang kind maps to its PpTok: punctuators, every literal class, unknown, and identifiers and keywords alike")]
def test_clang_kind(t : T?) {
    t |> equal(clang_kind("hashhash"), int(PpTok.HASHHASH))
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

[test(description = "the edge-case unit gives clang's tokens through the pp lexer, lexed raw and after clang -E", timeout = 1200)]
def test_edge_unit_against_clang(t : T?) {
    var error : string
    let flags <- preprocess_flags(error)
    t |> equal(error, "")
    let unit = "compare/pp/fixtures/edge_tokens.c"
    let work = path_join(test_temp_dir(), "pp_oracle")
    mkdir_rec(work)
    for (raw in fixed_array(true, false)) {
        let r <- compare_unit(unit, work, flags, 5, raw)
        t |> equal(r.error, "", "raw {raw}")
        t |> success(r.clang_tokens > 80, "raw {raw}: {r.clang_tokens} tokens")
        t |> equal(r.diffs, 0, "raw {raw}: {r.shown}")
    }
}
