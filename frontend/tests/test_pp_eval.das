options gen2
options stack = 1048576
require dastest/testing_boost public
require strings
require daslib/strings_boost
require ../pp_expand.das
require ../c_defines.das

//! `frontend/pp_eval.das`: the `#if` evaluator over in-memory files - intmax_t and uintmax_t
//! arithmetic and its conversions, the sign trap, every literal form, `defined`, the feature queries
//! against the `linux` table, `__has_include` through the include path, the errors, `#elif` chains
//! and nesting.

// a preprocessor with expansion over `files` (path, text pairs), started at `main.c` with the
// `linux` table's macros, its feature table, and the include path `inc`
def private started(files : array<tuple<string; string>>) : Preprocessor {
    var mem = new PpMemoryProvider()
    for (f in files) {
        mem->add(f._0, f._1)
    }
    var error = ""
    let entries <- read_predefined(predefined_path("linux"), error)
    var pp : Preprocessor
    pp_expand_start(pp, mem, "main.c", entries, array<string>("inc"), 1000000000l)
    pp.eval.features <- read_features(features_path("linux"), error)
    return <- pp
}

// every token handed out, a blank between them
def private stream(var pp : Preprocessor) : string {
    return build_string() $(var out) {
        var first = true
        while (pp_next_token(pp)) {
            if (!first) {
                out |> write(" ")
            }
            first = false
            out |> write(pp_token_spelling(pp))
        }
    }
}

// the diagnostics, `<W|E> <line>:<col> <what>`, a `|` between them; `<built-in>`'s left out
def private diagnostics(pp : Preprocessor) : string {
    let parts <- [for (d in pp.diags); "{d.severity == PpSeverity.error ? "E" : "W"} {d.line}:{d.col} {d.what}"; where d.file == 0]
    return join(parts, " | ")
}

// the stream of `main.c` holding `text` with the files `more`, and its diagnostics
def private run_text(text : string; more : array<tuple<string; string>> = array<tuple<string; string>>()) : tuple<out : string; diags : string> {
    var all <- [("main.c", text)]
    all |> push_from(more)
    var pp <- started(all)
    let out = stream(pp)
    return (out = out, diags = diagnostics(pp))
}

// `#if expr` choosing between YES and NO
def private verdict(expr : string; more : array<tuple<string; string>> = array<tuple<string; string>>()) : string =>
    run_text("#if {expr}\nYES\n#else\nNO\n#endif\n", more).out

// clang 22's verdict on each expression under the dumper's flags, pinned: `-E` on `#if <expr>`
def private pinned(t : T?; cases : array<tuple<string; string>>) {
    for (c in cases) {
        t |> equal(verdict(c._0), c._1, c._0)
    }
}

[test(description = "the sign trap of glibc's bits/wchar.h: L'\\0' is wchar_t, signed int here, so L'\\0' - 1 > 0 is false; an unsigned operand makes the operation unsigned")]
def test_sign_trap(t : T?) {
    pinned(t, [("L'\\0' - 1 > 0", "NO"), ("L'\\0' - 1 < 0", "YES"), ("0u - 1 > 0", "YES"), ("-1 > 0u", "YES"), ("-1 < 0", "YES"),
               ("U'\\0' - 1 > 0", "YES"), ("u'\\0' - 1 > 0", "YES"), ("'\\0' - 1 > 0", "YES"), ("-1 > 0 ? 1 : 0u - 1", "YES"),
               ("(0 ? 0u : -1) > 0", "YES"), ("(1 ? -1 : 0u) > 0", "YES"), ("(1 ? -1 : 0) > 0", "NO"), ("(1 > 0) - 2 < 0", "YES"),
               ("(!0u - 2) > 0", "NO"), ("-1 >> 63 == -1", "YES"), ("0xFFFFFFFFFFFFFFFF == -1", "YES"),
               ("18446744073709551615 == -1", "YES"), ("9223372036854775808 > 0", "YES"), ("9223372036854775807 > 0", "YES")])
    let r = run_text("#if -1 > 0u\n#endif\n")
    t |> equal(r.diags, "W 1:8 left side of operator converted from negative value to unsigned: -1 to 18446744073709551615")
}

