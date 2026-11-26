options gen2
options stack = 262144
require dastest/testing_boost public
require strings
require daslib/strings_boost
require ../c_parser.das
require _preprocessed_headers

//! `frontend/c_parser.das`, its statements: every C99 statement and the GNU forms Dumper A takes as
//! a tree, the scopes of blocks and `for`, labels named like a typedef, every refusal and malformed
//! statement as a located error, the nesting bound of the statement forms, and a unit of
//! preprocessed headers and a program with real bodies parsed with no allocation per token.

// a parser over `text` with `T` a typedef name
def private opened(var p : CParser; text : string) {
    c_parser_open_text(p, text, "t.c")
    c_declare(p, c_symbol(p.unit, "T"), CBinding.TYPEDEF)
}

// the statement `text` to its end as a tree, or `error: <message>`; `T` is a typedef name
def private stmt(text : string) : string {
    var p : CParser
    opened(p, text)
    let s = c_statement(p)
    c_expect_end(p)
    return p.failed ? "error: {p.err}" : c_dump(p.ast, p.unit, s)
}

[test(description = "a compound statement holds declarations and statements in any order; an expression statement, a null statement, `goto`, `continue`, `break` and `return` with and without a value")]
def test_simple(t : T?) {
    t |> equal(stmt("\{ int a = 1; a++; \{ ; \} T b; \}"),
               "(compound [(decl 0 [(spec int)] [(init_decl (d_name a) (int 1) -)]) (expr_stmt (postfix ++ (ident a))) (compound [(null)]) (decl 0 [(typedef_name T)] [(init_decl (d_name b) - -)])])")
    t |> equal(stmt("\{\}"), "(compound [])")
    t |> equal(stmt("\{ static int s; _Static_assert(1, \"m\"); \}"),
               "(compound [(decl 0 [(spec static) (spec int)] [(init_decl (d_name s) - -)]) (static_assert (int 1) (string \"m\"))])")
    t |> equal(stmt("f(x), y = 2;"), "(expr_stmt (binary , (call (ident f) [(ident x)]) (assign = (ident y) (int 2))))")
    t |> equal(stmt(";"), "(null)")
    t |> equal(stmt("\{ goto out; continue; break; return; return a + 1; \}"),
               "(compound [(goto out) (continue) (break) (return -) (return (binary + (ident a) (int 1)))])")
}

[test(description = "labels: a name, `case` with a constant expression and a GNU range, `default`, a run of labels each the statement of the one before, a label named like a typedef, attributes after a label, and a label at a block's end or before a declaration as clang takes them")]
def test_labels(t : T?) {
    t |> equal(stmt("l: x;"), "(label l (expr_stmt (ident x)))")
    t |> equal(stmt("T: x;"), "(label T (expr_stmt (ident x)))")
    t |> equal(stmt("\{ T: x; \}"), "(compound [(label T (expr_stmt (ident x)))])")
    t |> equal(stmt("switch (x) \{ case 1 ... 3: case (T)4 + sizeof(T): break; default: ; \}"),
               "(switch (ident x) (compound [(case (int 1) (int 3) (case (binary + (cast (type_name [(typedef_name T)] -) (int 4)) (sizeof_type (type_name [(typedef_name T)] -))) - (break))) (default (null))]))")
    t |> equal(stmt("a: b: default: x;"), "(label a (label b (default (expr_stmt (ident x)))))")
    t |> equal(stmt("l: __attribute__((unused)) ;"), "(label l (null) [(attribute __attribute__((unused)))])")
    t |> equal(stmt("\{ l: \}"), "(compound [(label l -)])")
    t |> equal(stmt("\{ l: int y; \}"), "(compound [(label l (decl 0 [(spec int)] [(init_decl (d_name y) - -)]))])")
    t |> success(stmt("{repeat("l: ", 3000)};") |> starts_with("(label l (label l"))
}

