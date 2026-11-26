options gen2
options stack = 262144
require dastest/testing_boost public
require strings
require daslib/strings_boost
require ../c_parser.das

//! `frontend/c_parser.das`, its expressions and type names: every C99 form and the GNU ones as a
//! tree, precedence and associativity, the typedef-name decisions, every refusal and malformed
//! input as a located error, the nesting bound, and no allocation per token. The stack is the
//! one the nesting bound asks for.

// a parser over `text` with `T`, `U` and `size_t` declared as typedef names
def private opened(var p : CParser; text : string) {
    c_parser_open_text(p, text, "t.c")
    for (name in fixed_array("T", "U", "size_t")) {
        c_declare(p, c_symbol(p.unit, name), CBinding.TYPEDEF)
    }
}

// the tree of the expression `p` parses to its end, or `error: <message>`
def private finished(var p : CParser; e : int; places : bool = false) : string {
    c_expect_end(p)
    return p.failed ? "error: {p.err}" : c_dump(p.ast, p.unit, e, places)
}

// the tree of the expression `text`, or `error: <message>`
def private parsed(text : string; places : bool = false) : string {
    var p : CParser
    opened(p, text)
    let e = c_expression(p)
    return finished(p, e, places)
}

[test(description = "every primary expression: an identifier, each constant, adjacent string literals as one node, `__func__` and its GNU spellings, a parenthesised expression")]
def test_primary(t : T?) {
    t |> equal(parsed("x"), "(ident x)")
    t |> equal(parsed("42u"), "(int 42u)")
    t |> equal(parsed("1.5f"), "(float 1.5f)")
    t |> equal(parsed("L'a'"), "(char L'a')")
    t |> equal(parsed("\"a\" \"b\" L\"c\""), "(string \"a\" \"b\" L\"c\")")
    t |> equal(parsed("__func__"), "(func_name __func__)")
    t |> equal(parsed("__PRETTY_FUNCTION__"), "(func_name __PRETTY_FUNCTION__)")
    t |> equal(parsed("(x)"), "(paren (ident x))")
}

[test(description = "every postfix form: subscript, call with and without arguments, `.`, `->`, `++`, `--`, and a chain of them binding left to right")]
def test_postfix(t : T?) {
    t |> equal(parsed("a[i]"), "(index (ident a) (ident i))")
    t |> equal(parsed("f()"), "(call (ident f) [])")
    t |> equal(parsed("f(a, b = 1)"), "(call (ident f) [(ident a) (assign = (ident b) (int 1))])")
    t |> equal(parsed("f(a,)"), "error: t.c:1:5: expected an expression, got ')'")
    t |> equal(parsed("f(a, b,)"), "error: t.c:1:8: expected an expression, got ')'")
    t |> equal(parsed("f(,)"), "error: t.c:1:3: expected an expression, got ','")
    t |> equal(parsed("s.x"), "(member . (ident s) x)")
    t |> equal(parsed("p->x"), "(member -> (ident p) x)")
    t |> equal(parsed("i++"), "(postfix ++ (ident i))")
    t |> equal(parsed("i--"), "(postfix -- (ident i))")
    t |> equal(parsed("a.b[1]->c(2)--"), "(postfix -- (call (member -> (index (member . (ident a) b) (int 1)) c) [(int 2)]))")
}

[test(description = "a compound literal holds its type name and its initializer list: positional items, member, index and GNU range designators, a nested list, a trailing comma, an empty list")]
def test_compound_literal(t : T?) {
    t |> equal(parsed("(T)\{1, .x = 2, [3] = 4, [1 ... 2] = 5, \{6\}, \}"),
               "(compound_literal (type_name [(typedef_name T)] -) (init_list [(init [] (int 1)) (init [(field x)] (int 2)) (init [(index_desig (int 3) -)] (int 4)) (init [(index_desig (int 1) (int 2))] (int 5)) (init [] (init_list [(init [] (int 6))]))]))")
    t |> equal(parsed("(int[])\{\}"), "(compound_literal (type_name [(spec int)] (d_array 0 - - [])) (init_list []))")
    t |> equal(parsed("(T)\{.a.b[0] = 1\}.a"), "(member . (compound_literal (type_name [(typedef_name T)] -) (init_list [(init [(field a) (field b) (index_desig (int 0) -)] (int 1))])) a)")
}

