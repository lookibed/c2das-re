options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require daslib/fio
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

// every diagnostic, `<W|E|F> <line>:<col> <what>`, a `|` between them
def private diagnostics(pp : Preprocessor) : string {
    let parts <- [for (d in pp.diags); "{d.severity == PpSeverity.fatal ? "F" : d.severity == PpSeverity.error ? "E" : "W"} {d.line}:{d.col} {d.what}"]
    return join(parts, " | ")
}

// the pragma ledger, `<line>:<col>@<emitted> <text>` each, an `#ident` entry marked so
def private pragma_rows(pp : Preprocessor) : string {
    let rows <- [for (p in pp.pragmas); "{p.line}:{p.col}@{p.emitted} {p.ident ? "ident " : ""}{p.text}"]
    return join(rows, " | ")
}

// the pack ledger, `<action> <value> <tag> -> <current>` each
def private pack_rows(pp : Preprocessor) : string {
    let rows <- [for (p in pp.packs); "{p.action} {p.value} {p.tag} -> {p.current}"]
    return join(rows, " | ")
}

// `text` written to the file `path`
def private write_text(path, text : string) {
    fopen(path, "wb") $(f) {
        fwrite(f, text)
    }
}

// a provider whose files all exist and only `main.c` reads: an #include of any other name finds a
// file it cannot read
class ReadFailsProvider : PpFileProvider {
    def override exists(path : string) : bool => true
    def override identity(path : string) : string => path
    def override read(path : string; var bytes : array<uint8>) : bool {
        return false if (path != "main.c")
        let text = "#include \"x.h\"\nafter\n"
        bytes |> reserve(length(text) + 1)
        peek_data(text) $(chars) {
            for (c in chars) {
                bytes |> push(c)
            }
        }
        return true
    }
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

[test(description = "a missing file is a fatal error naming the folders searched, and the unit ends there, as clang's compile ends")]
def test_missing_file(t : T?) {
    var pp <- started([("src/main.c", "before\n#include \"nope.h\"\nafter\n#error never\n#if 1\n")], "src/main.c", array<string>(), ["inc"])
    t |> equal(stream(pp), "before")
    t |> equal(diagnostics(pp), "F 2:10 'nope.h' file not found; searched: src, inc")
    t |> equal(inclusions(pp), "\"nope.h\":-:not_found")
    var angled <- started([("src/main.c", "#include <gone.h>\nafter\n")], "src/main.c", array<string>(), ["inc"])
    t |> equal(stream(angled), "")
    t |> equal(diagnostics(angled), "F 1:10 'gone.h' file not found; searched: inc")
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
        placed |> push("{pp_token_spelling(pp)}:{pp.names[pp.tok.pname]}:{int64(pp.tok.pline)}/{pp.tok.tok.line}")
    }
    t |> equal(join(placed, " "), "a:main.c:1/1 b:main.c:100/3 c:main.c:102/5 d:other.c:7/7 e:marked.c:40/9 h:h.h:1/1 f:marked.c:42/11")
    var bad <- started([("main.c", "#line 0x10\n#line 4294967296\n#line 5 L\"w\"\n#line\n#line 9 \"n\" z\n#line N\n# 4294967296 \"m\"\ny\n")])
    t |> equal(stream(bad), "y")
    t |> equal(diagnostics(bad), "E 1:7 #line directive requires a simple digit sequence | E 2:7 #line directive requires a positive integer argument | E 3:9 invalid filename for #line directive | E 4:2 #line directive requires a positive integer argument | W 5:13 extra tokens at end of #line directive | E 6:7 #line directive requires a positive integer argument | E 7:3 line marker directive requires a positive integer argument")
    t |> equal(pp.diags |> length, 0)
}

[test(description = "#line takes any number up to 4294967295, clang's unsigned line, and the presumed line wraps past it as clang's does")]
def test_line_unsigned(t : T?) {
    var pp <- started([("main.c", "#line 2147483648\na\n#line 4294967295\nb\nc\n# 4294967295 \"q.c\"\nd\n")])
    var placed : array<string>
    while (pp_next_token(pp)) {
        placed |> push("{pp_token_spelling(pp)}:{pp.names[pp.tok.pname]}:{int64(pp.tok.pline)}")
    }
    t |> equal(join(placed, " "), "a:main.c:2147483648 b:main.c:4294967295 c:main.c:0 d:q.c:4294967295")
    t |> equal(diagnostics(pp), "")
}

