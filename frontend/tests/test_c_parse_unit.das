options gen2
options stack = 262144
require dastest/testing_boost public
require strings
require daslib/strings_boost
require ../c_parser.das
require _preprocessed_headers

//! `frontend/c_parser.das`, its records, enums, function definitions and units: every member,
//! bit-field, enumerator and definition form as a dumped tree, the tag and enumerator scopes, the
//! old-style declaration list, the body kept as its tokens and the scope it is read in, the
//! file-scope forms, every refusal and malformed input as a located error, the nesting bound of the
//! new recursive forms, and a unit of preprocessed headers and a program parsed with no allocation
//! per token.

// a parser over `text` with `T` a typedef name
def private opened(var p : CParser; text : string) {
    c_parser_open_text(p, text, "t.c")
    c_declare(p, c_symbol(p.unit, "T"), CBinding.TYPEDEF)
}

// the external declarations of the unit `text`, each tree and a blank between them, or
// `error: <message>`; `T` is a typedef name before the first
def private unit(text : string) : string {
    var p : CParser
    opened(p, text)
    let u = c_unit(p)
    return "error: {p.err}" if (p.failed)
    var parts : array<string>
    var at = p.ast.nodes[u].a
    while (at >= 0) {
        parts |> push(c_dump(p.ast, p.unit, at))
        at = p.ast.nodes[at].next
    }
    return join(parts, " ")
}

// the next declaration of `p` as a tree, or `error: <message>`
def private next_decl(var p : CParser) : string {
    let d = c_declaration(p)
    return p.failed ? "error: {p.err}" : c_dump(p.ast, p.unit, d)
}

// the expression `skip` tokens into the body of definition `def` up to its `;`, read in the scope of
// the definition's parameters as its body will be, as a tree; the cursor ends where it was
def private body_expr(var p : CParser; def_node, skip : int) : string {
    let back = p.pos
    let f = c_name_function(p.ast, p.ast.nodes[p.ast.nodes[def_node].b].a)
    c_scope_open(p)
    c_parameters_declare(p, f)
    p.pos = p.ast.nodes[p.ast.nodes[def_node].d].a + skip
    let e = c_expression(p)
    c_scope_close(p)
    p.pos = back
    return p.failed ? "error: {p.err}" : c_dump(p.ast, p.unit, e)
}

