options gen2
options stack = 1048576
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../pp/pp_oracle.das
require ../../frontend/pp_lexer.das
require ../../frontend/pp_directives.das
require ../../converter/tiers.das
require ../../converter/dumper_a.das

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
    let none : array<ReferenceFailure>
    let totals = run_set("missing", units, test_temp_dir(), flags, none, 5, true)
    t |> equal(describe_totals("t", totals), "t: 5 tokens, 0 diffs, 0 reference failures (listed), 1 reference failures (unlisted), 0 listed units preprocessed")
}

[test(description = "the list of units the reference cannot preprocess: every line read with its reason, a unit matched by the end of its path")]
def test_reference_failures(t : T?) {
    let listed <- reference_failures(fread(REFERENCE_FAILURES))
    t |> equal(length(listed), 7)
    for (f in listed) {
        t |> success(starts_with(f.suffix, "gcc.c-torture/execute/") && ends_with(f.suffix, ".c"), f.suffix)
        t |> success(!empty(f.reason), f.suffix)
    }
    let one <- reference_failures("# a comment\n\nx/a.c\twhy\nno tab\n")
    t |> equal(length(one), 1)
    t |> equal(listed_reason(one, "/r/x/a.c"), "why")
    t |> equal(listed_reason(one, "x/a.c"), "why")
    t |> equal(listed_reason(one, "/r/xx/a.c"), "")
    t |> equal(listed_reason(one, "/r/x/a.cc"), "")
}

[test(description = "a set counts a listed reference failure apart from an unlisted one, and a listed unit the reference preprocessed as stale", timeout = 600)]
def test_listed_failures(t : T?) {
    var error : string
    let flags <- preprocess_flags(error)
    let listed <- reference_failures("pp/fixtures/no_such_listed.c\tby decision\npp/fixtures/bom_tokens.c\tnot really\n")
    let units <- ["compare/pp/fixtures/no_such_listed.c", "compare/pp/fixtures/no_such_unit.c", "compare/pp/fixtures/bom_tokens.c"]
    let totals = run_set("listed", units, test_temp_dir(), flags, listed, 5)
    t |> equal(describe_totals("t", totals), "t: 5 tokens, 0 diffs, 1 reference failures (listed), 1 reference failures (unlisted), 1 listed units preprocessed")
}

