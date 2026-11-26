options gen2
options stack = 262144
require dastest/testing_boost public
require strings
require daslib/strings_boost
require ../c_parser.das
require _preprocessed_headers

//! `frontend/c_parser.das`, its declarations: specifiers with their storage classes, named
//! declarators, init-declarators, `_Static_assert`, and the typedef table filled as each name is
//! declared; every refusal and malformed declaration as a located error, the nesting bound, and no
//! allocation per token over the preprocessed own headers.

// the declarations of `text` to its end, each tree and a blank between them, or `error: <message>`;
// `T` is a typedef name before the first
def private decls(text : string) : string {
    var p : CParser
    c_parser_open_text(p, text, "t.c")
    c_declare(p, c_symbol(p.unit, "T"), CBinding.TYPEDEF)
    var parts : array<string>
    while (!p.failed && p.unit.toks[p.pos].kind != int(CTok.EOF)) {
        let d = c_declaration(p)
        if (!p.failed) {
            parts |> push(c_dump(p.ast, p.unit, d))
        }
    }
    return p.failed ? "error: {p.err}" : join(parts, " ")
}

// the next declaration of `p` as a tree, or `error: <message>`
def private next_decl(var p : CParser) : string {
    let d = c_declaration(p)
    return p.failed ? "error: {p.err}" : c_dump(p.ast, p.unit, d)
}

// the next expression of `p` up to its `;`, which it takes, as a tree
def private next_expr(var p : CParser) : string {
    let e = c_expression(p)
    if (!p.failed && p.unit.toks[p.pos].kind == int(CTok.SEMI)) {
        p.pos++
    }
    return p.failed ? "error: {p.err}" : c_dump(p.ast, p.unit, e)
}

// a parser over `text` with `T` a typedef name
def private opened(var p : CParser; text : string) {
    c_parser_open_text(p, text, "t.c")
    c_declare(p, c_symbol(p.unit, "T"), CBinding.TYPEDEF)
}

