options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require ../c_tokens.das

//! `frontend/c_tokens.das`: the C tokens of a preprocessed unit over the pp-lexer, keywords by
//! their interned symbol, pp-numbers classified, line markers placing the tokens after them.

// the class letter of a C token kind: I identifier, K keyword, N integer, F floating, C character
// constant, S string literal, P punctuator
def private class_of(kind : int) : string {
    if (kind == int(CTok.IDENTIFIER)) {
        return "I"
    } elif (kind >= int(CTok.VOID)) {
        return "K"
    } elif (kind == int(CTok.INT_CONSTANT)) {
        return "N"
    } elif (kind == int(CTok.FLOAT_CONSTANT)) {
        return "F"
    } elif (kind == int(CTok.CHAR_CONSTANT)) {
        return "C"
    } elif (kind == int(CTok.STRING_LITERAL)) {
        return "S"
    }
    return "P"
}

// the tokens of `text`, each `<class>:<spelling>`, or `error: <message>`
def private lexed(text : string) : string {
    var unit : CUnit
    if (!c_tokens_of_text(unit, text, "t.c")) {
        return "error: {unit.err}"
    }
    let parts <- [for (t in range(length(unit.toks) - 1)); "{class_of(unit.toks[t].kind)}:{c_spelling(unit, t)}"]
    return join(parts, " ")
}

// every token of `text` placed, `<spelling>@<file>:<line>:<col>`, the end of input last
def private placed(text : string) : string {
    var unit : CUnit
    if (!c_tokens_of_text(unit, text, "t.c")) {
        return "error: {unit.err}"
    }
    var parts : array<string>
    parts |> reserve(length(unit.toks))
    for (t in range(length(unit.toks))) {
        let spelling = unit.toks[t].kind == int(CTok.EOF) ? "$" : c_spelling(unit, t)
        parts |> push("{spelling}@{c_where(unit, t)}")
    }
    return join(parts, " ")
}

// the kind of the one token of `text`
def private kind_of(text : string) : int {
    var unit : CUnit
    c_tokens_of_text(unit, text, "t.c")
    return length(unit.toks) == 2 ? unit.toks[0].kind : -1
}

[test(description = "an identifier is a keyword by its interned symbol: every C99, C11 and GNU spelling has its kind, any other name stays an identifier")]
def test_keywords(t : T?) {
    t |> run("the C99 keywords") @(t : T?) {
        t |> equal(lexed("auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while _Bool _Complex _Imaginary"),
                   "K:auto K:break K:case K:char K:const K:continue K:default K:do K:double K:else K:enum K:extern K:float K:for K:goto K:if K:inline K:int K:long K:register K:restrict K:return K:short K:signed K:sizeof K:static K:struct K:switch K:typedef K:union K:unsigned K:void K:volatile K:while K:_Bool K:_Complex K:_Imaginary")
    }
    t |> run("the C11 keywords") @(t : T?) {
        t |> equal(lexed("_Alignas _Alignof _Atomic _Generic _Noreturn _Static_assert _Thread_local"),
                   "K:_Alignas K:_Alignof K:_Atomic K:_Generic K:_Noreturn K:_Static_assert K:_Thread_local")
    }
    t |> run("every spelling of the table lexes to its kind; a GNU alternate to its standard keyword's") @(t : T?) {
        for (kw in KEYWORDS) {
            t |> equal(kind_of(kw._0), int(kw._1), kw._0)
        }
        t |> equal(kind_of("__const__"), int(CTok.CONST))
        t |> equal(kind_of("__inline__"), int(CTok.INLINE))
        t |> equal(kind_of("__attribute"), int(CTok.ATTRIBUTE))
        t |> equal(kind_of("asm"), int(CTok.ASM))
        t |> equal(kind_of("typeof"), int(CTok.TYPEOF))
        t |> equal(kind_of("__PRETTY_FUNCTION__"), int(CTok.FUNC_NAME))
    }
    t |> run("a name near a keyword, a C23 or C++ keyword and a builtin function are identifiers") @(t : T?) {
        t |> equal(lexed("Int __attribute__x _bool bool true nullptr __builtin_expect __builtin_choose_expr typeof_ $int"),
                   "I:Int I:__attribute__x I:_bool I:bool I:true I:nullptr I:__builtin_expect I:__builtin_choose_expr I:typeof_ I:$int")
    }
    t |> run("a name interned before the unit opened keeps its symbol and is a keyword or not by its spelling") @(t : T?) {
        var unit : CUnit
        c_tokens_of_text(unit, "x int", "a.c")
        let x = unit.toks[0].sym
        c_tokens_of_text(unit, "int x", "b.c")
        t |> equal(unit.toks[0].kind, int(CTok.INT))
        t |> equal(unit.toks[1].kind, int(CTok.IDENTIFIER))
        t |> equal(unit.toks[1].sym, x)
    }
}