[test(description = "struct and union bodies: member declarators, bit-fields named, unnamed and zero-width, anonymous members, nested definitions, forward and incomplete tags, a flexible array member, function pointer members, an empty body, `;` and `_Static_assert` among the members")]
def test_records(t : T?) {
    t |> run("members, several declarators, a union") @(t : T?) {
        t |> equal(unit("struct S \{ int a; char *b, c[3]; \} s; union U \{ int i; float f; \};"),
                   "(decl 0 [(record struct S 1 [(member_decl 0 [(spec int)] [(member (d_name a) -)]) (member_decl 0 [(spec char)] [(member (d_pointer (d_name b) []) -) (member (d_array 0 (d_name c) (int 3) []) -)])])] [(init_decl (d_name s) - -)]) (decl 0 [(record union U 1 [(member_decl 0 [(spec int)] [(member (d_name i) -)]) (member_decl 0 [(spec float)] [(member (d_name f) -)])])] [])")
    }
    t |> run("bit-fields: named, unnamed, zero-width") @(t : T?) {
        t |> equal(unit("struct B \{ unsigned a : 3, : 0; int : 2; signed b : 1; \};"),
                   "(decl 0 [(record struct B 1 [(member_decl 0 [(spec unsigned)] [(member (d_name a) (int 3)) (member - (int 0))]) (member_decl 0 [(spec int)] [(member - (int 2))]) (member_decl 0 [(spec signed)] [(member (d_name b) (int 1))])])] [])")
    }
    t |> run("anonymous members, a nested definition, `__extension__` before a member") @(t : T?) {
        t |> equal(unit("struct O \{ struct I \{ int x; \} i; union \{ int u; \}; __extension__ struct \{ int y; \}; \};"),
                   "(decl 0 [(record struct O 1 [(member_decl 0 [(record struct I 1 [(member_decl 0 [(spec int)] [(member (d_name x) -)])])] [(member (d_name i) -)]) (member_decl 0 [(record union - 1 [(member_decl 0 [(spec int)] [(member (d_name u) -)])])] []) (member_decl 1 [(record struct - 1 [(member_decl 0 [(spec int)] [(member (d_name y) -)])])] [])])] [])")
    }
    t |> run("forward and incomplete tags, a flexible array member, a function pointer member, an empty body") @(t : T?) {
        t |> equal(unit("struct F; struct F *p; union U;"), "(decl 0 [(record struct F 0 [])] []) (decl 0 [(record struct F 0 [])] [(init_decl (d_pointer (d_name p) []) - -)]) (decl 0 [(record union U 0 [])] [])")
        t |> equal(unit("struct V \{ int n; int a[]; \};"), "(decl 0 [(record struct V 1 [(member_decl 0 [(spec int)] [(member (d_name n) -)]) (member_decl 0 [(spec int)] [(member (d_array 0 (d_name a) - []) -)])])] [])")
        t |> equal(unit("struct C \{ int (*cb)(T, int); \};"),
                   "(decl 0 [(record struct C 1 [(member_decl 0 [(spec int)] [(member (d_function 0 (d_paren (d_pointer (d_name cb) []) []) [(param [(typedef_name T)] -) (param [(spec int)] -)]) -)])])] [])")
        t |> equal(unit("struct E \{\};"), "(decl 0 [(record struct E 1 [])] [])")
    }
    t |> run("`;` alone and `_Static_assert` among the members") @(t : T?) {
        t |> equal(unit("struct A \{ ; int a; _Static_assert(1, \"x\"); \};"),
                   "(decl 0 [(record struct A 1 [(member_decl 0 [(spec int)] [(member (d_name a) -)]) (static_assert (int 1) (string \"x\"))])] [])")
    }
}

[test(description = "attributes on a record and its members are kept as nodes: after the keyword, after the body, before a later member declarator and after a member, a bit-field's included; several in a row keep their order")]
def test_record_attributes(t : T?) {
    t |> equal(unit("struct __attribute__((packed)) P \{ int a __attribute__((aligned(8))), __attribute__((x)) b; \} __attribute__((aligned(16)));"),
               "(decl 0 [(record struct P 1 [(member_decl 0 [(spec int)] [(member (d_name a) - [(attribute __attribute__((aligned(8))))]) (member (d_name b) - [(attribute __attribute__((x)))])])] [(attribute __attribute__((packed))) (attribute __attribute__((aligned(16))))])] [])")
    t |> equal(unit("struct Q \{ int a : 3 __attribute__((packed)); \} __attribute__((packed)) __attribute__((aligned(4))) q;"),
               "(decl 0 [(record struct Q 1 [(member_decl 0 [(spec int)] [(member (d_name a) (int 3) [(attribute __attribute__((packed)))])])] [(attribute __attribute__((packed))) (attribute __attribute__((aligned(4))))])] [(init_decl (d_name q) - -)])")
    t |> equal(unit("struct __attribute__((a)) __attribute__((b)) R \{ int x, __attribute__((c)) __attribute__((d)) y __attribute__((e)); \} __attribute__((f));"),
               "(decl 0 [(record struct R 1 [(member_decl 0 [(spec int)] [(member (d_name x) -) (member (d_name y) - [(attribute __attribute__((c))) (attribute __attribute__((d))) (attribute __attribute__((e)))])])] [(attribute __attribute__((a))) (attribute __attribute__((b))) (attribute __attribute__((f)))])] [])")
}