[test(description = "declaration specifiers: every storage class and function specifier, `_Alignas`, attributes, `__extension__` before a declaration, and the storage classes C11 6.7.1p2 lets combine")]
def test_specifiers(t : T?) {
    t |> run("storage classes, function specifiers, qualifiers, `_Alignas`") @(t : T?) {
        t |> equal(decls("static const int x;"), "(decl 0 [(spec static) (spec const) (spec int)] [(init_decl (d_name x) - -)])")
        t |> equal(decls("extern volatile unsigned long y;"), "(decl 0 [(spec extern) (spec volatile) (spec unsigned) (spec long)] [(init_decl (d_name y) - -)])")
        t |> equal(decls("auto int a; register int r;"), "(decl 0 [(spec auto) (spec int)] [(init_decl (d_name a) - -)]) (decl 0 [(spec register) (spec int)] [(init_decl (d_name r) - -)])")
        t |> equal(decls("inline static int f(void);"), "(decl 0 [(spec inline) (spec static) (spec int)] [(init_decl (d_function 0 (d_name f) [(param [(spec void)] -)]) - -)])")
        t |> equal(decls("__inline__ _Noreturn void e(void);"), "(decl 0 [(spec inline) (spec _Noreturn) (spec void)] [(init_decl (d_function 0 (d_name e) [(param [(spec void)] -)]) - -)])")
        t |> equal(decls("_Alignas(16) int al; _Alignas(T) char c;"), "(decl 0 [(alignas_expr (int 16)) (spec int)] [(init_decl (d_name al) - -)]) (decl 0 [(alignas_type (type_name [(typedef_name T)] -)) (spec char)] [(init_decl (d_name c) - -)])")
        t |> equal(decls("__attribute__((unused)) static int u;"), "(decl 0 [(attribute __attribute__((unused))) (spec static) (spec int)] [(init_decl (d_name u) - -)])")
        t |> equal(decls("__extension__ __extension__ long long ll;"), "(decl 1 [(spec long) (spec long)] [(init_decl (d_name ll) - -)])")
        t |> equal(decls("_Complex int ci;"), "(decl 0 [(spec _Complex) (spec int)] [(init_decl (d_name ci) - -)])")
    }
    t |> run("`_Thread_local` and `__thread` beside `static` or `extern`, a storage class repeated") @(t : T?) {
        t |> equal(decls("_Thread_local static int t; __thread extern int u; __thread int v;"),
                   "(decl 0 [(spec _Thread_local) (spec static) (spec int)] [(init_decl (d_name t) - -)]) (decl 0 [(spec _Thread_local) (spec extern) (spec int)] [(init_decl (d_name u) - -)]) (decl 0 [(spec _Thread_local) (spec int)] [(init_decl (d_name v) - -)])")
        t |> equal(decls("static static int s;"), "(decl 0 [(spec static) (spec static) (spec int)] [(init_decl (d_name s) - -)])")
    }
    t |> run("storage classes that do not combine, and a parameter's storage class other than `register`") @(t : T?) {
        t |> equal(decls("static extern int x;"), "error: t.c:1:8: expected a storage class that combines with those before it, got 'extern'")
        t |> equal(decls("typedef static int x;"), "error: t.c:1:9: expected a storage class that combines with those before it, got 'static'")
        t |> equal(decls("_Thread_local auto int v;"), "error: t.c:1:15: expected a storage class that combines with those before it, got 'auto'")
        t |> equal(decls("register _Thread_local int v;"), "error: t.c:1:10: expected a storage class that combines with those before it, got '_Thread_local'")
        t |> equal(decls("void m(static int x);"), "error: t.c:1:8: expected 'register' as a parameter's storage class, got 'static'")
        t |> equal(decls("void m(inline int x);"), "error: t.c:1:8: expected 'register' as a parameter's storage class, got 'inline'")
        t |> equal(decls("void m(register int x);"), "(decl 0 [(spec void)] [(init_decl (d_function 0 (d_name m) [(param [(spec register) (spec int)] (d_name x))]) - -)])")
    }
    t |> run("a declaration with no type specifier and no specifier at all") @(t : T?) {
        t |> equal(decls("static x;"), "error: t.c:1:1: a specifier list with no type specifier is not parsed")
        t |> equal(decls("const;"), "error: t.c:1:1: a specifier list with no type specifier is not parsed")
        t |> equal(decls("x;"), "error: t.c:1:1: expected a declaration, got 'x'")
        t |> equal(decls("int int x;"), "error: t.c:1:5: expected a type specifier that combines with those before it, got 'int'")
    }
}

