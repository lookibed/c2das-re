options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require daslib/functional
require ../criteria_scan.das
require ../criteria_count.das
require ../criteria_defines.das
require ../criteria_file.das
require ../readability_inputs.das
require ../../converter/tiers.das

// the raw counts of one C text and one emitted module named `m`, under the constant names given
def private raw_of(c_text, das_text : string; constants : table<string; bool>) : table<string; int> {
    var sources : array<CSource>
    sources |> emplace(scan_c(c_text, array<bool>()))
    var modules : array<DasModule>
    modules |> emplace(scan_das(das_text, "m", false))
    let none : table<string; bool>
    let raw <- count_criteria(sources, modules, constants, none)
    return <- clone_to_move(raw.counts)
}

def private raw_of(c_text, das_text : string) : table<string; int> => <- raw_of(c_text, das_text, default<table<string; bool>>)

// a C function `f` of two code lines and a das function `f` around `body`
def private in_f(body : string) : table<string; int> => <- raw_of("int f(void) \{\n  return 1;\n\}\n", "def f : int \{\n{body}\n\}\n")

def private got(c : table<string; int>; key : string) : int => c?[key] ?? 0

[test]
def test_lexer(t : T?) {
    t |> run("comments by line, a block comment over lines, strings and characters as tokens") @(t : T?) {
        let lx <- lex("int a; /* one\n * two */ char c = '\\'';\n// three\nchar *s = \"//x\";\n", true)
        t |> equal(lx.comments, ["one", "two", "three", "", ""])
        t |> equal([for (tk in lx.toks); tk.text; where tk.kind == TokKind.chr], ["'\\''"])
        t |> equal([for (tk in lx.toks); tk.text; where tk.kind == TokKind.str], ["\"//x\""])
    }
    t |> run("a directive continues past a trailing backslash; the longest operator wins") @(t : T?) {
        let lx <- lex("#define A \\\n  1\nx <<= 2;\n", true)
        t |> equal(lx.directive, [true, true, false, false])
        t |> success(has_value([for (tk in lx.toks); tk.text], "<<="))
    }
    t |> run("numbers keep their suffix, a hex number its letters, an exponent its sign") @(t : T?) {
        let lx <- lex("8u 0x1Fp+3 1e-5 1.5lf", false)
        t |> equal([for (tk in lx.toks); tk.text], ["8u", "0x1Fp+3", "1e-5", "1.5lf"])
    }
}

[test]
def test_c_source(t : T?) {
    t |> run("functions, not records, initializers or prototypes") @(t : T?) {
        let cs <- scan_c("struct S \{ int a; \};\nint g(int);\nint t[2] = \{ 1, 2 \};\nstatic int *f (int x)\n\{\n  return 0;\n\}\n", array<bool>())
        t |> equal(length(cs.functions), 1)
        t |> equal(cs.functions[0].name, "f")
        t |> equal(cs.functions[0].first, 3)
        t |> equal(cs.functions[0].last, 6)
    }
    t |> run("includes, quoted includes, defines and switches") @(t : T?) {
        let cs <- scan_c("#include <stdio.h>\n#include \"lua.h\"\n#define N 3\nint f(int x) \{ switch (x) \{ default: return N; \} \}\n", array<bool>())
        t |> equal(cs.includes, 2)
        t |> equal(cs.quoted_includes, ["lua.h"])
        t |> equal(cs.defined, ["N"])
        t |> equal(cs.switches, 1)
        t |> equal(cs.idents?["N"] ?? 0, 1)
    }
    t |> run("a branch the preprocessor emitted none of is left out, a live one kept") @(t : T?) {
        let text = "#if 0\nint dead = 'a'; /* dead */\n#else\nint live = 'b'; /* live */\n#endif\n"
        let emitted <- [false, false, false, true, false]
        let cs <- scan_c(text, emitted)
        t |> equal([for (k in keys(cs.chars)); k], ["'b'"])
        t |> equal(cs.comment_texts, ["live"])
        let all <- scan_c(text, array<bool>())
        t |> equal(length(all.chars), 2)
    }
}