[test(description = "enum bodies: enumerators with and without constant expressions, a trailing comma, attributes on the enum and an enumerator; each enumerator an ordinary identifier from the end of its own definition on")]
def test_enums(t : T?) {
    t |> run("enumerators, values, a trailing comma") @(t : T?) {
        t |> equal(unit("enum E \{ A, B = 2, C = B + 1, \} e;"),
                   "(decl 0 [(enum E 1 [(enumerator A -) (enumerator B (int 2)) (enumerator C (binary + (ident B) (int 1)))])] [(init_decl (d_name e) - -)])")
        t |> equal(unit("enum \{ X \};"), "(decl 0 [(enum - 1 [(enumerator X -)])] [])")
        t |> equal(unit("enum E; enum E e;"), "(decl 0 [(enum E 0 [])] []) (decl 0 [(enum E 0 [])] [(init_decl (d_name e) - -)])")
    }
    t |> run("attributes after the keyword, after the body and after an enumerator's name") @(t : T?) {
        t |> equal(unit("enum __attribute__((packed)) E \{ A __attribute__((deprecated)) = 1, B \} __attribute__((aligned(4)));"),
                   "(decl 0 [(enum E 1 [(enumerator A (int 1) [(attribute __attribute__((deprecated)))]) (enumerator B -)] [(attribute __attribute__((packed))) (attribute __attribute__((aligned(4))))])] [])")
    }
    t |> run("an enumerator shadows a typedef name after its own value: `enum \{ T = sizeof(T) \}` reads the type, the next use the constant") @(t : T?) {
        t |> equal(unit("enum \{ T = sizeof(T), U = T \}; int x = T;"),
                   "(decl 0 [(enum - 1 [(enumerator T (sizeof_type (type_name [(typedef_name T)] -))) (enumerator U (ident T))])] []) (decl 0 [(spec int)] [(init_decl (d_name x) (ident T) -)])")
    }
}

[test(description = "tag and enumerator scopes: a tag binds nothing in the ordinary name space, a record body opens no scope, a tag defined in a parameter list, and the probe's cases s1, f10 and f13")]
def test_scopes(t : T?) {
    t |> run("s1 `struct s1 \{ T T; int z; \};`: a member named as the typedef binds nothing") @(t : T?) {
        t |> equal(unit("struct s1 \{ T T; int z; \}; T after;"),
                   "(decl 0 [(record struct s1 1 [(member_decl 0 [(typedef_name T)] [(member (d_name T) -)]) (member_decl 0 [(spec int)] [(member (d_name z) -)])])] []) (decl 0 [(typedef_name T)] [(init_decl (d_name after) - -)])")
    }
    t |> run("f10 `\{ enum \{ T = 5 \}; int q = T; \}`: an enumerator in a block shadows the typedef until the block closes") @(t : T?) {
        var p : CParser
        opened(p, "enum \{ T = 5 \}; int q = T; T r;")
        c_scope_open(p)
        t |> equal(next_decl(p), "(decl 0 [(enum - 1 [(enumerator T (int 5))])] [])")
        t |> equal(next_decl(p), "(decl 0 [(spec int)] [(init_decl (d_name q) (ident T) -)])")
        c_scope_close(p)
        t |> equal(next_decl(p), "(decl 0 [(typedef_name T)] [(init_decl (d_name r) - -)])")
    }
    t |> run("f13 `\{ struct T \{ int a; \} s; T t; \}`: a tag named as the typedef leaves it a type") @(t : T?) {
        var p : CParser
        opened(p, "struct T \{ int a; \} s; T t;")
        c_scope_open(p)
        t |> equal(next_decl(p), "(decl 0 [(record struct T 1 [(member_decl 0 [(spec int)] [(member (d_name a) -)])])] [(init_decl (d_name s) - -)])")
        t |> equal(next_decl(p), "(decl 0 [(typedef_name T)] [(init_decl (d_name t) - -)])")
    }
    t |> run("an enumerator of a member's enum binds in the scope around the record") @(t : T?) {
        t |> equal(unit("struct S \{ enum \{ T \} e; \} s; int x = T;"),
                   "(decl 0 [(record struct S 1 [(member_decl 0 [(enum - 1 [(enumerator T -)])] [(member (d_name e) -)])])] [(init_decl (d_name s) - -)]) (decl 0 [(spec int)] [(init_decl (d_name x) (ident T) -)])")
    }
    t |> run("a tag defined in a parameter list; an enumerator declared there ends with the prototype") @(t : T?) {
        t |> equal(unit("void f(struct S \{ int a; \} x);"),
                   "(decl 0 [(spec void)] [(init_decl (d_function 0 (d_name f) [(param [(record struct S 1 [(member_decl 0 [(spec int)] [(member (d_name a) -)])])] (d_name x))]) - -)])")
        t |> equal(unit("void g(enum \{ T \} e, int a[T]); T y;"),
                   "(decl 0 [(spec void)] [(init_decl (d_function 0 (d_name g) [(param [(enum - 1 [(enumerator T -)])] (d_name e)) (param [(spec int)] (d_array 0 (d_name a) (ident T) []))]) - -)]) (decl 0 [(typedef_name T)] [(init_decl (d_name y) - -)])")
    }
}