[test(description = "a compound literal is a postfix expression, so it is the operand of `++`, `--`, `sizeof` and every other unary operator; a parenthesised type name there without its braces is an error")]
def test_compound_literal_operands(t : T?) {
    t |> equal(parsed("++(T)\{1\}"), "(unary ++ (compound_literal (type_name [(typedef_name T)] -) (init_list [(init [] (int 1))])))")
    t |> equal(parsed("--(T)\{1\}.x"), "(unary -- (member . (compound_literal (type_name [(typedef_name T)] -) (init_list [(init [] (int 1))])) x))")
    t |> equal(parsed("++(int)\{1\}"), "(unary ++ (compound_literal (type_name [(spec int)] -) (init_list [(init [] (int 1))])))")
    t |> equal(parsed("sizeof ++(T)\{1\}"), "(sizeof_expr (unary ++ (compound_literal (type_name [(typedef_name T)] -) (init_list [(init [] (int 1))]))))")
    t |> equal(parsed("&(T)\{1\}"), "(unary & (compound_literal (type_name [(typedef_name T)] -) (init_list [(init [] (int 1))])))")
    t |> equal(parsed("++(int)x"), "error: t.c:1:8: expected '\{' after a parenthesised type name, got 'x'")
}

[test(description = "the type specifiers of a list combine by C11 6.7.2p2 or the one that does not is an error at its token; a typedef name after a type specifier is no type; a list with no type specifier is refused")]
def test_specifier_combinations(t : T?) {
    t |> run("the combinations 6.7.2p2 lists, in any order, and GNU `_Complex` alone") @(t : T?) {
        t |> equal(parsed("(long long int)x"), "(cast (type_name [(spec long) (spec long) (spec int)] -) (ident x))")
        t |> equal(parsed("(int long long unsigned)x"), "(cast (type_name [(spec int) (spec long) (spec long) (spec unsigned)] -) (ident x))")
        t |> equal(parsed("(short unsigned int)x"), "(cast (type_name [(spec short) (spec unsigned) (spec int)] -) (ident x))")
        t |> equal(parsed("(signed char)x"), "(cast (type_name [(spec signed) (spec char)] -) (ident x))")
        t |> equal(parsed("(long double _Complex)x"), "(cast (type_name [(spec long) (spec double) (spec _Complex)] -) (ident x))")
        t |> equal(parsed("(_Complex)x"), "(cast (type_name [(spec _Complex)] -) (ident x))")
        t |> equal(parsed("(const T const)x"), "(cast (type_name [(spec const) (typedef_name T) (spec const)] -) (ident x))")
        t |> equal(parsed("(unsigned char)x"), "(cast (type_name [(spec unsigned) (spec char)] -) (ident x))")
        t |> equal(parsed("(signed short)x"), "(cast (type_name [(spec signed) (spec short)] -) (ident x))")
        t |> equal(parsed("(signed long)x"), "(cast (type_name [(spec signed) (spec long)] -) (ident x))")
        t |> equal(parsed("(long long signed)x"), "(cast (type_name [(spec long) (spec long) (spec signed)] -) (ident x))")
        t |> equal(parsed("(float _Complex)x"), "(cast (type_name [(spec float) (spec _Complex)] -) (ident x))")
    }
    t |> run("a specifier that does not combine with those before it") @(t : T?) {
        let cases = fixed_array(("(T int)x", "1:4", "int"), ("(int int)x", "1:6", "int"), ("(long long long)x", "1:12", "long"),
            ("(short double)x", "1:8", "double"), ("(unsigned float)x", "1:11", "float"), ("(signed unsigned)x", "1:9", "unsigned"),
            ("(void int)x", "1:7", "int"), ("(_Bool char)x", "1:8", "char"), ("(struct S int)x", "1:11", "int"),
            ("(int struct S)x", "1:6", "struct"), ("(T typeof(x))y", "1:4", "typeof"))
        for (c in cases) {
            t |> equal(parsed(c._0), "error: t.c:{c._1}: expected a type specifier that combines with those before it, got '{c._2}'", c._0)
        }
    }
    t |> run("a typedef name after a type specifier is no type specifier") @(t : T?) {
        t |> equal(parsed("(long T)x"), "error: t.c:1:7: expected ')', got 'T'")
        t |> equal(parsed("(typeof(x) T)x"), "error: t.c:1:12: expected ')', got 'T'")
        t |> equal(parsed("(int static)x"), "error: t.c:1:6: expected ')', got 'static'")
    }
    t |> run("no type specifier at all: C99 has no implicit int") @(t : T?) {
        t |> equal(parsed("(const)x"), "error: t.c:1:2: a specifier list with no type specifier is not parsed")
        t |> equal(parsed("sizeof(const)"), "error: t.c:1:8: a specifier list with no type specifier is not parsed")
        t |> equal(parsed("(_Alignas(8))x"), "error: t.c:1:2: a specifier list with no type specifier is not parsed")
        t |> equal(parsed("(void (*)(register x))f"), "error: t.c:1:11: a specifier list with no type specifier is not parsed")
    }
}