[test]
def test_das_module(t : T?) {
    t |> run("a function runs from its def to the closing brace at the margin; a one-line def is none") @(t : T?) {
        let dm <- scan_das("require crt\ndef g : int => 1\n\ndef private f(x : int) : int \{\n    if (x) \{\n    \}\n    return x\n\}\n", "m", false)
        t |> equal(dm.requires, 1)
        t |> equal(length(dm.functions), 1)
        t |> equal(dm.functions[0].name, "f")
        t |> equal(dm.functions[0].first, 3)
        t |> equal(dm.functions[0].last, 7)
    }
    t |> run("a def whose parameter list the line layout broke opens at the line ending in its brace; an expression def before a block is none") @(t : T?) {
        let dm <- scan_das("def g : int => 1
struct S \{
    a : int
\}
def private f(x : int;
        y : int) : int \{
    return x
\}
", "m", false)
        t |> equal(length(dm.functions), 1)
        t |> equal(dm.functions[0].name, "f")
        t |> equal(dm.functions[0].first, 5)
        t |> equal(dm.functions[0].last, 7)
    }
}

[test]
def test_wrapped_statements(t : T?) {
    t |> run("a literal cast counts once per statement the line layout broke inside its parentheses, however many lines") @(t : T?) {
        let wrapped = in_f("    t = fixed_array(uint8(0), uint8(1),\n            uint8(2), uint8(3),\n            uint8(4))\n    u = uint8(5)")
        t |> equal(got(wrapped, "literal_cast_lines"), 2)
    }
}

[test]
def test_ratio_criteria(t : T?) {
    t |> run("comments: a line equal to a C comment line, or of two words inside one, is carried") @(t : T?) {
        let c = raw_of("/* make room for it */\nint f(void) \{\n  return 1; /* retry */\n\}\n", "// generated by c2das - regenerate, never edit\ndef f : int \{\n    // room for it\n    // retry\n    return 1\n\}\n")
        t |> equal(got(c, "c_comment_lines"), 2)
        t |> equal(got(c, "das_comment_lines"), 2)
        t |> equal(got(c, "das_comments_carried"), 2)
    }
    t |> run("every raw key is counted, zero included, so a fresh sample compares key by key") @(t : T?) {
        let c = raw_of("", "")
        t |> equal(length(c), length(RAW_KEYS))
        t |> equal(c?["setjmp_sites"] ?? -1, 0)
    }
    t |> run("comments: a word inside a C comment and a converter note are not") @(t : T?) {
        let c = raw_of("/* retry the call */\nint f(void) \{ return 1; \}\n", "def f : int \{\n    // retry\n    // re-dispatch\n    return 1\n\}\n")
        t |> equal(got(c, "das_comments_carried"), 0)
    }
    t |> run("constant names: a use by name counts up to the C uses, a number does not") @(t : T?) {
        let consts <- {"LIMIT" => true}
        let named = raw_of("int f(void) \{ return LIMIT; \}\n", "def f : int \{\n    return LIMIT + LIMIT\n\}\n", consts)
        t |> equal(got(named, "c_constant_uses"), 1)
        t |> equal(got(named, "das_constant_names"), 1)
        let number = raw_of("int f(void) \{ return LIMIT; \}\n", "def f : int \{\n    return 42\n\}\n", consts)
        t |> equal(got(number, "das_constant_names"), 0)
    }
    t |> run("character literals: the same spelling counts, a number does not") @(t : T?) {
        t |> equal(got(raw_of("int f(void) \{ return '%'; \}\n", "def f : int \{\n    return '%'\n\}\n"), "das_char_literals"), 1)
        t |> equal(got(raw_of("int f(void) \{ return '%'; \}\n", "def f : int \{\n    return 37\n\}\n"), "das_char_literals"), 0)
    }
    t |> run("macro blow-up: within 1.5 das lines per C line, and past it") @(t : T?) {
        let within = in_f("    return 1")
        t |> equal(got(within, "fn_matched"), 1)
        t |> equal(got(within, "fn_within"), 1)
        let blown = in_f("    var a = 1\n    a++\n    return a")
        t |> equal(got(blown, "fn_within"), 0)
        t |> equal(got(blown, "fn_worst_x100"), 166)
    }
    t |> run("macro blow-up: a renamed function matches its C name, an unknown one nothing") @(t : T?) {
        t |> equal(got(raw_of("int match(void) \{ return 1; \}\nint main(void) \{ return 0; \}\n", "def _c_match : int \{\n    return 1\n\}\ndef c_main : int \{\n    return 0\n\}\ndef other : int \{\n    return 0\n\}\n"), "fn_matched"), 2)
    }
    t |> run("switch flags, flag lines and `_goto` states") @(t : T?) {
        let c = in_f("    var _flag = false\n    _flag ||= _goto == 0\n    _goto = 1")
        t |> equal(got(c, "flag_switches"), 1)
        t |> equal(got(c, "flag_lines"), 1)
        t |> equal(got(c, "goto_state_lines"), 2)
        let plain = in_f("    var flag = false")
        t |> equal(got(plain, "flag_switches"), 0)
    }
    t |> run("setjmp: a trampoline loop around the try, and a try alone") @(t : T?) {
        let looped = in_f("    while (_sj_run) \{\n        try \{\n        \} recover \{\n        \}\n    \}")
        t |> equal(got(looped, "setjmp_sites"), 1)
        t |> equal(got(looped, "setjmp_loops"), 1)
        let flat = in_f("    try \{\n    \} recover \{\n    \}")
        t |> equal(got(flat, "setjmp_loops"), 0)
    }
    t |> run("string literals: a reinterpreted string counts, a cast of a pointer does not") @(t : T?) {
        let c = raw_of("int f(void) \{ return g(\"s\"); \}\n", "def f : int \{\n    return g(reinterpret<uint8?>(\"s\"), reinterpret<int?>(p))\n\}\n")
        t |> equal(got(c, "c_strings"), 1)
        t |> equal(got(c, "das_string_reinterprets"), 1)
        t |> equal(got(c, "reinterpret_casts_sites"), 1)
        // the converter's `cstr("...")` is the same literal reinterpreted; a call of a name counts not
        let helper = raw_of("int f(void) \{ return g(\"s\"); \}\n", "def f : int \{\n    return g(cstr(\"s\"), cstr(name))\n\}\n")
        t |> equal(got(helper, "das_string_reinterprets"), 1)
        t |> equal(got(helper, "reinterpret_casts_sites"), 0)
    }
}

[test]
def test_literal_arithmetic_groups(t : T?) {
    t |> run("a parenthesized constant is an operand like a number; a call's or a cast's parentheses and a group holding a name are not") @(t : T?) {
        t |> equal(got(in_f("    x = 3 | (0 << 4)"), "literal_arithmetic_sites"), 2)
        t |> equal(got(in_f("    x = y + (7 * 2)"), "literal_arithmetic_sites"), 1)
        t |> equal(got(in_f("    x = f(3) + 1"), "literal_arithmetic_sites"), 0)
        t |> equal(got(in_f("    x = (a + 3) + 1"), "literal_arithmetic_sites"), 0)
    }
}

[test]
def test_function_criteria(t : T?) {
    t |> run("temporaries: `_tN`, `_first`, a discarded `let _tN` and a self-assignment") @(t : T?) {
        let c = in_f("    var _t0 = p\n    var _first = true\n    let _t1 = x\n    L.top = L.top\n    return _t0")
        t |> equal(got(c, "temporaries_sites"), 4)
        t |> equal(got(c, "discarded_temps"), 1)
        t |> equal(got(c, "self_assignments"), 1)
        t |> equal(got(c, "fn_temporaries"), 1)
    }
    t |> run("temporaries: a named local, a read `let _tN` and an assignment are not") @(t : T?) {
        let c = in_f("    var t0 = p\n    L.top = L.bot\n    var _tx = 1")
        t |> equal(got(c, "temporaries_sites"), 0)
        t |> equal(got(c, "fn_temporaries"), 0)
    }
    t |> run("addr/deref pairs: `addr(b).n`, `addr(deref(...))`, `deref(addr(...))`") @(t : T?) {
        t |> equal(got(in_f("    x = addr(b).n + addr(deref(p + i)) + deref(addr(a[0]) + i)"), "addr_deref_sites"), 3)
        t |> equal(got(in_f("    x = addr(b) + deref(p)"), "addr_deref_sites"), 0)
    }
    t |> run("qualified calls: `__::` and a program module, not an outside one") @(t : T?) {
        let sources <- [scan_c("int f(void) \{ return 1; \}\n", array<bool>())]
        let modules <- [scan_das("def f : int \{\n    return __::g() + lgc::h() + crt::strlen(s)\n\}\n", "m", false), scan_das("def h : int \{\n    return 0\n\}\n", "lgc", false)]
        let none : table<string; bool>
        let raw <- count_criteria(sources, modules, none, none)
        t |> equal(raw.counts?["qualified_calls_sites"] ?? 0, 2)
    }
    t |> run("stray braces: a lone `\{` opens a bare block, a statement's `\{` does not") @(t : T?) {
        t |> equal(got(in_f("    \{\n        x = 1\n    \}"), "stray_braces_sites"), 1)
        t |> equal(got(in_f("    if (x) \{\n        x = 1\n    \}"), "stray_braces_sites"), 0)
    }
    t |> run("label stubs (`label N:` and `goto label N`, not the gone `c_label_end()`), `_c_` renames, `? 1 : 0` round trips") @(t : T?) {
        let c = in_f("    label 1:\n    goto label 1\n    c_label_end()\n    x = t._c_array\n    y = (x ? 1 : 0) != 0")
        t |> equal(got(c, "label_stubs_sites"), 2)
        t |> equal(got(c, "fn_label_stubs"), 1)
        t |> equal(got(c, "c_renames_sites"), 1)
        t |> equal(got(c, "bool_roundtrip_sites"), 1)
        let none = in_f("    x = t.array_c\n    y = x ? 2 : 0\n    var label = 3")
        t |> equal(got(none, "c_renames_sites") + got(none, "bool_roundtrip_sites") + got(none, "label_stubs_sites"), 0)
    }
    t |> run("casts: a numeric type, intptr or enum_from_int called; not a declaration, a field or another call") @(t : T?) {
        let c = in_f("    x = int(y) + uint8(z) * uint64(w)\n    p = intptr(q)\n    e = enum_from_int(type<E>, 7)")
        t |> equal(got(c, "cast_sites"), 5)
        let none = in_f("    var n : int = 3\n    x = o.int(y)\n    y = float3(1.0, 2.0, 3.0)\n    z = type<int>")
        t |> equal(got(none, "cast_sites"), 0)
    }
    t |> run("a cast of a bare number literal is a literal-cast line, once per line, not a cast site") @(t : T?) {
        let c = in_f("    t = [[uint8 uint8(0); uint8(1); uint8(8)]]\n    x = uint64(0) + uint(y)\n    z = int(0x10 + 1)")
        t |> equal(got(c, "literal_cast_lines"), 2)
        t |> equal(got(c, "cast_sites"), 2, "`uint(y)` and `int(0x10 + 1)`: an expression is no bare literal")
        t |> equal(got(in_f("    x = int(y)"), "literal_cast_lines"), 0)
    }
    t |> run("addr and deref sites, all of them; the pair criterion stays the pairs") @(t : T?) {
        let c = in_f("    x = addr(b).n + addr(deref(p + i)) + deref(addr(a[0]) + i)\n    y = deref(p) + addr(q)")
        t |> equal(got(c, "addr_sites"), 4)
        t |> equal(got(c, "deref_sites"), 3)
        t |> equal(got(c, "addr_deref_sites"), 3)
        let none = in_f("    x = address.n + dereference(p)")
        t |> equal(got(none, "addr_sites") + got(none, "deref_sites"), 0)
    }
    t |> run("temporary names: every `_tN` spelled, declared or used; the declarations stay the temporaries") @(t : T?) {
        let c = in_f("    var _t0 = p\n    let _t1 = _t0 + 1\n    return _t0 + _t1")
        t |> equal(got(c, "temp_name_sites"), 5)
        t |> equal(got(c, "temporaries_sites"), 2)
        t |> equal(got(in_f("    var t0 = p\n    return _tx + _t"), "temp_name_sites"), 0)
    }
    t |> run("the sites count over the whole module, the function flags over matched functions only") @(t : T?) {
        let c = raw_of("int f(void) \{\n  return 1;\n\}\n", "var g = int(h)\ndef f : int \{\n    return int(a)\n\}\ndef helper : int \{\n    return int(b) + int(d)\n\}\n")
        t |> equal(got(c, "cast_sites"), 4)
        t |> equal(got(c, "fn_matched"), 1)
    }
    t |> run("literal arithmetic: an operator between two literals, not a literal and a name") @(t : T?) {
        t |> equal(got(in_f("    x = uint(0 + 7 + 8)"), "literal_arithmetic_sites"), 2)
        t |> equal(got(in_f("    x = y + 7"), "literal_arithmetic_sites"), 0)
    }
    t |> run("lost parentheses: a shift beside an additive or bitwise operator at one level") @(t : T?) {
        t |> equal(got(in_f("    b = 1 << b - 1"), "lost_parens_sites"), 1)
        t |> equal(got(in_f("    b = i >> 7 & 255"), "lost_parens_sites"), 1)
        t |> equal(got(in_f("    b = 1 << (b - 1)"), "lost_parens_sites"), 0)
        t |> equal(got(in_f("    b = -a - 1"), "lost_parens_sites"), 0)
        t |> equal(got(in_f("    var a : array<array<int>> = f(-1 << 2)"), "lost_parens_sites"), 0)
    }
}

[test]
def test_module_criteria(t : T?) {
    t |> run("layout checks, late binding and long lines per module") @(t : T?) {
        let long_line = "    x = {repeat("a", 157)}"
        let c = in_f("{long_line}\n    static_assert(typeinfo sizeof(type<S>) == 8, \"S\")\n    g_slot = @@__::g")
        t |> equal(got(c, "modules"), 1)
        t |> equal(got(c, "modules_layout_check"), 1)
        t |> equal(got(c, "modules_late_bound"), 1)
        t |> equal(got(c, "modules_long_lines"), 1)
        t |> equal(got(c, "long_lines"), 1)
    }
    t |> run("a link module is late-bound by its name; a 160-byte line and a plain static_assert are not flagged") @(t : T?) {
        let line = "    x = {repeat("a", 152)}"
        let plain = in_f("{line}\n    static_assert(x == 1)")
        t |> equal(got(plain, "modules_layout_check") + got(plain, "modules_late_bound") + got(plain, "modules_long_lines"), 0)
        var modules : array<DasModule>
        modules |> emplace(scan_das("var x = 1\n", "lua_link", false))
        let none : table<string; bool>
        let raw <- count_criteria(array<CSource>(), modules, none, none)
        t |> equal(raw.counts?["modules_late_bound"] ?? 0, 1)
    }
    t |> run("repeated blocks: a window of four lines seen twice covers its lines") @(t : T?) {
        t |> equal(repeated_lines(["a", "b", "c", "d", "a", "b", "c", "d"]), 8)
        t |> equal(repeated_lines(["a", "b", "c", "d", "e"]), 0)
        t |> equal(repeated_lines(["a"]), 0)
    }
}

[test]
def test_defines(t : T?) {
    t |> run("the preprocessor's output: markers place the main file's lines, defines and undefs in order") @(t : T?) {
        let text = "# 1 \"m.c\"\n# 1 \"<built-in>\" 1\n#define B 2\n# 1 \"m.c\" 2\n#define A 1\n\nint x;\n#undef B\n# 7 \"m.c\"\nint y;\n"
        let pp <- read_preprocessed(text, "m.c")
        t |> equal(pp.emitted, [false, false, true, false, false, false, true])
        t |> success(key_exists(pp.macros, "A") && !key_exists(pp.macros, "B"))
    }
    t |> run("a constant through function-like macros and casts; a name, a call or a recursion is not") @(t : T?) {
        let macros <- read_preprocessed("#define makevariant(t,v) ((t) | ((v) << 4))\n#define TNUM 3\n#define VNUMINT makevariant(TNUM, 0)\n#define CAST ((lu_byte)(1 << 6))\n#define SZ (sizeof(int) * 2)\n#define NAME some_var\n#define CALL f(1)\n#define SELF SELF\n#define FN(x) (x)\n#define CH '%'\n#define EMPTY\n", "m.c").macros
        let names <- constant_names(["VNUMINT", "CAST", "SZ", "NAME", "CALL", "SELF", "FN", "CH", "EMPTY", "MISSING"], macros)
        t |> equal(sorted([for (k in keys(names)); k]), ["CAST", "CH", "SZ", "VNUMINT"])
    }
    t |> run("a constant expression: numbers under operators after casts, not a variable") @(t : T?) {
        t |> success(is_constant_expression(lex("((unsigned int)(~0)) >> 1", false).toks))
        t |> success(!is_constant_expression(lex("(x) + 1", false).toks))
        t |> success(!is_constant_expression(lex("", false).toks))
    }
    t |> run("clang preprocesses a unit: its constants, its own headers' and its live lines") @(t : T?) {
        var dir_error : string
        let dir = create_temp_directory("c2das_criteria", dir_error)
        t |> equal(dir_error, "")
        fwrite(path_join(dir, "own.h"), "#define FROM_HEADER (1 << 3)\n")
        let c_path = path_join(dir, "m.c")
        fwrite(c_path, "#include \"own.h\"\n#define LIMIT 10\n#ifdef NOPE\nint dead;\n#endif\nint f(void) \{ return LIMIT + FROM_HEADER + INT_MAX; \}\n")
        var error : string
        var pp <- preprocess(c_path, ["X=1"], array<string>(), array<string>(), error)
        t |> equal(error, "")
        t |> success(length(pp.emitted) > 5 && pp.emitted[5] && !pp.emitted[3], "{pp.emitted}")
        var units : array<Preprocessed>
        units |> emplace(pp)
        let names <- program_constants([c_path], array<string>(), units)
        t |> equal(sorted([for (k in keys(names)); k]), ["FROM_HEADER", "LIMIT"])
        var refused : string
        preprocess(path_join(dir, "missing.c"), array<string>(), array<string>(), array<string>(), refused)
        t |> success(refused |> contains("missing.c"), refused)
        rmdir_rec(dir)
    }
}

def private full_raw(fill : int) : table<string; int> {
    return <- {for (k in RAW_KEYS); k => fill}
}

[test]
def test_macro_calls(t : T?) {
    t |> run("C uses of the program's function-like macros, and the das uses that keep the name, capped") @(t : T?) {
        var sources : array<CSource>
        sources |> emplace(scan_c("#define twice(x) ((x) * 2)\nint f(int a) \{\n  return twice(a) + twice(1) + g(a);\n\}\n", array<bool>()))
        t |> equal(sources[0].calls?["twice"] ?? 0, 2)
        t |> equal(sources[0].calls?["g"] ?? 0, 1)
        var modules : array<DasModule>
        modules |> emplace(scan_das("def f(a : int) : int \{\n    return twice(a) + twice(1) + twice(2) + g(a)\n\}\n", "m", false))
        let none : table<string; bool>
        let raw <- count_criteria(sources, modules, none, {"twice" => true})
        t |> equal(raw.counts?["c_macro_calls"] ?? 0, 2)
        t |> equal(raw.counts?["das_macro_calls"] ?? 0, 2, "capped at the C uses")
        let unnamed <- count_criteria(sources, modules, none, none)
        t |> equal(unnamed.counts?["c_macro_calls"] ?? 0, 0, "a name no macro has is a call")
    }
    t |> run("the program's function-like macros: the own defines that take parameters in some unit") @(t : T?) {
        var dir_error : string
        let dir = create_temp_directory("c2das_criteria_macros", dir_error)
        t |> equal(dir_error, "")
        let c_path = path_join(dir, "m.c")
        fwrite(c_path, "#define LIMIT 10\n#define twice(x) ((x) * 2)\nint f(int a) \{ return twice(a) + LIMIT; \}\n")
        var error : string
        var pp <- preprocess(c_path, array<string>(), array<string>(), array<string>(), error)
        t |> equal(error, "")
        var units : array<Preprocessed>
        units |> emplace(pp)
        let names <- program_function_macros([c_path], array<string>(), units)
        t |> equal(sorted([for (k in keys(names)); k]), ["twice"])
        rmdir_rec(dir)
    }
}

[test]
def test_lengths(t : T?) {
    t |> run("the functions' body lines: how many, the median, the 90th percentile, the longest, the long ones; the converter's own left out") @(t : T?) {
        let body = join([for (i in range(101)); "    x = {i}"], "\n")
        let das = "def a : int \{\n    return 1\n\}\ndef b : int \{\n    x = 1\n    x = 2\n    return x\n\}\ndef c : int \{\n{body}\n    return x\n\}\n[init] def private c2das_layout_check \{\n    static_assert(1 == 1, \"x\")\n\}\n"
        let c = raw_of("int a(void) \{\n  return 1;\n\}\n", das)
        t |> equal(got(c, "fn_total"), 3)
        t |> equal(got(c, "fn_lines_median"), 3)
        t |> equal(got(c, "fn_lines_p90"), 102)
        t |> equal(got(c, "fn_lines_max"), 102)
        t |> equal(got(c, "fn_long"), 1)
    }
    t |> run("the matched functions' ratios: the lines past 1.5x the C lines, the 90th percentile") @(t : T?) {
        let c_text = "int a(void) \{\n  return 1;\n\}\nint b(void) \{\n  return 2;\n\}\n"
        let das = "def a : int \{\n    return 1\n\}\ndef b : int \{\n    x = 1\n    x = 2\n    x = 3\n    return x\n\}\n"
        let c = raw_of(c_text, das)
        t |> equal(got(c, "fn_matched"), 2)
        t |> equal(got(c, "fn_within"), 1)
        t |> equal(got(c, "blowup_lines"), 2, "b: 6 das lines against 3 C lines, 4 allowed")
        t |> equal(got(c, "fn_p90_x100"), 200)
        t |> equal(got(c, "fn_median_x100"), 200)
    }
    t |> run("a percentile of a sorted list, and the distributions of an empty one") @(t : T?) {
        t |> equal(percentile([1, 2, 3, 4], 50), 3)
        t |> equal(percentile([1, 2, 3, 4], 90), 4)
        t |> equal(percentile([1, 2, 3, 4], 100), 4)
        t |> equal(percentile(array<int>(), 50), 0)
        var c : table<string; int>
        distribution_counts(array<int>(), array<int>(), c)
        t |> equal(c?["fn_total"] ?? -1, 0)
        t |> equal(c?["fn_worst_x100"] ?? -1, 0)
    }
}

[test]
def test_density(t : T?) {
    t |> run("a density is sites per thousand das code lines; a C-side one needs C code; an unknown name is n/a") @(t : T?) {
        t |> equal(density("casts", {"cast_sites" => 5, "das_code_lines" => 2000}), 2.5lf)
        t |> equal(density("switch_machinery", {"flag_switches" => 1, "flag_lines" => 2, "goto_state_lines" => 3, "das_code_lines" => 1000}), 6.0lf)
        t |> equal(density("lost_comments", {"c_comment_lines" => 10, "das_comments_carried" => 4, "das_code_lines" => 1000, "c_code_lines" => 1}), 6.0lf)
        t |> equal(density("unnamed_constants", {"c_constant_uses" => 10, "das_constant_names" => 4, "das_code_lines" => 1000, "c_code_lines" => 1}), 6.0lf)
        t |> equal(density("macro_expansions", {"c_macro_calls" => 3, "das_macro_calls" => 0, "das_code_lines" => 1000, "c_code_lines" => 1}), 3.0lf)
        t |> equal(density("lost_chars", {"c_char_literals" => 2, "das_char_literals" => 5, "das_code_lines" => 1000, "c_code_lines" => 1}), 0.0lf)
        t |> equal(density("literal_casts", {"literal_cast_lines" => 3, "das_code_lines" => 1000}), 3.0lf)
        t |> equal(density("excess_repeats", {"das_repeated_lines" => 300, "das_code_lines" => 1000, "c_repeated_lines" => 100, "c_code_lines" => 500}), 100.0lf, "300 repeated, the C's own share 20% of 1000 is 200")
        t |> equal(density("excess_repeats", {"das_repeated_lines" => 100, "das_code_lines" => 1000, "c_repeated_lines" => 400, "c_code_lines" => 500}), 0.0lf)
        t |> equal(density("excess_repeats", {"das_repeated_lines" => 100, "das_code_lines" => 1000}), NOT_APPLICABLE)
        t |> equal(density("lost_comments", {"c_comment_lines" => 10, "das_code_lines" => 1000}), NOT_APPLICABLE, "no C code: a hand-written port")
        t |> equal(density("casts", {"cast_sites" => 5}), NOT_APPLICABLE)
        t |> equal(density("no_such_density", full_raw(1)), NOT_APPLICABLE)
        t |> equal(length(DENSITIES), length([for (d in DENSITIES); d; where density(d, full_raw(1)) >= 0.0lf]), "every density applies to full counts")
    }
    t |> run("the totals sum what applies; the das side leaves the C-side densities out") @(t : T?) {
        var cap : CriteriaCapture
        var hand <- full_raw(0)
        hand["das_code_lines"] = 1000
        hand["cast_sites"] = 40
        hand["addr_sites"] = 2
        cap.rows["hand/plmpeg-stream"] <- hand
        var lua <- full_raw(0)
        lua["das_code_lines"] = 1000
        lua["c_code_lines"] = 500
        lua["cast_sites"] = 100
        lua["c_comment_lines"] = 30
        cap.rows["lua/lua"] <- lua
        let table_ <- density_table(cap)
        t |> equal(table_?["hand/plmpeg-stream"]?[TOTAL] ?? -2.0lf, 42.0lf)
        t |> equal(table_?["hand/plmpeg-stream"]?[DAS_SIDE] ?? -2.0lf, 42.0lf)
        t |> equal(table_?["hand/plmpeg-stream"]?["lost_comments"] ?? -2.0lf, NOT_APPLICABLE)
        t |> equal(table_?["lua/lua"]?[TOTAL] ?? -2.0lf, 130.0lf)
        t |> equal(table_?["lua/lua"]?[DAS_SIDE] ?? -2.0lf, 100.0lf)
        t |> equal(sum_applicable([NOT_APPLICABLE]), NOT_APPLICABLE)
    }
    t |> run("the programs column pools lua/lua and the projects by their lines; the suites, luac, the layouts, opt-ins and the hand ports stay out") @(t : T?) {
        var cap : CriteriaCapture
        var lua <- full_raw(0)
        lua["das_code_lines"] = 1000
        lua["cast_sites"] = 100
        cap.rows["lua/lua"] <- lua
        var project <- full_raw(0)
        project["das_code_lines"] = 3000
        project["cast_sites"] = 60
        cap.rows["project/binjgb"] <- project
        for (row in ["lua/luac", "lua/lua@single", "lua/lua@inline", "csmith", "hand/plmpeg-stream"]) {
            var other <- full_raw(0)
            other["das_code_lines"] = 1000
            other["cast_sites"] = 900
            cap.rows[row] <- other
        }
        let table_ <- density_table(cap)
        t |> equal(table_?[PROGRAMS]?["casts"] ?? -2.0lf, 40.0lf, "160 sites over 4000 lines, not the mean of 100 and 20")
        t |> success(in_programs("lua/lua") && in_programs("project/quakegeneric") && !in_programs("lua/luac") && !in_programs("lua/lua@single") && !in_programs("csmith") && !in_programs("hand/plmpeg-stream"))
        t |> success(layout_row("lua/lua@single") && layout_row("lua/luac@source-cut") && !layout_row("lua/lua") && !layout_row("lua/lua@goto"))
        t |> equal(row_of("hand/plmpeg-stream"), "hand/plmpeg-stream")
        t |> success(!in_all("hand/plmpeg-stream"))
        let columns <- density_columns(table_)
        t |> equal(columns, ["lua/lua", "lua/luac", "csmith", "project/binjgb", PROGRAMS, "hand/plmpeg-stream"])
    }
    t |> run("no program row, no programs column") @(t : T?) {
        var cap : CriteriaCapture
        cap.rows["csmith"] <- full_raw(1)
        t |> success(!key_exists(density_table(cap), PROGRAMS))
    }
}

[test]
def test_project_preprocessing(t : T?) {
    t |> run("the lines a unit emits from a header it includes, under the header's own path") @(t : T?) {
        var dir_error : string
        let dir = create_temp_directory("c2das_criteria_header", dir_error)
        t |> equal(dir_error, "")
        mkdir_rec(path_join(dir, "lib"))
        mkdir_rec(path_join(dir, "src"))
        let header = path_join(dir, "lib/one.h")
        fwrite(header, "int one(void);\n#ifdef ONE_IMPL\nint one(void) \{ return 1; \}\n#endif\n")
        fwrite(path_join(dir, "src/a.c"), "#define ONE_IMPL\n#include \"../lib/one.h\"\n")
        fwrite(path_join(dir, "src/b.c"), "#include \"../lib/one.h\"\n")
        var error : string
        var with_impl <- preprocess(path_join(dir, "src/a.c"), array<string>(), array<string>(), array<string>(), error)
        var without <- preprocess(path_join(dir, "src/b.c"), array<string>(), array<string>(), array<string>(), error)
        t |> equal(error, "")
        var units : array<Preprocessed>
        units |> emplace(without)
        let declared <- emitted_lines(header, units)
        t |> success(!empty(declared) && declared[0] && (length(declared) < 3 || !declared[2]), "{declared}")
        t |> equal(length(scan_c(fread(header), declared).functions), 0)
        units |> emplace(with_impl)
        let defined <- emitted_lines(header, units)
        t |> success(length(defined) > 2 && defined[0] && defined[2], "{defined}")
        t |> equal(length(scan_c(fread(header), defined).functions), 1)
        t |> equal(length(emitted_lines(path_join(dir, "src/b.c"), units)), 0, "a main file is no included file")
        rmdir_rec(dir)
    }
    t |> run("a project's include folders and forced includes reach the preprocessing and its own headers") @(t : T?) {
        var dir_error : string
        let dir = create_temp_directory("c2das_criteria_inc", dir_error)
        t |> equal(dir_error, "")
        mkdir_rec(path_join(dir, "inc"))
        fwrite(path_join(dir, "inc/far.h"), "#define FAR_LIMIT 64\n")
        fwrite(path_join(dir, "inc/forced.h"), "#define FORCED 1\n")
        let c_path = path_join(dir, "m.c")
        fwrite(c_path, "#include \"far.h\"\n#ifdef FORCED\nint live;\n#endif\nint f(void) \{ return FAR_LIMIT; \}\n")
        var error : string
        var pp <- preprocess(c_path, array<string>(), [path_join(dir, "inc")], [path_join(dir, "inc/forced.h")], error)
        t |> equal(error, "")
        t |> success(length(pp.emitted) > 2 && pp.emitted[2], "the forced include's macro keeps the branch: {pp.emitted}")
        t |> equal(own_files([c_path], [path_join(dir, "inc")]), [c_path, path_join(dir, "inc/far.h")])
        t |> equal(own_files([c_path], array<string>()), [c_path])
        var units : array<Preprocessed>
        units |> emplace(pp)
        let names <- program_constants([c_path], [path_join(dir, "inc")], units)
        t |> equal(sorted([for (k in keys(names)); k]), ["FAR_LIMIT"])
        var unfound : string
        preprocess(c_path, array<string>(), array<string>(), array<string>(), unfound)
        t |> success(unfound |> contains("far.h"), "without the include folder clang refuses: {unfound}")
        rmdir_rec(dir)
    }
}

[test]
def test_compliance(t : T?) {
    t |> run("a share is capped at the whole, a clean share is what the defect leaves, nothing is n/a") @(t : T?) {
        t |> equal(compliance("comments", {"das_comments_carried" => 3, "c_comment_lines" => 4}), 75.0lf)
        t |> equal(compliance("char_literals", {"das_char_literals" => 9, "c_char_literals" => 4}), 100.0lf)
        t |> equal(compliance("temporaries", {"fn_temporaries" => 1, "fn_matched" => 4}), 75.0lf)
        t |> equal(compliance("long_lines", {"modules_long_lines" => 1, "modules" => 2}), 50.0lf)
        t |> equal(compliance("comments", default<table<string; int>>), NOT_APPLICABLE)
        t |> equal(compliance("no_such_criterion", full_raw(1)), NOT_APPLICABLE)
    }
    t |> run("each formula of its own") @(t : T?) {
        t |> equal(compliance("macro_blowup", {"fn_within" => 1, "fn_matched" => 2}), 50.0lf)
        t |> equal(compliance("constant_names", {"das_constant_names" => 1, "c_constant_uses" => 4}), 25.0lf)
        t |> equal(compliance("switch_flags", {"flag_switches" => 1, "c_switches" => 4}), 75.0lf)
        t |> equal(compliance("switch_flags", {"flag_switches" => 2}), 0.0lf)
        t |> equal(compliance("require_lines", {"c_includes" => 2, "das_requires" => 4}), 50.0lf)
        t |> equal(compliance("setjmp", {"setjmp_loops" => 1, "setjmp_sites" => 1}), 0.0lf)
        t |> equal(compliance("string_literals", {"das_string_reinterprets" => 1, "c_strings" => 4}), 75.0lf)
        t |> equal(compliance("repeated_blocks", {"das_code_lines" => 10, "das_repeated_lines" => 5, "c_code_lines" => 10, "c_repeated_lines" => 0}), 50.0lf)
        t |> equal(compliance("repeated_blocks", {"das_code_lines" => 10, "c_code_lines" => 10, "c_repeated_lines" => 10}), 100.0lf)
        t |> equal(compliance("repeated_blocks", {"c_code_lines" => 10}), NOT_APPLICABLE)
    }
    t |> run("the mean skips what does not apply; none applying is n/a") @(t : T?) {
        t |> equal(mean_applicable([50.0lf, NOT_APPLICABLE, 100.0lf]), 75.0lf)
        t |> equal(mean_applicable([NOT_APPLICABLE]), NOT_APPLICABLE)
        t |> equal(column_total({"comments" => 0.0lf, "temporaries" => 50.0lf}), 25.0lf)
    }
    t |> run("a row's sum pools the ratios for the median and the worst") @(t : T?) {
        let summed <- sum_raw([{"fn_matched" => 2, "fn_median_x100" => 7}, {"fn_matched" => 3}], [50, 100, 300], [4, 9])
        t |> equal(summed?["fn_matched"] ?? 0, 5)
        t |> equal(summed?["fn_median_x100"] ?? 0, 100)
        t |> equal(summed?["fn_worst_x100"] ?? 0, 300)
        t |> equal(length(summed), length(RAW_KEYS))
    }
    t |> run("a Lua or project key is its own row, a suite key its suite's") @(t : T?) {
        t |> equal(row_of("lua/lua@source-cut"), "lua/lua@source-cut")
        t |> equal(row_of("project/h264bsd-mp4"), "project/h264bsd-mp4")
        t |> equal(row_of("csmith/123"), "csmith")
        t |> equal(row_of("bare"), "bare")
    }
}

def private sample_capture : CriteriaCapture {
    var cap : CriteriaCapture
    var lua <- full_raw(0)
    lua["c_comment_lines"] = 10
    lua["fn_matched"] = 4
    lua["fn_within"] = 3
    lua["fn_temporaries"] = 1
    lua["modules"] = 2
    cap.rows["lua/lua"] <- lua
    var suite <- full_raw(0)
    suite["c_comment_lines"] = 2
    suite["das_comments_carried"] = 1
    cap.rows["csmith"] <- suite
    cap.sample["c_testsuite/00085"] <- full_raw(1)
    return <- cap
}

[test]
def test_capture_text(t : T?) {
    let text = criteria_text(sample_capture())
    t |> run("the four sections, a column per measured row and `all`, percentages to one decimal") @(t : T?) {
        t |> success(text |> starts_with("\{\n  \"compliance\": \{\n    \"lua/lua\": \{\"comments\": 0.0, \"constant_names\": null, \"char_literals\": null, \"macro_blowup\": 75.0,"), text)
        t |> success(text |> contains("\n    \"all\": \{\"comments\": 25.0,"), text)
        t |> success(text |> contains("\"sample\": \{\n    \"c_testsuite/00085\": \{\"addr_deref_sites\": 1,"), text)
        t |> success(text |> contains("\"totals\": \{\n    \"lua/lua\": "), text)
        t |> success(find(text, "\"lua/lua\": \{\"comments\"") < find(text, "\"csmith\": \{\"comments\""), text)
    }
    t |> run("an opt-in row has its own column and leaves `all` as the default rows make it") @(t : T?) {
        var cap <- sample_capture()
        var inlined <- full_raw(0)
        inlined["c_comment_lines"] = 10
        inlined["das_comments_carried"] = 10
        cap.rows["lua/lua@inline"] <- inlined
        let with_opt_in = criteria_text(cap)
        t |> success(with_opt_in |> contains("\n    \"lua/lua@inline\": \{\"comments\": 100.0,"), with_opt_in)
        t |> success(with_opt_in |> contains("\n    \"all\": \{\"comments\": 25.0,"), with_opt_in)
    }
    t |> run("a project row has its own column and leaves `all` as the default rows make it") @(t : T?) {
        var cap <- sample_capture()
        var project <- full_raw(0)
        project["c_comment_lines"] = 10
        cap.rows["project/wasm3"] <- project
        let with_project = criteria_text(cap)
        t |> success(with_project |> contains("\n    \"project/wasm3\": \{\"comments\": 0.0,"), with_project)
        t |> success(with_project |> contains("\n    \"all\": \{\"comments\": 25.0,"), with_project)
        t |> success(in_all("lua/lua") && in_all("csmith") && !in_all("lua/luac@inline") && !in_all("project/binjgb"))
    }
    t |> run("the density section: a column per measured row then `programs`, the totals last, a hand port's C-side densities null") @(t : T?) {
        var cap <- sample_capture()
        var hand <- full_raw(0)
        hand["das_code_lines"] = 500
        hand["cast_sites"] = 25
        cap.rows["hand/plmpeg-stream"] <- hand
        let with_hand = criteria_text(cap)
        t |> success(with_hand |> contains("\n  \"density\": \{\n    \"lua/lua\": \{\"casts\": "), with_hand)
        t |> success(with_hand |> contains("\n    \"hand/plmpeg-stream\": \{\"casts\": 50.0, "), with_hand)
        t |> success(with_hand |> contains("\"lost_comments\": null, \"unnamed_constants\": null, \"macro_expansions\": null, \"lost_chars\": null, \"blowup_lines\": null, \"excess_repeats\": null, \"total\": 50.0, \"das_side\": 50.0\}"), with_hand)
        t |> success(with_hand |> contains("\n    \"programs\": \{\"casts\": "), with_hand)
        t |> success(find(with_hand, "\"hand/plmpeg-stream\": \{\"casts\"") < find(with_hand, "\"programs\": \{\"casts\""), "`programs` closes the section as `all` does")
        t |> success(find(with_hand, "\"density\":") < find(with_hand, "\"raw\":"), with_hand)
        t |> equal(check_criteria(with_hand), array<string>())
        t |> success(join(check_criteria(replace(with_hand, "\"total\": 50.0", "\"total\": 49.0")), "") |> contains("not the writer's spelling"))
        t |> success(join(check_criteria(replace(with_hand, "\"hand/plmpeg-stream\": \{\"casts\": 50.0", "\"hand/other\": \{\"casts\": 50.0")), "") |> contains("not the writer's spelling"))
    }
    t |> run("the text passes the shape check and reads back") @(t : T?) {
        t |> equal(check_criteria(text), array<string>())
        var error : string
        let back <- read_criteria(text, error)
        t |> equal(error, "")
        t |> equal(back.rows?["lua/lua"]?["fn_within"] ?? 0, 3)
        t |> equal(back.sample?["c_testsuite/00085"]?["modules"] ?? 0, 1)
    }
    t |> run("the shape check: not JSON, an unknown key or row, a missing or negative count, an edited percentage") @(t : T?) {
        t |> success(join(check_criteria("[1]"), "") |> contains("not a JSON object"))
        t |> success(join(check_criteria(replace(text, "\"compliance\":", "\"extra\": 1,\n  \"compliance\":")), "") |> contains("unknown top-level key `extra`"))
        t |> success(join(check_criteria(replace(text, "\"csmith\": \{\"addr", "\"doom\": \{\"addr")), "") |> contains("raw has the unknown row `doom`"))
        t |> success(join(check_criteria(replace(text, "\"addr_deref_sites\": 1,", "")), "") |> contains("sample.c_testsuite/00085 lacks `addr_deref_sites`"))
        t |> success(join(check_criteria(replace(text, "\"addr_deref_sites\": 1,", "\"addr_deref_sites\": -1,")), "") |> contains("is not a non-negative integer"))
        t |> success(join(check_criteria(replace(text, "\"addr_deref_sites\": 1,", "\"addr_deref_sites\": 1, \"zz\": 1,")), "") |> contains("unknown key `zz`"))
        t |> success(join(check_criteria(replace(text, "\"comments\": 25.0", "\"comments\": 99.0")), "") |> contains("not the writer's spelling"))
        t |> success(join(check_criteria(replace(text, "\"raw\": \{", "\"raw\": [], \"x\": \{")), "") |> contains("raw is not an object"))
        let density_start = find(text, "  \"density\":")
        let without = slice(text, 0, density_start) + slice(text, find(text, "  \"raw\":"))
        t |> success(join(check_criteria(without), "") |> contains("the missing section `density`"), without)
    }
}

[test]
def test_tables(t : T?) {
    t |> run("the table: a row per criterion, a column per measured row, n/a and the totals") @(t : T?) {
        let table_text = render_criteria(sample_capture())
        t |> success(table_text |> contains("| Criterion "), table_text)
        t |> success(table_text |> contains("lua/lua") && table_text |> contains("csmith") && table_text |> contains(" all |"), table_text)
        t |> success(table_text |> contains("n/a"), table_text)
        t |> success(table_text |> contains("**total**"), table_text)
        t |> success(!(table_text |> contains("lua/luac")), table_text)
    }
    t |> run("the density table: a row per density, the columns of `density_columns`, the two totals; the length table beside it") @(t : T?) {
        var cap <- sample_capture()
        var hand <- full_raw(0)
        hand["das_code_lines"] = 500
        hand["cast_sites"] = 25
        hand["fn_total"] = 3
        hand["fn_lines_median"] = 7
        cap.rows["hand/plmpeg-stream"] <- hand
        let density_text = render_density(cap)
        t |> success(density_text |> contains("| Per 1000 lines ") && density_text |> contains(" hand/plmpeg-stream |"), density_text)
        t |> success(density_text |> contains("| casts ") && density_text |> contains("**total**") && density_text |> contains("**das-side**"), density_text)
        t |> success(density_text |> contains(" programs "), density_text)
        let lengths_text = render_lengths(cap)
        t |> success(lengths_text |> contains("| Function lengths ") && lengths_text |> contains("| functions ") && lengths_text |> contains("| over 100 lines "), lengths_text)
        t |> success(lengths_text |> contains("| das/C median ") && lengths_text |> contains("n/a"), lengths_text)
        t |> success(!(lengths_text |> contains(" programs ")), lengths_text)
    }
    t |> run("the fold verdicts: every outermost expansion, the folded ones and the faulting-argument ones, each a line of the length table") @(t : T?) {
        var counts : table<string; int>
        fold_counts({"folded" => 7, "faulting" => 2, "effects" => 1}, counts)
        t |> equal(counts?["macro_sites"] ?? -1, 10)
        t |> equal(counts?["macro_folded"] ?? -1, 7)
        t |> equal(counts?["macro_faulting"] ?? -1, 2)
        var none : table<string; int>
        fold_counts(default<table<string; int>>, none)
        t |> equal(none?["macro_sites"] ?? -1, 0)
        t |> equal(none?["macro_faulting"] ?? -1, 0)
        var cap <- sample_capture()
        cap.rows["lua/lua"]["macro_sites"] = 11392
        cap.rows["lua/lua"]["macro_folded"] = 2604
        cap.rows["lua/lua"]["macro_faulting"] = 224
        let lengths_text = render_lengths(cap)
        t |> success(lengths_text |> contains("| macro sites ") && lengths_text |> contains(" 11392 |"), lengths_text)
        t |> success(lengths_text |> contains("| macro sites folded ") && lengths_text |> contains(" 2604 |"), lengths_text)
        t |> success(lengths_text |> contains("| faulting arguments ") && lengths_text |> contains(" 224 |"), lengths_text)
    }
    t |> run("the density delta: main, now and the signed difference over `programs`; a base before the density keys says so") @(t : T?) {
        var before <- sample_capture()
        before.rows["lua/lua"]["das_code_lines"] = 1000
        before.rows["lua/lua"]["cast_sites"] = 100
        var after := before
        after.rows["lua/lua"]["cast_sites"] = 50
        let delta = render_density_delta(before, after)
        t |> success(delta |> contains("| casts ") && delta |> contains("100.0 |") && delta |> contains("50.0 |") && delta |> contains("-50.0 |"), delta)
        t |> success(delta |> contains("**total**") && delta |> contains("**das-side**"), delta)
        var old := before
        old.lacks <- ["c_files", "density"]
        t |> success(render_density_delta(old, after) |> contains("| casts "), "a base lacking only the coverage keys and the section still gives a delta")
        old.lacks <- ["cast_sites"]
        t |> success(render_density_delta(old, after) |> starts_with("no density delta: the base capture predates the keys cast_sites"))
    }
    t |> run("the delta: main, now and the signed difference on the `all` column") @(t : T?) {
        var after <- sample_capture()
        after.rows["csmith"]["das_comments_carried"] = 2
        let delta = render_delta(sample_capture(), after)
        t |> success(delta |> contains("| comments "), delta)
        t |> success(delta |> contains("25.0 |") && delta |> contains("50.0 |") && delta |> contains("+25.0 |"), delta)
        t |> success(delta |> contains("n/a"), delta)
        let same = render_delta(after, after)
        t |> success(same |> contains("| 0.0 |") || same |> contains("|   0.0 |") || same |> contains(" 0.0 |"), same)
        let fell = render_delta(after, sample_capture())
        t |> success(fell |> contains("-25.0 |"), fell)
    }
}

[test]
def test_worker_file(t : T?) {
    t |> run("the worker file reads back as written, its ratios included") @(t : T?) {
        let raw = CriteriaRaw(counts <- full_raw(2), ratios <- [50, 150], lengths <- [3, 40])
        var error : string
        let back <- read_result_text(result_text(raw, ""), error)
        t |> equal(error, "")
        t |> equal(back.counts?["fn_matched"] ?? 0, 2)
        t |> equal(back.ratios, [50, 150])
        t |> equal(back.lengths, [3, 40])
    }
    t |> run("an error keeps its text on one line; a file with no status is an error") @(t : T?) {
        var error : string
        read_result_text(result_text(CriteriaRaw(), "convert: no\nmore"), error)
        t |> equal(error, "convert: no more")
        var none : string
        read_result_text("", none)
        t |> equal(none, "no result")
    }
    t |> run("the sample: every key measured as recorded, or the keys that differ named") @(t : T?) {
        let cap <- sample_capture()
        var fresh <- {for (k in SAMPLE_KEYS); k => full_raw(1)}
        let no_failures : table<string; string>
        var committed := cap
        for (k in SAMPLE_KEYS) {
            committed.sample[k] <- full_raw(1)
        }
        t |> equal(length(sample_freshness(committed, fresh, no_failures)), 1)
        t |> success(sample_freshness(committed, fresh, no_failures)[0] |> starts_with("sample: the 4 sample inputs"))
        fresh[SAMPLE_KEYS[0]]["modules"] = 7
        let stale <- sample_freshness(committed, fresh, no_failures)
        t |> equal(length(stale), 1)
        t |> success(stale[0] |> contains("stale: {SAMPLE_KEYS[0]}") && stale[0] |> contains("(modules)"), stale[0])
    }
}

// the worker run on one input key, and the result file it wrote; `rust` the Rust checkout it reads
// the compare projects from, `hand` the folder of the plmpeg hand port, each its default when ""
def private run_worker(key : string; var result : string&; rust : string = ""; hand : string = "") : int {
    var argv <- empty(rust) && empty(hand) ? array<string>() : ["env"]
    if (!empty(rust)) {
        argv |> push("C2DAS_RUST={rust}")
    }
    if (!empty(hand)) {
        argv |> push("C2DAS_HAND_PLMPEG={hand}")
    }
    argv |> push_from(daslang_cmd(CONVERTED_MODULES), ["metrics/criteria.das", "--", "--one", key])
    var out : string
    let rc = run_and_capture(argv, out, 300.0)
    let path = "metrics/work/{key}/criteria.txt"
    result = fexist(path) ? fread(path) : out
    return rc
}

[test]
def test_failed_sample(t : T?) {
    t |> run("an input that does not convert is an error line, and the gate names it failed, not stale") @(t : T?) {
        var result : string
        t |> equal(run_worker("c_testsuite/no_such_test", result), 0)
        t |> success(result |> starts_with("error convert: "), result)
        var error : string
        read_result_text(result, error)
        let failed <- {SAMPLE_KEYS[0] => error}
        let fresh <- {for (k in SAMPLE_KEYS); k => full_raw(1); where k != SAMPLE_KEYS[0]}
        var committed <- sample_capture()
        for (k in SAMPLE_KEYS) {
            committed.sample[k] <- full_raw(1)
        }
        let lines <- sample_freshness(committed, fresh, failed)
        t |> equal(length(lines), 1)
        t |> success(lines[0] |> starts_with("failed: {SAMPLE_KEYS[0]}: convert: "), lines[0])
    }
}

[test]
def test_fold_worker(t : T?) {
    t |> run("the worker records the conversion's fold verdicts: FOO's two expansions in 00066 are sites, both folded") @(t : T?) {
        var result : string
        t |> equal(run_worker("c_testsuite/00066", result), 0)
        t |> success(result |> starts_with("ok\n"), result)
        t |> equal(count_of(result, "macro_sites"), 2)
        t |> equal(count_of(result, "macro_folded"), 2)
        t |> equal(count_of(result, "macro_faulting"), 0)
    }
}

// the gate run in `dir` as its working directory, its output in `out`
def private run_gate(dir : string; var out : string&) : int {
    var argv <- ["bash", "-c", "cd \"$1\" && shift && \"$@\" 2>&1", "gate", dir]
    argv |> push_from(daslang_cmd([for (m in CONVERTED_MODULES); get_full_file_name(m)]), [get_full_file_name("metrics/criteria.das"), "--", "--report", "--delta-ref", "HEAD"])
    return run_and_capture(argv, out, 300.0)
}

[test]
def test_gate(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_criteria_gate", dir_error)
    t |> equal(dir_error, "")
    mkdir_rec(path_join(dir, "metrics"))
    let capture_path = path_join(dir, "metrics/criteria_linux.json")
    t |> run("missing: the gate is red and says to record") @(t : T?) {
        var out : string
        t |> equal(run_gate(dir, out), 1, out)
        t |> success(out |> contains("metrics/criteria_linux.json is missing"), out)
    }
    t |> run("unreadable: the gate is red and names the finding") @(t : T?) {
        fwrite(capture_path, "[1]")
        var out : string
        t |> equal(run_gate(dir, out), 1, out)
        t |> success(out |> contains("not a JSON object"), out)
    }
    t |> run("present: the gate prints the table, no delta outside a repository, and is green") @(t : T?) {
        fwrite(capture_path, criteria_text(sample_capture()))
        var out : string
        t |> equal(run_gate(dir, out), 0, out)
        t |> success(out |> contains("**Readability criteria**") && out |> contains("**total**"), out)
        t |> success(out |> contains("no capture at HEAD: no delta"), out)
        t |> success(out |> contains("sample: not re-measured"), out)
    }
    rmdir_rec(dir)
}

// a stand-in Rust checkout under `dir`: binjgb converts whole from its `all.c` graph, wasm3's graph
// holds a variable-length array, so it converts file by file, one file refused
def private stand_in_rust(dir : string) {
    let cases = "\{\"cases\": [\{\"id\": \"binjgb-cgb-acid2-std\", \"expected\": \{\"stdout\": \"\"\}\}, \{\"id\": \"wasm3-fib32-std\", \"expected\": \{\"stdout\": \"\"\}\}]\}\n"
    mkdir_rec(path_join(dir, "tests/canonical"))
    fwrite(path_join(dir, "tests/canonical/cases.json"), cases)
    let files <- [
        (path = "binjgb/src/binjgb_all.c", text = "#include \"all.c\"\n#include \"entry.c\"\n"),
        (path = "binjgb/src/all.c", text = "#include \"cpu.c\"\n"),
        (path = "binjgb/src/entry.c", text = "#include \"cpu.h\"\nint main(void) \{ return step(MAX_STEPS); \}\n"),
        (path = "binjgb/upstream/binjgb/src/cpu.h", text = "#define MAX_STEPS 40\nint step(int n);\n"),
        (path = "binjgb/upstream/binjgb/src/cpu.c", text = "#include \"cpu.h\"\n#define LIB_IMPLEMENTATION\n#include \"lib.h\"\n// one step\nint step(int n) \{ return twice(n) > MAX_STEPS ? 0 : n; \}\n"),
        (path = "binjgb/upstream/binjgb/src/lib.h", text = "int twice(int x);\n#ifdef LIB_IMPLEMENTATION\n// doubled\nint twice(int x) \{ return 2 * x; \}\n#endif\n"),
        (path = "wasm3/src/all_host.c", text = "#include \"all.c\"\n#include \"host.c\"\n"),
        (path = "wasm3/src/all.c", text = "#include \"m3_add.c\"\n#include \"m3_vla.c\"\n"),
        (path = "wasm3/src/host.c", text = "int main(void) \{ return 0; \}\n"),
        (path = "wasm3/upstream/wasm3/source/m3_add.c", text = "int add(int a, int b) \{ return a + b; \}\n"),
        (path = "wasm3/upstream/wasm3/source/m3_vla.c", text = "int first(int n) \{ int a[n + 1]; a[0] = n; return a[0]; \}\n")]
    for (f in files) {
        let path = path_join(dir, "tests/manual/{f.path}")
        mkdir_rec(dir_name(path))
        fwrite(path, f.text)
    }
}

// the raw count `key` of a worker file
def private count_of(result, key : string) : int {
    var error : string
    return read_result_text(result, error).counts?[key] ?? -1
}

[test]
def test_project_worker(t : T?) {
    var dir_error : string
    let rust = create_temp_directory("c2das_criteria_rust", dir_error)
    t |> equal(dir_error, "")
    stand_in_rust(rust)
    t |> run("a project that converts whole is measured over every C file its graph compiles, its include folders followed") @(t : T?) {
        var result : string
        t |> equal(run_worker("project/binjgb", result, rust), 0)
        t |> success(result |> starts_with("ok\n"), result)
        t |> equal(count_of(result, "c_files"), 2, "cpu.c through all.c, and entry.c: {result}")
        t |> equal(count_of(result, "c_files_converted"), 2)
        t |> equal(count_of(result, "c_constant_uses"), 2, "MAX_STEPS of the header in an include folder: {result}")
        t |> equal(count_of(result, "c_comment_lines"), 2, "the single-header implementation's comment counts: {result}")
        t |> equal(count_of(result, "fn_matched"), 3, "step, main and the header's twice: {result}")
        t |> success(fexist("metrics/work/project/binjgb/whole/binjgb_all.das"), "the publisher's whole tree")
    }
    t |> run("a project that refuses whole is measured over the files that convert alone, the coverage recorded") @(t : T?) {
        var result : string
        t |> equal(run_worker("project/wasm3", result, rust), 0)
        t |> success(result |> starts_with("ok\n"), result)
        t |> equal(count_of(result, "c_files"), 3)
        t |> equal(count_of(result, "c_files_converted"), 2)
        t |> equal(count_of(result, "fn_matched"), 2, result)
    }
    t |> run("a project the table lacks, and one the checkout lacks, are errors") @(t : T?) {
        var result : string
        t |> equal(run_worker("project/nethack", result, rust), 0)
        t |> equal(result, "error no compare project nethack\n")
        t |> equal(run_worker("project/doomgeneric", result, rust), 0)
        t |> success(result |> starts_with("error the Rust checkout has no "), result)
    }
    rmdir_rec(rust)
}

[test]
def test_hand_worker(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_criteria_hand", dir_error)
    t |> equal(dir_error, "")
    t |> run("a hand-written port is scanned where its variable points: every .das file, no C side, no conversion") @(t : T?) {
        fwrite(path_join(dir, "a.das"), "def f(p : int?) : int \{\n    return int(deref(p)) + 1\n\}\n")
        fwrite(path_join(dir, "b.das"), "def g : int \{\n    return 2\n\}\n")
        fwrite(path_join(dir, "notes.md"), "not das\n")
        var result : string
        t |> equal(run_worker("hand/plmpeg-stream", result, "", dir), 0)
        t |> success(result |> starts_with("ok\n"), result)
        t |> equal(count_of(result, "modules"), 2)
        t |> equal(count_of(result, "cast_sites"), 1)
        t |> equal(count_of(result, "deref_sites"), 1)
        t |> equal(count_of(result, "fn_total"), 2)
        t |> equal(count_of(result, "c_code_lines"), 0)
        t |> equal(count_of(result, "c_files"), 0)
    }
    t |> run("a folder with no .das file, and a port the table lacks, are errors") @(t : T?) {
        let empty_dir = path_join(dir, "empty")
        mkdir_rec(empty_dir)
        var result : string
        t |> equal(run_worker("hand/plmpeg-stream", result, "", empty_dir), 0)
        t |> equal(result, "error no .das file under {empty_dir}\n")
        t |> equal(run_worker("hand/nethack", result, "", dir), 0)
        t |> equal(result, "error no hand-written port hand/nethack\n")
    }
    rmdir_rec(dir)
}

[test]
def test_worker_argv(t : T?) {
    t |> run("a project's worker raises its soft address-space limit to the hard one; any other worker runs daslang as is") @(t : T?) {
        let argv <- worker_argv("metrics/criteria.das", "project/doomgeneric")
        t |> equal(argv[length(argv) - 1], "project/doomgeneric")
        var probe <- ["prlimit", "--as=1073741824:2147483648"]
        probe |> push_from([for (a, i in argv, count()); a; where i < 4], ["bash", "-c", "ulimit -S -v"])
        var out : string
        t |> equal(run_and_capture(probe, out, 60.0), 0, out)
        t |> equal(strip(out), "2097152")
        let lua <- worker_argv("metrics/criteria.das", "lua/lua")
        t |> equal(lua[0], daslang_cmd(CONVERTED_MODULES)[0])
    }
}

[test]
def test_base_capture(t : T?) {
    t |> run("a delta base recorded before c_files existed reads with them 0; any other finding refuses it") @(t : T?) {
        let text = criteria_text(sample_capture())
        let older = replace(replace(text, "\"c_files\": 0, ", ""), "\"c_files_converted\": 0, ", "")
        t |> success(older != text && !empty(check_criteria(older)), older)
        var error : string
        let base <- base_capture_of_text(older, "main", error)
        t |> equal(error, "")
        t |> equal(length(base.rows), length(sample_capture().rows))
        t |> equal(base.lacks, ["c_files", "c_files_converted"])
        let density_start = find(text, "  \"density\":")
        let before_density = slice(text, 0, density_start) + slice(text, find(text, "  \"raw\":"))
        var section_error : string
        let old <- base_capture_of_text(before_density, "main", section_error)
        t |> equal(section_error, "")
        t |> equal(old.lacks, ["density"])
        var refused : string
        base_capture_of_text(replace(older, "\"fn_matched\": ", "\"fn_unknown\": "), "main", refused)
        t |> success(refused |> starts_with("main: ") && refused |> contains("fn_unknown"), refused)
    }
}

[test]
def test_unary_deref_criteria(t : T?) {
    t |> run("a unary `*` is a deref site and pairs as `deref(` does; a product is none") @(t : T?) {
        let c = in_f("    *p = **pp + *q\n    x = addr(*p) + *addr(a[0])\n    return *r")
        t |> equal(got(c, "deref_sites"), 7)
        t |> equal(got(c, "addr_deref_sites"), 2)
        let products = in_f("    x = a * b + (c) * d + f(e) * g + h[0] * *p\n    y *= 2")
        t |> equal(got(products, "deref_sites"), 1)
    }
}

[test]
def test_int_of_criteria(t : T?) {
    t |> run("`int_of(c)` is a bool round trip, as the `c ? 1 : 0` it expands to; a field or a longer name is none") @(t : T?) {
        t |> equal(got(in_f("    x = int_of(a < b) + (c ? 1 : 0)"), "bool_roundtrip_sites"), 2)
        t |> equal(got(in_f("    x = s.int_of + int_of_x(a)"), "bool_roundtrip_sites"), 0)
    }
}