[test(description = "a malformed record or enum ends with a located error at each position: the tag, a member's specifiers, declarator, width and end, the body's end, an enumerator, its value and the list")]
def test_malformed_records(t : T?) {
    let cases = fixed_array(
        ("struct;", "t.c:1:7: expected a tag name or '\{' after 'struct', got ';'"),
        ("enum = 1;", "t.c:1:6: expected a tag name or '\{' after 'enum', got '='"),
        ("struct S \{ int a \};", "t.c:1:18: expected ';', got '\}'"),
        ("struct S \{ int a;", "t.c:1:18: expected a member declaration, got end of input"),
        ("struct S \{ static int a; \};", "t.c:1:12: expected a member declaration, got 'static'"),
        ("struct S \{ x; \};", "t.c:1:12: expected a member declaration, got 'x'"),
        ("struct S \{ int a : ; \};", "t.c:1:20: expected an expression, got ';'"),
        ("struct S \{ int a, ; \};", "t.c:1:19: expected a declarator, got ';'"),
        ("struct S \{ int a __asm__(\"x\"); \};", "t.c:1:18: expected ';', got '__asm__'"),
        ("struct S __attribute__((packed)) \{ int a; \};", "t.c:1:34: expected a declarator, got '\{'"),
        ("enum E \{ \};", "t.c:1:10: expected an enumerator, got '\}'"),
        ("enum E \{ A B \};", "t.c:1:12: expected '\}', got 'B'"),
        ("enum E \{ A = \};", "t.c:1:14: expected an expression, got '\}'"),
        ("enum E \{ 1 \};", "t.c:1:10: expected an enumerator, got '1'"),
        ("enum E \{ A,, \};", "t.c:1:12: expected an enumerator, got ','"),
        ("enum E \{ A", "t.c:1:11: expected '\}', got end of input"))
    for (c in cases) {
        t |> equal(unit(c._0), "error: {c._1}", c._0)
    }
    t |> equal(unit("struct S \{ const; \};"), "error: t.c:1:12: a specifier list with no type specifier is not parsed")
}