[test(description = "every operator with C's precedence and associativity, over intmax_t")]
def test_operators(t : T?) {
    pinned(t, [("1 + 2 * 3 == 7", "YES"), ("(1 + 2) * 3 == 9", "YES"), ("7 / 2 == 3", "YES"), ("-7 / 2 == -3", "YES"), ("-7 % 2 == -1", "YES"),
               ("7 % -2 == 1", "YES"), ("10 - 2 - 3 == 5", "YES"), ("1 << 4 == 16", "YES"), ("256 >> 4 == 16", "YES"), ("-8 >> 1 == -4", "YES"),
               ("1 < 2 && 2 <= 2 && 3 > 2 && 3 >= 3", "YES"), ("1 == 1 != 0", "YES"), ("(6 & 3) == 2", "YES"), ("(6 ^ 3) == 5", "YES"),
               ("(6 | 3) == 7", "YES"), ("1 || 0 && 0", "YES"), ("0 && 1 || 1", "YES"), ("~0 == -1", "YES"), ("!0 == 1", "YES"),
               ("!5 == 0", "YES"), ("-(-3) == +3", "YES"), ("1 ? 2 : 3 ? 4 : 5", "YES"), ("(0 ? 2 : 0 ? 4 : 5) == 5", "YES"),
               ("1 ? 2, 3 : 4", "YES"), ("(1, 0)", "NO"), ("(0, 1)", "YES"), ("1 == 1L == 1", "YES"), ("~0u == 18446744073709551615u", "YES"),
               ("1ULL << 63 > 0", "YES"), ("1 << 63 < 0", "YES"), ("(-9223372036854775807-1) % -1 == 0", "YES"),
               ("(-9223372036854775807-1) / -1 < 0", "YES"), ("9223372036854775807 + 1 < 0", "YES"), ("1 << 64", "NO"), ("1 << -1", "NO"),
               ("8 >> -1", "NO"), ("2 << 62", "YES")])
    t |> equal(run_text("#if 1 << 63\n#endif\n").diags, "W 1:7 integer overflow in preprocessor expression")
}

[test(description = "short-circuiting: a division by zero in a branch not evaluated is no error")]
def test_short_circuit(t : T?) {
    pinned(t, [("0 && 1/0", "NO"), ("1 || 1/0", "YES"), ("0 ? 1/0 : 2", "YES"), ("1 ? 2 : 1/0", "YES"),
               ("(0 ? 0/0u : -1) < 0", "NO"), ("(0 ? 0u/0 : -1) < 0", "NO"), ("(1 ? -1 : 0/0u) < 0", "NO"), ("(1 ? -1 : 0/0) < 0", "YES"),
               ("(0 ? 0 + 1U : -2) < 0", "NO")])
    t |> equal(run_text("#if 0 && 1/0\n#endif\n#if 1 || 1 << 64\n#endif\n").diags, "")
}

[test(description = "integer constants: decimal, octal, hex, binary, every suffix; a floating constant, a bad digit or suffix is an error")]
def test_integer_literals(t : T?) {
    pinned(t, [("010 == 8", "YES"), ("0x10 == 16", "YES"), ("0X1f == 31", "YES"), ("0b101 == 5", "YES"), ("0B11 == 3", "YES"),
               ("1u == 1", "YES"), ("1U", "YES"), ("1l", "YES"), ("1L", "YES"), ("1ll", "YES"), ("1LL == 1", "YES"), ("1ul", "YES"),
               ("1lu", "YES"), ("1uLL", "YES"), ("1Lu", "YES"), ("1llu", "YES"), ("0", "NO"), ("00", "NO"), ("1lul", "NO"), ("1lL", "NO"),
               ("1.0", "NO"), ("1e3", "NO"), ("0x1p3", "NO"), ("1i", "NO"), ("08", "NO"), ("0x", "NO"), ("1_000", "NO"), ("0b12", "NO")])
    t |> equal(run_text("#if 1.0\n#endif\n#if 08\n#endif\n#if 0x\n#endif\n#if 1lul\n#endif\n#if 0b12\n#endif\n").diags,
               "E 1:5 floating point literal in preprocessor expression | E 3:5 invalid digit '8' in octal constant | E 5:5 invalid suffix 'x' on integer constant | E 7:5 invalid suffix 'lul' on integer constant | E 9:5 invalid digit '2' in binary constant")
    t |> equal(run_text("#if 9223372036854775808\n#endif\n").diags, "W 1:5 integer literal is too large to be represented in a signed integer type, interpreting as unsigned")
}

