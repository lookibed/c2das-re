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

[test(description = "every C punctuator keeps the pp-lexer's kind, a digraph the kind of what it spells; `#`, `##`, `::` and any other character are stray errors")]
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
    t |> run("a digraph") @(t : T?) {
        t |> equal(kind_of("<:"), int(CTok.LBRACKET))
        t |> equal(kind_of("%>"), int(CTok.RBRACE))
    }
    t |> run("a stray character or a preprocessor-only punctuator") @(t : T?) {
        t |> equal(lexed("a # b"), "error: t.c:1:3: stray '#'")
        t |> equal(lexed("a ## b"), "error: t.c:1:3: stray '##'")
        t |> equal(lexed("a::b"), "error: t.c:1:2: stray '::'")
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
    t |> run("a file a marker names again has the id it had") @(t : T?) {
        var unit : CUnit
        c_tokens_of_text(unit, "# 1 \"a.c\"\nb\n# 1 \"b.h\"\nc\n# 2 \"a.c\"\nd", "t.c")
        t |> equal(unit.toks[0].file, 1)
        t |> equal(unit.toks[1].file, 2)
        t |> equal(unit.toks[2].file, 1)
        t |> equal(c_file_name(unit, 2), "b.h")
    }
    t |> run("a marker at the end of the unit leaves the end placed after the last token") @(t : T?) {
        t |> equal(placed("x\n# 4 \"y.h\""), "x@t.c:1:1 $@t.c:1:2")
        t |> equal(placed(""), "$@t.c:1:1")
        t |> equal(placed("# 5\n\"s\""), "\"s\"@t.c:5:1 $@t.c:5:4")
    }
    t |> run("a directive that is no line marker is an error naming it") @(t : T?) {
        t |> equal(lexed("x\n#pragma once\ny"), "error: t.c:2:2: the directive '#pragma' is not parsed")
        t |> equal(lexed("# 1 \"h.h\"\n#define A 1"), "error: h.h:1:2: the directive '#define' is not parsed")
        t |> equal(lexed("x\n#\ny"), "error: t.c:3:1: an empty directive '#' is not parsed")
        t |> equal(lexed("x\n#\nline 7\ny"), "error: t.c:3:1: an empty directive '#' is not parsed")
        t |> equal(lexed("x\n#\n5\ny"), "error: t.c:3:1: an empty directive '#' is not parsed")
        t |> equal(lexed("#line x"), "error: t.c:1:7: the directive '#x' is not parsed")
        t |> equal(lexed("# 0x10 \"a.c\""), "error: t.c:1:3: the directive '#0x10' is not parsed")
        t |> equal(lexed("# 3 L\"w.h\"\nx"), "error: t.c:1:5: a line marker's file name 'L\"w.h\"' is not parsed")
        t |> equal(lexed("# 3 u8\"w.h\"\nx"), "error: t.c:1:5: a line marker's file name 'u8\"w.h\"' is not parsed")
        t |> equal(lexed("# 9999999999 \"a.c\""), "error: t.c:1:3: the directive '#9999999999' is not parsed")
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

[test(description = "reading a unit's C tokens allocates no string and no heap block per token: the token array grows by doubling, a line marker's file is interned, and a second read allocates nothing")]
def test_no_allocation(t : T?) {
    let line = "x = y[0x10] * (z - 1.5f) + sizeof(int) ; s = \"a\" ;\n"
    let text = build_string() $(var w) {
        for (i in range(400)) {
            if (i % 50 == 0) {
                w |> write("# {i + 1} \"{i % 100 == 0 ? "a.h" : "b.h"}\" 1\n")
            }
            w |> write(line)
        }
    }
    var unit : CUnit
    let first = allocations_of_read(unit, text)
    t |> success(first.x > 8000, "{first.x} tokens")
    t |> equal(first.z, 0, "string allocations, first read")
    t |> success(first.y <= 20, "heap allocations {first.y} for {first.x} tokens: the array's doublings and the new names")
    let again = allocations_of_read(unit, text)
    t |> equal(again.x, first.x)
    t |> equal(again.y, 0, "heap allocations, the array grown and every name known")
    t |> equal(again.z, 0, "string allocations, every name known")
}