[test(description = "every unary operator, `sizeof` of an expression, a type name and a compound literal, and `_Alignof` and `__alignof__` keeping which keyword was spelled")]
def test_unary(t : T?) {
    t |> run("the prefix operators") @(t : T?) {
        for (op in fixed_array("++", "--", "&", "*", "+", "-", "~", "!")) {
            t |> equal(parsed("{op}x"), "(unary {op} (ident x))", op)
        }
    }
    t |> run("sizeof") @(t : T?) {
        t |> equal(parsed("sizeof x"), "(sizeof_expr (ident x))")
        t |> equal(parsed("sizeof(x)"), "(sizeof_expr (paren (ident x)))")
        t |> equal(parsed("sizeof(T)"), "(sizeof_type (type_name [(typedef_name T)] -))")
        t |> equal(parsed("sizeof(int *)"), "(sizeof_type (type_name [(spec int)] (d_pointer - [])))")
        t |> equal(parsed("sizeof (T)\{1\}.a"), "(sizeof_expr (member . (compound_literal (type_name [(typedef_name T)] -) (init_list [(init [] (int 1))])) a))")
        t |> equal(parsed("sizeof sizeof x"), "(sizeof_expr (sizeof_expr (ident x)))")
    }
    t |> run("_Alignof and __alignof__") @(t : T?) {
        t |> equal(parsed("_Alignof(int)"), "(alignof_type _Alignof (type_name [(spec int)] -))")
        t |> equal(parsed("__alignof(T)"), "(alignof_type __alignof__ (type_name [(typedef_name T)] -))")
        t |> equal(parsed("__alignof__ x"), "(alignof_expr __alignof__ (ident x))")
        t |> equal(parsed("_Alignof(x)"), "(alignof_expr _Alignof (paren (ident x)))")
    }
}

[test(description = "the typedef table decides each ambiguity: a cast or a parenthesised operand, `sizeof` of a type or an expression, a compound literal or a parenthesised name, and a typedef name an ordinary identifier shadows")]
def test_ambiguities(t : T?) {
    t |> run("`(T)-x` is a cast; `(x)-y` a subtraction") @(t : T?) {
        t |> equal(parsed("(T)-x"), "(cast (type_name [(typedef_name T)] -) (unary - (ident x)))")
        t |> equal(parsed("(x)-y"), "(binary - (paren (ident x)) (ident y))")
        t |> equal(parsed("(T)(U)x"), "(cast (type_name [(typedef_name T)] -) (cast (type_name [(typedef_name U)] -) (ident x)))")
        t |> equal(parsed("(T)*p"), "(cast (type_name [(typedef_name T)] -) (unary * (ident p)))")
        t |> equal(parsed("(x)*p"), "(binary * (paren (ident x)) (ident p))")
    }
    t |> run("`(T)\{...\}` is a compound literal; `(x)` before a brace is not") @(t : T?) {
        t |> equal(parsed("(T)\{0\}"), "(compound_literal (type_name [(typedef_name T)] -) (init_list [(init [] (int 0))]))")
        t |> equal(parsed("(x)\{0\}"), "error: t.c:1:4: expected end of input, got '\{'")
    }
    t |> run("a typedef name after a type specifier is no type: `(long T)` leaves `T` unread") @(t : T?) {
        t |> equal(parsed("(long T)x"), "error: t.c:1:7: expected ')', got 'T'")
        t |> equal(parsed("(const T)x"), "(cast (type_name [(spec const) (typedef_name T)] -) (ident x))")
    }
    t |> run("an ordinary identifier in an inner scope shadows the typedef name until the scope closes") @(t : T?) {
        var p : CParser
        opened(p, "(T)-x, (T)-x")
        c_scope_open(p)
        c_declare(p, c_symbol(p.unit, "T"), CBinding.ORDINARY)
        t |> equal(c_dump(p.ast, p.unit, c_assignment(p)), "(binary - (paren (ident T)) (ident x))")
        c_scope_close(p)
        t |> equal(c_spelling(p.unit, p.pos), ",")
        p.pos++
        t |> equal(finished(p, c_assignment(p)), "(cast (type_name [(typedef_name T)] -) (unary - (ident x)))")
    }
    t |> run("a parameter named like a typedef shadows it in the rest of its prototype only") @(t : T?) {
        t |> equal(parsed("(void (*)(T T))f + (T)1"),
                   "(binary + (cast (type_name [(spec void)] (d_function 0 (d_paren (d_pointer - []) []) [(param [(typedef_name T)] (d_name T))])) (ident f)) (cast (type_name [(typedef_name T)] -) (int 1)))")
        t |> equal(parsed("(void (*)(T T, T x))f"), "error: t.c:1:16: expected a parameter declaration, got 'T'")
    }
}

// the tree of `a <x> b <y> c`, the operators of the binary nodes as given
def private two_ops(x, y : string; x_inner : bool) : string =>
    x_inner ? "(binary {y} (binary {x} (ident a) (ident b)) (ident c))" : "(binary {x} (ident a) (binary {y} (ident b) (ident c)))"

