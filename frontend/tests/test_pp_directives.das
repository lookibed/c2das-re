options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require ../pp_directives.das
require ../c_defines.das

//! `frontend/pp_directives.das`: the directives and the `#include` stack over in-memory files, the
//! predefined-macro table and the own headers through `fio`.

// a preprocessor over the in-memory `files` (path, text pairs), started at `main`
def private started(files : array<tuple<string; string>>; main : string = "main.c"; predefines : array<string> = array<string>();
                    search : array<string> = array<string>()) : Preprocessor {
    var mem = new PpMemoryProvider()
    for (f in files) {
        mem->add(f._0, f._1)
    }
    var pp : Preprocessor
    pp_start(pp, mem, main, predefines, search)
    return <- pp
}

// every token the preprocessor hands out, spelled, a blank between them
def private stream(var pp : Preprocessor) : string {
    var parts : array<string>
    while (pp_next_token(pp)) {
        parts |> push(pp_token_spelling(pp))
    }
    return join(parts, " ")
}

// the tokens of `main.c` holding `text` and of the other `files`
def private preprocessed(text : string; files : array<tuple<string; string>> = array<tuple<string; string>>()) : string {
    var all <- [("main.c", text)]
    all |> push_from(files)
    var pp <- started(all)
    return stream(pp)
}

// every diagnostic, `<W|E> <line>:<col> <what>`, a `|` between them
def private diagnostics(pp : Preprocessor) : string {
    let parts <- [for (d in pp.diags); "{d.severity == PpSeverity.error ? "E" : "W"} {d.line}:{d.col} {d.what}"]
    return join(parts, " | ")
}

// the inclusions, `<spelled>:<path or ->:<skip>`
def private inclusions(pp : Preprocessor) : string {
    let parts <- [for (inc in pp.inclusions); "{inc.spelled}:{inc.file >= 0 ? pp.files[inc.file].path : "-"}:{inc.skip}"]
    return join(parts, " ")
}

[test(description = "a line that is no directive passes through as its tokens, placed in their physical file, and a directive line leaves no token")]
def test_pass_through(t : T?) {
    var pp <- started([("main.c", "int x;\n#define A 1\n  y = A;\n")])
    var placed : array<string>
    while (pp_next_token(pp)) {
        placed |> push("{pp_token_spelling(pp)}@{pp.tok.tok.line}:{pp.tok.tok.col}{pp.tok.tok.at_bol ? "^" : ""}")
    }
    t |> equal(join(placed, " "), "int@1:1^ x@1:5 ;@1:6 y@3:3^ =@3:5 A@3:7 ;@3:8")
    t |> equal(pp.emitted, 7)
    t |> equal(diagnostics(pp), "")
}

[test(description = "a quoted name is searched in the includer's directory first, then the include path in order; an angled name skips the includer's directory")]
def test_search_order(t : T?) {
    let files <- [("src/main.c", "#include \"x.h\"\n#include <x.h>\n#include <y.h>\n#include \"sub/z.h\"\n"),
                  ("src/x.h", "src_x\n"), ("inc1/x.h", "inc1_x\n"), ("inc2/x.h", "inc2_x\n"), ("inc2/y.h", "inc2_y\n"),
                  ("src/sub/z.h", "#include \"w.h\"\n"), ("src/sub/w.h", "sub_w\n"), ("src/w.h", "src_w\n")]
    var pp <- started(files, "src/main.c", array<string>(), ["inc1", "inc2"])
    t |> equal(stream(pp), "src_x inc1_x inc2_y sub_w")
    t |> equal(inclusions(pp), "\"x.h\":src/x.h:none <x.h>:inc1/x.h:none <y.h>:inc2/y.h:none \"sub/z.h\":src/sub/z.h:none \"w.h\":src/sub/w.h:none")
}