[test(description = "function definitions: a prototype's, with specifiers, attributes after the declarator and `__extension__`, one returning a function pointer; the body kept as its tokens to the brace that balances its first")]
def test_definitions(t : T?) {
    t |> equal(unit("int main(void) \{ return 0; \}"), "(func_def 0 [(spec int)] (init_decl (d_function 0 (d_name main) [(param [(spec void)] -)]) - -) [] (body \{ return 0; \}))")
    t |> equal(unit("static inline void f(int a) __attribute__((noinline)) \{ \{ a; \} \{\} \} int x;"),
               "(func_def 0 [(spec static) (spec inline) (spec void)] (init_decl (d_function 0 (d_name f) [(param [(spec int)] (d_name a))]) - - [(attribute __attribute__((noinline)))]) [] (body \{ \{ a; \} \{\} \})) (decl 0 [(spec int)] [(init_decl (d_name x) - -)])")
    t |> equal(unit("__extension__ int (*h(int a))(int) \{ return 0; \}"),
               "(func_def 1 [(spec int)] (init_decl (d_function 0 (d_paren (d_pointer (d_function 0 (d_name h) [(param [(spec int)] (d_name a))]) []) []) [(param [(spec int)] -)]) - -) [] (body \{ return 0; \}))")
    t |> equal(unit("int (f)(void) \{\}"), "(func_def 0 [(spec int)] (init_decl (d_function 0 (d_paren (d_name f) []) [(param [(spec void)] -)]) - -) [] (body \{\}))")
    t |> equal(unit("int f(void) \{\} int g(void) \{\}"),
               "(func_def 0 [(spec int)] (init_decl (d_function 0 (d_name f) [(param [(spec void)] -)]) - -) [] (body \{\})) (func_def 0 [(spec int)] (init_decl (d_function 0 (d_name g) [(param [(spec void)] -)]) - -) [] (body \{\}))")
}

[test(description = "old-style definitions: the declaration list types each name of the identifier list once, a typedef name in it is a type, `register`, a parenthesised name, a record defined there, and the identifier list of a declarator that returns a function pointer; the probe's case f16")]
def test_old_style(t : T?) {
    t |> run("f16 `int f16(a, b) T a; int b; \{ return a + b; \}`") @(t : T?) {
        t |> equal(unit("int f16(a, b) T a; int b; \{ return a + b; \}"),
                   "(func_def 0 [(spec int)] (init_decl (d_function 2 (d_name f16) [(ident_param a) (ident_param b)]) - -) [(decl 0 [(typedef_name T)] [(init_decl (d_name a) - -)]) (decl 0 [(spec int)] [(init_decl (d_name b) - -)])] (body \{ return a + b; \}))")
    }
    t |> run("`register`, a list declaring two, a parenthesised name, a record, attributes before the list") @(t : T?) {
        t |> equal(unit("int f(a, b, c) register int a, b; int (c); \{\}"),
                   "(func_def 0 [(spec int)] (init_decl (d_function 2 (d_name f) [(ident_param a) (ident_param b) (ident_param c)]) - -) [(decl 0 [(spec register) (spec int)] [(init_decl (d_name a) - -) (init_decl (d_name b) - -)]) (decl 0 [(spec int)] [(init_decl (d_paren (d_name c) []) - -)])] (body \{\}))")
        t |> equal(unit("int f(a) __attribute__((unused)) struct S \{ int x; \} a; \{\}"),
                   "(func_def 0 [(spec int)] (init_decl (d_function 2 (d_name f) [(ident_param a)]) - - [(attribute __attribute__((unused)))]) [(decl 0 [(record struct S 1 [(member_decl 0 [(spec int)] [(member (d_name x) -)])])] [(init_decl (d_name a) - -)])] (body \{\}))")
    }
    t |> run("the identifier list of the declarator the name is declared through") @(t : T?) {
        t |> equal(unit("int (*f(a))(int) int a; \{\}"),
                   "(func_def 0 [(spec int)] (init_decl (d_function 0 (d_paren (d_pointer (d_function 2 (d_name f) [(ident_param a)]) []) []) [(param [(spec int)] -)]) - -) [(decl 0 [(spec int)] [(init_decl (d_name a) - -)])] (body \{\}))")
    }
}