[test(description = "the corpora: every header of the own set, the fetched single-exec suite and gcc-torture's execute folder")]
def test_corpus_units(t : T?) {
    let root = getcwd()
    var error : string
    let headers <- corpus_units(root, "frontend", error)
    t |> equal(error, "")
    t |> success(length(headers) > 10, "{length(headers)} headers")
    t |> equal(find_index_if(headers, $(u) => !ends_with(u, ".h")), -1)
    t |> success(find_index_if(headers, $(u) => ends_with(u, "/stdio.h")) >= 0)
    for (corpus in fixed_array("c-testsuite", "gcc-torture")) {
        error = ""
        var inscope suite <- corpus_units(root, corpus, error)
        if (!empty(error)) {
            to_log(LOG_INFO, "{error}: its corpus is not checked\n")
            continue
        }
        t |> success(length(suite) > 100, "{corpus}: {length(suite)} units")
        t |> equal(find_index_if(suite, $(u) => !ends_with(u, ".c")), -1, corpus)
    }
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

[test(description = "the #pragma and #ident lines of clang's -E output are counted, a blank after the # included, and no other line")]
def test_pragma_lines(t : T?) {
    t |> equal(pragma_lines("int x;\n#pragma pack(1)\n  #  pragma weak w\n# 3 \"a.c\"\npragma;\n#ident \"v\"\nident;\n"), 3)
}

// clang-side tokens of `spellings`, a blank between them, each an identifier
def private clang_side(spellings : string) : array<OracleToken> =>
    <- [for (s in split(spellings, " ")); OracleToken(kind = int(PpTok.IDENTIFIER), spelling = s); where !empty(s)]

// PP.2-side tokens of `spellings`: a token ending in `!` names a macro PP.2 defined, one ending in
// `&` stands in a function-like macro's call, one ending in `?` stands in a group PP.4 chooses
def private pp_side(spellings : string) : array<Pp2Token> {
    var toks : array<Pp2Token>
    for (s in split(spellings, " ")) {
        continue if (empty(s))
        let marked = ends_with(s, "!") || ends_with(s, "&") || ends_with(s, "?")
        toks |> push(Pp2Token(tok = OracleToken(kind = int(PpTok.IDENTIFIER), spelling = marked ? slice(s, 0, length(s) - 1) : s),
                              macro = ends_with(s, "!"), in_call = ends_with(s, "&"), undecided = ends_with(s, "?")))
    }
    return <- toks
}

// the differences of the two sides, classed: `<class> c<at>+<count> p<at>+<count>` each
def private classed(clang_spellings, pp_spellings : string; pp3_at, pp4_at : array<int>; clang_macros : array<string>) : string {
    let clang <- clang_side(clang_spellings)
    let ours <- pp_side(pp_spellings)
    var r = Pp2Result()
    r.pp3_at := pp3_at
    r.pp4_at := pp4_at
    var gave_up = false
    r.differences <- pp2_differences(clang, ours, 100, gave_up)
    let macros <- {for (m in clang_macros); m => true}
    let parts <- [for (d in r.differences); "{pp2_difference_class(r, d, clang, ours, macros)} c{d.clang_at}+{d.clang_count} p{d.pp_at}+{d.pp_count}"]
    return join(parts, " | ")
}

[test(description = "the alignment reports every difference, not the first: a non-macro difference after a macro's is its own, a difference before every macro differs, an insertion is one run")]
def test_pp2_differences(t : T?) {
    let none <- array<int>()
    let no_macros <- array<string>()
    t |> equal(classed("a b c", "a b c", none, none, no_macros), "")
    t |> equal(classed("a 1 b x c", "a M! b y c", none, none, no_macros), "needs_pp3 c1+1 p1+1 | differs c3+1 p3+1")
    t |> equal(classed("x a 1", "y a M!", none, none, no_macros), "differs c0+1 p0+1 | needs_pp3 c2+1 p2+1")
    t |> equal(classed("a b c d", "a d", none, none, no_macros), "differs c1+2 p1+0")
    t |> equal(classed("a 1 2 3 b", "a F! ( x ) b", none, none, no_macros), "needs_pp3 c1+3 p1+4")
    var gave_up = false
    let far <- pp2_differences(clang_side("a b c d"), pp_side("w x y z"), 1, gave_up)
    t |> success(gave_up)
    t |> equal(length(far), 1)
    t |> equal("{far[0].clang_at}+{far[0].clang_count} {far[0].pp_at}+{far[0].pp_count}", "0+4 0+4")
}

[test(description = "the directive oracle's tokens are the same by kind, spelling and at_bol alone; line, column and space do not count")]
def test_same_pp2_token(t : T?) {
    let a = OracleToken(kind = 1, spelling = "a", at_bol = true)
    t |> success(same_pp2_token(a, OracleToken(kind = 1, spelling = "a", at_bol = true, line = 9, col = 9, has_space = true)))
    t |> success(!same_pp2_token(a, OracleToken(kind = 2, spelling = "a", at_bol = true)))
    t |> success(!same_pp2_token(a, OracleToken(kind = 1, spelling = "b", at_bol = true)))
    t |> success(!same_pp2_token(a, OracleToken(kind = 1, spelling = "a")))
}

[test(description = "a difference needs PP.4 at a place left to PP.4, where an insertion may slide, in a group PP.4 chooses, or naming clang's macro PP.2 lacks past such a place; PP.3 for PP.2's macro or a place left to PP.3; else it differs")]
def test_pp2_difference_class(t : T?) {
    let none <- array<int>()
    let no_macros <- array<string>()
    t |> equal(classed("a b c", "a c", none, [1], no_macros), "needs_pp4 c1+1 p1+0")
    t |> equal(classed("a b c", "a c", none, [2], no_macros), "differs c1+1 p1+0")
    t |> success(starts_with(classed("int a ; int b ;", "int b ;", none, [0], no_macros), "needs_pp4 "))
    t |> success(starts_with(classed("int a ; int a ;", "int a ;", none, [3], no_macros), "needs_pp4 "))
    t |> success(starts_with(classed("int a ;", "int a ; int a ;", none, [0], no_macros), "needs_pp4 "))
    t |> equal(classed("a x b", "a y? b", none, none, no_macros), "needs_pp4 c1+1 p1+1")
    t |> equal(classed("a 1 b", "a N b", none, [0], ["N"]), "needs_pp4 c1+1 p1+1")
    t |> equal(classed("a 1 b", "a N b", none, none, ["N"]), "differs c1+1 p1+1")
    t |> equal(classed("a 1 b", "a N b", none, [3], ["N"]), "differs c1+1 p1+1")
    t |> equal(classed("a h1 h2 b", "a b", [1], none, no_macros), "needs_pp3 c1+2 p1+0")
    t |> equal(classed("a x b", "a y b", none, none, ["x"]), "differs c1+1 p1+1")
    t |> equal(classed("a 7 b", "a __LINE__ b", none, none, no_macros), "needs_pp3 c1+1 p1+1")
    t |> equal(classed("s a + b ;", "s F! (& a& ,& b& )& ;", none, none, no_macros), "needs_pp3 c1+0 p1+2 | needs_pp3 c2+1 p4+1 | needs_pp3 c4+0 p6+1")
    t |> equal(classed("s 2 * f ;", "s f! (& 2& )& ;", none, none, no_macros), "needs_pp3 c1+2 p1+0 | needs_pp3 c4+0 p2+3")
    t |> equal(classed("s a + b ; x", "s F! (& a& ,& b& )& ; y", none, none, no_macros), "needs_pp3 c1+0 p1+2 | needs_pp3 c2+1 p4+1 | needs_pp3 c4+0 p6+1 | differs c5+1 p8+1")
}

// a result whose differences are of `classes`
def private with_classes(classes : array<Pp2Class>) : Pp2Result {
    var r = Pp2Result()
    r.differences |> reserve(length(classes))
    for (cls in classes) {
        r.differences |> push(Pp2Difference(cls = cls))
    }
    return <- r
}

[test(description = "a unit's class is the latest its differences and places left over wait for; an error of PP.2's own, a difference that differs, or a pragma count no later item explains makes it differ")]
def test_pp2_class(t : T?) {
    t |> equal(pp2_class(with_classes(array<Pp2Class>())), Pp2Class.clean)
    t |> equal(pp2_class(with_classes([Pp2Class.needs_pp3, Pp2Class.needs_pp3])), Pp2Class.needs_pp3)
    t |> equal(pp2_class(with_classes([Pp2Class.needs_pp3, Pp2Class.differs, Pp2Class.needs_pp4])), Pp2Class.differs)
    t |> equal(pp2_class(with_classes([Pp2Class.needs_pp4, Pp2Class.needs_pp3])), Pp2Class.needs_pp4)
    var pp3 <- with_classes(array<Pp2Class>())
    pp3.pp3_at |> push(0)
    t |> equal(pp2_class(pp3), Pp2Class.needs_pp3)
    var pp4 <- with_classes([Pp2Class.needs_pp3])
    pp4.pp4_at |> push(0)
    t |> equal(pp2_class(pp4), Pp2Class.needs_pp4)
    var late <- with_classes(array<Pp2Class>())
    late.late_errors = 1
    t |> equal(pp2_class(late), Pp2Class.needs_pp4)
    var own <- with_classes(array<Pp2Class>())
    own.errors |> push("1:2 invalid preprocessing directive")
    t |> equal(pp2_class(own), Pp2Class.differs)
    var pragmas <- with_classes(array<Pp2Class>())
    pragmas.clang_pragmas = 1
    t |> equal(pp2_class(pragmas), Pp2Class.differs)
    pragmas.pp4_at |> push(0)
    t |> equal(pp2_class(pragmas), Pp2Class.needs_pp4)
    var expanded <- with_classes([Pp2Class.needs_pp3])
    expanded.clang_pragmas = 2
    expanded.pp_pragmas = 1
    t |> equal(pp2_class(expanded), Pp2Class.needs_pp3)
    expanded.pp_pragmas = 3
    t |> equal(pp2_class(expanded), Pp2Class.differs)
}

// `text` written to `name` under the test's temporary folder; its path
def private unit_file(name, text : string) : string {
    let dir = path_join(test_temp_dir(), "pp2_units")
    mkdir_rec(dir)
    return unit_of(dir, name, [for (ch in text); uint8(ch)])
}

[test(description = "PP.2's side of a unit marks its macro names and its tokens in groups PP.4 chooses, places what it left to PP.3 and PP.4, counts its pragma and pack entries, and keeps only its own errors")]
def test_pp2_tokens_bookkeeping(t : T?) {
    var error : string
    let setup <- pp2_setup(error)
    t |> equal(error, "")
    let unit = unit_file("mixed.c", "#define M 1\n#define F(x) x\nint a;\nM;\nF((a), b) F c;\n#if X > 1\nint b;\n#else\nint e;\n#error inside\n#endif\nint c;\n#include NAME\n#pragma pack(1)\n#pragma weak w\n#warning w\n#bogus\n")
    var r = Pp2Result(unit = unit)
    let toks <- pp2_tokens(unit, setup.entries, setup.search, r)
    t |> equal(join([for (o in toks); "{o.tok.spelling}{o.macro ? "!" : ""}{o.in_call ? "&" : ""}{o.undecided ? "?" : ""}"], " "),
               "int a ; M! ; F! (& (& a& )& ,& b& )& F! c ; int? e? ;? int c ;")
    t |> equal(r.pp4_at |> length, 1)
    t |> equal(r.pp4_at[0], 16)
    t |> equal(r.pp3_at |> length, 1)
    t |> equal(r.pp3_at[0], 22)
    t |> equal(r.pp_pragmas, 2)
    t |> equal(r.late_errors, 1)
    t |> equal(join(r.errors, " | "), "17:2 invalid preprocessing directive")
    let tail = unit_file("tail.c", "int z;\n#if X > 1\n#endif\n")
    var rt = Pp2Result(unit = tail)
    let tail_toks <- pp2_tokens(tail, setup.entries, setup.search, rt)
    t |> equal(length(tail_toks), 3)
    t |> equal(rt.pp4_at[0], 3)
    var rm = Pp2Result()
    let none <- pp2_tokens("compare/pp/fixtures/pp2/no_such_unit.c", setup.entries, setup.search, rm)
    t |> equal(length(none), 0)
    t |> equal(join(rm.errors, " | "), "cannot read compare/pp/fixtures/pp2/no_such_unit.c")
}

[test(description = "a corpus that is unknown or whose folder is missing, a suite not fetched among them, is an error, never an empty corpus")]
def test_corpus_units_errors(t : T?) {
    var error : string
    let root = path_join(test_temp_dir(), "empty_root")
    mkdir_rec(root)
    let suite <- corpus_units(root, "c-testsuite", error)
    t |> equal(length(suite), 0)
    t |> success(find(error, "corpus c-testsuite: ") >= 0 && find(error, "suites/c_testsuite/fetch.sh") >= 0, error)
    error = ""
    let torture <- corpus_units(root, "gcc-torture", error)
    t |> equal(length(torture), 0)
    t |> success(find(error, "corpus gcc-torture: ") >= 0 && find(error, "suites/gcc_torture/fetch.sh") >= 0, error)
    error = ""
    let own <- corpus_units(root, "frontend", error)
    t |> equal(length(own), 0)
    t |> success(starts_with(error, "corpus frontend: ") && ends_with(error, " is missing"), error)
    error = ""
    let unknown <- corpus_units(getcwd(), "nosuch", error)
    t |> equal(error, "unknown corpus 'nosuch': frontend, c-testsuite, gcc-torture, pp2 or pp3")
    error = ""
    let fixtures <- corpus_units(getcwd(), "pp2", error)
    t |> equal(error, "")
    t |> equal(length(fixtures), 5)
}

[test(description = "the directive fixtures give clang's -E token stream through PP.2: guards, pragma once, #line, nested #if 0, pragmas, #import and #ident", timeout = 1200)]
def test_pp2_fixtures_against_clang(t : T?) {
    var error : string
    let flags <- preprocess_flags(error)
    t |> equal(error, "")
    let setup <- pp2_setup(error)
    t |> equal(error, "")
    let work = path_join(test_temp_dir(), "pp2_oracle")
    mkdir_rec(work)
    let units <- corpus_units(getcwd(), "pp2", error)
    t |> equal(error, "")
    for (unit in units) {
        let r <- compare_unit_pp2(unit, work, flags, setup.entries, setup.search, 5)
        t |> equal(r.error, "", unit)
        t |> equal(r.cls, Pp2Class.clean, "{unit}: {r.shown} {r.errors}")
        t |> equal(length(r.differences), 0, unit)
        t |> success(r.clang_tokens > 2, unit)
    }
}

[test(description = "the directive oracle's set run counts each class, and each reference failure listed or unlisted as the lexer's run does", timeout = 1200)]
def test_run_set_pp2_counts(t : T?) {
    var error : string
    let flags <- preprocess_flags(error)
    t |> equal(error, "")
    let setup <- pp2_setup(error)
    t |> equal(error, "")
    let work = path_join(test_temp_dir(), "pp2_set")
    mkdir_rec(work)
    var units <- corpus_units(getcwd(), "pp2", error)
    units |> push(unit_file("pp3.c", "#define M 1\nint x = M;\n"))
    units |> push(unit_file("pp4.c", "#if 2 > 1\nint x;\n#endif\n"))
    units |> push(unit_file("differs.c", "#pragma pack(3)\nint x;\n"))
    units |> push(unit_file("rejected.c", "#bogus\nint x;\n"))
    units |> push("compare/pp/fixtures/pp2/no_such_unit.c")
    let listed <- reference_failures("pp2_units/rejected.c\tby decision\n")
    let totals = run_set_pp2("t", oracle_units(units), work, flags, listed, setup.entries, setup.search, 0)
    t |> equal("{totals.units}", "5,1,1,1")
    t |> equal("{totals.oracle.listed} {totals.oracle.unlisted} {totals.oracle.stale}", "1 1 0")
}

[test(description = "run.das --pp2 runs the directive oracle: exit 0 over the clean fixture set and past a listed reference failure, 1 past an unlisted one, when a unit differs or a corpus is unknown", timeout = 1200)]
def test_run_pp2_command_line(t : T?) {
    let work = path_join(test_temp_dir(), "pp2_cli")
    var argv <- daslang_cmd(["dasCRuntime", "c_runtime", "fetch/dasFlex"])
    argv |> push_from(["compare/pp/run.das", "--", "--pp2", "--corpus", "pp2", "--work", work])
    var out : string
    let clean_rc = run_and_capture(argv, out, 600.0)
    t |> equal(clean_rc, 0, out)
    t |> success(find(out, "total (pp2): 5 clean, 0 need PP.3, 0 need PP.4, 0 differ, 0 reference failures (listed), 0 reference failures (unlisted), 0 listed units preprocessed") >= 0, out)
    var missing := argv
    missing |> push("compare/pp/fixtures/pp2/no_such_unit.c")
    let missing_rc = run_and_capture(missing, out, 600.0)
    t |> equal(missing_rc, 1, out)
    t |> success(find(out, "0 differ, 0 reference failures (listed), 1 reference failures (unlisted)") >= 0, out)
    let torture = path_join(test_temp_dir(), "pp2_listed/gcc.c-torture/execute")
    mkdir_rec(torture)
    let listed_unit = path_join(torture, "loop-2f.c")
    fwrite(listed_unit, "#include <sys/mman.h>\nint x;\n")
    var listed := argv
    listed |> push(listed_unit)
    let listed_rc = run_and_capture(listed, out, 600.0)
    t |> equal(listed_rc, 0, out)
    t |> success(find(out, "0 differ, 1 reference failures (listed), 0 reference failures (unlisted)") >= 0, out)
    var differs := argv
    differs |> push(unit_file("cli_differs.c", "#pragma pack(3)\nint x;\n"))
    let differs_rc = run_and_capture(differs, out, 600.0)
    t |> equal(differs_rc, 1, out)
    var unknown := argv
    unknown |> push_from(["--corpus", "nosuch"])
    let unknown_rc = run_and_capture(unknown, out, 600.0)
    t |> equal(unknown_rc, 1, out)
    t |> success(find(out, "unknown corpus 'nosuch'") >= 0, out)
}

[test(description = "through a symbolic link to a folder, `..` leads where the file system says, so PP.2 over fio reads the file clang reads", timeout = 1200)]
def test_pp2_symlinked_folder(t : T?) {
    let root = get_full_file_name(path_join(test_temp_dir(), "pp2_link"))
    mkdir_rec(path_join(root, "real/deep"))
    mkdir_rec(path_join(root, "inc"))
    let files <- [("real/deep/x.h", "#pragma once\n#include \"../y.h\"\n"), ("real/y.h", "int real_y;\n"), ("inc/y.h", "int inc_y;\n"),
                  ("main.c", "#include <l/x.h>\n#include \"real/deep/x.h\"\nint end_of_main;\n")]
    for (f in files) {
        fopen(path_join(root, f._0), "wb") $(h) {
            fwrite(h, f._1)
        }
    }
    let link = path_join(root, "inc/l")
    if (!stat(link).is_dir) {
        var out : string
        let ln_rc = run_and_capture(["ln", "-s", path_join(root, "real/deep"), link], out, 60.0)
        t |> equal(ln_rc, 0, out)
    }
    let main = path_join(root, "main.c")
    var pp : Preprocessor
    t |> success(pp_start(pp, new PpFioProvider(), main, array<string>(), [path_join(root, "inc")]))
    var ours : array<string>
    while (pp_next_token(pp)) {
        ours |> push(pp_token_spelling(pp))
    }
    t |> equal(join(ours, " "), "int real_y ; int end_of_main ;")
    var clang_out : string
    let clang_rc = run_and_capture([default_clang(), "-E", "-P", "-nostdinc", "-I", path_join(root, "inc"), main], clang_out, 300.0)
    t |> equal(clang_rc, 0, clang_out)
    t |> success(find(clang_out, "real_y") >= 0 && find(clang_out, "inc_y") < 0, clang_out)
}

[test(description = "a corpus list reads a unit a line, its path then its flags; blank lines are skipped")]
def test_list_units(t : T?) {
    let list = path_join(test_temp_dir(), "corpus.txt")
    fwrite(list, "/a/x.c -I/a -DN=1\n\n/b/y.t -x c\n")
    let units <- list_units(list)
    t |> equal(length(units), 2)
    t |> equal("{units[0].path} {join(units[0].flags, " ")}", "/a/x.c -I/a -DN=1")
    t |> equal("{units[1].path} {join(units[1].flags, " ")}", "/b/y.t -x c")
}

[test(description = "a unit's own flags reach both sides: -I before the include path, -D after the table, -x to clang; any other flag fails the unit", timeout = 1200)]
def test_pp3_unit_flags(t : T?) {
    var error : string
    let flags <- preprocess_flags(error)
    t |> equal(error, "")
    let setup <- pp2_setup(error)
    t |> equal(error, "")
    let work = path_join(test_temp_dir(), "pp3_flags")
    mkdir_rec(work)
    let inc = path_join(test_temp_dir(), "pp3_inc")
    mkdir_rec(inc)
    fwrite(path_join(inc, "own_header.h"), "int from_header = N;\n")
    let unit = unit_file("flags.c", "#include <own_header.h>\nint x = N + 1;\n")
    let r <- compare_unit_pp2(unit, work, flags, setup.entries, setup.search, 5, true, ["-I{inc}", "-DN=7", "-x", "c"])
    t |> equal(r.error, "")
    t |> equal(r.cls, Pp2Class.clean, "{r.shown} {r.errors}")
    t |> equal(r.clang_tokens, 12)
    let bad <- compare_unit_pp2(unit, work, flags, setup.entries, setup.search, 5, true, ["-O2"])
    t |> equal(bad.error, "unsupported unit flag -O2")
}

[test(description = "the expansion fixtures give clang's -E token stream through PP.3, each pragma at clang's place: the C11 examples, rescanning, GNU variadics, # and ##, the builtins, directive lines, _Pragma in arguments and the edges clang settles", timeout = 1200)]
def test_pp3_fixtures_against_clang(t : T?) {
    var error : string
    let flags <- preprocess_flags(error)
    t |> equal(error, "")
    let setup <- pp2_setup(error)
    t |> equal(error, "")
    let work = path_join(test_temp_dir(), "pp3_oracle")
    mkdir_rec(work)
    let units <- corpus_units(getcwd(), "pp3", error)
    t |> equal(error, "")
    t |> equal(length(units), 7)
    for (unit in units) {
        let r <- compare_unit_pp2(unit, work, flags, setup.entries, setup.search, 5, true)
        t |> equal(r.error, "", unit)
        t |> equal(r.cls, Pp2Class.clean, "{unit}: {r.shown} {r.errors}")
        t |> success(r.clang_tokens > 10, unit)
    }
}

[test(description = "in PP.3's expanded stream no difference waits for PP.3: a name left as it is differs, where PP.2's stream would need PP.3")]
def test_pp3_no_needs_pp3(t : T?) {
    let clang <- [OracleToken(kind = int(PpTok.IDENTIFIER), spelling = "one"), OracleToken(kind = int(PpTok.SEMI), spelling = ";")]
    let ours <- [Pp2Token(tok = OracleToken(kind = int(PpTok.IDENTIFIER), spelling = "__LINE__")), Pp2Token(tok = OracleToken(kind = int(PpTok.SEMI), spelling = ";"))]
    let none : table<string; bool>
    let d = Pp2Difference(clang_at = 0, clang_count = 1, pp_at = 0, pp_count = 1)
    t |> equal(pp2_difference_class(Pp2Result(), d, clang, ours, none), Pp2Class.needs_pp3)
    t |> equal(pp2_difference_class(Pp2Result(expanded = true), d, clang, ours, none), Pp2Class.differs)
}

[test(description = "run_oracle --pp3 runs the expansion oracle: exit 0 over the fixture set; a corpus list that is missing, or an unlisted reference failure, is exit 1", timeout = 1200)]
def test_run_oracle_pp3(t : T?) {
    let work = path_join(test_temp_dir(), "pp3_run")
    var fixtures = OracleArgs(work = work, pp3 = true)
    fixtures.corpus |> push("pp3")
    t |> equal(run_oracle(fixtures), 0)
    var missing = OracleArgs(work = work, pp3 = true)
    missing.list |> push(path_join(test_temp_dir(), "no_such_list.txt"))
    t |> equal(run_oracle(missing), 1)
    var unlisted = OracleArgs(work = work, pp3 = true)
    unlisted.units |> push("compare/pp/fixtures/pp2/no_such_unit.c")
    t |> equal(run_oracle(unlisted), 1)
}

[test(description = "in PP.3's stream a token from a macro defined in a group PP.4 chooses is marked, through the call its name came from; a macro defined before is not")]
def test_pp3_late_macro(t : T?) {
    var error : string
    let setup <- pp2_setup(error)
    t |> equal(error, "")
    let unit = unit_file("late.c", "#define U int\nU a;\n#if 2 > 1\n#define T long\n#else\n#define T short\n#endif\n#define W T\nT x; W y; U z;\n")
    var r = Pp2Result(unit = unit, expanded = true)
    let toks <- pp2_tokens(unit, setup.entries, setup.search, r)
    t |> equal(join([for (o in toks); "{o.tok.spelling}{o.late_macro ? "!" : ""}"], " "), "int a ; short! x ; short! y ; int z ;")
    let clang <- [OracleToken(kind = int(PpTok.IDENTIFIER), spelling = "long")]
    let none : table<string; bool>
    let d = Pp2Difference(clang_at = 0, clang_count = 1, pp_at = 6, pp_count = 1)
    t |> equal(pp2_difference_class(r, d, clang, toks, none), Pp2Class.needs_pp4)
    let early = Pp2Difference(clang_at = 0, clang_count = 1, pp_at = 0, pp_count = 1)
    t |> equal(pp2_difference_class(r, early, clang, toks, none), Pp2Class.differs)
}

[test(description = "in PP.3's stream a token of a macro defined outside every group PP.4 chooses is not late, though the read that defined it met such a group; it is late when the call naming it came from a macro defined in one")]
def test_pp3_late_macro_through_parent(t : T?) {
    var error : string
    let setup <- pp2_setup(error)
    t |> equal(error, "")
    let unit = unit_file("late_parent.c", "#define U int\n#if 2 > 1\n#define T U\n#else\n#define T U\n#endif\nU a;\nT x;\n")
    var r = Pp2Result(unit = unit, expanded = true)
    let toks <- pp2_tokens(unit, setup.entries, setup.search, r)
    t |> equal(join([for (o in toks); "{o.tok.spelling}{o.late_macro ? "!" : ""}"], " "), "int a ; int! x ;")
}

[test(description = "in PP.3's stream no token is marked a macro name, a painted name of a defined macro included")]
def test_pp3_no_macro_marks(t : T?) {
    var error : string
    let setup <- pp2_setup(error)
    t |> equal(error, "")
    let unit = unit_file("painted.c", "#define AA BB\n#define BB AA\nAA ;\n")
    var r = Pp2Result(unit = unit, expanded = true)
    let toks <- pp2_tokens(unit, setup.entries, setup.search, r)
    t |> equal(join([for (o in toks); "{o.tok.spelling}{o.macro ? "?" : ""}"], " "), "AA ;")
}

[test(description = "a unit's -I is searched before the include path, on PP.3's side as clang searches it: a header of the same name there wins", timeout = 1200)]
def test_pp3_unit_include_first(t : T?) {
    var error : string
    let flags <- preprocess_flags(error)
    t |> equal(error, "")
    let setup <- pp2_setup(error)
    t |> equal(error, "")
    let work = path_join(test_temp_dir(), "pp3_order")
    mkdir_rec(work)
    let inc = path_join(test_temp_dir(), "pp3_shadow")
    mkdir_rec(inc)
    fwrite(path_join(inc, "stddef.h"), "int from_shadow;\n")
    let unit = unit_file("order.c", "#include <stddef.h>\nint x;\n")
    let r <- compare_unit_pp2(unit, work, flags, setup.entries, setup.search, 5, true, ["-I{inc}"])
    t |> equal(r.error, "")
    t |> equal(r.cls, Pp2Class.clean, "{r.shown} {r.errors}")
    t |> equal(r.clang_tokens, 6)
}

[test(description = "run.das --pp3 runs a corpus list and units through PP.3: each set's line and the total are headed pp3, and a listed fixture is clean", timeout = 1200)]
def test_run_pp3_command_line(t : T?) {
    let work = path_join(test_temp_dir(), "pp3_cli")
    let list = path_join(test_temp_dir(), "pp3_list.txt")
    fwrite(list, "compare/pp/fixtures/pp3/gnu.c\n")
    var argv <- daslang_cmd(["dasCRuntime", "c_runtime", "fetch/dasFlex"])
    argv |> push_from(["compare/pp/run.das", "--", "--pp3", "--list", list, "--work", work, "compare/pp/fixtures/pp3/rescan.c"])
    var out : string
    let rc = run_and_capture(argv, out, 600.0)
    t |> equal(rc, 0, out)
    t |> success(find(out, "pp3_list.txt (pp3): 1 units, 1 clean,") >= 0, out)
    t |> success(find(out, "units (pp3): 1 units, 1 clean,") >= 0, out)
    t |> success(find(out, "total (pp3): 2 clean,") >= 0, out)
}

[test(description = "an error outside every group PP.4 chooses is PP.2's own though its read met such a group; one met in such a group, or in PP.3's stream expanding a macro defined in one, is late")]
def test_late_errors(t : T?) {
    var error : string
    let setup <- pp2_setup(error)
    t |> equal(error, "")
    let own = unit_file("late_own.c", "#if 2 > 1\n#endif\n#error boom\nx\n")
    var r = Pp2Result(unit = own)
    pp2_tokens(own, setup.entries, setup.search, r)
    t |> equal(join(r.errors, " | "), "3:2 #error boom")
    t |> equal(r.late_errors, 0)
    let late = unit_file("late_paste.c", "#if 2 > 1\n#define C(a,b) a##b\n#else\n#define C(a,b) a##b\n#error in\n#endif\nC(+,/) x\n")
    var rl = Pp2Result(unit = late, expanded = true)
    pp2_tokens(late, setup.entries, setup.search, rl)
    t |> equal(join(rl.errors, " | "), "")
    t |> equal(rl.late_errors, 2)
}

[test(description = "the place of a #pragma or #ident line of clang's output is the count of its tokens on the lines before it")]
def test_pragma_places(t : T?) {
    let clang <- [for (line in [1, 1, 3, 5]); OracleToken(kind = int(PpTok.IDENTIFIER), spelling = "a", line = line)]
    t |> equal(join([for (p in pragma_places("a a\n#pragma x\na\n#ident \"v\"\na\n#pragma y\n", clang)); "{p}"], " "), "2 3 4")
}

[test(description = "a unit whose streams are equal differs when a pragma stands at another place than clang's, though the counts agree")]
def test_pragma_place_class(t : T?) {
    var r <- with_classes(array<Pp2Class>())
    r.clang_pragmas = 2
    r.pp_pragmas = 2
    r.clang_pragma_at <- [0, 11]
    r.pp_pragma_at <- [0, 11]
    t |> equal(pp2_class(r), Pp2Class.clean)
    r.pp_pragma_at <- [0, 7]
    t |> equal(pp2_class(r), Pp2Class.differs)
    var moved <- with_classes([Pp2Class.needs_pp4])
    moved.clang_pragmas = 1
    moved.pp_pragmas = 1
    moved.clang_pragma_at <- [3]
    moved.pp_pragma_at <- [5]
    t |> equal(pp2_class(moved), Pp2Class.needs_pp4)
}