[test(description = "#include_next searches the include path after the folder the including file was found in")]
def test_include_next(t : T?) {
    let files <- [("main.c", "#include <x.h>\n"), ("a/x.h", "a_x\n#include_next <x.h>\n"), ("b/x.h", "b_x\n")]
    var pp <- started(files, "main.c", array<string>(), ["a", "b"])
    t |> equal(stream(pp), "a_x b_x")
    var main_next <- started([("main.c", "#include_next <x.h>\n"), ("a/x.h", "a_x\n")], "main.c", array<string>(), ["a"])
    t |> equal(stream(main_next), "a_x")
    t |> equal(diagnostics(main_next), "W 1:15 #include_next in primary source file")
}

[test(description = "a missing file is an error naming the folders searched; the line after it is read")]
def test_missing_file(t : T?) {
    var pp <- started([("src/main.c", "#include \"nope.h\"\n#include <gone.h>\nafter\n")], "src/main.c", array<string>(), ["inc"])
    t |> equal(stream(pp), "after")
    t |> equal(diagnostics(pp), "E 1:10 'nope.h' file not found; searched: src, inc | E 2:10 'gone.h' file not found; searched: inc")
    t |> equal(inclusions(pp), "\"nope.h\":-:not_found <gone.h>:-:not_found")
    var empty_name <- started([("main.c", "#include \"\"\n#include\n#include \"a.h\" extra\n"), ("a.h", "a\n")])
    t |> equal(stream(empty_name), "a")
    t |> equal(diagnostics(empty_name), "E 1:10 empty filename | E 2:2 expected \"FILENAME\" or <FILENAME> | W 3:16 extra tokens at end of #include directive")
}

[test(description = "a file with #pragma once is read once; a second #include of it is skipped and recorded so")]
def test_pragma_once(t : T?) {
    let files <- [("main.c", "#include \"a.h\"\n#include \"./a.h\"\n#include \"a.h\"\nend\n"), ("a.h", "#pragma once\nonce_a\n")]
    var pp <- started(files)
    t |> equal(stream(pp), "once_a end")
    t |> equal(inclusions(pp), "\"a.h\":a.h:none \"./a.h\":a.h:pragma_once \"a.h\":a.h:pragma_once")
    t |> equal(length(pp.pragmas), 0)
    var main_once <- started([("main.c", "#pragma once\nx\n")])
    t |> equal(stream(main_once), "x")
    t |> equal(diagnostics(main_once), "W 1:2 #pragma once in main file")
}

[test(description = "a whole-file #ifndef/#define/#endif guard is recorded, so a second #include is skipped unopened while the macro is defined")]
def test_include_guards(t : T?) {
    t |> run("the #ifndef guard and the !defined forms") @(t : T?) {
        let files <- [("main.c", "#include \"a.h\"\n#include \"a.h\"\n#include \"b.h\"\n#include \"b.h\"\n#include \"c.h\"\n#include \"c.h\"\n"),
                      ("a.h", "// leading comment\n#ifndef A_H\n#define A_H\na\n#endif\n// trailing comment\n"),
                      ("b.h", "#if !defined(B_H)\n#define B_H\nb\n#endif\n"), ("c.h", "#if !defined C_H\n#define C_H\nc\n#endif\n")]
        var pp <- started(files)
        t |> equal(stream(pp), "a b c")
        t |> equal(inclusions(pp), "\"a.h\":a.h:none \"a.h\":a.h:guard \"b.h\":b.h:none \"b.h\":b.h:guard \"c.h\":c.h:none \"c.h\":c.h:guard")
        let a_h = pp.file_of?["a.h"] ?? -1
        t |> equal(pp_name(pp, pp.files[a_h].guard), "A_H")
        t |> equal(pp.files[a_h].entered, 1)
    }
    t |> run("a file with a token or a directive outside the group, or an #else of it, has no guard and is read again") @(t : T?) {
        let files <- [("main.c", "#include \"t.h\"\n#include \"t.h\"\n#include \"d.h\"\n#include \"d.h\"\n#include \"e.h\"\n#include \"e.h\"\n"),
                      ("t.h", "#ifndef T_H\n#define T_H\n#endif\nt\n"), ("d.h", "#define D 1\n#ifndef D_H\n#define D_H\n#endif\nd\n"),
                      ("e.h", "#ifndef E_H\n#define E_H\n#else\ne\n#endif\n")]
        var pp <- started(files)
        t |> equal(stream(pp), "t t d d e")
        t |> equal(inclusions(pp), "\"t.h\":t.h:none \"t.h\":t.h:none \"d.h\":d.h:none \"d.h\":d.h:none \"e.h\":e.h:none \"e.h\":e.h:none")
        for (f in pp.files) {
            t |> equal(f.guard, -1, f.path)
        }
    }
    t |> run("a nested conditional inside the guard keeps it; an #undef of the guard macro reopens the file") @(t : T?) {
        let files <- [("main.c", "#include \"n.h\"\n#include \"n.h\"\n#undef N_H\n#include \"n.h\"\n"),
                      ("n.h", "#ifndef N_H\n#define N_H\n#if 1\nn\n#else\nm\n#endif\n#endif\n")]
        var pp <- started(files)
        t |> equal(stream(pp), "n n")
        t |> equal(inclusions(pp), "\"n.h\":n.h:none \"n.h\":n.h:guard \"n.h\":n.h:none")
    }
}