[test(description = "selection and iteration statements: `if` with and without `else`, a dangling `else` binding to the nearest `if`, a long `else if` chain read with no recursion, `switch`, `while`, `do`, and `for` with a declaration, an expression or nothing in each place, its declaration's storage class `auto` or `register` alone")]
def test_control(t : T?) {
    t |> equal(stmt("if (a) x; else y;"), "(if (ident a) (expr_stmt (ident x)) (expr_stmt (ident y)))")
    t |> equal(stmt("if (a) if (b) x; else y;"), "(if (ident a) (if (ident b) (expr_stmt (ident x)) (expr_stmt (ident y))) -)")
    t |> equal(stmt("if (a) x; else if (b) y; else z;"), "(if (ident a) (expr_stmt (ident x)) (if (ident b) (expr_stmt (ident y)) (expr_stmt (ident z))))")
    t |> success(stmt("if (a) x;{repeat(" else if (a) x;", 3000)} else y;") |> ends_with("(expr_stmt (ident y)){repeat(")", 3001)}"))
    t |> equal(stmt("while (i < n) i++;"), "(while (binary < (ident i) (ident n)) (expr_stmt (postfix ++ (ident i))))")
    t |> equal(stmt("do x--; while (x);"), "(do (expr_stmt (postfix -- (ident x))) (ident x))")
    t |> equal(stmt("for (;;) ;"), "(for - - - (null))")
    t |> equal(stmt("for (i = 0; i < n; i++) break;"),
               "(for (assign = (ident i) (int 0)) (binary < (ident i) (ident n)) (postfix ++ (ident i)) (break))")
    t |> equal(stmt("for (int i = 0, j; ; ) continue;"),
               "(for (decl 0 [(spec int)] [(init_decl (d_name i) (int 0) -) (init_decl (d_name j) - -)]) - - (continue))")
    t |> equal(stmt("for (T x; x; ) ;"), "(for (decl 0 [(typedef_name T)] [(init_decl (d_name x) - -)]) (ident x) - (null))")
    t |> equal(stmt("for (auto int i = 0; ; ) ;"), "(for (decl 0 [(spec auto) (spec int)] [(init_decl (d_name i) (int 0) -)]) - - (null))")
    t |> equal(stmt("for (register int i = 0; ; ) ;"), "(for (decl 0 [(spec register) (spec int)] [(init_decl (d_name i) (int 0) -)]) - - (null))")
    for (word in fixed_array("static", "extern", "typedef", "_Thread_local")) {
        t |> equal(stmt("for (const {word} int i; ; ) ;"), "error: t.c:1:12: expected 'auto' or 'register' as a for declaration's storage class, got '{word}'", word)
    }
}

[test(description = "the GNU forms: `__extension__` before a declaration and a statement, attributes on a null statement and before a declaration, a statement expression, and asm statements basic and extended, their operands kept as token ranges")]
def test_gnu(t : T?) {
    t |> equal(stmt("\{ __extension__ int y; __extension__ y++; \}"),
               "(compound [(decl 1 [(spec int)] [(init_decl (d_name y) - -)]) (expr_stmt (extension (postfix ++ (ident y))))])")
    t |> equal(stmt("\{ __attribute__((fallthrough)); __attribute__((unused)) int z; \}"),
               "(compound [(null [(attribute __attribute__((fallthrough)))]) (decl 0 [(attribute __attribute__((unused))) (spec int)] [(init_decl (d_name z) - -)])])")
    t |> equal(stmt("y = (\{ int z = 1; z + 1; \});"),
               "(expr_stmt (assign = (ident y) (stmt_expr (compound [(decl 0 [(spec int)] [(init_decl (d_name z) (int 1) -)]) (expr_stmt (binary + (ident z) (int 1)))]))))")
    t |> equal(stmt("asm(\"nop\");"), "(asm 0 (string \"nop\") [] [] [])")
    t |> equal(stmt("__asm__ __volatile__ (\"\" ::: \"memory\");"), "(asm 1 (string \"\") [] [] [(asm_operand \"memory\")])")
    t |> equal(stmt("asm volatile inline (\"mov %1, %0\" : \"=r\"(x) : [in] \"r\"(y + 1), \"m\"(a[(1)]) : \"cc\", \"memory\");"),
               "(asm 3 (string \"mov %1, %0\") [(asm_operand \"=r\"(x))] [(asm_operand [in] \"r\"(y + 1)) (asm_operand \"m\"(a[(1)]))] [(asm_operand \"cc\") (asm_operand \"memory\")])")
    t |> equal(stmt("asm(\"\" : : : );"), "(asm 0 (string \"\") [] [] [])")
    t |> equal(stmt("asm(\"\" :: \"r\"(x));"), "(asm 0 (string \"\") [] [(asm_operand \"r\"(x))] [])")
}