[test(description = "the binary operators bind by C11 6.5's levels and to the left; `?:` and assignment bind to the right, the comma operator loosest")]
def test_precedence(t : T?) {
    t |> run("each level binds tighter than the next, either way round") @(t : T?) {
        let pairs = fixed_array(("*", "+"), ("-", "<<"), (">>", "<"), ("<=", "=="), ("!=", "&"), ("&", "^"), ("^", "|"), ("|", "&&"), ("&&", "||"))
        for (pair in pairs) {
            t |> equal(parsed("a {pair._0} b {pair._1} c"), two_ops(pair._0, pair._1, true), "{pair._0} {pair._1}")
            t |> equal(parsed("a {pair._1} b {pair._0} c"), two_ops(pair._1, pair._0, false), "{pair._1} {pair._0}")
        }
    }
    t |> run("the operators of one level bind to the left") @(t : T?) {
        let pairs = fixed_array(("/", "*"), ("%", "/"), ("-", "+"), ("<<", ">>"), ("<", ">="), (">", "<="), ("==", "!="), ("&", "&"), ("||", "||"))
        for (pair in pairs) {
            t |> equal(parsed("a {pair._0} b {pair._1} c"), two_ops(pair._0, pair._1, true), "{pair._0} {pair._1}")
        }
    }
    t |> run("unary, postfix and cast operands bind tighter than any binary operator") @(t : T?) {
        t |> equal(parsed("-a * b"), "(binary * (unary - (ident a)) (ident b))")
        t |> equal(parsed("*p++"), "(unary * (postfix ++ (ident p)))")
        t |> equal(parsed("!a == b"), "(binary == (unary ! (ident a)) (ident b))")
        t |> equal(parsed("sizeof a + b"), "(binary + (sizeof_expr (ident a)) (ident b))")
        t |> equal(parsed("(T)a + b"), "(binary + (cast (type_name [(typedef_name T)] -) (ident a)) (ident b))")
        t |> equal(parsed("&a[1]"), "(unary & (index (ident a) (int 1)))")
    }
    t |> run("`?:` below `||`, assignment below `?:`, comma below assignment") @(t : T?) {
        t |> equal(parsed("a || b ? c : d"), "(cond (binary || (ident a) (ident b)) (ident c) (ident d))")
        t |> equal(parsed("a = b ? c : d"), "(assign = (ident a) (cond (ident b) (ident c) (ident d)))")
        t |> equal(parsed("a ? b = c, d : e"), "(cond (ident a) (binary , (assign = (ident b) (ident c)) (ident d)) (ident e))")
        t |> equal(parsed("a, b = c"), "(binary , (ident a) (assign = (ident b) (ident c)))")
    }
    t |> run("`?:` and assignment bind to the right, the comma operator to the left") @(t : T?) {
        t |> equal(parsed("a ? b : c ? d : e"), "(cond (ident a) (ident b) (cond (ident c) (ident d) (ident e)))")
        t |> equal(parsed("a = b += c"), "(assign = (ident a) (assign += (ident b) (ident c)))")
        t |> equal(parsed("a, b, c"), "(binary , (binary , (ident a) (ident b)) (ident c))")
    }
    t |> run("every assignment operator") @(t : T?) {
        for (op in fixed_array("=", "*=", "/=", "%=", "+=", "-=", "<<=", ">>=", "&=", "^=", "|=")) {
            t |> equal(parsed("a {op} b"), "(assign {op} (ident a) (ident b))", op)
        }
    }
    t |> run("a constant expression stops before an assignment or a comma") @(t : T?) {
        var p : CParser
        opened(p, "a ? b : c = d")
        t |> equal(finished(p, c_constant_expression(p)), "error: t.c:1:11: expected end of input, got '='")
        opened(p, "a + 1, 2")
        t |> equal(c_dump(p.ast, p.unit, c_constant_expression(p)), "(binary + (ident a) (int 1))")
    }
}