[test(description = "a line marker's flag 1 enters a presumed file and its flag 2 leaves it; a flag 2 with no flag 1 before it in the file is an error and the marker is ignored, as clang ignores it")]
def test_line_marker_flags(t : T?) {
    var pp <- started([("main.c", "a\n# 5 \"x.h\" 2\nb\n# 6 \"y.h\" 1\nc\n# 7 \"z.h\" 2\nd\n# 8 \"w.h\" 2\ne\n")])
    var placed : array<string>
    while (pp_next_token(pp)) {
        placed |> push("{pp_token_spelling(pp)}:{pp.names[pp.tok.pname]}:{int64(pp.tok.pline)}")
    }
    t |> equal(join(placed, " "), "a:main.c:1 b:main.c:3 c:y.h:6 d:z.h:7 e:z.h:9")
    t |> equal(diagnostics(pp), "E 2:11 invalid line marker flag '2': cannot pop empty include stack | E 8:11 invalid line marker flag '2': cannot pop empty include stack")
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

[test(description = "#if and #elif ask the evaluator (frontend/pp_eval.das) with no expansion set: an undefined name is 0, and an error skips the group with its diagnostic")]
def test_if_hook(t : T?) {
    t |> equal(preprocessed("#define X\n#if defined X\na\n#endif\n#if defined(X)\nb\n#endif\n#if !defined(Y)\nc\n#endif\n#if !!1\nd\n#endif\n#if 0\ne\n#endif\n"), "a b c d")
    var pp <- started([("main.c", "#if X > 1\nno\n#elif 2 * 3 == 6\nyes\n#endif\n#if\n#endif\n")])
    t |> equal(stream(pp), "yes")
    t |> equal(diagnostics(pp), "E 6:2 expected value in expression")
}

[test(description = "a line marker and a #line read allocate nothing once their names are known: no string and no heap block per marker, a file name stored once, its simple, octal and hex escapes read as clang reads them")]
def test_line_markers_allocate_nothing(t : T?) {
    let markers = "# 5 \"a.c\"\nx\n# 7 \"b\\\\c\\x41\\101\\t.h\" 1\ny\n#line 9\nz\n# 3 \"a.c\" 2\nw\n#line 11 \"a.c\"\nv\n"
    var pp <- started([("main.c", "first\n" + repeat(markers, 500))])
    for (_ in range(6)) {
        t |> success(pp_next_token(pp))
    }
    let strings = int(string_heap_allocation_count())
    let heap = int(heap_allocation_count())
    var count = 0
    while (pp_next_token(pp)) {
        count++
    }
    let strings_used = int(string_heap_allocation_count()) - strings
    let heap_used = int(heap_allocation_count()) - heap
    t |> equal(count, 2495)
    t |> equal(diagnostics(pp), "")
    t |> equal("{strings_used} strings, {heap_used} heap blocks", "0 strings, 0 heap blocks")
    t |> equal(join([for (n in pp.names); n], " "), "main.c <built-in> a.c b\\cAA\t.h")
}

[test(description = "with no expansion set, an #if, #elif or #line naming a macro outside defined's operand records the tokens handed out before it")]
def test_unexpanded_lines(t : T?) {
    var pp <- started([("main.c", "#define N 1\na\n#if defined N || defined(N)\nb\n#endif\n#if N\n#elif N\n#endif\nc\n#line N\nd\n")])
    t |> equal(stream(pp), "a b c d")
    t |> equal(join([for (p in pp.unexpanded); "{p}"], " "), "2 2 3")
}

[test(description = "with no expansion set, a conditional is undecided when its line reads a macro otherwise than clang - never for a function-like name without (, a query operand clang reads unexpanded or __has_include's <...> -; its group marks its diagnostics and definitions, defined or #ifdef of such a definition is undecided too, a builtin name the expansion replaces makes it undecided, an evaluator error stays decided unless it stands at a macro name, and #line's error on a macro is marked")]
def test_undecided_conditionals(t : T?) {
    var pp <- started([("main.c", "#define F(x) x\n#define N 1\n#if F || __has_builtin(N) || __has_include(<N.h>)\n#endif\na\n#if !N\n#define D 1\n#error in\n#endif\n#ifdef D\nb\n#endif\n#if defined(D)\n#endif\n#if F(1)\n#endif\n#if 1 +\n#endif\n#define L 7\n#line L\n#if __LINE__ > 0\n#endif\n")])
    t |> equal(stream(pp), "a b")
    t |> equal(join([for (p in pp.unexpanded); "{p}"], " "), "1 1 2 2 2 2")
    t |> equal(join([for (d in pp.diags); "{d.line}:{d.undecided ? "undecided" : "decided"}"], " "), "8:undecided 15:undecided 17:decided 20:undecided")
    t |> success(pp.macros[pp_macro_index(pp, "D")].undecided)
    t |> success(!pp.macros[pp_macro_index(pp, "N")].undecided)
    t |> success(empty(pp.conds))
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
    var pp <- started([("main.c", "#\n# /* c */\n#bogus x y\n#assert x\n# \"s\"\nz\n")])
    t |> equal(stream(pp), "z")
    t |> equal(diagnostics(pp), "E 3:2 invalid preprocessing directive | E 4:2 invalid preprocessing directive | E 5:3 invalid preprocessing directive")
}

[test(description = "#ident and #sccs take a string literal into the pragma ledger, marked as an #ident line, as clang's -E prints both; anything else is an error and tokens after it a warning")]
def test_ident(t : T?) {
    var pp <- started([("main.c", "a\n#ident \"v1\"\n#sccs L\"v2\"\n#ident x\n#ident\n#ident \"v3\" junk\n#ident u8\"v4\"\n#if 0\n#ident bad\n#endif\nb\n")])
    t |> equal(stream(pp), "a b")
    t |> equal(pragma_rows(pp), "2:2@1 ident \"v1\" | 3:2@1 ident L\"v2\" | 6:2@1 ident \"v3\"")
    t |> equal(diagnostics(pp), "E 4:8 invalid #ident directive | E 5:2 invalid #ident directive | W 6:13 extra tokens at end of #ident directive | E 7:8 invalid #ident directive")
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
    t |> equal(diagnostics(pp), "W 11:9 pragma pop_macro could not pop 'A', no matching push_macro | W 12:2 malformed #pragma push_macro, ignored")
}

[test(description = "#pragma pack lands in the pack ledger: set, reset, push and pop with a tag or a value, the alignment in force after each")]
def test_pack_ledger(t : T?) {
    var pp <- started([("main.c", "#pragma pack(4)\n#pragma pack(push, 1)\n#pragma pack(push, outer, 2)\n#pragma pack(push)\n#pragma pack(pop, outer)\n#pragma pack(pop)\n#pragma pack()\n#pragma pack(show)\n#pragma pack(3)\n#pragma pack 1\n")])
    t |> equal(stream(pp), "")
    t |> equal(pack_rows(pp), "set 4  -> 4 | push 1  -> 1 | push 2 outer -> 2 | push 0  -> 2 | pop 0 outer -> 1 | pop 0  -> 4 | reset 0  -> 0 | show 0  -> 0")
    t |> equal(diagnostics(pp), "W 9:9 expected #pragma pack parameter to be '1', '2', '4', '8', or '16' | W 10:14 missing '(' after '#pragma pack' - ignoring")
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

[test(description = "a path loses its `.` components and doubled `/`, keeps every `..` and its root")]
def test_normalized_path(t : T?) {
    t |> equal(normalized_path("./a/./b/../c.h"), "a/b/../c.h")
    t |> equal(normalized_path("/x//y/../z"), "/x/y/../z")
    t |> equal(normalized_path("../a/../../b"), "../a/../../b")
    t |> equal(normalized_path("/"), "/")
    t |> equal(normalized_path("/../a"), "/../a")
}

[test(description = "#ifdef, #ifndef or #elifndef with no name or a non-identifier is an error, and its group is skipped as clang skips it")]
def test_ifdef_name_errors(t : T?) {
    var pp <- started([("main.c", "#ifdef\nno1\n#endif\n#ifndef 1\nno2\n#endif\n#if 0\n#elifndef\nno3\n#endif\nend\n")])
    t |> equal(stream(pp), "end")
    t |> equal(diagnostics(pp), "E 1:2 macro name missing in #ifdef | E 4:9 macro names must be identifiers | E 8:2 macro name missing in #elifndef")
}

[test(description = "tokens after an #else or #endif that close a group nested in a skipped one, or an #else after a taken group, are dropped without a warning")]
def test_skipped_trailing_tokens_quiet(t : T?) {
    var pp <- started([("main.c", "#if 1\na\n#elif 1\nb\n#else junk\nc\n#endif\n#if 0\n#if 1\n#else junk\n#endif junk\n#endif\n")])
    t |> equal(stream(pp), "a")
    t |> equal(diagnostics(pp), "")
}

[test(description = "tokens after the #endif of a top-level skipped conditional warn, as clang warns")]
def test_endif_of_skipped_top_level_warns(t : T?) {
    var pp <- started([("main.c", "#if 0\n#endif junk\n")])
    t |> equal(stream(pp), "")
    t |> equal(diagnostics(pp), "W 2:8 extra tokens at end of #endif directive")
}

[test(description = "a stray #endif drops the rest of its line: its tokens never reach the stream")]
def test_stray_endif_drops_line(t : T?) {
    var pp <- started([("main.c", "#endif junk\nx\n")])
    t |> equal(stream(pp), "x")
    t |> equal(diagnostics(pp), "E 1:2 #endif without #if")
}

[test(description = "no include guard: a directive or a conditional before the #ifndef, an #elif of it, a second group after it, or an #if with more than !defined X; a file read again keeps one entry")]
def test_guard_negatives(t : T?) {
    let files <- [("main.c", "#include \"v.h\"\n#include \"v.h\"\n#include \"w.h\"\n#include \"w.h\"\n#include \"x.h\"\n#define X_H\n#include \"x.h\"\n#include \"y.h\"\n#define Y_H\n#include \"y.h\"\n#include \"z.h\"\n#define Z_H\n#include \"z.h\"\n#include \"d.h\"\n#include \"d.h\"\n#include \"f.h\"\n#include \"f.h\"\n"),
                  ("v.h", "#if 1\n#endif\n#ifndef V_H\n#define V_H\nv\n#endif\n"),
                  ("w.h", "#ifndef W1\n#define W1\nw\n#endif\n#ifndef W2\n#endif\n"),
                  ("x.h", "#if !defined(X_H) && 1\n#endif\n"),
                  ("y.h", "#if !defined Y_H || 0\n#endif\n"),
                  ("z.h", "#if ~defined Z_H\n#endif\n"),
                  ("d.h", "#define D 1\n#ifndef D_H\n#define D_H\nd\n#endif\n"),
                  ("f.h", "#ifndef F_H\n#define F_H\nf\n#elif 1\n#endif\n")]
    var pp <- started(files)
    t |> equal(stream(pp), "v w d f")
    t |> equal(inclusions(pp), "\"v.h\":v.h:none \"v.h\":v.h:none \"w.h\":w.h:none \"w.h\":w.h:none \"x.h\":x.h:none \"x.h\":x.h:none \"y.h\":y.h:none \"y.h\":y.h:none \"z.h\":z.h:none \"z.h\":z.h:none \"d.h\":d.h:none \"d.h\":d.h:none \"f.h\":f.h:none \"f.h\":f.h:none")
    let v_h = pp.file_of?["v.h"] ?? -1
    t |> equal(pp.files[v_h].entered, 2)
    t |> equal(length([for (f in pp.files); f; where f.path == "v.h"]), 1)
}

[test(description = "a null directive before the #ifndef keeps the include guard, as clang's include-guard detection ignores it")]
def test_guard_after_null_directive(t : T?) {
    var pp <- started([("main.c", "#include \"u.h\"\n#include \"u.h\"\n"), ("u.h", "#\n#ifndef U_H\n#define U_H\nu\n#endif\n#\n")])
    t |> equal(stream(pp), "u")
    t |> equal(inclusions(pp), "\"u.h\":u.h:none \"u.h\":u.h:guard")
}

[test(description = "a diagnostic and a pragma ledger entry carry the presumed line and file #line gives their place")]
def test_presumed_place_of_ledgers(t : T?) {
    var pp <- started([("main.c", "#line 100 \"p.c\"\n#pragma foo\n#error e\n")])
    t |> equal(stream(pp), "")
    t |> equal("{pp.names[pp.pragmas[0].pname]}:{int64(pp.pragmas[0].pline)}", "p.c:100")
    t |> equal("{pp.names[pp.diags[0].pname]}:{int64(pp.diags[0].pline)}", "p.c:101")
}

[test(description = "a parameter list ending after '(', after a comma or after a GNU name..., or going on past a variadic parameter, is missing its ')'")]
def test_define_param_list_ends(t : T?) {
    var pp <- started([("main.c", "#define A(\n#define B(x,\n#define C(x...\n#define D(..., y)\n#define E(x... y)\n")])
    t |> equal(stream(pp), "")
    t |> equal(diagnostics(pp), "E 1:10 missing ')' in macro parameter list | E 2:12 missing ')' in macro parameter list | E 3:12 missing ')' in macro parameter list | E 4:14 missing ')' in macro parameter list | E 5:16 missing ')' in macro parameter list")
    t |> equal(length(pp.macros), 0)
}

[test(description = "an object-like body may hold '#'; a function-like body ending in '#' is an error")]
def test_define_hash_in_body(t : T?) {
    var pp <- started([("main.c", "#define S # x\n#define T(x) x #\n")])
    t |> equal(stream(pp), "")
    t |> equal(diagnostics(pp), "E 2:2 '#' is not followed by a macro parameter")
    t |> equal(join([for (m in pp.macros); pp_name(pp, m.name)], ","), "S")
}

[test(description = "an object-like body with no space after the name warns as clang's C99 mode does, and is defined")]
def test_define_no_space_after_name(t : T?) {
    var pp <- started([("main.c", "#define NOWS+\n#define NOWS2\"s\"\n#define SP +\n#define FN(x)x\n")])
    t |> equal(stream(pp), "")
    t |> equal(diagnostics(pp), "W 1:13 ISO C99 requires whitespace after the macro name | W 2:14 ISO C99 requires whitespace after the macro name")
    t |> equal(pp_macro_body_text(pp, pp.macros[pp_macro_index(pp, "NOWS")]), "+")
}

[test(description = "a redefinition differing in kind, variadic marker, parameter count or names, token count, a spelling's length or inner whitespace warns")]
def test_redefinition_differences(t : T?) {
    var pp <- started([("main.c", "#define A() a\n#define A a\n#define V(a...) a\n#define V(a) a\n#define P(a) 1\n#define P(a, b) 1\n#define C 1\n#define C 1 2\n#define N(a) 1\n#define N(b) 1\n#define L 1\n#define L 12\n#define W a+b\n#define W a + b\n")])
    t |> equal(stream(pp), "")
    t |> equal(diagnostics(pp), "W 2:2 'A' macro redefined | W 4:2 'V' macro redefined | W 6:2 'P' macro redefined | W 8:2 'C' macro redefined | W 10:2 'N' macro redefined | W 12:2 'L' macro redefined | W 14:2 'W' macro redefined")
}

[test(description = "#undef with no name, a non-identifier or `defined` is an error")]
def test_undef_errors(t : T?) {
    var pp <- started([("main.c", "#define defined_not 1\n#undef\n#undef 1\n#undef defined\n")])
    t |> equal(stream(pp), "")
    t |> equal(diagnostics(pp), "E 2:2 macro name missing | E 3:8 macro name must be an identifier | E 4:8 'defined' cannot be used as a macro name")
}

[test(description = "an absolute name is read as it is, not under the includer's folder; a missing one names itself as searched")]
def test_include_absolute(t : T?) {
    var pp <- started([("src/main.c", "#include \"/abs/./a.h\"\n#include \"/abs/none.h\"\n"), ("/abs/a.h", "abs_a\n")], "src/main.c")
    t |> equal(stream(pp), "abs_a")
    t |> equal(inclusions(pp), "\"/abs/./a.h\":/abs/a.h:none \"/abs/none.h\":-:not_found")
    t |> equal(diagnostics(pp), "F 2:10 '/abs/none.h' file not found; searched: /abs/none.h")
}

[test(description = "a quoted #include_next skips the includer's folder; one in a file found by its quote folder warns and searches the whole path")]
def test_include_next_forms(t : T?) {
    var quoted <- started([("main.c", "#include <x.h>\n"), ("a/x.h", "a_x\n#include_next \"x.h\"\n"), ("b/x.h", "b_x\n")], "main.c", array<string>(), ["a", "b"])
    t |> equal(stream(quoted), "a_x b_x")
    t |> equal(diagnostics(quoted), "")
    var relative <- started([("main.c", "#include \"q.h\"\n"), ("q.h", "#include_next <r.h>\n"), ("inc/r.h", "r\n")], "main.c", array<string>(), ["inc"])
    t |> equal(stream(relative), "r")
    t |> equal(diagnostics(relative), "W 1:15 #include_next in file found relative to primary source file or found by absolute path; will search from start of include path")
}

[test(description = "#include_next searches after the folder of the inclusion, not of the file: a file found in its includer's folder inherits the includer's, as gcc's limits.h -> syslimits.h -> #include_next <limits.h> needs")]
def test_include_next_per_inclusion(t : T?) {
    t |> run("gcc's limits.h pattern reads the next limits.h once, as clang does") @(t : T?) {
        let files <- [("main.c", "#include <limits.h>\nend\n"),
                      ("g1/limits.h", "#ifndef _GCC_LIMITS_H_\n#ifndef _GCC_NEXT_LIMITS_H\n#include \"syslimits.h\"\n#endif\ngcc_limits\n#endif\n"),
                      ("g1/syslimits.h", "#define _GCC_NEXT_LIMITS_H\n#include_next <limits.h>\n#undef _GCC_NEXT_LIMITS_H\n"),
                      ("g2/limits.h", "libc_limits\n")]
        var pp <- started(files, "main.c", array<string>(), ["g1", "g2"])
        t |> equal(stream(pp), "libc_limits gcc_limits end")
        t |> equal(diagnostics(pp), "")
    }
    t |> run("a file found in its includer's folder searches after the includer's folder") @(t : T?) {
        let files <- [("main.c", "#include <x.h>\nend\n"), ("a/x.h", "a_x\n#include \"s.h\"\n"), ("a/s.h", "a_s\n#include_next <x.h>\n"), ("b/x.h", "b_x\n")]
        var pp <- started(files, "main.c", array<string>(), ["a", "b"])
        t |> equal(stream(pp), "a_x a_s b_x end")
        t |> equal(diagnostics(pp), "")
    }
    t |> run("one file reached by two inclusions searches after each inclusion's own folder") @(t : T?) {
        let files <- [("main.c", "#include \"b/y.h\"\n#include <y.h>\n"), ("b/y.h", "#include_next <z.h>\n"), ("a/z.h", "a_z\n"), ("c/z.h", "c_z\n")]
        var pp <- started(files, "main.c", array<string>(), ["a", "b", "c"])
        t |> equal(stream(pp), "a_z c_z")
        t |> equal(diagnostics(pp), "W 1:15 #include_next in file found relative to primary source file or found by absolute path; will search from start of include path")
        t |> equal(length(pp.files), 5)
    }
}

[test(description = "a `..` after a linked folder leads where the link's target says, and one file reached through a link and directly is one file")]
def test_identity_through_link(t : T?) {
    var mem = new PpMemoryProvider()
    mem->link("inc/l", "real/deep")
    mem->add("main.c", "#include <l/x.h>\n#include \"real/deep/x.h\"\n")
    mem->add("real/deep/x.h", "#pragma once\n#include \"../y.h\"\n")
    mem->add("real/y.h", "real_y\n")
    mem->add("inc/y.h", "inc_y\n")
    var pp : Preprocessor
    t |> success(pp_start(pp, mem, "main.c", array<string>(), ["inc"]))
    t |> equal(stream(pp), "real_y")
    t |> equal(inclusions(pp), "<l/x.h>:inc/l/x.h:none \"../y.h\":inc/l/../y.h:none \"real/deep/x.h\":inc/l/x.h:pragma_once")
    t |> equal(join([for (f in pp.files); f.identity], " "), "main.c  real/deep/x.h real/y.h")
}

[test(description = "the fio provider knows a file by its real path: one header reached by a relative and an absolute spelling is one file, for #pragma once and for an include guard")]
def test_identity_relative_absolute(t : T?) {
    let dir = get_full_file_name(path_join(test_temp_dir(), "pp2_identity"))
    mkdir_rec(path_join(dir, "sub"))
    write_text(path_join(dir, "once.h"), "#pragma once\nonce\n")
    write_text(path_join(dir, "guarded.h"), "#ifndef G_H\n#define G_H\nguarded\n#endif\n")
    write_text(path_join(dir, "main.c"), "#include <once.h>\n#include \"{dir}/once.h\"\n#include \"sub/../once.h\"\n#include <guarded.h>\n#include \"{dir}/guarded.h\"\nend\n")
    var error : string
    let rel = relative(dir, getcwd(), error)
    t |> equal(error, "")
    var pp : Preprocessor
    t |> success(pp_start(pp, new PpFioProvider(), path_join(dir, "main.c"), array<string>(), [rel]))
    t |> equal(stream(pp), "once guarded end")
    let skips <- [for (inc in pp.inclusions); "{inc.skip}"]
    t |> equal(join(skips, " "), "none pragma_once pragma_once none guard")
    t |> equal(length(pp.files), 4)
}

[test(description = "#import reads a file once: a later #import or #include of it is skipped, as clang marks it include-once")]
def test_import(t : T?) {
    var pp <- started([("main.c", "#include \"i.h\"\n#import \"i.h\"\n#import \"j.h\"\n#import \"j.h\"\n#include \"j.h\"\n#import\n#import \"k.h\"\n#include \"k.h\"\n"),
                       ("i.h", "i\n"), ("j.h", "j\n"), ("k.h", "k\n")])
    t |> equal(stream(pp), "i j k")
    t |> equal(inclusions(pp), "\"i.h\":i.h:none \"i.h\":i.h:pragma_once \"j.h\":j.h:none \"j.h\":j.h:pragma_once \"j.h\":j.h:pragma_once \"k.h\":k.h:none \"k.h\":k.h:pragma_once")
    t |> equal(diagnostics(pp), "E 6:2 expected \"FILENAME\" or <FILENAME>")
}

[test(description = "a file that exists but cannot be read is a fatal error naming it, recorded as not found, and the unit ends there")]
def test_include_read_fails(t : T?) {
    var pp : Preprocessor
    t |> success(pp_start(pp, new ReadFailsProvider(), "main.c", array<string>(), array<string>()))
    t |> equal(stream(pp), "")
    t |> equal(diagnostics(pp), "F 1:10 cannot read 'x.h'")
    t |> equal(inclusions(pp), "\"x.h\":-:not_found")
}

[test(description = "with no expansion set, a macro in an #if line is a name worth 0, and the evaluator's errors - defined of a non-name, an unclosed defined(, trailing tokens - are placed at their tokens")]
def test_if_hook_errors(t : T?) {
    var pp <- started([("main.c", "#define X 2\n#if X\na\n#endif\n#if 10\nb\n#endif\n#if defined 1\nc\n#endif\n#if defined(X Y\nd\n#endif\n#if 1 && 0\ne\n#endif\n#if 1 2\nf\n#endif\n")])
    t |> equal(stream(pp), "b")
    t |> equal(diagnostics(pp), "E 8:13 macro name must be an identifier | E 11:15 missing ')' after 'defined' | E 17:7 token is not a valid binary operator in a preprocessor subexpression")
}

[test(description = "a #pragma pack read by clang's grammar: each malformed form gets clang's warning at clang's column and no ledger entry")]
def test_pack_malformed(t : T?) {
    var pp <- started([("main.c", "#pragma pack(push\n#pragma pack 4)\n#pragma pack(foo)\n#pragma pack(push 1 2)\n#pragma pack(push, \"s\")\n#pragma pack(4 4)\n#pragma pack(,)\n#pragma pack(push, 4, id2)\n#pragma pack(push, a, b)\n#pragma pack(4) x\n#pragma pack(show, 1)\n#pragma pack\n")])
    t |> equal(stream(pp), "")
    t |> equal(length(pp.packs), 0)
    t |> equal(diagnostics(pp), "W 1:18 missing ')' after '#pragma pack' - ignoring | W 2:14 missing '(' after '#pragma pack' - ignoring | W 3:14 unknown action for '#pragma pack' - ignored | W 4:19 missing ')' after '#pragma pack' - ignoring | W 5:20 expected integer or identifier in '#pragma pack' - ignored | W 6:16 missing ')' after '#pragma pack' - ignoring | W 7:14 missing ')' after '#pragma pack' - ignoring | W 8:21 missing ')' after '#pragma pack' - ignoring | W 9:23 expected integer or identifier in '#pragma pack' - ignored | W 10:17 extra tokens at end of '#pragma pack' - ignored | W 11:18 missing ')' after '#pragma pack' - ignoring | W 12:13 missing '(' after '#pragma pack' - ignoring")
}

[test(description = "pack(show) keeps the alignment in force, pop with a value sets it, a pop on an empty stack warns as clang does and keeps it, a pop of an unknown tag keeps it")]
def test_pack_stack_edges(t : T?) {
    var pp <- started([("main.c", "#pragma pack(pop)\n#pragma pack(8)\n#pragma pack(show)\n#pragma pack(push, 1)\n#pragma pack(pop, 2)\n#pragma pack(push, t, 4)\n#pragma pack(pop, nosuch)\n#pragma pack(pop, t, 1)\n")])
    t |> equal(stream(pp), "")
    t |> equal(pack_rows(pp), "pop 0  -> 0 | set 8  -> 8 | show 0  -> 8 | push 1  -> 1 | pop 2  -> 2 | push 4 t -> 4 | pop 0 nosuch -> 4 | pop 1 t -> 1")
    t |> equal(diagnostics(pp), "W 1:9 #pragma pack(pop, ...) failed: stack empty")
}

[test(description = "push_macro of a wide string or with trailing tokens is malformed; popping a name saved undefined leaves it undefined to #ifdef")]
def test_push_pop_macro_edges(t : T?) {
    var pp <- started([("main.c", "#pragma push_macro(L\"A\")\n#pragma push_macro(\"A\") x\n#pragma push_macro(\"U\")\n#define U\n#pragma pop_macro(\"U\")\n#ifdef U\nu\n#endif\n")])
    t |> equal(stream(pp), "")
    t |> equal(diagnostics(pp), "W 1:2 malformed #pragma push_macro, ignored | W 2:2 malformed #pragma push_macro, ignored")
}

[test(description = "tokens after #pragma once warn, and the file is still read once")]
def test_pragma_once_extra_tokens(t : T?) {
    var pp <- started([("main.c", "#include \"a.h\"\n#include \"a.h\"\n"), ("a.h", "#pragma once junk\na\n")])
    t |> equal(stream(pp), "a")
    t |> equal(diagnostics(pp), "W 1:2 extra tokens at end of #pragma once directive")
}

[test(description = "a #line file name reads \\\\ and \\\" as one character each")]
def test_line_name_escapes(t : T?) {
    var pp <- started([("main.c", "#line 5 \"a\\\\b\\\".c\"\nx\n")])
    t |> success(pp_next_token(pp))
    t |> equal(pp.names[pp.tok.pname], "a\\b\".c")
    t |> equal(pp.tok.pline, 5u)
}

[test(description = "a function-like predefined entry is defined with its parameters; an entry that is no definition is an error and skipped")]
def test_predefined_entries(t : T?) {
    var pp <- started([("main.c", "x\n")], "main.c", ["F(a, b)=a+b", "1BAD", "OK"])
    t |> equal(stream(pp), "x")
    t |> equal(diagnostics(pp), "E 0:0 not a macro definition: 1BAD")
    let f := pp.macros[pp_macro_index(pp, "F")]
    t |> success(f.function_like)
    t |> equal(join([for (p in f.params); pp_name(pp, p)], ","), "a,b")
    t |> equal(pp_macro_body_text(pp, f), "a+b")
    t |> success(pp_macro_index(pp, "OK") >= 0)
}

[test(description = "the providers answer for their own files only: memory reads no unknown path, fio sees no folder as a file; the main path is normalized")]
def test_provider_edges(t : T?) {
    var mem = new PpMemoryProvider()
    mem->add("a.c", "a\n")
    var bytes : array<uint8>
    t |> success(!mem->read("b.c", bytes))
    t |> equal(mem->identity("/x/./y/../z.h"), "/x/z.h")
    var fio = new PpFioProvider()
    let dir = own_include_dir()
    t |> success(!fio->exists(dir))
    t |> success(fio->exists("{dir}/stdio.h"))
    var folder : Preprocessor
    t |> success(!pp_start(folder, fio, dir, array<string>(), array<string>()))
    var dotted <- started([("main.c", "m\n")], "./main.c")
    t |> equal(stream(dotted), "m")
    t |> equal(dotted.files[0].path, "main.c")
}

// the bytes of `span` as a string
def private span_text(span : tuple<data : uint8 const?; len : int>) : string {
    return build_string() $(var out) {
        for (i in range(span.len)) {
            out |> write_char(int(unsafe(span.data[i])))
        }
    }
}

[test(description = "a token's spelling outlives its file: the tokens of an included file, kept past the include's end and more reads, are spelled from the buffer the unit keeps, splices removed")]
def test_spelling_outlives_file(t : T?) {
    var pp <- started([("main.c", "#include \"h.h\"\nafter more\n"), ("h.h", "in\\\nside 42 \"s\"\n")])
    var kept : array<PpOutToken>
    while (pp_next_token(pp)) {
        kept |> push(pp.tok)
        let spelled = pp_token_spelling(pp)
        t |> equal(span_text(pp_token_span(pp)), spelled)
    }
    t |> equal(join([for (k in kept); pp_spelling_of(pp, k)], " "), "inside 42 \"s\" after more")
    t |> equal(join([for (k in kept); span_text(pp_span_of(pp, k))], " "), "inside 42 \"s\" after more")
    t |> equal(length(pp.closed), 2)
    t |> success(kept[0].buffer != kept[3].buffer)
    t |> equal(kept[0].spelled, PpSpelled.source)
    t |> equal("{kept[0].at} {kept[0].len} {kept[0].tok.len}", "0 6 8")
}

[test(description = "a preprocessed unit read as the C tokens read it: each token's presumed file and line from the line markers, its column and its kept spelling, with no marker re-read by the reader")]
def test_preprocessed_stream(t : T?) {
    var pp <- started([("x.i", "# 1 \"x.c\"\n# 1 \"<built-in>\" 1\n# 1 \"x.c\" 2\nint a;\n# 5 \"h.h\" 1\nlong  b;\n# 2 \"x.c\" 2\nc\n")], "x.i")
    var kept : array<PpOutToken>
    while (pp_next_token(pp)) {
        kept |> push(pp.tok)
    }
    let placed <- [for (k in kept); "{pp_spelling_of(pp, k)}@{pp.names[k.pname]}:{int64(k.pline)}:{k.tok.col}"]
    t |> equal(join(placed, " "), "int@x.c:1:1 a@x.c:1:5 ;@x.c:1:6 long@h.h:5:1 b@h.h:5:7 ;@h.h:5:8 c@x.c:2:1")
    t |> equal(diagnostics(pp), "")
}

[test(description = "the directive layer follows clang's diagnostics: a #line operand that is no number asks for a positive integer, __VA_OPT__ in a macro that is not variadic warns")]
def test_clang_directive_messages(t : T?) {
    var line <- started([("main.c", "#line \"x\"\n#line 0x10\n")])
    stream(line)
    t |> equal(diagnostics(line), "E 1:7 #line directive requires a positive integer argument | E 2:7 #line directive requires a simple digit sequence")
    var va_opt <- started([("main.c", "#define F(x) #__VA_OPT__(x) __VA_OPT__(y)\n#define G(...) __VA_OPT__(x)\n")])
    stream(va_opt)
    t |> equal(diagnostics(va_opt), "W 1:15 __VA_OPT__ can only appear in the expansion of a variadic macro")
}

[test(description = "a macro defined, and a diagnostic met, in a group an #if chose belong to that group alone; the directive lines are counted in skipped groups too")]
def test_chosen_groups(t : T?) {
    var pp <- started([("main.c", "#define A 1\n#if X > 1\n#define B 2\n#else\n#define C 3\n#error in\n#endif\n#define D 4\n#error out\nz\n")])
    t |> equal(stream(pp), "z")
    t |> equal(join([for (m in pp.macros); pp_name(pp, m.name)], " "), "A C D")
    t |> equal(join([for (d in pp.diags); d.what], " | "), "#error in | #error out")
    var counted <- started([("main.c", "#if 1\n#endif\n#define g(x) x\n#if 0\n#elif 1\n#endif\n")])
    stream(counted)
    t |> equal(counted.directives_read, 6)
}

[test(description = "with no expansion set, a #line whose operand names no macro is no unexpanded line: clang reads it the same, an error, so nothing is left to PP.3")]
def test_line_undefined_name_not_marked(t : T?) {
    var pp <- started([("main.c", "a\n#line N\nb\n")])
    t |> equal(stream(pp), "a b")
    t |> equal(diagnostics(pp), "E 2:7 #line directive requires a positive integer argument")
    t |> equal(length(pp.unexpanded), 0)
}

// every lexer diagnostic, `<file>:<line>:<col> <what>`, `skipped` after one met in a skipped group, a `|` between them
def private lexer_diagnostics(pp : Preprocessor) : string {
    let parts <- [for (d in pp.lx.diags); "{d.file}:{d.line}:{d.col} {d.what}{d.skipped ? " skipped" : ""}"]
    return join(parts, " | ")
}

[test(description = "a lexer diagnostic met in a skipped group is marked skipped, as clang does not diagnose a group it skips: a bad byte on the line after #if 0, inside it and in a nested conditional, an unterminated comment; one on the line after #else, in an included file and on the line after the #include is not")]
def test_lexer_diags_in_skipped_groups(t : T?) {
    var pp <- started([("main.c", "a \xff\n#if 0\n\xff b\nc \xff\n#if 1\n\xff\n#endif\n#else\n\xff d\n#endif\n#include \"h.h\"\n\xff e\n#if 0\n/* open\n"),
                       ("h.h", "h \xff\n")])
    t |> equal(stream(pp), "a \xff \xff d h \xff \xff e")
    t |> equal(lexer_diagnostics(pp), ("0:1:3 invalid UTF-8: byte 255 | 0:3:1 invalid UTF-8: byte 255 skipped | 0:4:3 invalid UTF-8: byte 255 skipped | " +
                                       "0:6:1 invalid UTF-8: byte 255 skipped | 0:9:1 invalid UTF-8: byte 255 | 0:12:1 invalid UTF-8: byte 255 | " +
                                       "2:1:3 invalid UTF-8: byte 255 | 0:14:1 unterminated /* comment skipped"))
    t |> equal(diagnostics(pp), "E 13:2 unterminated conditional directive")
}

[test(description = "a lexer diagnostic carries the presumed line and file #line gives its place, kept when the header it was met in closes in the same read, and the includer's for the token after an #include line")]
def test_lexer_diag_presumed_place(t : T?) {
    var pp <- started([("main.c", "#line 20 \"m.c\"\n#include \"h.h\"\n\xff z\n"), ("h.h", "#line 50 \"p.h\"\nh\n/* open")])
    t |> success(pp_next_token(pp))
    t |> equal(pp_token_spelling(pp), "h")
    t |> success(pp_next_token(pp))
    t |> equal(pp_token_spelling(pp), "\xff")
    let shown <- [for (d in pp.lx.diags); "{pp.names[d.pname]}:{int64(d.pline)} {d.line}:{d.col} {d.what}"]
    t |> equal(join(shown, " | "), "m.c:21 3:1 invalid UTF-8: byte 255 | p.h:51 3:1 unterminated /* comment")
}

[test(description = "an unterminated conditional is placed at its #if and raised past the last byte of the file that left it open, an included one too; an unterminated comment's end counted; a directive diagnostic is raised at the token the reader stands on")]
def test_unterminated_conditional_raised_at_end(t : T?) {
    var pp <- started([("main.c", "#include \"h.h\"\n#if 1\nx\n"), ("h.h", "#ifdef A\n#else\n\n")])
    t |> equal(stream(pp), "x")
    let shown <- [for (d in pp.diags); "{d.file}:{d.line}:{d.col} raised {d.raised.file}:{d.raised.offset}:{d.raised.line}:{d.raised.col} {d.what}"]
    t |> equal(join(shown, " | "), ("2:1:2 raised 2:16:4:1 unterminated conditional directive | " +
                                    "0:2:2 raised 0:23:4:1 unterminated conditional directive"))
    var comment <- started([("main.c", "#if 1\n/* open\nmore")])
    stream(comment)
    t |> equal("{comment.diags[0].raised.offset}:{comment.diags[0].raised.line}:{comment.diags[0].raised.col}", "18:3:5")
    var direct <- started([("main.c", "#bogus x\ny\n")])
    stream(direct)
    t |> equal("{direct.diags[0].line}:{direct.diags[0].col} raised {direct.diags[0].raised.line}:{direct.diags[0].raised.col}", "1:2 raised 1:2")
}

[test(description = "#pragma GCC poison makes each later use of its names clang's error - in the text, a later macro body, #ifdef, defined, #undef, a #define's name, an #elif line evaluated and another pragma - but not in a skipped group or a repeated poison; a defined macro warns, a token that is no name is an error ending the list; no ledger entry")]
def test_pragma_poison(t : T?) {
    var pp <- started([("main.c", ("#define OLD foo\n#pragma GCC poison foo bar\nint foo;\n#define AFTER bar\n#ifdef foo\n#endif\n#if defined(bar)\n#endif\n" +
                                   "#undef foo\n#define foo 1\n#if 0\nfoo\n#endif\n#pragma GCC poison foo\n#pragma GCC poison OLD\n#pragma GCC poison a \"s\" c\n" +
                                   "c a\n#pragma weird foo\n#pragma GCC poison zz\n#if 0\n#elif defined(zz)\n#endif\n#pragma clang poison zed\nzed\n#pragma GCC poison\n"))])
    t |> equal(stream(pp), "int foo ; c a zed")
    t |> equal(diagnostics(pp), ("E 3:5 attempt to use a poisoned identifier | E 4:15 attempt to use a poisoned identifier | " +
                                 "E 5:8 attempt to use a poisoned identifier | E 7:13 attempt to use a poisoned identifier | " +
                                 "E 9:8 attempt to use a poisoned identifier | E 10:9 attempt to use a poisoned identifier | " +
                                 "W 15:20 poisoning existing macro | E 16:22 can only poison identifier tokens | " +
                                 "E 17:3 attempt to use a poisoned identifier | E 18:15 attempt to use a poisoned identifier | " +
                                 "E 21:15 attempt to use a poisoned identifier | E 24:1 attempt to use a poisoned identifier"))
    t |> equal(pragma_rows(pp), "18:2@5 weird foo")
}

// every lexer diagnostic, `<line>:<col> <what>` and its marks, `skipped`, `directive` and `undecided`, a `|` between them
def private lexer_marks(pp : Preprocessor) : string {
    let parts <- [for (d in pp.lx.diags); "{d.line}:{d.col} {d.what}{d.skipped ? " skipped" : ""}{d.directive ? " directive" : ""}{d.undecided ? " undecided" : ""}"]
    return join(parts, " | ")
}

[test(description = "an #elif or #else line ending an active group is read as that group's, as clang reads it: a poisoned name on it is an error and its bad byte is not skipped; the line of one ending a skipped group or met in one stays quiet")]
def test_elif_else_after_active_group_read_active(t : T?) {
    var pp <- started([("main.c", ("#pragma GCC poison zap\n#if 1\n#elif zap \xff\n#endif\n#if 1\n#else zap \xff\n#endif\n#if 0\n#elif 1\n#else zap\n#endif\n" +
                                   "#if 1\n#elif 1\n#else zap \xff\n#endif\n#if 0\n#if 1\n#else zap\n#endif\n#endif\n"))])
    t |> equal(stream(pp), "")
    t |> equal(diagnostics(pp), ("E 3:7 attempt to use a poisoned identifier | E 6:7 attempt to use a poisoned identifier | " +
                                 "W 6:7 extra tokens at end of #else directive | E 10:7 attempt to use a poisoned identifier | " +
                                 "W 10:7 extra tokens at end of #else directive"))
    t |> equal(lexer_marks(pp), ("3:11 invalid UTF-8: byte 255 directive | 6:11 invalid UTF-8: byte 255 directive | " +
                                 "14:11 invalid UTF-8: byte 255 skipped directive"))
}

[test(description = "an #error or #warning line is read raw, as clang reads it: a poisoned name in its message is no error")]
def test_error_warning_lines_raw(t : T?) {
    var pp <- started([("main.c", "#pragma GCC poison zap\n#warning zap here\n#error zap\nzap\n")])
    t |> equal(stream(pp), "zap")
    t |> equal(diagnostics(pp), "W 2:2 #warning zap here | E 3:2 #error zap | E 4:1 attempt to use a poisoned identifier")
}

[test(description = "a bad byte on an active directive's line is marked directive, as clang does not diagnose it; one in the text is not, and an unterminated comment on a directive's line is no directive mark")]
def test_lexer_diag_directive_mark(t : T?) {
    var pp <- started([("main.c", "#define X 1 \xff\n#pragma foo \xff\n#include \xff\n\xff y\n#define Y /* open\n")])
    t |> equal(stream(pp), "\xff y")
    t |> equal(lexer_marks(pp), ("1:13 invalid UTF-8: byte 255 directive | 2:13 invalid UTF-8: byte 255 directive | " +
                                 "3:10 invalid UTF-8: byte 255 directive | 4:1 invalid UTF-8: byte 255 | 5:11 unterminated /* comment"))
}

[test(description = "a lexer diagnostic met on a #line line keeps the presumed place the line had; the next line's takes the new one")]
def test_lexer_diag_on_line_directive_old_place(t : T?) {
    var pp <- started([("main.c", "int a;\n#line 100 \"z.c\" /* open\nmore\n")])
    stream(pp)
    let shown <- [for (d in pp.lx.diags); "{pp.names[d.pname]}:{int64(d.pline)} {d.line}:{d.col} {d.what}"]
    t |> equal(join(shown, " | "), "main.c:2 2:17 unterminated /* comment")
    var next <- started([("main.c", "#line 100 \"z.c\"\n\xff\n")])
    stream(next)
    let moved <- [for (d in next.lx.diags); "{next.names[d.pname]}:{int64(d.pline)} {d.line}:{d.col}"]
    t |> equal(join(moved, " | "), "z.c:100 2:1")
}

[test(description = "an unterminated comment opening on a directive's line is the line's, as clang reads it with the line: not skipped though the directive opens a skipped group; one opening on the line after #if 0 is skipped")]
def test_unterminated_comment_on_directive_line(t : T?) {
    for (text in ["#if 0 /* open", "#ifdef NOPE /* open", "#if 1\n#else /* open", "#if 1\n#elif 1 /* open", "#if 0\n#else /* open"]) {
        var pp <- started([("main.c", text)])
        stream(pp)
        t |> equal(length(pp.lx.diags), 1, text)
        t |> success(!pp.lx.diags[0].skipped, "{text}: {lexer_marks(pp)}")
    }
    var after <- started([("main.c", "#if 0\n/* open")])
    stream(after)
    t |> equal(lexer_marks(after), "2:1 unterminated /* comment skipped")
}

[test(description = "a lexer diagnostic met in a group an undecided conditional chose is marked undecided, the skipped group too, since clang may read it; one after its #endif is not")]
def test_lexer_diag_undecided_mark(t : T?) {
    var pp <- started([("main.c", "#define N 1\n#if N\n\xff a\n#endif\n\xff b\n")])
    stream(pp)
    t |> equal(lexer_marks(pp), "3:1 invalid UTF-8: byte 255 skipped undecided | 5:1 invalid UTF-8: byte 255")
}

[test(description = "#pragma GCC poison passes over __VA_ARGS__ and __VA_OPT__, as clang does: a variadic body using them is no error")]
def test_poison_va_args_passed_over(t : T?) {
    var pp <- started([("main.c", "#pragma GCC poison __VA_ARGS__ __VA_OPT__\n#define F(...) __VA_OPT__(,) __VA_ARGS__\nF(x)\n")])
    t |> equal(stream(pp), "F ( x )")
    t |> equal(diagnostics(pp), "")
}

[test(description = "#pragma GCC error and GCC warning are an error and a warning at the pragma's kind with the value of their plain string literals, joined, parenthesized or not; any other form is clang's error at clang's token; #pragma clang warning stays a ledger entry")]
def test_pragma_gcc_message(t : T?) {
    var pp <- started([("main.c", ("#pragma GCC error \"boom here\"\n#pragma GCC warning (\"x\\\"y\\tz\" \"!\")\n#pragma GCC error\n#pragma GCC warning L\"wide\"\n" +
                                   "#pragma GCC error (\"a\" x)\n#pragma GCC warning \"a\" )\n#pragma GCC warning (\n#pragma GCC error (\"a\"\n" +
                                   "#pragma GCC warning (42)\n#pragma clang warning \"kept\"\n#pragma GCC warning \"\\101\\x42\"\n"))])
    t |> equal(stream(pp), "")
    t |> equal(diagnostics(pp), ("E 1:13 boom here | W 2:13 x\"y\tz! | E 3:13 pragma error requires parenthesized string | " +
                                 "E 4:13 pragma warning requires parenthesized string | E 5:24 pragma error requires parenthesized string | " +
                                 "E 6:25 pragma warning requires parenthesized string | E 7:22 expected string literal in pragma warning | " +
                                 "E 8:23 pragma error requires parenthesized string | E 9:22 expected string literal in pragma warning | W 11:13 AB"))
    t |> equal(pragma_rows(pp), "10:2@0 clang warning \"kept\"")
}