[test(description = "a universal character name naming a basic character, a surrogate or a code point past U+10FFFF makes its identifier an error (C11 6.4.3p2), so no keyword is spelled through one; `$`, `@`, a backquote and any other UCN stay")]
def test_ucn_identifiers(t : T?) {
    t |> equal(lexed("\\u0069nt x"), "error: t.c:1:1: invalid universal character name in '\\u0069nt'")
    t |> equal(lexed("x \\U00000041"), "error: t.c:1:3: invalid universal character name in '\\U00000041'")
    t |> equal(lexed("\\ud800"), "error: t.c:1:1: invalid universal character name in '\\ud800'")
    t |> equal(lexed("\\U00110000"), "error: t.c:1:1: invalid universal character name in '\\U00110000'")
    t |> equal(lexed("\\u0080"), "error: t.c:1:1: invalid universal character name in '\\u0080'")
    t |> equal(lexed("\\udfff"), "error: t.c:1:1: invalid universal character name in '\\udfff'")
    t |> equal(lexed("\\U0010FFFF"), "I:\\U0010FFFF")
    t |> equal(lexed("\\u0024y \\u0040 \\u0060 a\\u00e9 \\U0001F600"), "I:\\u0024y I:\\u0040 I:\\u0060 I:a\\u00e9 I:\\U0001F600")
    t |> equal(lexed("x\\u00e9 x\\u00e9 \\u0069nt"), "error: t.c:1:17: invalid universal character name in '\\u0069nt'")
}

[test(description = "a pp-number is an integer or a floating constant by C11 6.4.4, its suffix checked; one that is neither is an error naming it")]
def test_numbers(t : T?) {
    t |> run("integer constants: decimal, octal, hexadecimal, GNU binary, every suffix") @(t : T?) {
        t |> equal(lexed("0 42 017 0x1F 0X1f 0b101 0B1 42u 42U 42l 42L 42ul 42Lu 42ll 42LL 42ull 42LLU 42llu 0x1fULL 07lu"),
                   "N:0 N:42 N:017 N:0x1F N:0X1f N:0b101 N:0B1 N:42u N:42U N:42l N:42L N:42ul N:42Lu N:42ll N:42LL N:42ull N:42LLU N:42llu N:0x1fULL N:07lu")
    }
    t |> run("floating constants: decimal and hexadecimal, every suffix") @(t : T?) {
        t |> equal(lexed("1.0 .5 1. 1e10 1E-3 1.5f 1.5F 1.5l 2e+3L 09.5 0x1p3 0x1.8p-2 0x.8P1f 0X1P+4L 1.e5"),
                   "F:1.0 F:.5 F:1. F:1e10 F:1E-3 F:1.5f F:1.5F F:1.5l F:2e+3L F:09.5 F:0x1p3 F:0x1.8p-2 F:0x.8P1f F:0X1P+4L F:1.e5")
    }
    t |> run("a pp-number that is no constant is an error at its place") @(t : T?) {
        let bad = fixed_array("09", "0b2", "0x", "0xg", "1lL", "1uu", "1lul", "1lll", "1.5ff", "1.5u", "0x1.8", "1e", "1e+", "0x1p", "1i", "12abc", "1..2", "0b", ".5e3x", "0xp1", "0x.p1", "0b12", "0b1z", "08")
        for (text in bad) {
            t |> equal(lexed("x {text}"), "error: t.c:1:3: invalid numeric constant '{text}'", text)
        }
    }
}

[test(description = "character constants and string literals keep their prefixes, and adjacent string literals stay separate tokens for the parser to join")]
def test_literals(t : T?) {
    t |> equal(lexed("'a' L'b' u'c' U'd' '\\n' \"s\" u8\"s\" L\"s\" \"a\" \"b\""),
               "C:'a' C:L'b' C:u'c' C:U'd' C:'\\n' S:\"s\" S:u8\"s\" S:L\"s\" S:\"a\" S:\"b\"")
}