[test(description = "the GNU forms inside expressions are kept as nodes: `?:` with no middle operand, a statement expression and the scope it closes, `__extension__`, `__builtin_va_arg`, `__builtin_offsetof`, `__builtin_types_compatible_p`, `typeof` and attributes in a type name")]
def test_gnu_forms(t : T?) {
    t |> equal(parsed("a ?: b"), "(cond (ident a) - (ident b))")
    t |> equal(parsed("(\{ x; \})"), "(stmt_expr (compound [(expr_stmt (ident x))]))")
    t |> equal(parsed("a + (\{ int T = 1; T; \}) * T"), "error: t.c:1:27: expected an expression, got 'T'")
    t |> equal(parsed("__extension__ (a + b)"), "(extension (paren (binary + (ident a) (ident b))))")
    t |> equal(parsed("__extension__ (int)x"), "(extension (cast (type_name [(spec int)] -) (ident x)))")
    t |> equal(parsed("-(int)x"), "(unary - (cast (type_name [(spec int)] -) (ident x)))")
    t |> equal(parsed("__builtin_va_arg(ap, int)"), "(va_arg (ident ap) (type_name [(spec int)] -))")
    t |> equal(parsed("__builtin_offsetof(struct S, a.b[2].c)"),
               "(offsetof (type_name [(record struct S 0 [])] -) [(field a) (field b) (index_desig (int 2) -) (field c)])")
    t |> equal(parsed("__builtin_types_compatible_p(int, T)"), "(types_compatible (type_name [(spec int)] -) (type_name [(typedef_name T)] -))")
    t |> equal(parsed("__builtin_choose_expr(1, a, b)"), "(call (ident __builtin_choose_expr) [(int 1) (ident a) (ident b)])")
    t |> equal(parsed("(typeof(x))y"), "(cast (type_name [(typeof_expr (ident x))] -) (ident y))")
    t |> equal(parsed("(__typeof__(int *))p"), "(cast (type_name [(typeof_type (type_name [(spec int)] (d_pointer - [])))] -) (ident p))")
    t |> equal(parsed("(__attribute__((unused)) int)x"), "(cast (type_name [(attribute __attribute__((unused))) (spec int)] -) (ident x))")
    t |> equal(parsed("(int *__attribute__((aligned(8))) const)p"), "(cast (type_name [(spec int)] (d_pointer - [(attribute __attribute__((aligned(8)))) (spec const)])) (ident p))")
    t |> equal(parsed("(int (__attribute__((x)) *))p"), "(cast (type_name [(spec int)] (d_paren (d_pointer - []) [(attribute __attribute__((x)))])) (ident p))")
    t |> equal(parsed("(struct __attribute__((packed)) S *)p"), "(cast (type_name [(record struct S 0 [] [(attribute __attribute__((packed)))])] (d_pointer - [])) (ident p))")
}