[test(description = "named declarators: pointers with qualifiers, arrays of every form, prototypes with named and abstract parameters, `...` and `(void)`, parenthesised declarators, an asm label and attributes after a declarator or a parameter")]
def test_declarators(t : T?) {
    t |> run("pointers and parentheses") @(t : T?) {
        t |> equal(decls("int *const *volatile p;"), "(decl 0 [(spec int)] [(init_decl (d_pointer (d_pointer (d_name p) [(spec volatile)]) [(spec const)]) - -)])")
        t |> equal(decls("int ((x));"), "(decl 0 [(spec int)] [(init_decl (d_paren (d_paren (d_name x) []) []) - -)])")
        t |> equal(decls("int (*(*x)(void))[3];"),
                   "(decl 0 [(spec int)] [(init_decl (d_array 0 (d_paren (d_pointer (d_function 0 (d_paren (d_pointer (d_name x) []) []) [(param [(spec void)] -)]) []) []) (int 3) []) - -)])")
    }
    t |> run("arrays: unsized, sized, `static`, `[*]`, qualifiers in a parameter") @(t : T?) {
        t |> equal(decls("int x[], y[3][4];"), "(decl 0 [(spec int)] [(init_decl (d_array 0 (d_name x) - []) - -) (init_decl (d_array 0 (d_array 0 (d_name y) (int 3) []) (int 4) []) - -)])")
        t |> equal(decls("void z(int a[static const 3], int b[*], int c[const]);"),
                   "(decl 0 [(spec void)] [(init_decl (d_function 0 (d_name z) [(param [(spec int)] (d_array 1 (d_name a) (int 3) [(spec const)])) (param [(spec int)] (d_array 2 (d_name b) - [])) (param [(spec int)] (d_array 0 (d_name c) - [(spec const)]))]) - -)])")
    }
    t |> run("prototypes") @(t : T?) {
        t |> equal(decls("extern int f(int, char *, ...);"), "(decl 0 [(spec extern) (spec int)] [(init_decl (d_function 1 (d_name f) [(param [(spec int)] -) (param [(spec char)] (d_pointer - []))]) - -)])")
        t |> equal(decls("int g(void), h();"), "(decl 0 [(spec int)] [(init_decl (d_function 0 (d_name g) [(param [(spec void)] -)]) - -) (init_decl (d_function 0 (d_name h) []) - -)])")
        t |> equal(decls("int (*fp)(int x, T (*cb)(T));"),
                   "(decl 0 [(spec int)] [(init_decl (d_function 0 (d_paren (d_pointer (d_name fp) []) []) [(param [(spec int)] (d_name x)) (param [(typedef_name T)] (d_function 0 (d_paren (d_pointer (d_name cb) []) []) [(param [(typedef_name T)] -)]))]) - -)])")
    }
    t |> run("an asm label, attributes after a declarator, before a later declarator and after a parameter") @(t : T?) {
        t |> equal(decls("char *s __asm__(\"real\" \"_name\") __attribute__((unused));"),
                   "(decl 0 [(spec char)] [(init_decl (d_pointer (d_name s) []) - (asm_label (string \"real\" \"_name\")) [(attribute __attribute__((unused)))])])")
        t |> equal(decls("int a, __attribute__((x)) b __attribute__((y));"),
                   "(decl 0 [(spec int)] [(init_decl (d_name a) - -) (init_decl (d_name b) - - [(attribute __attribute__((x))) (attribute __attribute__((y)))])])")
        t |> equal(decls("void k(int x __attribute__((unused)));"),
                   "(decl 0 [(spec void)] [(init_decl (d_function 0 (d_name k) [(param [(spec int)] (d_name x) [(attribute __attribute__((unused)))])]) - -)])")
        t |> equal(decls("void n(void) __attribute__((noreturn));"),
                   "(decl 0 [(spec void)] [(init_decl (d_function 0 (d_name n) [(param [(spec void)] -)]) - - [(attribute __attribute__((noreturn)))])])")
    }
}

[test(description = "init-declarator lists: expressions and initializer lists with designators, a declaration with no declarator, and `_Static_assert` with and without its message")]
def test_declarations(t : T?) {
    t |> equal(decls("static const int *p = 0, a[3] = \{1, [2] = 2\};"),
               "(decl 0 [(spec static) (spec const) (spec int)] [(init_decl (d_pointer (d_name p) []) (int 0) -) (init_decl (d_array 0 (d_name a) (int 3) []) (init_list [(init [] (int 1)) (init [(index_desig (int 2) -)] (int 2))]) -)])")
    t |> equal(decls("T s = \{ .x = 1, .y = \{ 2 \} \};"),
               "(decl 0 [(typedef_name T)] [(init_decl (d_name s) (init_list [(init [(field x)] (int 1)) (init [(field y)] (init_list [(init [] (int 2))]))]) -)])")
    t |> equal(decls("int x = 1, y = x + 1;"), "(decl 0 [(spec int)] [(init_decl (d_name x) (int 1) -) (init_decl (d_name y) (binary + (ident x) (int 1)) -)])")
    t |> equal(decls("int;"), "(decl 0 [(spec int)] [])")
    t |> equal(decls("_Static_assert(sizeof(int) == 4, \"int\");"), "(static_assert (binary == (sizeof_type (type_name [(spec int)] -)) (int 4)) (string \"int\"))")
    t |> equal(decls("_Static_assert(1);"), "(static_assert (int 1) -)")
}