[test(description = "scopes: a block's declarations end with it, a `for` declaration with the `for` (the probe's f7 and f15), a typedef shadowed in a block is a type again after it (f1, f5), and a selection statement's body is a scope of its own")]
def test_scopes(t : T?) {
    t |> run("f7 `for (int T = 0; T < 1; T++) ; T y;`") @(t : T?) {
        t |> equal(stmt("\{ for (int T = 0; T < 1; T++) ; T y; \}"),
                   "(compound [(for (decl 0 [(spec int)] [(init_decl (d_name T) (int 0) -)]) (binary < (ident T) (int 1)) (postfix ++ (ident T)) (null)) (decl 0 [(typedef_name T)] [(init_decl (d_name y) - -)])])")
    }
    t |> run("f15 `for (int T = 0; T < 1; T++) \{ T = 2; \} T z;`") @(t : T?) {
        t |> equal(stmt("\{ for (int T = 0; T < 1; T++) \{ T = 2; \} T z; \}"),
                   "(compound [(for (decl 0 [(spec int)] [(init_decl (d_name T) (int 0) -)]) (binary < (ident T) (int 1)) (postfix ++ (ident T)) (compound [(expr_stmt (assign = (ident T) (int 2)))])) (decl 0 [(typedef_name T)] [(init_decl (d_name z) - -)])])")
    }
    t |> run("f1 and f5: a block's object or typedef ends with the block") @(t : T?) {
        t |> equal(stmt("\{ \{ int T; T = 1; \} T c; \}"),
                   "(compound [(compound [(decl 0 [(spec int)] [(init_decl (d_name T) - -)]) (expr_stmt (assign = (ident T) (int 1)))]) (decl 0 [(typedef_name T)] [(init_decl (d_name c) - -)])])")
        t |> equal(stmt("\{ \{ typedef char U; U c; \} U d; \}"), "error: t.c:1:30: expected ';', got 'd'")
    }
    t |> run("an `if` body and a `while` body end their declarations") @(t : T?) {
        t |> equal(stmt("\{ if (1) \{ int T; \} T a; while (1) \{ int T; \} T b; \}"),
                   "(compound [(if (int 1) (compound [(decl 0 [(spec int)] [(init_decl (d_name T) - -)])]) -) (decl 0 [(typedef_name T)] [(init_decl (d_name a) - -)]) (while (int 1) (compound [(decl 0 [(spec int)] [(init_decl (d_name T) - -)])])) (decl 0 [(typedef_name T)] [(init_decl (d_name b) - -)])])")
    }
    t |> run("an enumerator an `if` condition declares ends with the `if`, one its body declares with the body") @(t : T?) {
        t |> equal(stmt("\{ if (sizeof(enum \{ T \})) ; T x; \}"),
                   "(compound [(if (sizeof_type (type_name [(enum - 1 [(enumerator T -)])] -)) (null) -) (decl 0 [(typedef_name T)] [(init_decl (d_name x) - -)])])")
        t |> equal(stmt("if (1) sizeof(enum \{ T \}); else (T)1;"),
                   "(if (int 1) (expr_stmt (sizeof_type (type_name [(enum - 1 [(enumerator T -)])] -))) (expr_stmt (cast (type_name [(typedef_name T)] -) (int 1))))")
    }
    t |> run("an enumerator a `while` condition or a `for` clause declares ends with the statement") @(t : T?) {
        t |> equal(stmt("\{ while (sizeof(enum \{ T \})) ; T x; \}"),
                   "(compound [(while (sizeof_type (type_name [(enum - 1 [(enumerator T -)])] -)) (null)) (decl 0 [(typedef_name T)] [(init_decl (d_name x) - -)])])")
        t |> equal(stmt("\{ for (; sizeof(enum \{ T \}); ) ; T x; \}"),
                   "(compound [(for - (sizeof_type (type_name [(enum - 1 [(enumerator T -)])] -)) - (null)) (decl 0 [(typedef_name T)] [(init_decl (d_name x) - -)])])")
    }
    t |> run("an enumerator a `do` condition declares ends with the `do`") @(t : T?) {
        t |> equal(stmt("\{ do ; while (sizeof(enum \{ T \})); T x; \}"),
                   "(compound [(do (null) (sizeof_type (type_name [(enum - 1 [(enumerator T -)])] -))) (decl 0 [(typedef_name T)] [(init_decl (d_name x) - -)])])")
    }
    t |> run("an enumerator a `switch` condition declares ends with the `switch`") @(t : T?) {
        t |> equal(stmt("\{ switch (sizeof(enum \{ T \})) ; T x; \}"),
                   "(compound [(switch (sizeof_type (type_name [(enum - 1 [(enumerator T -)])] -)) (null)) (decl 0 [(typedef_name T)] [(init_decl (d_name x) - -)])])")
    }
}