[test(description = "a type name: builtin specifiers and qualifiers, tags, typedef names, and abstract pointer, array, function and parenthesised declarators")]
def test_type_names(t : T?) {
    t |> equal(parsed("(unsigned long long)x"), "(cast (type_name [(spec unsigned) (spec long) (spec long)] -) (ident x))")
    t |> equal(parsed("(const char *)p"), "(cast (type_name [(spec const) (spec char)] (d_pointer - [])) (ident p))")
    t |> equal(parsed("(int *const *)p"), "(cast (type_name [(spec int)] (d_pointer (d_pointer - []) [(spec const)])) (ident p))")
    t |> equal(parsed("(int (*)[3])p"), "(cast (type_name [(spec int)] (d_array 0 (d_paren (d_pointer - []) []) (int 3) [])) (ident p))")
    t |> equal(parsed("(int (*)(int, char *))f"),
               "(cast (type_name [(spec int)] (d_function 0 (d_paren (d_pointer - []) []) [(param [(spec int)] -) (param [(spec char)] (d_pointer - []))])) (ident f))")
    t |> equal(parsed("(void (*)(void))f"), "(cast (type_name [(spec void)] (d_function 0 (d_paren (d_pointer - []) []) [(param [(spec void)] -)])) (ident f))")
    t |> equal(parsed("(int (*)(register int x, ...))f"),
               "(cast (type_name [(spec int)] (d_function 1 (d_paren (d_pointer - []) []) [(param [(spec register) (spec int)] (d_name x))])) (ident f))")
    t |> equal(parsed("(int (*)())f"), "(cast (type_name [(spec int)] (d_function 0 (d_paren (d_pointer - []) []) [])) (ident f))")
    t |> equal(parsed("(int (*[2])(void))0"),
               "(cast (type_name [(spec int)] (d_function 0 (d_paren (d_pointer (d_array 0 - (int 2) []) []) []) [(param [(spec void)] -)])) (int 0))")
    t |> equal(parsed("(char [static const 3])x"), "(cast (type_name [(spec char)] (d_array 1 - (int 3) [(spec const)])) (ident x))")
    t |> equal(parsed("(int [*])x"), "(cast (type_name [(spec int)] (d_array 2 - - [])) (ident x))")
    t |> equal(parsed("(int [*p])x"), "(cast (type_name [(spec int)] (d_array 0 - (unary * (ident p)) [])) (ident x))")
    t |> equal(parsed("(char [const static 3])x"), "(cast (type_name [(spec char)] (d_array 1 - (int 3) [(spec const)])) (ident x))")
    t |> equal(parsed("(int ((*)))x"), "(cast (type_name [(spec int)] (d_paren (d_paren (d_pointer - []) []) [])) (ident x))")
    t |> equal(parsed("(int ([3]))x"), "(cast (type_name [(spec int)] (d_paren (d_array 0 - (int 3) []) [])) (ident x))")
    t |> equal(parsed("(T)\{x\}"), "(compound_literal (type_name [(typedef_name T)] -) (init_list [(init [] (ident x))]))")
    t |> equal(parsed("(struct S *)p"), "(cast (type_name [(record struct S 0 [])] (d_pointer - [])) (ident p))")
    t |> equal(parsed("(union U)u"), "(cast (type_name [(record union U 0 [])] -) (ident u))")
    t |> equal(parsed("(enum E)1"), "(cast (type_name [(enum E 0 [])] -) (int 1))")
    t |> equal(parsed("(struct S \{ int a; \} *)p"), "(cast (type_name [(record struct S 1 [(member_decl 0 [(spec int)] [(member (d_name a) -)])])] (d_pointer - [])) (ident p))")
    t |> equal(parsed("(union \{ int a; \})u"), "(cast (type_name [(record union - 1 [(member_decl 0 [(spec int)] [(member (d_name a) -)])])] -) (ident u))")
    t |> equal(parsed("(enum \{ A \})1"), "(cast (type_name [(enum - 1 [(enumerator A -)])] -) (int 1))")
    t |> equal(parsed("(_Bool)x"), "(cast (type_name [(spec _Bool)] -) (ident x))")
    t |> equal(parsed("(_Atomic int)x"), "(cast (type_name [(spec _Atomic) (spec int)] -) (ident x))")
    t |> equal(parsed("(_Alignas(8) int)x"), "(cast (type_name [(alignas_expr (int 8)) (spec int)] -) (ident x))")
    t |> equal(parsed("(_Alignas(T) int)x"), "(cast (type_name [(alignas_type (type_name [(typedef_name T)] -)) (spec int)] -) (ident x))")
    t |> equal(parsed("(void (*)(int (x)))f"),
               "(cast (type_name [(spec void)] (d_function 0 (d_paren (d_pointer - []) []) [(param [(spec int)] (d_paren (d_name x) []))])) (ident f))")
    t |> equal(parsed("(void (*)(int (T)))f"),
               "(cast (type_name [(spec void)] (d_function 0 (d_paren (d_pointer - []) []) [(param [(spec int)] (d_function 0 - [(param [(typedef_name T)] -)]))])) (ident f))")
    t |> equal(parsed("(__const __volatile__ T * __restrict)p"),
               "(cast (type_name [(spec const) (spec volatile) (typedef_name T)] (d_pointer - [(spec restrict)])) (ident p))")
    var p : CParser
    opened(p, "int (*)(void)")
    t |> equal(finished(p, c_type_name(p)), "(type_name [(spec int)] (d_function 0 (d_paren (d_pointer - []) []) [(param [(spec void)] -)]))")
}

[test(description = "a construct the parser does not take fails closed: `file:line:col: <construct> is not parsed` at its first token")]
def test_refusals(t : T?) {
    t |> equal(parsed("&&lab"), "error: t.c:1:1: a label address (&&label) is not parsed")
    t |> equal(parsed("_Generic(x, int: 1)"), "error: t.c:1:1: a generic selection (_Generic) is not parsed")
    t |> equal(parsed("(__int128)x"), "error: t.c:1:2: the __int128 type is not parsed")
    t |> equal(parsed("(unsigned __int128)x"), "error: t.c:1:11: the __int128 type is not parsed")
    t |> equal(parsed("(_Atomic(int))x"), "error: t.c:1:2: the _Atomic(type) specifier is not parsed")
    t |> equal(parsed("(_Imaginary)x"), "error: t.c:1:2: the _Imaginary type is not parsed")
    t |> equal(parsed("(__auto_type)x"), "error: t.c:1:2: __auto_type is not parsed")
    t |> equal(parsed("__real__ x"), "error: t.c:1:1: __real__ is not parsed")
    t |> equal(parsed("__imag__ x"), "error: t.c:1:1: __imag__ is not parsed")
    t |> equal(parsed("__label__"), "error: t.c:1:1: a local label declaration (__label__) is not parsed")
    t |> equal(parsed("(T)\{x: 1\}"), "error: t.c:1:5: the old GNU designator 'member:' is not parsed")
}