[test(description = "a typedef name enters the table right after its declarator; an ordinary name in an inner scope or a prototype shadows it until the scope closes; the probe's typedef-scope cases that need no statement, record, enum or definition")]
def test_typedef_table(t : T?) {
    t |> run("a typedef declares a type name for what follows, redeclared as the same typedef too") @(t : T?) {
        t |> equal(decls("typedef int U; U u; typedef int U; U *v;"),
                   "(decl 0 [(spec typedef) (spec int)] [(init_decl (d_name U) - -)]) (decl 0 [(typedef_name U)] [(init_decl (d_name u) - -)]) (decl 0 [(spec typedef) (spec int)] [(init_decl (d_name U) - -)]) (decl 0 [(typedef_name U)] [(init_decl (d_pointer (d_name v) []) - -)])")
        t |> equal(decls("typedef int U, *P; P q;"), "(decl 0 [(spec typedef) (spec int)] [(init_decl (d_name U) - -) (init_decl (d_pointer (d_name P) []) - -)]) (decl 0 [(typedef_name P)] [(init_decl (d_name q) - -)])")
        t |> equal(decls("typedef int U = 1;"), "error: t.c:1:15: expected ';', got '='")
    }
    t |> run("`T a;`: a typedef name as the type") @(t : T?) {
        t |> equal(decls("T a;"), "(decl 0 [(typedef_name T)] [(init_decl (d_name a) - -)])")
    }
    t |> run("f1 `\{ int T; T = 1; \}`: a block-scope object shadows the typedef until the block closes") @(t : T?) {
        var p : CParser
        opened(p, "int T; T = 1; T b;")
        c_scope_open(p)
        t |> equal(next_decl(p), "(decl 0 [(spec int)] [(init_decl (d_name T) - -)])")
        t |> equal(next_expr(p), "(assign = (ident T) (int 1))")
        c_scope_close(p)
        t |> equal(next_decl(p), "(decl 0 [(typedef_name T)] [(init_decl (d_name b) - -)])")
    }
    t |> run("f2 `T (x);` and f4 `T * x;`: declarations, not a call or a product") @(t : T?) {
        t |> equal(decls("T (x);"), "(decl 0 [(typedef_name T)] [(init_decl (d_paren (d_name x) []) - -)])")
        t |> equal(decls("T * x;"), "(decl 0 [(typedef_name T)] [(init_decl (d_pointer (d_name x) []) - -)])")
    }
    t |> run("f3 `(T) - x`: a cast") @(t : T?) {
        var p : CParser
        opened(p, "(T) - x")
        t |> equal(next_expr(p), "(cast (type_name [(typedef_name T)] -) (unary - (ident x)))")
    }
    t |> run("f5 `\{ typedef char T; T c; \} T d;`: an inner typedef ends with its block") @(t : T?) {
        var p : CParser
        opened(p, "typedef char T; T c; T d;")
        c_scope_open(p)
        t |> equal(next_decl(p), "(decl 0 [(spec typedef) (spec char)] [(init_decl (d_name T) - -)])")
        t |> equal(next_decl(p), "(decl 0 [(typedef_name T)] [(init_decl (d_name c) - -)])")
        c_scope_close(p)
        t |> equal(next_decl(p), "(decl 0 [(typedef_name T)] [(init_decl (d_name d) - -)])")
    }
    t |> run("f6 `void f6(T T)` and f9 `void f9(int T)`: a parameter shadows the typedef in its prototype only") @(t : T?) {
        t |> equal(decls("void f6(T T); T after;"),
                   "(decl 0 [(spec void)] [(init_decl (d_function 0 (d_name f6) [(param [(typedef_name T)] (d_name T))]) - -)]) (decl 0 [(typedef_name T)] [(init_decl (d_name after) - -)])")
        t |> equal(decls("void f9(int T, int (*g)(int (T)));"),
                   "(decl 0 [(spec void)] [(init_decl (d_function 0 (d_name f9) [(param [(spec int)] (d_name T)) (param [(spec int)] (d_function 0 (d_paren (d_pointer (d_name g) []) []) [(param [(spec int)] (d_paren (d_name T) []))]))]) - -)])")
    }
    t |> run("f8 `unsigned T; T = 3;` and f14 `T T; T = 6;`: the declared name is ordinary from its declarator on") @(t : T?) {
        var p : CParser
        opened(p, "unsigned T; T = 3;")
        c_scope_open(p)
        t |> equal(next_decl(p), "(decl 0 [(spec unsigned)] [(init_decl (d_name T) - -)])")
        t |> equal(next_expr(p), "(assign = (ident T) (int 3))")
        opened(p, "T T; T = 6;")
        c_scope_open(p)
        t |> equal(next_decl(p), "(decl 0 [(typedef_name T)] [(init_decl (d_name T) - -)])")
        t |> equal(next_expr(p), "(assign = (ident T) (int 6))")
    }
    t |> run("f12 `int f12(T);`: an abstract parameter of the typedef's type") @(t : T?) {
        t |> equal(decls("int f12(T);"), "(decl 0 [(spec int)] [(init_decl (d_function 0 (d_name f12) [(param [(typedef_name T)] -)]) - -)])")
    }
    t |> run("f17 `int x = sizeof(T), T = 1;` and `int T = T;`: a name is declared right after its declarator") @(t : T?) {
        var p : CParser
        opened(p, "int x = sizeof(T), T = 1; T = 2;")
        c_scope_open(p)
        t |> equal(next_decl(p), "(decl 0 [(spec int)] [(init_decl (d_name x) (sizeof_type (type_name [(typedef_name T)] -)) -) (init_decl (d_name T) (int 1) -)])")
        t |> equal(next_expr(p), "(assign = (ident T) (int 2))")
        t |> equal(decls("int T = T;"), "(decl 0 [(spec int)] [(init_decl (d_name T) (ident T) -)])")
    }
    t |> run("f18 `int T = 1; \{ T * 2; \}`: the shadowing reaches an inner block, where `T * 2` is a product") @(t : T?) {
        var p : CParser
        opened(p, "int T = 1; T * 2;")
        c_scope_open(p)
        t |> equal(next_decl(p), "(decl 0 [(spec int)] [(init_decl (d_name T) (int 1) -)])")
        c_scope_open(p)
        t |> equal(next_expr(p), "(binary * (ident T) (int 2))")
    }
    t |> run("`__builtin_va_list` is a typedef name before the first line, as clang declares it") @(t : T?) {
        t |> equal(decls("__builtin_va_list ap;"), "(decl 0 [(typedef_name __builtin_va_list)] [(init_decl (d_name ap) - -)])")
    }
}