[test(description = "every C punctuator keeps the pp-lexer's kind, a digraph the kind of what it spells, `::` is two colons; `#`, `##` and any other character are stray errors")]
def test_punctuators(t : T?) {
    t |> run("every punctuator of 6.4.6 but `#` and `##`") @(t : T?) {
        let puncts = "[ ] ( ) \{ \} . -> ++ -- & * + - ~ ! / % << >> < > <= >= == != ^ | && || ? : ; ... = *= /= %= += -= <<= >>= &= ^= |= ,"
        let expected <- [for (p in split(puncts, " ")); "P:{p}"]
        t |> equal(lexed(puncts), join(expected, " "))
    }
    t |> run("a punctuator's kind names it in a message") @(t : T?) {
        t |> equal(kind_of("<<="), int(CTok.SHL_ASSIGN))
        t |> equal(c_kind_name(int(CTok.SHL_ASSIGN)), "<<=")
        t |> equal(c_kind_name(int(CTok.LBRACE)), "\{")
        t |> equal(c_kind_name(int(CTok.GNU_ALIGNOF)), "__alignof__")
        t |> equal(c_kind_name(int(CTok.IDENTIFIER)), "token kind 256")
    }
    t |> run("`::` is two colons, as C17 has no `::` and GNU asm spells `:` twice") @(t : T?) {
        t |> equal(placed("a::b"), "a@t.c:1:1 :@t.c:1:2 :@t.c:1:3 b@t.c:1:4 $@t.c:1:5")
    }
    t |> run("a digraph") @(t : T?) {
        t |> equal(kind_of("<:"), int(CTok.LBRACKET))
        t |> equal(kind_of("%>"), int(CTok.RBRACE))
    }
    t |> run("a stray character or a preprocessor-only punctuator") @(t : T?) {
        t |> equal(lexed("a # b"), "error: t.c:1:3: stray '#'")
        t |> equal(lexed("a ## b"), "error: t.c:1:3: stray '##'")
        t |> equal(lexed("a @"), "error: t.c:1:3: stray '@'")
        t |> equal(lexed("\\"), "error: t.c:1:1: stray '\\'")
        t |> equal(lexed("x \"abc"), "error: t.c:1:3: stray '\"abc'")
    }
    t |> run("an unterminated comment is an error at its `/*`") @(t : T?) {
        t |> equal(lexed("a /* b"), "error: t.c:1:3: unterminated /* comment")
    }
}

[test(description = "a line marker places the lines after it in the file and at the line it names; any other directive is an error")]
def test_line_markers(t : T?) {
    t |> run("markers with and without flags, `#line`, and a marker that keeps the file") @(t : T?) {
        t |> equal(placed("a\n# 1 \"a.c\"\nb\n# 10 \"b.h\" 1 3 4\n  c d\n\ne\n# 3 \"a.c\" 2\nf\n#line 20 \"c.h\"\ng\n# 5\nh"),
                   "a@t.c:1:1 b@a.c:1:1 c@b.h:10:3 d@b.h:10:5 e@b.h:12:1 f@a.c:3:1 g@c.h:20:1 h@c.h:5:1 $@c.h:5:2")
    }
    t |> run("a file a marker names again has the id it had; file 1 is the predefined macros' buffer") @(t : T?) {
        var unit : CUnit
        c_tokens_of_text(unit, "# 1 \"a.c\"\nb\n# 1 \"b.h\"\nc\n# 2 \"a.c\"\nd", "t.c")
        t |> equal(unit.toks[0].file, 2)
        t |> equal(unit.toks[1].file, 3)
        t |> equal(unit.toks[2].file, 2)
        t |> equal(c_file_name(unit, 1), "<built-in>")
        t |> equal(c_file_name(unit, 3), "b.h")
    }
    t |> run("a marker at the end of the unit leaves the end placed after the last token") @(t : T?) {
        t |> equal(placed("x\n# 4 \"y.h\""), "x@t.c:1:1 $@t.c:1:2")
        t |> equal(placed(""), "$@t.c:1:1")
        t |> equal(placed("# 5\n\"s\""), "\"s\"@t.c:5:1 $@t.c:5:4")
    }
    t |> run("any other directive is the preprocessor's: done, a `#define` expanding nothing here") @(t : T?) {
        t |> equal(lexed("x\n#pragma once\ny"), "I:x I:y")
        t |> equal(lexed("# 1 \"h.h\"\n#define A 1\nA"), "I:A")
        t |> equal(lexed("x\n#\ny"), "I:x I:y")
        t |> equal(lexed("x\n#\nline 7\ny"), "I:x I:line N:7 I:y")
        t |> equal(lexed("x\n#\n5\ny"), "I:x N:5 I:y")
    }
    t |> run("a malformed directive is the preprocessor's error at its place") @(t : T?) {
        t |> equal(lexed("x\n#assert y\nz"), "error: t.c:2:2: invalid preprocessing directive")
        t |> equal(lexed("# 0x10 \"a.c\""), "error: t.c:1:3: line marker directive requires a simple digit sequence")
        t |> equal(lexed("# 3 L\"w.h\"\nx"), "error: t.c:1:5: invalid filename for line marker directive")
        t |> equal(lexed("# 3 u8\"w.h\"\nx"), "error: t.c:1:5: invalid filename for line marker directive")
        t |> equal(lexed("# 9999999999 \"a.c\""), "error: t.c:1:3: line marker directive requires a positive integer argument")
        t |> equal(lexed("x\n# 4 \"a.c\" 2\ny"), "error: t.c:2:11: invalid line marker flag '2': cannot pop empty include stack")
    }
    t |> run("a warning is no error") @(t : T?) {
        t |> equal(lexed("#ifdef A\n#endif B\nx"), "I:x")
    }
}