[test(description = "malformed input ends with a located error naming what was expected: truncated at each nesting level, unbalanced, or a stray token")]
def test_malformed(t : T?) {
    let cases = fixed_array(
        ("", "t.c:1:1: expected an expression, got end of input"),
        ("(a", "t.c:1:3: expected ')', got end of input"),
        ("((a", "t.c:1:4: expected ')', got end of input"),
        ("a)", "t.c:1:2: expected end of input, got ')'"),
        ("f(g(", "t.c:1:5: expected an expression, got end of input"),
        ("f(a, ", "t.c:1:5: expected an expression, got end of input"),
        ("a[1", "t.c:1:4: expected ']', got end of input"),
        ("a ? b", "t.c:1:6: expected ':', got end of input"),
        ("a +", "t.c:1:4: expected an expression, got end of input"),
        ("a = = b", "t.c:1:5: expected an expression, got '='"),
        ("1 2", "t.c:1:3: expected end of input, got '2'"),
        ("(int)", "t.c:1:6: expected an expression, got end of input"),
        ("(T)\{1, ", "t.c:1:7: expected an expression, got end of input"),
        ("(T)\{.x", "t.c:1:7: expected '=', got end of input"),
        ("(T)\{[1 = 2\}", "t.c:1:8: expected ']', got '='"),
        ("sizeof(int", "t.c:1:11: expected ')', got end of input"),
        ("sizeof(T)\{", "t.c:1:11: expected an expression, got end of input"),
        ("(int [3)x", "t.c:1:8: expected ']', got ')'"),
        ("(int (*)(int,))f", "t.c:1:14: expected a parameter declaration, got ')'"),
        ("(struct)x", "t.c:1:8: expected a tag name or '\{' after 'struct', got ')'"),
        ("s.", "t.c:1:3: expected a member name, got end of input"),
        ("p->1", "t.c:1:4: expected a member name, got '1'"),
        ("__builtin_offsetof(T, )", "t.c:1:23: expected a member name, got ')'"),
        ("__builtin_offsetof(T, a+)", "t.c:1:24: expected ')', got '+'"),
        ("__builtin_va_arg(ap)", "t.c:1:20: expected ',', got ')'"),
        ("__builtin_va_arg(ap, 1)", "t.c:1:22: expected a type name, got '1'"),
        ("(T)\{. = 2\}", "t.c:1:7: expected a member name, got '='"),
        ("(__attribute__((x int)x", "t.c:1:24: expected ')' closing __attribute__, got end of input"),
        ("(int __attribute__ x)y", "t.c:1:20: expected '((' after __attribute__, got 'x'"),
        ("T", "t.c:1:1: expected an expression, got 'T'"),
        ("(static int)x", "t.c:1:2: expected an expression, got 'static'"),
        ("if", "t.c:1:1: expected an expression, got 'if'"),
        ("(int __attribute__(x))y", "t.c:1:19: expected '((' after __attribute__, got '('"),
        ("(typeof x)y", "t.c:1:9: expected '(', got 'x'"),
        ("(_Alignas(1, 2) int)x", "t.c:1:12: expected ')', got ','"),
        ("__builtin_offsetof(T, a[1 ... 2])", "t.c:1:27: expected ']', got '...'"),
        ("(T)\{1", "t.c:1:6: expected '\}', got end of input"),
        ("__builtin_types_compatible_p(int T)", "t.c:1:34: expected ',', got 'T'"),
        ("__builtin_types_compatible_p(int, int", "t.c:1:38: expected ')', got end of input"),
        ("__builtin_offsetof(T a)", "t.c:1:22: expected ',', got 'a'"),
        ("(void (*)(int (*, int))f", "t.c:1:17: expected ')', got ','"),
        ("(int (*)(int, ...[2]))f", "t.c:1:18: expected ')', got '['"))
    for (c in cases) {
        t |> equal(parsed(c._0), "error: {c._1}", c._0)
    }
    var p : CParser
    opened(p, "(a b")
    c_expression(p)
    t |> success(p.failed && p.pos == p.last, "the cursor stays at the end after an error")
}

// `text` repeated `count` times, then `inner`, then `closer` repeated `count` times
def private nested(text : string; count : int; inner, closer : string) : string => "{repeat(text, count)}{inner}{repeat(closer, count)}"