[test(description = "#include nests at most 200 files deep, as clang allows; the include past it is an error and skipped")]
def test_depth_limit(t : T?) {
    var pp <- started([("main.c", "#include \"self.h\"\nend\n"), ("self.h", "x\n#include \"self.h\"\n")])
    var x = 0
    var last = ""
    while (pp_next_token(pp)) {
        last = pp_token_spelling(pp)
        x += last == "x" ? 1 : 0
    }
    t |> equal(x, PP_MAX_INCLUDE_DEPTH - 1)
    t |> equal(last, "end")
    t |> equal(length(pp.diags), 1)
    t |> equal(pp.diags[0].what, "#include nested depth 200 exceeds maximum of 200")
    t |> equal(pp.inclusions[length(pp.inclusions) - 1].skip, PpIncludeSkip.too_deep)
}

[test(description = "#line N \"name\" makes the next line report line N of the file name, a GNU line marker too, until the file ends; the physical place stays")]
def test_line(t : T?) {
    let files <- [("main.c", "a\n#line 100\nb\n\nc\n#line 7 \"other.c\"\nd\n# 40 \"marked.c\" 1 3\ne\n#include \"h.h\"\nf\n"), ("h.h", "h\n")]
    var pp <- started(files)
    var placed : array<string>
    while (pp_next_token(pp)) {
        placed |> push("{pp_token_spelling(pp)}:{pp.names[pp.tok.pname]}:{pp.tok.pline}/{pp.tok.tok.line}")
    }
    t |> equal(join(placed, " "), "a:main.c:1/1 b:main.c:100/3 c:main.c:102/5 d:other.c:7/7 e:marked.c:40/9 h:h.h:1/1 f:marked.c:42/11")
    var bad <- started([("main.c", "#line 0x10\n#line 2147483648\n#line 5 L\"w\"\n#line\n#line 9 \"n\" z\n#line N\ny\n")])
    t |> equal(stream(bad), "y")
    t |> equal(diagnostics(bad), "E 1:7 #line directive requires a simple digit sequence | E 2:7 line number out of range | E 3:9 invalid filename for #line directive | E 4:2 #line directive requires a positive integer argument | W 5:13 extra tokens at end of #line directive | E 6:2 #line of macro-expanded tokens needs PP.3: N")
    t |> equal(pp.diags |> length, 0)
}