[test(description = "the body is read in the scope of its definition's parameters: the probe's f6 and f9 bodies see the parameter that shadows the typedef, f16's its old-style names, and after the definition the typedef is a type again")]
def test_body_scope(t : T?) {
    var p : CParser
    opened(p, "void f6(T T) \{ T = 2; \} void f9(int T) \{ T = 4; \} int f16(a, b) T a; int b; \{ return a + b; \} T after;")
    let u = c_unit(p)
    t |> success(!p.failed, p.err)
    let f6 = p.ast.nodes[u].a
    let f9 = p.ast.nodes[f6].next
    let f16 = p.ast.nodes[f9].next
    t |> equal(body_expr(p, f6, 1), "(assign = (ident T) (int 2))")
    t |> equal(body_expr(p, f9, 1), "(assign = (ident T) (int 4))")
    t |> equal(body_expr(p, f16, 2), "(binary + (ident a) (ident b))")
    t |> equal(c_dump(p.ast, p.unit, p.ast.nodes[f16].next), "(decl 0 [(typedef_name T)] [(init_decl (d_name after) - -)])")
    t |> equal(unit("int T(void) \{ return 0; \} int y = T;"),
               "(func_def 0 [(spec int)] (init_decl (d_function 0 (d_name T) [(param [(spec void)] -)]) - -) [] (body \{ return 0; \})) (decl 0 [(spec int)] [(init_decl (d_name y) (ident T) -)])")
}

[test(description = "a malformed definition ends with a located error: a declarator a body cannot follow, an unbalanced body, and every rule of an old-style declaration list")]
def test_malformed_definitions(t : T?) {
    let cases = fixed_array(
        ("int f(void) __asm__(\"g\") \{\}", "t.c:1:26: expected ';', got '\{'"),
        ("typedef int F(void) \{\}", "t.c:1:21: expected ';', got '\{'"),
        ("int a, f(void) \{\}", "t.c:1:16: expected ';', got '\{'"),
        ("int (*fp)(void) \{\}", "t.c:1:17: expected ';', got '\{'"),
        ("int f(void) int x; \{\}", "t.c:1:13: expected ';', got 'int'"),
        ("int f(void) \{ \{ return 0; \}", "t.c:1:28: expected '\}' closing the function body, got end of input"),
        ("int f(a) int a = 1; \{\}", "t.c:1:16: expected ';', got '='"),
        ("int f(a) static int a; \{\}", "t.c:1:10: expected 'register' as a parameter's storage class, got 'static'"),
        ("int f(a) typedef int a; \{\}", "t.c:1:10: expected 'register' as a parameter's storage class, got 'typedef'"),
        ("int f(a, b) int a; \{\}", "t.c:1:20: expected a declaration of parameter 'b', got '\{'"),
        ("int f(a) \{\}", "t.c:1:10: expected a declaration of parameter 'a', got '\{'"),
        ("int f(a) int c; \{\}", "t.c:1:14: expected a name of the identifier list, got 'c'"),
        ("int f(a) int a, a; \{\}", "t.c:1:17: expected a parameter declared once, got 'a'"),
        ("int f(a) _Static_assert(1, \"\"); int a; \{\}", "t.c:1:10: expected a declaration, got '_Static_assert'"),
        ("int f(a) int a;", "t.c:1:16: expected a declaration, got end of input"),
        ("int f(a) x; \{\}", "t.c:1:10: expected a declaration, got 'x'"))
    for (c in cases) {
        t |> equal(unit(c._0), "error: {c._1}", c._0)
    }
    t |> equal(unit("int f(a) int a; __attribute__((x)) \{\}"), "error: t.c:1:17: a specifier list with no type specifier is not parsed")
    t |> equal(unit("int (*f(int a))(b) \{\}"), "error: t.c:1:17: an identifier list outside a function definition is not parsed")
    t |> equal(unit("int f(a) int g(b); \{\}"), "error: t.c:1:16: an identifier list outside a function definition is not parsed")
}