[test(description = "nesting is bounded: 256 levels parse within the test's 256 KiB stack, one more is refused at the token that opens it, a binary operator ladder costs no level, and no chain of any recursive form runs the stack out")]
def test_nesting_bound(t : T?) {
    t |> run("an expression in 255 parentheses is 256 levels and parses; 256 parentheses are refused at the last") @(t : T?) {
        t |> success(parsed(nested("(", 255, "x", ")")) |> starts_with("(paren (paren"))
        t |> equal(parsed(nested("(", 256, "x", ")")), "error: t.c:1:257: nesting deeper than 256 levels is not parsed")
    }
    t |> run("a ladder of every binary level inside each parenthesis costs no more than the parenthesis; a subscript or a call and its parenthesis cost two") @(t : T?) {
        let ladder = "(a||a&&a|a^a&a==a<a<<a+a*"
        t |> success(parsed(nested(ladder, 255, "x", ")")) |> starts_with("(paren (binary || (ident a) (binary &&"))
        t |> equal(parsed(nested(ladder, 256, "x", ")")), "error: t.c:1:{255 * length(ladder) + 2}: nesting deeper than 256 levels is not parsed")
        t |> success(parsed(nested("a[{ladder}", 127, "x", ")]")) |> starts_with("(index (ident a)"))
        t |> success(parsed(nested("f({ladder}", 127, "x", "))")) |> starts_with("(call (ident f)"))
    }
    t |> run("the deepest frames per level, `__builtin_offsetof` designators, at the bound") @(t : T?) {
        t |> success(parsed(nested("__builtin_offsetof(T, a[", 255, "0", "])")) |> starts_with("(offsetof"))
        t |> equal(parsed(nested("__builtin_offsetof(T, a[", 256, "0", "])")), "error: t.c:1:{255 * 24 + 20}: nesting deeper than 256 levels is not parsed")
    }
    t |> run("a compound literal where a unary expression stands, a cast and a nested abstract declarator each refuse the level they open") @(t : T?) {
        t |> equal(parsed("- - {repeat("++(T)\{", 3000)}"), "error: t.c:1:385: nesting deeper than 256 levels is not parsed")
        t |> equal(parsed("{repeat("-(T)", 3000)}x"), "error: t.c:1:510: nesting deeper than 256 levels is not parsed")
        t |> equal(parsed("(int {repeat("(", 3000)}"), "error: t.c:1:259: nesting deeper than 256 levels is not parsed")
    }
    t |> run("every recursive form ends with the refusal") @(t : T?) {
        let chains = fixed_array("{repeat("- ", 3000)}x", "(int {repeat("*", 3000)})x", "(T){repeat("\{", 3000)}",
            "{repeat("a ? b : ", 3000)}c", "{repeat("a ? ", 3000)}c", "{repeat("a = ", 3000)}c", "{repeat("(T)", 3000)}x", "{repeat("f(", 3000)}",
            "(int {repeat("(int ", 3000)})x", "{repeat("sizeof ", 3000)}x", "(typeof({repeat("typeof(", 3000)}", "{repeat("a[", 3000)}",
            "{repeat("++(T)\{", 3000)}", "{repeat("sizeof(typeof(", 3000)}", "{repeat("__builtin_offsetof(T, a[", 3000)}",
            "(int {repeat("(*", 3000)}", "{repeat("a ?: ", 3000)}c")
        for (text in chains) {
            t |> success(parsed(text) |> ends_with("nesting deeper than 256 levels is not parsed"), slice(text, 0, 12))
        }
    }
}

[test(description = "the dump walks a tree of any depth with its own stack: a flat sum of 5000 terms is a left chain 5000 nodes deep")]
def test_deep_dump(t : T?) {
    let text = "a{repeat(" + a", 4999)}"
    let dump = parsed(text)
    t |> success(dump |> starts_with("{repeat("(binary + ", 4999)}(ident a)"))
    t |> success(dump |> ends_with(" (ident a))"))
}

[test(description = "every node is placed at its first token, through a line marker too, and an error names the file a marker named")]
def test_places(t : T?) {
    t |> equal(parsed("a +\n  b * c", true), "(binary@1:1 + (ident@1:1 a) (binary@2:3 * (ident@2:3 b) (ident@2:7 c)))")
    t |> equal(parsed("# 7 \"x.h\"\n  f(\n(T)1)", true), "(call@7:3 (ident@7:3 f) [(cast@8:1 (type_name@8:2 [(typedef_name@8:2 T)] -) (int@8:4 1))])")
    t |> equal(parsed("# 7 \"x.h\"\na +"), "error: x.h:7:4: expected an expression, got end of input")
    t |> equal(parsed("x @"), "error: t.c:1:3: stray '@'")
}

[test(description = "parsing a long expression allocates no string and a fixed number of heap blocks, however many tokens it holds")]
def test_no_allocation(t : T?) {
    let text = build_string() $(var w) {
        w |> write("x")
        for (i in range(2000)) {
            w |> write(" + a[{i}] * (T)b->c")
        }
    }
    var p : CParser
    opened(p, text)
    let heap = int(heap_allocation_count())
    let strings = int(string_heap_allocation_count())
    let e = c_expression(p)
    let heap_used = int(heap_allocation_count()) - heap
    let strings_used = int(string_heap_allocation_count()) - strings
    c_expect_end(p)
    t |> success(!p.failed && e >= 0, p.err)
    t |> success(length(p.unit.toks) > 20000, "{length(p.unit.toks)} tokens")
    t |> equal(strings_used, 0, "string allocations")
    t |> success(heap_used <= 2, "heap allocations {heap_used} over {length(p.ast.nodes)} nodes")
}