[test(description = "nested conditionals take one group each, a skipped group's directives only nest, and misplaced ones are errors")]
def test_conditionals(t : T?) {
    t |> run("groups taken and skipped, nesting inside a skipped group") @(t : T?) {
        let text = "#if 0\n#if 1\nno1\n#else\nno2\n#endif\n#define HIDDEN 1\n#error never\n#bogus\n#elif 1\nyes1\n#ifdef HIDDEN\nno3\n#elif 0\nno4\n#else\nyes2\n#endif\n#elif 1\nno5\n#else\nno6\n#endif\n"
        var pp <- started([("main.c", text)])
        t |> equal(stream(pp), "yes1 yes2")
        t |> equal(diagnostics(pp), "")
        t |> equal(pp_macro_index(pp, "HIDDEN"), -1)
    }
    t |> run("#ifdef, #ifndef, #elifdef and #elifndef ask the macro table") @(t : T?) {
        t |> equal(preprocessed("#define A\n#ifdef A\na\n#endif\n#ifndef A\nna\n#endif\n#ifdef B\nb\n#elifdef A\nea\n#endif\n#if 0\n#elifndef B\nenb\n#endif\n"), "a ea enb")
    }
    t |> run("an #else or #elif after #else, an #endif or #else without #if, and an open #if at the end are errors") @(t : T?) {
        var pp <- started([("main.c", "#if 1\na\n#else\nb\n#else\nc\n#elif 1\n#endif\n#endif\n#else\n#if 1\nd\n")])
        t |> equal(stream(pp), "a d")
        t |> equal(diagnostics(pp), "E 5:2 #else after #else | E 7:2 #elif after #else | E 9:2 #endif without #if | E 10:2 #else without #if | E 11:2 unterminated conditional directive")
    }
    t |> run("a conditional open at the end of an included file is closed there, not in its includer") @(t : T?) {
        var pp <- started([("main.c", "#include \"h.h\"\nm\n#endif\n"), ("h.h", "#if 0\n")])
        t |> equal(stream(pp), "m")
        t |> equal(diagnostics(pp), "E 1:2 unterminated conditional directive | E 3:2 #endif without #if")
    }
    t |> run("tokens after #endif, #else, #ifdef and #undef are a warning and never reach the stream") @(t : T?) {
        var pp <- started([("main.c", "#ifdef A B\n#else C\nx\n#endif D\n#undef A B\n")])
        t |> equal(stream(pp), "x")
        t |> equal(diagnostics(pp), "W 1:10 extra tokens at end of #ifdef directive | W 2:7 extra tokens at end of #else directive | W 4:8 extra tokens at end of #endif directive | W 5:10 extra tokens at end of #undef directive")
    }
}

[test(description = "the #if evaluator reads 0, 1 and defined until PP.4; any other expression is a diagnostic naming PP.4 and false")]
def test_if_hook(t : T?) {
    t |> equal(preprocessed("#define X\n#if defined X\na\n#endif\n#if defined(X)\nb\n#endif\n#if !defined(Y)\nc\n#endif\n#if !!1\nd\n#endif\n#if 0\ne\n#endif\n"), "a b c d")
    var pp <- started([("main.c", "#if X > 1\nno\n#elif 1\nyes\n#endif\n#if\n#endif\n")])
    t |> equal(stream(pp), "yes")
    t |> equal(diagnostics(pp), "E 1:2 #if expression needs the PP.4 evaluator: X > 1 | E 6:2 #if with no expression")
}

[test(description = "#ifdef sees the predefined-macro table of the linux dialect, defined before the first line")]
def test_predefined(t : T?) {
    var error : string
    var entries <- read_predefined(predefined_path("linux"), error)
    t |> equal(error, "")
    entries |> push("FROM_SIDECAR")
    var pp <- started([("main.c", "#ifdef __linux__\nlinux\n#endif\n#ifdef __clang__\nclang\n#endif\n#ifdef __STDC_NO_VLA__\nnovla\n#endif\n#ifdef FROM_SIDECAR\nsidecar\n#endif\n")], "main.c", entries)
    t |> equal(stream(pp), "linux novla sidecar")
    t |> equal(diagnostics(pp), "")
    let version = pp_macro_index(pp, "__STDC_VERSION__")
    t |> success(version >= 0)
    t |> equal(pp_macro_body_text(pp, pp.macros[version]), "201710L")
    t |> equal(pp.names[pp.files[pp.macros[version].file].name], PP_BUILTIN_NAME)
    t |> equal(pp_macro_body_text(pp, pp.macros[pp_macro_index(pp, "FROM_SIDECAR")]), "1")
}