[test(description = "file-scope forms: `;` alone, `__extension__` before a declaration and alone, `_Static_assert`, a declaration of attributes alone, an empty unit; a file-scope asm is refused, a declaration with no type specifier still is")]
def test_file_scope(t : T?) {
    t |> equal(unit(";; int x;; __extension__ ;"), "(decl 0 [(spec int)] [(init_decl (d_name x) - -)])")
    t |> equal(unit("__extension__ typedef long long ll; ll v;"),
               "(decl 1 [(spec typedef) (spec long) (spec long)] [(init_decl (d_name ll) - -)]) (decl 0 [(typedef_name ll)] [(init_decl (d_name v) - -)])")
    t |> equal(unit("_Static_assert(1, \"m\");"), "(static_assert (int 1) (string \"m\"))")
    t |> equal(unit("__attribute__((unused)); __attribute__((a)) __attribute__((b));"),
               "(decl 0 [(attribute __attribute__((unused)))] []) (decl 0 [(attribute __attribute__((a))) (attribute __attribute__((b)))] [])")
    t |> equal(unit(""), "")
    t |> equal(unit("int x; asm(\"nop\");"), "error: t.c:1:8: a file-scope asm is not parsed")
    t |> equal(unit("__extension__ __asm__ volatile(\"\");"), "error: t.c:1:15: a file-scope asm is not parsed")
    t |> equal(unit("const;"), "error: t.c:1:1: a specifier list with no type specifier is not parsed")
    t |> equal(unit("__attribute__((x)) x;"), "error: t.c:1:1: a specifier list with no type specifier is not parsed")
    t |> equal(unit("int x; \}"), "error: t.c:1:8: expected a declaration, got '\}'")
    var p : CParser
    opened(p, "__attribute__((unused));")
    c_scope_open(p)
    t |> equal(next_decl(p), "error: t.c:1:1: a specifier list with no type specifier is not parsed")
}