[test(description = "a statement the parser does not take is refused at its token: a computed goto, `asm goto`, a local label declaration, a label address and a nested function definition")]
def test_refusals(t : T?) {
    t |> equal(stmt("goto *p;"), "error: t.c:1:6: a computed goto (goto *) is not parsed")
    t |> equal(stmt("asm goto (\"\" :::: l);"), "error: t.c:1:5: asm goto is not parsed")
    t |> equal(stmt("\{ __label__ a; \}"), "error: t.c:1:3: a local label declaration (__label__) is not parsed")
    t |> equal(stmt("p = &&l;"), "error: t.c:1:5: a label address (&&label) is not parsed")
    t |> equal(stmt("\{ int g(void) \{ return 0; \} \}"), "error: t.c:1:15: a nested function definition is not parsed")
    t |> equal(stmt("\{ __attribute__((x)) x++; \}"), "error: t.c:1:3: a specifier list with no type specifier is not parsed")
}

[test(description = "a malformed statement ends with a located error at each position: a block's end, each parenthesis, `while` after `do`, each `;` of a `for`, a label, a `case`, an asm statement's parts, and a declaration where a statement must stand")]
def test_malformed(t : T?) {
    let cases = fixed_array(
        ("\{ x; ", "t.c:1:5: expected '\}', got end of input"),
        ("if x) ;", "t.c:1:4: expected '(', got 'x'"),
        ("if (x ;", "t.c:1:7: expected ')', got ';'"),
        ("if (x) int y;", "t.c:1:8: expected an expression, got 'int'"),
        ("while (x) ", "t.c:1:10: expected an expression, got end of input"),
        ("switch x;", "t.c:1:8: expected '(', got 'x'"),
        ("do x; (x);", "t.c:1:7: expected 'while', got '('"),
        ("do x; while (x)", "t.c:1:16: expected ';', got end of input"),
        ("for (;;", "t.c:1:8: expected an expression, got end of input"),
        ("for (int i = 0 i;;) ;", "t.c:1:16: expected ';', got 'i'"),
        ("for (i; i ) ;", "t.c:1:11: expected ';', got ')'"),
        ("for (i i;;) ;", "t.c:1:8: expected ';', got 'i'"),
        ("goto 1;", "t.c:1:6: expected a label name, got '1'"),
        ("return 1", "t.c:1:9: expected ';', got end of input"),
        ("case 1 x;", "t.c:1:8: expected ':', got 'x'"),
        ("case 1 ... ;", "t.c:1:12: expected an expression, got ';'"),
        ("default x;", "t.c:1:9: expected ':', got 'x'"),
        ("x", "t.c:1:2: expected ';', got end of input"),
        ("else x;", "t.c:1:1: expected an expression, got 'else'"),
        ("asm(x);", "t.c:1:5: expected a string literal, got 'x'"),
        ("asm \"\";", "t.c:1:5: expected '(', got '\"\"'"),
        ("asm volatile volatile (\"\");", "t.c:1:14: expected '(', got 'volatile'"),
        ("asm(\"\" : , );", "t.c:1:10: expected an asm operand, got ','"),
        ("asm(\"\" : \"r\"(x) : : : );", "t.c:1:21: expected ')', got ':'"),
        ("asm(\"\" : \"r\"(x", "t.c:1:15: expected ')', got end of input"),
        ("asm(\"nop\")", "t.c:1:11: expected ';', got end of input"))
    for (c in cases) {
        t |> equal(stmt(c._0), "error: {c._1}", c._0)
    }
}