[test(description = "character constants: escapes, multi-character, the L, u and U prefixes, with clang's values and signedness under -funsigned-char")]
def test_char_literals(t : T?) {
    pinned(t, [("'a' == 97", "YES"), ("'\\n' == 10", "YES"), ("'\\0' == 0", "YES"), ("'\\x41' == 65", "YES"), ("'\\101' == 65", "YES"),
               ("'\\e' == 27", "YES"), ("'\\'' == 39", "YES"), ("'\\\\' == 92", "YES"), ("'\\?' == 63", "YES"), ("'\\q' == 'q'", "YES"),
               ("'\\xff' == 255", "YES"), ("'\\377' - 256 < 0", "NO"), ("'ab' == 0x6162", "YES"), ("'abcd' == 0x61626364", "YES"),
               ("'abcde' == 0x62636465", "YES"), ("'\\777' == 255", "YES"), ("'\\400' == 0", "YES"), ("'\\x100'", "NO"),
               ("L'a' == 97", "YES"), ("L'\\xffffffff' == -1", "YES"), ("L'\\xffffffff' < 0", "YES"), ("L'\\u00e9' == 0xe9", "YES"),
               ("u'x' - 'y' > 0", "YES"), ("U'\\U0001F600' == 0x1F600", "YES"), ("u'\\U0001F600'", "NO"), ("'\\u00e9' == 0xe9", "NO"),
               ("L'ab'", "NO"), ("u8'a' == 97", "NO"), ("U'\\u\{1234\}' == U'\\u1234'", "YES"), ("U'\\x\{10fffd\}' == 0x10FFFD", "YES"),
               ("U'\\o\{1234\}' == 0x29c", "YES"), ("'\\x\{41\}' == 65", "YES"), ("'\\u\{e9\}'", "NO"), ("'\\x\{\}'", "NO")])
    t |> equal(run_text("#if 'ab'\n#endif\n#if L'ab'\n#endif\n#if '\\777'\n#endif\n").diags,
               "W 1:5 multi-character character constant | E 3:5 wide character literals may not contain multiple characters | E 5:5 octal escape sequence out of range")
}

[test(description = "defined X and defined(X), of a macro and of a builtin name; an identifier that names no macro is 0, true and false among them; a function-like use of one is an error")]
def test_defined(t : T?) {
    t |> equal(run_text("#define X\n#if defined X && defined(X) && !defined Y && !defined(Y)\nyes\n#endif\n").out, "yes")
    pinned(t, [("defined __FILE__", "YES"), ("defined __LINE__", "YES"), ("defined __COUNTER__", "YES"), ("defined __has_include", "YES"),
               ("defined __has_builtin", "YES"), ("defined __is_identifier", "YES"), ("defined __has_cpp_attribute", "NO"), ("true", "NO"),
               ("false == 0", "YES"), ("UNDEFINED_NAME == 0", "YES"), ("foo(1)", "NO"), ("defined X Y", "NO"), ("defined", "NO"),
               ("defined(", "NO"), ("defined(X", "NO"), ("defined 1", "NO")])
    t |> equal(run_text("#ifdef __FILE__\na\n#endif\n#ifndef __has_include\nb\n#endif\n#undef __FILE__\n#ifdef __FILE__\nc\n#endif\n").out, "a")
    t |> equal(run_text("#if foo(1)\n#endif\n#if defined\n#endif\n#if defined(X\n#endif\n#if defined 1\n#endif\n").diags,
               "E 1:5 function-like macro 'foo' is not defined | E 3:5 macro name missing | E 5:13 missing ')' after 'defined' | E 7:13 macro name must be an identifier")
}

[test(description = "the errors: division by zero, unbalanced parentheses, a missing operand, an empty #if, a string, a comma at the top - the group is skipped, but tokens after a whole expression keep its value as clang does")]
def test_errors(t : T?) {
    pinned(t, [("1/0", "NO"), ("1%0", "NO"), ("(1", "NO"), ("1 +", "NO"), ("", "NO"), ("\"s\"", "NO"), ("1)", "YES"), ("1, 2", "YES"),
               ("1 2", "NO"), ("1 ? 2", "NO"), ("()", "NO"), ("1 = 1", "NO")])
    t |> equal(run_text("#if 1/0\n#endif\n#if (1\n#endif\n#if 1 +\n#endif\n#if\n#endif\n#if \"s\"\n#endif\n#if 1, 2\n#endif\n").diags,
               "E 1:6 division by zero in preprocessor expression | E 3:6 expected ')' in preprocessor expression | E 5:7 expected value in expression | E 7:2 expected value in expression | E 9:5 invalid token at start of a preprocessor expression | E 11:6 expected end of line in preprocessor expression")
}

[test(description = "the feature queries answer as clang under the linux dialect: a known name, a known-false one, and an unknown one each")]
def test_feature_queries(t : T?) {
    pinned(t, [("__has_builtin(__builtin_expect)", "YES"), ("__has_builtin(__builtin_nope)", "NO"), ("__has_builtin(int)", "NO"),
               ("__has_feature(c_atomic)", "YES"), ("__has_feature(cxx_rvalue_references)", "NO"), ("__has_feature(nope)", "NO"),
               ("__has_extension(c_static_assert)", "YES"), ("__has_extension(nope)", "NO"),
               ("__has_attribute(packed)", "YES"), ("__has_attribute(__packed__)", "YES"), ("__has_attribute(nope)", "NO"),
               ("__has_c_attribute(nodiscard) == 202003", "YES"), ("__has_c_attribute(gnu::packed)", "YES"),
               ("__has_c_attribute(clang::fallthrough)", "NO"), ("__has_c_attribute(nope)", "NO"),
               ("__has_warning(\"-Wunused\")", "YES"), ("__has_warning(\"-Wnope\")", "NO"), ("__has_warning(\"unused\")", "NO"),
               ("__is_identifier(int)", "NO"), ("__is_identifier(foo)", "YES"), ("__is_target_os(linux)", "YES"),
               ("__is_target_os(windows)", "NO"), ("__is_target_arch(x86_64)", "YES"), ("__building_module(x)", "NO"),
               ("__has_cpp_attribute(nodiscard)", "NO"), ("__has_feature", "NO"), ("__has_feature(1)", "NO"),
               ("__has_attribute(gnu::packed)", "NO"), ("__has_warning(-Wunused)", "NO")])
}