[test(description = "record nesting is bounded: 256 nested bodies parse in the test's 256 KiB stack and the 257th is refused at its brace; a body in a member function's parameter list holds two levels a cycle; long chains end in the refusal")]
def test_nesting_bound(t : T?) {
    t |> success(unit("{repeat("struct\{", 256)}int x;{repeat("\}a;", 256)}") |> starts_with("(decl 0 [(record struct - 1"))
    t |> equal(unit("{repeat("struct\{", 257)}int x;{repeat("\}a;", 257)}"), "error: t.c:1:{256 * 7 + 7}: nesting deeper than 256 levels is not parsed")
    t |> success(unit("{repeat("struct\{int(*f)(", 127)}int{repeat(");\}", 127)}s;") |> starts_with("(decl 0 [(record struct - 1"))
    t |> equal(unit("{repeat("struct\{int(*f)(", 128)}int{repeat(");\}", 128)}s;"), "error: t.c:1:{127 * 15 + 12}: nesting deeper than 256 levels is not parsed")
    t |> success(unit("{repeat("struct\{int f(", 128)}int{repeat(");\}", 128)}s;") |> starts_with("(decl 0 [(record struct - 1"))
    for (text in fixed_array("{repeat("struct\{", 3000)}", "{repeat("union\{struct\{int(*f)(", 3000)}", "{repeat("enum\{A=sizeof(struct\{", 3000)}")) {
        t |> success(unit(text) |> ends_with("nesting deeper than 256 levels is not parsed"), slice(text, 0, 12))
    }
}

let private PROGRAM <- fixed_array(
    "# 1 \"prog.c\"",
    "typedef struct node node_t;",
    "struct node \{",
    "    int key;",
    "    unsigned color : 1, : 0;",
    "    node_t *left, *right;",
    "    union \{ long l; double d; \} value;",
    "    struct \{ char tag[4]; int used; \} __attribute__((aligned(8)));",
    "\};",
    "enum color \{ RED, BLACK = 1, \};",
    "typedef enum \{ OP_ADD, OP_SUB = OP_ADD + 2, OP_LAST \} op_t;",
    "struct table \{ size_t count; node_t *items[]; \} __attribute__((packed));",
    "static const char *names[] = \{ \"red\", \"black\" \};",
    "_Static_assert(sizeof(op_t) == sizeof(int), \"op\");",
    "static int compare(const void *a, const void *b) \{",
    "    const node_t *x = a, *y = b;",
    "    return (x->key > y->key) - (x->key < y->key);",
    "\}",
    "static node_t *insert(node_t *root, node_t *n) \{",
    "    if (!root) \{ return n; \}",
    "    if (n->key < root->key) \{ root->left = insert(root->left, n); \} else \{ root->right = insert(root->right, n); \}",
    "    return root;",
    "\}",
    "int old_sum(count, values) int count; const int *values; \{",
    "    int s = 0; for (int i = 0; i < count; i++) \{ s += values[i]; \} return s;",
    "\}",
    "__extension__ typedef long long wide_t;",
    "wide_t total(op_t op, wide_t a, wide_t b) __attribute__((const));",
    "int main(int argc, char **argv) \{",
    "    node_t nodes[3] = \{ \{ 1 \}, \{ 2 \}, \{ 3 \} \};",
    "    node_t *root = 0;",
    "    for (int i = 0; i < 3; i++) \{ root = insert(root, &nodes[i]); \}",
    "    qsort(nodes, 3, sizeof(node_t), compare);",
    "    printf(\"%s %d\\n\", names[RED], old_sum(argc, (const int *)argv));",
    "    return 0;",
    "\}")

[test(description = "a whole unit, the preprocessed own headers and a program of records, enums, typedefs and definitions, parses to one external declaration per declaration, allocating no string and a fixed number of heap blocks however many tokens it holds")]
def test_whole_unit(t : T?) {
    let text = "{join(PREPROCESSED_HEADERS, "\n")}\n{join(PROGRAM, "\n")}"
    var p : CParser
    c_parser_open_text(p, text, "x.c")
    let heap = int(heap_allocation_count())
    let strings = int(string_heap_allocation_count())
    let u = c_unit(p)
    let heap_used = int(heap_allocation_count()) - heap
    let strings_used = int(string_heap_allocation_count()) - strings
    t |> success(!p.failed, p.err)
    var count = 0
    var definitions = 0
    var at = p.ast.nodes[u].a
    while (at >= 0) {
        count++
        definitions += p.ast.nodes[at].kind == CNode.FUNC_DEF ? 1 : 0
        at = p.ast.nodes[at].next
    }
    t |> equal(count, 169 + 13, "external declarations: the headers', the program's")
    t |> equal(definitions, 4, "function definitions")
    t |> equal(strings_used, 0, "string allocations")
    t |> success(heap_used <= 16, "heap allocations {heap_used} over {length(p.unit.toks)} tokens and {count} declarations")
}

[test(description = "array declarators where C.1c adds a place: a member's array takes no qualifier, `static` or `[*]`, an old-style parameter's takes a qualifier or `static` but no `[*]`, nor does a definition's own parameter at any level, while a prototype inside one may")]
def test_array_contexts(t : T?) {
    t |> equal(unit("int f(a) int a[static 3]; \{\}"),
               "(func_def 0 [(spec int)] (init_decl (d_function 2 (d_name f) [(ident_param a)]) - -) [(decl 0 [(spec int)] [(init_decl (d_array 1 (d_name a) (int 3) []) - -)])] (body \{\}))")
    t |> equal(unit("void f(int (*p)(int q[*])) \{\}"),
               "(func_def 0 [(spec void)] (init_decl (d_function 0 (d_name f) [(param [(spec int)] (d_function 0 (d_paren (d_pointer (d_name p) []) []) [(param [(spec int)] (d_array 2 (d_name q) - []))]))]) - -) [] (body \{\}))")
    let cases = fixed_array(
        ("struct S \{ int a[const 3]; \};", "t.c:1:17: a qualifier or 'static' in an array declarator outside a parameter's outermost array is not parsed"),
        ("struct S \{ int a[*]; \};", "t.c:1:17: '[*]' outside a function prototype's parameter is not parsed"),
        ("int f(a) int a[*]; \{\}", "t.c:1:15: '[*]' outside a function prototype's parameter is not parsed"),
        ("void f(int a[3][*]) \{\}", "t.c:1:16: '[*]' outside a function prototype's parameter is not parsed"))
    for (c in cases) {
        t |> equal(unit(c._0), "error: {c._1}", c._0)
    }
}