[test(description = "a declaration the parser does not take is refused at its token: an identifier list outside a definition and the refused words; a function definition in a block is malformed at its brace")]
def test_refusals(t : T?) {
    t |> equal(decls("int f(void) \{ return 0; \}"), "error: t.c:1:13: expected ';', got '\{'")
    t |> equal(decls("int h(a, b);"), "error: t.c:1:7: an identifier list outside a function definition is not parsed")
    t |> equal(decls("int f(a) int a; \{\}"), "error: t.c:1:7: an identifier list outside a function definition is not parsed")
    t |> equal(decls("__int128 x;"), "error: t.c:1:1: the __int128 type is not parsed")
    t |> equal(decls("__auto_type x = 1;"), "error: t.c:1:1: __auto_type is not parsed")
    t |> equal(decls("_Atomic(int) x;"), "error: t.c:1:1: the _Atomic(type) specifier is not parsed")
    t |> equal(decls("__label__ l;"), "error: t.c:1:1: a local label declaration (__label__) is not parsed")
    t |> equal(decls("int x = _Generic(1, int: 2);"), "error: t.c:1:9: a generic selection (_Generic) is not parsed")
    t |> equal(decls("T s = \{ x: 1 \};"), "error: t.c:1:9: the old GNU designator 'member:' is not parsed")
}

[test(description = "a malformed declaration ends with a located error at each position: specifiers, declarator, suffixes, initializer, asm label, list and end")]
def test_malformed(t : T?) {
    let cases = fixed_array(
        ("int", "t.c:1:4: expected a declarator, got end of input"),
        ("int x", "t.c:1:6: expected ';', got end of input"),
        ("int x y;", "t.c:1:7: expected ';', got 'y'"),
        ("int = 3;", "t.c:1:5: expected a declarator, got '='"),
        ("int x = ;", "t.c:1:9: expected an expression, got ';'"),
        ("int x = \{1,", "t.c:1:12: expected an expression, got end of input"),
        ("int (x;", "t.c:1:7: expected ')', got ';'"),
        ("int *;", "t.c:1:6: expected a declarator, got ';'"),
        ("int x[3;", "t.c:1:8: expected ']', got ';'"),
        ("int f(int,);", "t.c:1:11: expected a parameter declaration, got ')'"),
        ("int f(int x", "t.c:1:12: expected ')', got end of input"),
        ("int f(a,);", "t.c:1:9: expected a parameter name, got ')'"),
        ("int x, ;", "t.c:1:8: expected a declarator, got ';'"),
        ("char *s __asm__(x);", "t.c:1:17: expected a string literal, got 'x'"),
        ("char *s __asm__(\"n\";", "t.c:1:20: expected ')', got ';'"),
        ("int x __attribute__((u);", "t.c:1:25: expected ')' closing __attribute__, got end of input"),
        ("_Static_assert(1, 2);", "t.c:1:19: expected a string literal, got '2'"),
        ("_Static_assert(1", "t.c:1:17: expected ')', got end of input"),
        ("_Static_assert(1, \"m\")", "t.c:1:23: expected ';', got end of input"),
        ("long long long x;", "t.c:1:11: expected a type specifier that combines with those before it, got 'long'"))
    for (c in cases) {
        t |> equal(decls(c._0), "error: {c._1}", c._0)
    }
}