[test(description = "__has_include and __has_include_next find a file through the include path, both name forms, and a macro naming the header")]
def test_has_include(t : T?) {
    let files <- [("inc/there.h", ""), ("local.h", "")]
    t |> equal(verdict("__has_include(<there.h>)", files), "YES")
    t |> equal(verdict("__has_include(\"there.h\")", files), "YES")
    t |> equal(verdict("__has_include(\"local.h\")", files), "YES")
    t |> equal(verdict("__has_include(<local.h>)", files), "NO")
    t |> equal(verdict("__has_include(<nope.h>)", files), "NO")
    t |> equal(run_text("#define HDR <there.h>\n#define linux 1\n#if __has_include(HDR) && !__has_include(<linux/x.h>)\nyes\n#endif\n", files).out, "yes")
    t |> equal(run_text("#if __has_include\n#endif\n#if __has_include(there.h)\n#endif\n").diags,
               "E 1:5 missing '(' after '__has_include' | E 3:19 expected \"FILENAME\" or <FILENAME>")
    let next <- [("inc/a.h", "#if __has_include_next(<a.h>)\nnext\n#else\nnone\n#endif\n"), ("inc2/a.h", "")]
    var mem = new PpMemoryProvider()
    mem->add("main.c", "#include <a.h>\n")
    for (f in next) {
        mem->add(f._0, f._1)
    }
    var pp : Preprocessor
    pp_expand_start(pp, mem, "main.c", array<string>(), array<string>("inc", "inc2"), 1000000000l)
    t |> equal(stream(pp), "next")
    t |> equal(verdict("__has_embed(\"local.h\") == 2", files), "YES")
}

[test(description = "#elif chains take the first true group; nesting inside skipped groups evaluates nothing")]
def test_elif_and_nesting(t : T?) {
    t |> equal(run_text("#if 0\na\n#elif 1 + 1 == 2\nb\n#elif 1\nc\n#else\nd\n#endif\n").out, "b")
    t |> equal(run_text("#if 0\na\n#elif 0\nb\n#else\nd\n#endif\n").out, "d")
    t |> equal(run_text("#if 1\n#if 2 > 3\nx\n#elif 1\ny\n#endif\n#elif 1/0\nz\n#endif\n").out, "y")
    let skipped = run_text("#if 0\n#if 1/0\n#elif 1/0\n#endif\n#endif\nend\n")
    t |> equal(skipped.out, "end")
    t |> equal(skipped.diags, "")
    t |> equal(run_text("#if 1/0\na\n#elif 1\nb\n#endif\n").out, "b")
}

[test(description = "__COUNTER__ in an #if line counts like anywhere else")]
def test_counter(t : T?) {
    t |> equal(run_text("#if __COUNTER__ == 0 && __COUNTER__ == 1\nyes\n#endif\n__COUNTER__\n").out, "yes 2")
}

[test(description = "the #if shapes of the own headers and c-testsuite, clang's verdict pinned for each")]
def test_corpus_shapes(t : T?) {
    pinned(t, [("defined(__GNUC__) && __GNUC__ >= 4", "YES"), ("__STDC_VERSION__ >= 199901L", "YES"), ("__STDC_VERSION__ >= 201112L && !defined(__STDC_NO_ATOMICS__)", "YES"),
               ("__SIZEOF_POINTER__ == 8", "YES"), ("__WCHAR_MAX__ > 0xffff", "YES"), ("__CHAR_BIT__ == 8 && __SCHAR_MAX__ == 127", "YES"),
               ("__INT_MAX__ == 2147483647", "YES"), ("__LONG_MAX__ > 2147483647L", "YES"), ("-1 < 0", "YES"), ("~0U >> 1 == 0x7fffffffffffffff", "YES"),
               ("(-1 >> 1) == -1", "YES"), ("'\\377' < 0", "NO"), ("defined(__x86_64__) || defined(_M_X64)", "YES"),
               ("__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__", "YES"), ("__has_builtin(__builtin_unreachable) || __GNUC__ > 4", "YES")])
}