[test(description = "#define stores object-like and function-like macros as token lists with their parameters and variadic marker, unexpanded")]
def test_define(t : T?) {
    var pp <- started([("main.c", "#define OBJ (1 +  2)\n#define F(a, b, ...) a ## b # a __VA_ARGS__\n#define G(args...) g(args)\n#define H (x) x\n#define E\n#define Z() z\n#undef E\nOBJ F\n")])
    t |> equal(stream(pp), "OBJ F")
    t |> equal(diagnostics(pp), "")
    let obj := pp.macros[pp_macro_index(pp, "OBJ")]
    t |> success(!obj.function_like)
    t |> equal(pp_macro_body_text(pp, obj), "(1 + 2)")
    t |> equal("{obj.line}:{obj.col}", "1:9")
    let f := pp.macros[pp_macro_index(pp, "F")]
    t |> success(f.function_like && f.variadic)
    t |> equal(join([for (p in f.params); pp_name(pp, p)], ","), "a,b,__VA_ARGS__")
    t |> equal(pp_macro_body_text(pp, f), "a ## b # a __VA_ARGS__")
    let g := pp.macros[pp_macro_index(pp, "G")]
    t |> success(g.variadic)
    t |> equal(join([for (p in g.params); pp_name(pp, p)], ","), "args")
    let h := pp.macros[pp_macro_index(pp, "H")]
    t |> success(!h.function_like)
    t |> equal(pp_macro_body_text(pp, h), "(x) x")
    t |> equal(pp_macro_index(pp, "E"), -1)
    t |> equal(length(pp.macros[pp_macro_index(pp, "Z")].params), 0)
    t |> equal(length(pp.macros), 6)
}

[test(description = "a malformed #define is an error and defines nothing; a different redefinition warns, an identical one does not")]
def test_define_errors(t : T?) {
    var pp <- started([("main.c", "#define\n#define 1\n#define defined\n#define A(x, x)\n#define B(x\n#define C(x y)\n#define D(1)\n#define E(...) # __VA_ARGS__\n#define F(x) # y\n#define G ## x\n#define H x ##\n#define I(__VA_ARGS__)\n#define R 1\n#define R  1\n#define R 2\n")])
    t |> equal(stream(pp), "")
    t |> equal(diagnostics(pp), "E 1:2 macro name missing | E 2:9 macro name must be an identifier | E 3:9 'defined' cannot be used as a macro name | E 4:14 duplicate macro parameter name | E 5:11 missing ')' in macro parameter list | E 6:13 expected comma in macro parameter list | E 7:11 invalid token in macro parameter list | E 9:2 '#' is not followed by a macro parameter | E 10:2 '##' cannot appear at either end of a macro expansion | E 11:2 '##' cannot appear at either end of a macro expansion | E 12:11 __VA_ARGS__ can only appear in the expansion of a C99 variadic macro | W 15:2 'R' macro redefined")
    t |> equal(join([for (m in pp.macros); pp_name(pp, m.name)], ","), "E,R,R,R")
}

[test(description = "#error and #warning are diagnostics at their place carrying their text, and the preprocessor reads on")]
def test_error_warning(t : T?) {
    var pp <- started([("main.c", "a\n  #error  bad   thing \"here\"\n#warning careful\nb\n")])
    t |> equal(stream(pp), "a b")
    t |> equal(diagnostics(pp), "E 2:4 #error bad thing \"here\" | W 3:2 #warning careful")
}

[test(description = "the null directive is nothing, an unknown directive is an error and its line is dropped")]
def test_null_and_unknown(t : T?) {
    var pp <- started([("main.c", "#\n# /* c */\n#bogus x y\n#ident \"v\"\n# \"s\"\nz\n")])
    t |> equal(stream(pp), "z")
    t |> equal(diagnostics(pp), "E 3:2 invalid preprocessing directive | E 4:2 invalid preprocessing directive | E 5:3 invalid preprocessing directive")
}

[test(description = "an #include whose tokens are no header name is left for PP.3's expansion: a diagnostic, its tokens recorded")]
def test_include_needs_expansion(t : T?) {
    var pp <- started([("main.c", "#define HDR <a.h>\n#include HDR\nx\n"), ("a.h", "a\n")])
    t |> equal(stream(pp), "x")
    t |> equal(diagnostics(pp), "E 2:2 #include of macro-expanded tokens needs PP.3: HDR")
    t |> equal(inclusions(pp), "HDR:-:needs_expansion")
}