[test(description = "statement nesting is bounded: 256 nested blocks parse in the test's 256 KiB stack and the 257th is refused at its brace; an `if` body opens a level, so 255 of them and the expression inside are 256; long chains of every recursive statement form end in the refusal")]
def test_nesting_bound(t : T?) {
    t |> success(stmt("{repeat("\{", 256)}{repeat("\}", 256)}") |> starts_with("(compound [(compound"))
    t |> equal(stmt("{repeat("\{", 257)}{repeat("\}", 257)}"), "error: t.c:1:257: nesting deeper than 256 levels is not parsed")
    t |> success(stmt("{repeat("if (a) ", 255)}x;") |> starts_with("(if (ident a) (if"))
    t |> equal(stmt("{repeat("if (a) ", 256)}x;"), "error: t.c:1:{256 * 7 + 1}: nesting deeper than 256 levels is not parsed")
    let chains = fixed_array("{repeat("\{", 3000)}", "{repeat("if (a) ", 3000)}", "{repeat("while (a) ", 3000)}", "{repeat("for (;;) ", 3000)}",
        "{repeat("do ", 3000)}", "{repeat("switch (a) ", 3000)}", "{repeat("(\{", 3000)}", "{repeat("x = (\{ ", 3000)}", "{repeat("l: \{ ", 3000)}")
    for (text in chains) {
        t |> success(stmt(text) |> ends_with("nesting deeper than 256 levels is not parsed"), slice(text, 0, 12))
    }
}

let private PROGRAM <- fixed_array(
    "# 1 \"prog.c\"",
    "typedef struct \{ int kind; double value; \} token_t;",
    "enum \{ TK_NUM, TK_ADD, TK_MUL, TK_END \};",
    "static int next_kind(const char **s) \{",
    "    for (;;) \{",
    "        switch (**s) \{",
    "        case ' ': case '\\t': ++*s; continue;",
    "        case '0' ... '9': return TK_NUM;",
    "        case '+': ++*s; return TK_ADD;",
    "        case '*': ++*s; return TK_MUL;",
    "        default: return TK_END;",
    "        \}",
    "    \}",
    "\}",
    "static double eval(const char *s) \{",
    "    double acc = 0, term = 1;",
    "    int k;",
    "    while ((k = next_kind(&s)) != TK_END) \{",
    "        if (k == TK_NUM) \{ term *= strtod(s, (char **)&s); \}",
    "        else if (k == TK_ADD) \{ acc += term; term = 1; \}",
    "        else if (k == TK_MUL) continue;",
    "        else goto fail;",
    "    \}",
    "    return acc + term;",
    "fail:",
    "    return -1;",
    "\}",
    "int main(void) \{",
    "    int n = 0;",
    "    do \{ n++; \} while (n < 3);",
    "    int sq = (\{ int t = n; t * t; \});",
    "    __asm__ __volatile__ (\"\" ::: \"memory\");",
    "    for (int i = 0; i < n; i++) \{ token_t t = \{ TK_NUM, eval(\"1+2*3\") \}; printf(\"%f\\n\", t.value); \}",
    "    return sq == 9 ? 0 : 1;",
    "\}")

[test(description = "a whole unit, the preprocessed own headers and a program with real bodies, parses allocating no string and a fixed number of heap blocks however many tokens it holds")]
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
    var definitions = 0
    var at = p.ast.nodes[u].a
    while (at >= 0) {
        definitions += p.ast.nodes[at].kind == CNode.FUNC_DEF ? 1 : 0
        at = p.ast.nodes[at].next
    }
    t |> equal(definitions, 3, "function definitions")
    t |> equal(strings_used, 0, "string allocations")
    t |> success(heap_used <= 16, "heap allocations {heap_used} over {length(p.unit.toks)} tokens")
}