// the C tokens of `text` read after the unit already met every name in it: their count, and the
// heap and string-heap allocations the read made
def private allocations_of_read(var unit : CUnit; text : string) : int3 {
    var bytes : array<uint8>
    bytes |> reserve(length(text) + 1)
    for (c in text) {
        bytes |> push(uint8(c))
    }
    c_tokens_open(unit, bytes, "t.c")
    let heap = int(heap_allocation_count())
    let strings = int(string_heap_allocation_count())
    c_tokens_read(unit)
    return int3(length(unit.toks), int(heap_allocation_count()) - heap, int(string_heap_allocation_count()) - strings)
}

[test(description = "reading a unit's C tokens allocates no string and no heap block per token: the token array grows by doubling, and a second read allocates no more than the preprocessor's one block a unit; a line marker costs what the preprocessor's `#line` costs, a few blocks each")]
def test_no_allocation(t : T?) {
    let line = "x = y[0x10] * (z - 1.5f) + sizeof(int) ; s = \"a\" ;\n"
    let plain = build_string() $(var w) {
        for (_i in range(400)) {
            w |> write(line)
        }
    }
    var unit : CUnit
    let first = allocations_of_read(unit, plain)
    t |> success(first.x > 8000, "{first.x} tokens")
    t |> equal(first.z, 0, "string allocations, first read")
    t |> success(first.y <= 20, "heap allocations {first.y} for {first.x} tokens: the array's doublings and the new names")
    let again = allocations_of_read(unit, plain)
    t |> equal(again.x, first.x)
    t |> success(again.y <= 1, "heap allocations {again.y}, the array grown and every name known")
    t |> equal(again.z, 0, "string allocations, every name known")
    let marked = build_string() $(var w) {
        for (i in range(400)) {
            if (i % 50 == 0) {
                w |> write("# {i + 1} \"{i % 100 == 0 ? "a.h" : "b.h"}\" 1\n")
            }
            w |> write(line)
        }
    }
    allocations_of_read(unit, marked)
    let markers = allocations_of_read(unit, marked)
    t |> equal(markers.x, first.x)
    t |> success(markers.y <= again.y + 2 * 8, "heap allocations {markers.y} for 8 line markers")
    t |> success(markers.z <= 5 * 8, "string allocations {markers.z} for 8 line markers")
}

// a unit of C source over the in-memory `files` (path, text pairs), read from `main.c` with macro
// expansion
def private expanded_unit(var unit : CUnit; files : array<tuple<string; string>>) : bool {
    var mem = new PpMemoryProvider()
    for (f in files) {
        mem->add(f._0, f._1)
    }
    return c_tokens_expand(unit, mem, "main.c", array<string>(), array<string>(), 1000000000l)
}