[test(description = "every #pragma but once and pack lands in the pragma ledger with its tokens, its place and the tokens before it")]
def test_pragma_ledger(t : T?) {
    var pp <- started([("main.c", "a b\n#pragma warning(disable : 4996)\nc\n#  pragma GCC system_header\n#pragma\n")])
    t |> equal(stream(pp), "a b c")
    let rows <- [for (p in pp.pragmas); "{p.line}:{p.col}@{p.emitted} {p.text}"]
    t |> equal(join(rows, " | "), "2:2@2 warning(disable : 4996) | 4:4@3 GCC system_header | 5:2@3 ")
}

[test(description = "#pragma push_macro and pop_macro save and restore a name's definition, an undefined name included, and stay out of the ledger")]
def test_push_pop_macro(t : T?) {
    var pp <- started([("main.c", "#define A 1\n#pragma push_macro(\"A\")\n#undef A\n#define A 2\n#pragma push_macro(\"A\")\n#pragma push_macro(\"U\")\n#define U\n#pragma pop_macro(\"U\")\n#pragma pop_macro(\"A\")\n#pragma pop_macro(\"A\")\n#pragma pop_macro(\"A\")\n#pragma push_macro(A)\n")])
    t |> equal(stream(pp), "")
    t |> equal(pp_macro_body_text(pp, pp.macros[pp_macro_index(pp, "A")]), "1")
    t |> equal(pp_macro_index(pp, "U"), -1)
    t |> equal(length(pp.pragmas), 0)
    t |> equal(diagnostics(pp), "W 12:2 malformed #pragma push_macro, ignored")
}

[test(description = "#pragma pack lands in the pack ledger: set, reset, push and pop with a tag or a value, the alignment in force after each")]
def test_pack_ledger(t : T?) {
    var pp <- started([("main.c", "#pragma pack(4)\n#pragma pack(push, 1)\n#pragma pack(push, outer, 2)\n#pragma pack(push)\n#pragma pack(pop, outer)\n#pragma pack(pop)\n#pragma pack()\n#pragma pack(show)\n#pragma pack(3)\n#pragma pack 1\n")])
    t |> equal(stream(pp), "")
    let rows <- [for (p in pp.packs); "{p.action} {p.value} {p.tag} -> {p.current}"]
    t |> equal(join(rows, " | "), "set 4  -> 4 | push 1  -> 1 | push 2 outer -> 2 | push 0  -> 2 | pop 0 outer -> 1 | pop 0  -> 4 | reset 0  -> 0 | show 0  -> 0")
    t |> equal(diagnostics(pp), "W 9:2 malformed #pragma pack, ignored: pack(3) | W 10:2 malformed #pragma pack, ignored: pack 1")
    t |> equal(length(pp.pragmas), 0)
}

[test(description = "the fio provider reads the own headers: <stdio.h> through own_include_dir, each guarded header read once")]
def test_fio_own_headers(t : T?) {
    var error : string
    let entries <- read_predefined(predefined_path("linux"), error)
    let dir = own_include_dir()
    var pp : Preprocessor
    var provider = new PpFioProvider()
    let unit = "{dir}/stdio.h"
    t |> success(pp_start(pp, provider, unit, entries, [dir]))
    var count = 0
    while (pp_next_token(pp)) {
        count++
    }
    t |> success(count > 50)
    t |> equal(diagnostics(pp), "")
    t |> equal(inclusions(pp), "<stddef.h>:{dir}/stddef.h:none <bits/gnuc_va_list.h>:{dir}/bits/gnuc_va_list.h:none")
    t |> equal(pp_name(pp, pp.files[0].guard), "_STDIO_H")
    var missing : Preprocessor
    t |> success(!pp_start(missing, new PpMemoryProvider(), "none.c", array<string>(), array<string>()))
    t |> equal(missing.diags[0].what, "cannot read none.c")
}

[test(description = "a path is one key with its `.` components and `name/..` pairs removed")]
def test_normalized_path(t : T?) {
    t |> equal(normalized_path("./a/./b/../c.h"), "a/c.h")
    t |> equal(normalized_path("/x//y/../z"), "/x/z")
    t |> equal(normalized_path("../a/../../b"), "../../b")
}