[test(description = "declarator nesting is bounded like expressions: 256 levels of parentheses, pointers or parameter lists parse in the test's 256 KiB stack, one more is refused at its token, and long chains end in the refusal")]
def test_nesting_bound(t : T?) {
    t |> success(decls("int {repeat("(", 256)}x{repeat(")", 256)};") |> starts_with("(decl 0 [(spec int)] [(init_decl (d_paren"))
    t |> equal(decls("int {repeat("(", 257)}x{repeat(")", 257)};"), "error: t.c:1:261: nesting deeper than 256 levels is not parsed")
    t |> success(decls("int {repeat("*", 256)}x;") |> starts_with("(decl 0 [(spec int)] [(init_decl (d_pointer"))
    t |> equal(decls("int {repeat("*", 257)}x;"), "error: t.c:1:261: nesting deeper than 256 levels is not parsed")
    t |> success(decls("int f{repeat("(int (", 128)}x{repeat("))", 128)};") |> starts_with("(decl 0 [(spec int)] [(init_decl (d_function"))
    for (text in fixed_array("int {repeat("(*", 3000)}x", "int f{repeat("(int (*g)", 3000)}", "int f{repeat("(int (", 3000)}", "int x[{repeat("sizeof(int[", 3000)}",
            "int x = {repeat("\{", 3000)}", "typeof({repeat("typeof(", 3000)}")) {
        t |> success(decls(text) |> ends_with("nesting deeper than 256 levels is not parsed"), slice(text, 0, 12))
    }
}

[test(description = "parsing the preprocessed own headers allocates no string and a fixed number of heap blocks, however many declarations they hold")]
def test_no_allocation(t : T?) {
    let text = join(PREPROCESSED_HEADERS, "\n")
    var p : CParser
    c_parser_open_text(p, text, "x.c")
    let heap = int(heap_allocation_count())
    let strings = int(string_heap_allocation_count())
    var count = 0
    while (!p.failed && p.unit.toks[p.pos].kind != int(CTok.EOF)) {
        c_declaration(p)
        count++
    }
    let heap_used = int(heap_allocation_count()) - heap
    let strings_used = int(string_heap_allocation_count()) - strings
    t |> success(!p.failed, p.err)
    t |> success(count > 150, "{count} declarations")
    t |> equal(strings_used, 0, "string allocations")
    t |> success(heap_used <= 16, "heap allocations {heap_used} over {length(p.unit.toks)} tokens and {count} declarations")
}

// the declarations of `text` under the msvc dialect, as `decls` gives them
def private decls_msvc(text : string) : string {
    var p : CParser
    c_parser_open_text(p, text, "t.c", true)
    var parts : array<string>
    while (!p.failed && p.unit.toks[p.pos].kind != int(CTok.EOF)) {
        let d = c_declaration(p)
        if (!p.failed) {
            parts |> push(c_dump(p.ast, p.unit, d))
        }
    }
    return p.failed ? "error: {p.err}" : join(parts, " ")
}

[test(description = "the typedef names clang declares before a unit: both dialects' builtins, msvc's `size_t`, and the 128-bit integer names refused where they are used")]
def test_builtin_typedefs(t : T?) {
    t |> equal(decls("__builtin_ms_va_list a; __NSConstantString s;"),
               "(decl 0 [(typedef_name __builtin_ms_va_list)] [(init_decl (d_name a) - -)]) (decl 0 [(typedef_name __NSConstantString)] [(init_decl (d_name s) - -)])")
    t |> equal(decls("int n = sizeof(__builtin_ms_va_list);"), "(decl 0 [(spec int)] [(init_decl (d_name n) (sizeof_type (type_name [(typedef_name __builtin_ms_va_list)] -)) -)])")
    t |> equal(decls_msvc("size_t n;"), "(decl 0 [(typedef_name size_t)] [(init_decl (d_name n) - -)])")
    t |> equal(decls("size_t n;"), "error: t.c:1:1: expected a declaration, got 'size_t'")
    t |> equal(decls("__int128_t x;"), "error: t.c:1:1: the __int128 type is not parsed")
    t |> equal(decls("const __uint128_t y;"), "error: t.c:1:7: the __int128 type is not parsed")
}

[test(description = "an array declarator's `static`, qualifiers and `[*]` where clang takes them: `static` once and with a size, a qualifier or `static` in a parameter's outermost array only, `[*]` in a prototype's parameter only; `...` after a parameter; an asm label of unprefixed literals")]
def test_declarator_contexts(t : T?) {
    t |> run("accepted: a parameter's outermost array, `[*]` at any level of a prototype's parameter") @(t : T?) {
        t |> equal(decls("void f(int a[*], int b[3][*], int c[*][3], int d[const], int e[const *], int (*p)(int q[*]));"),
                   "(decl 0 [(spec void)] [(init_decl (d_function 0 (d_name f) [(param [(spec int)] (d_array 2 (d_name a) - [])) (param [(spec int)] (d_array 2 (d_array 0 (d_name b) (int 3) []) - [])) (param [(spec int)] (d_array 0 (d_array 2 (d_name c) - []) (int 3) [])) (param [(spec int)] (d_array 0 (d_name d) - [(spec const)])) (param [(spec int)] (d_array 2 (d_name e) - [(spec const)])) (param [(spec int)] (d_function 0 (d_paren (d_pointer (d_name p) []) []) [(param [(spec int)] (d_array 2 (d_name q) - []))]))]) - -)])")
    }
    t |> equal(decls("void g(int (a)[const 3]);"), "(decl 0 [(spec void)] [(init_decl (d_function 0 (d_name g) [(param [(spec int)] (d_array 0 (d_paren (d_name a) []) (int 3) [(spec const)]))]) - -)])")
    let cases = fixed_array(
        ("void f(int a[static const static 3]);", "t.c:1:27: expected an expression, got 'static'"),
        ("void f(int a[static]);", "t.c:1:20: expected an array size after 'static', got ']'"),
        ("void f(int a[static *]);", "t.c:1:21: expected an array size after 'static', got '*'"),
        ("int a[const 3];", "t.c:1:6: a qualifier or 'static' in an array declarator outside a parameter's outermost array is not parsed"),
        ("int a[static 3];", "t.c:1:6: a qualifier or 'static' in an array declarator outside a parameter's outermost array is not parsed"),
        ("void f(int a[3][const 3]);", "t.c:1:16: a qualifier or 'static' in an array declarator outside a parameter's outermost array is not parsed"),
        ("void f(int (*a)[const 3]);", "t.c:1:16: a qualifier or 'static' in an array declarator outside a parameter's outermost array is not parsed"),
        ("int a[*];", "t.c:1:6: '[*]' outside a function prototype's parameter is not parsed"),
        ("typedef int T[*];", "t.c:1:14: '[*]' outside a function prototype's parameter is not parsed"),
        ("int (*q)[*];", "t.c:1:9: '[*]' outside a function prototype's parameter is not parsed"),
        ("int n = sizeof(int[*]);", "t.c:1:19: '[*]' outside a function prototype's parameter is not parsed"),
        ("int f(...);", "t.c:1:7: a variadic parameter list with no parameter before '...' is not parsed"),
        ("char *s __asm__(L\"w\");", "t.c:1:17: a prefixed string literal in an asm label is not parsed"),
        ("char *s __asm__(u8\"x\");", "t.c:1:17: a prefixed string literal in an asm label is not parsed"),
        ("char *s __asm__(\"a\" L\"b\");", "t.c:1:21: a prefixed string literal in an asm label is not parsed"))
    for (c in cases) {
        t |> equal(decls(c._0), "error: {c._1}", c._0)
    }
}