// every token of the expanded `main.c` placed as `placed` writes them, or `error: <message>`
def private expanded(files : array<tuple<string; string>>) : string {
    var unit : CUnit
    if (!expanded_unit(unit, files)) {
        return "error: {unit.err}"
    }
    var parts : array<string>
    parts |> reserve(length(unit.toks))
    for (t in range(length(unit.toks))) {
        let spelling = unit.toks[t].kind == int(CTok.EOF) ? "$" : c_spelling(unit, t)
        parts |> push("{spelling}@{c_where(unit, t)}")
    }
    return join(parts, " ")
}

[test(description = "C source read with macro expansion: a token an expansion makes stands at the outermost macro name, as clang's expansion location does; a source token at its own place")]
def test_expansion_places(t : T?) {
    t |> run("an object-like and a function-like call, an argument on a later line") @(t : T?) {
        t |> equal(expanded([("main.c", "#define N 4\n#define ADD(a, b) a + b\nint x = ADD(N,\n  2);")]),
                   "int@main.c:3:1 x@main.c:3:5 =@main.c:3:7 4@main.c:3:9 +@main.c:3:9 2@main.c:3:9 ;@main.c:4:5 $@main.c:4:6")
    }
    t |> run("a call inside a call's replacement stands at the outer name") @(t : T?) {
        t |> equal(expanded([("main.c", "#define ONE 1\n#define F(v) v + ONE\n  F(2)")]),
                   "2@main.c:3:3 +@main.c:3:3 1@main.c:3:3 $@main.c:3:4")
    }
    t |> run("a token of an included file names that file, and `#line` moves the place") @(t : T?) {
        t |> equal(expanded([("main.c", "#include \"h.h\"\n#line 40 \"m.c\"\nb"), ("h.h", "a")]),
                   "a@h.h:1:1 b@m.c:40:1 $@m.c:40:2")
    }
}

[test(description = "a pasted or stringified token keeps its spelling after the preprocessor reuses its pool: the unit copies it")]
def test_scratch_spellings(t : T?) {
    var unit : CUnit
    let clean = expanded_unit(unit, [("main.c", "#define CAT(a, b) a ## b\n#define S(x) #x\nint CAT(fo, o) = CAT(1, 2); char *p = S(a  b); int CAT(x, y);")])
    t |> success(clean, unit.err)
    let spellings <- [for (k in range(length(unit.toks) - 1)); c_spelling(unit, k)]
    t |> equal(join(spellings, " "), "int foo = 12 ; char * p = \"a b\" ; int xy ;")
    t |> equal(unit.toks[1].kind, int(CTok.IDENTIFIER))
    t |> equal(unit.toks[3].kind, int(CTok.INT_CONSTANT))
    t |> equal(unit.toks[9].kind, int(CTok.STRING_LITERAL))
    let foo = c_symbol(unit, "foo")
    t |> equal(unit.toks[1].sym, foo)
}

[test(description = "an error of the preprocessor ends the read at its place: a directive's, a fatal `#include`'s, the lexer's under `#line`, and a token an expansion makes")]
def test_preprocessor_errors(t : T?) {
    t |> equal(expanded([("main.c", "int a;\n#error boom\nint b;")]), "error: main.c:2:2: #error boom")
    t |> equal(expanded([("main.c", "int a;\n#include \"h.h\"")]), "error: main.c:2:10: 'h.h' file not found; searched: .")
    t |> equal(expanded([("main.c", "#include \"h.h\""), ("h.h", "x\n#error inner")]), "error: h.h:2:2: #error inner")
    t |> equal(expanded([("main.c", "#line 10 \"q.c\"\nx /* b")]), "error: q.c:10:3: unterminated /* comment")
    t |> equal(expanded([("main.c", "#define AT(x) x @\nint a;\n  AT(1)")]), "error: main.c:3:3: stray '@'")
    t |> equal(expanded([("main.c", "#define BAD 08\nint a = BAD;")]), "error: main.c:2:9: invalid numeric constant '08'")
}

[test(description = "the text of a token range: the bytes between its ends when they are source tokens of one file in order, else the spellings with a blank between")]
def test_range_text(t : T?) {
    var unit : CUnit
    expanded_unit(unit, [("main.c", "#define CALL f(1,2)\nint x = g( 3 ,4 ); int y = CALL;")])
    t |> equal(c_range_text(unit, 4, 8), "( 3 ,4 )")
    t |> equal(c_range_text(unit, 13, 18), "f ( 1 , 2 )")
    t |> equal(c_range_text(unit, 8, 13), ") ; int y = f")
}
