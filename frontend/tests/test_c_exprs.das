options gen2
options stack = 262144
require dastest/testing_boost public
require strings
require daslib/strings_boost
require ../c_ir.das

//! `frontend/c_exprs.das` and `frontend/c_ir.das`: per conversion group the exact cast stream clang
//! writes, the literals' types and values, `sizeof`, initializers, the statements' C-IR, the order
//! the expression types enter the table, and every refusal with its place.

// a table entry as C spells it, short
def private spelled(types : array<CirType>; t : int) : string {
    return "?" if (t < 0)
    assume ty = types[t]
    if (ty.k == "int" || ty.k == "float") {
        return ty.spell
    } elif (ty.k == "ptr") {
        return "{spelled(types, ty.to)}*"
    } elif (ty.k == "array") {
        return "{spelled(types, ty.elem)}[{ty.count}]"
    }
    return ty.k
}

// expression `x` as one line: each node its kind and type, a cast its kind (`!` explicit)
def private shown(types : array<CirType>; x : CirExpr?) : string {
    return "-" if (x == null)
    let t = spelled(types, x.t)
    if (x.e == "cast") {
        return "{x.cast_kind}{x.explicit_cast ? "!" : ""}<{t}>({shown(types, x.a)})"
    } elif (x.e == "ref") {
        return x.vol ? "{x.name}~" : x.name
    } elif (x.e == "int_lit") {
        return x.is_char ? "'{x.v}'<{t}>" : "{x.v}<{t}>"
    } elif (x.e == "float_lit") {
        return "{x.v}<{t}>"
    } elif (x.e == "str_lit") {
        return "str<{t}>"
    } elif (x.e == "sizeof_v") {
        return "sizeof<{t}>={int64(x.trait_v)}:{spelled(types, x.of_t)}"
    } elif (x.e == "init_list") {
        return "\{" + join([for (it in x.init_items); "{it.pos}:{shown(types, it.v)}"], ", ") + "\}<{t}>"
    } elif (x.e == "call") {
        let args = join([for (a in x.args); shown(types, a)], ", ")
        return "call<{t}>({shown(types, x.fn)}; {args})"
    } elif (x.e == "index") {
        return "index<{t}>({shown(types, x.base)}, {shown(types, x.i)})"
    } elif (x.e == "cond") {
        return "cond<{t}>({shown(types, x.c)}, {shown(types, x.a)}, {shown(types, x.b)})"
    } elif (x.e == "un") {
        return "{x.op}<{t}>({shown(types, x.a)})"
    }
    let op = x.e == "assign" ? "assign{x.op}" : x.e == "comma" ? "comma" : x.op
    return "{op}<{t}>({shown(types, x.a)}, {shown(types, x.b)})"
}

// the statements of `st` and under it as lines into `out`: each kind with its expressions
def private statements(types : array<CirType>; st : CirStmt?; var out : array<string>) {
    return if (st == null)
    if (st.s == "decl") {
        out |> push("{st.name}:{spelled(types, st.t)}={shown(types, st.init)}")
    } elif (st.s == "expr" || st.s == "return") {
        out |> push("{st.s} {shown(types, st.e)}")
    } elif (st.s == "case") {
        out |> push("case {st.v}{st.is_char ? "c" : ""}")
    } elif (st.s == "label" || st.s == "goto") {
        out |> push("{st.s} {st.label_name}")
    } elif (st.s != "compound") {
        let parts = "{shown(types, st.cond)} {shown(types, st.inc)}"
        out |> push("{st.s} {parts}")
    }
    statements(types, st.init_s, out)
    for (kid in st.body) {
        statements(types, kid, out)
    }
    statements(types, st.then_s, out)
    statements(types, st.else_s, out)
    statements(types, st.body_s, out)
}

// the C-IR of unit `text` (named `t.c`) as lines joined by ` ; `: each global's initializer and
// each function's statements; `error: ` and the builder's error, or `parse error: `
def private ir_of(text : string; msvc : bool = false) : string {
    var p : CParser
    c_parser_open_text(p, text, "t.c", msvc)
    let u = c_unit(p)
    return "parse error: {p.err}" if (p.failed)
    var r = new CIr
    c_ir_open(*r, msvc ? target_llp64_msvc() : target_lp64_linux(), "")
    var out : array<string>
    if (c_ir_unit(*r, p, u)) {
        for (d in r.b.tu.decls) {
            if (d.k == "global" && d.init != null) {
                out |> push("{d.name}={shown(r.b.tu.types, d.init)}")
            } elif (d.k == "func") {
                statements(r.b.tu.types, d.body, out)
            }
        }
    } else {
        out |> push("error: {r.b.err}")
    }
    let listed = join(out, " ; ")
    delete_tu(r.b.tu)
    unsafe {
        delete r
    }
    return listed
}

[test(description = "group 1, the 6.3.2.1 conversions: an lvalue read, its type unqualified; an array, a string literal and a function decayed; none under &, sizeof, ++ and an assignment's left operand")]
def test_value_conversions(t : T?) {
    t |> equal(ir_of("int a[2]; int f(void); void g(void) \{ const int c = 1; volatile int v; c; v; a; \"s\"; f; &a; &f; v++; v = c; a[1]; \}"),
               "c:int=1<int> ; v:int=- ; expr LValueToRValue<int>(c) ; expr LValueToRValue<int>(v~) ; expr ArrayToPointerDecay<int*>(a) ; expr ArrayToPointerDecay<char*>(str<char[2]>) ; expr FunctionToPointerDecay<func*>(f) ; expr addr<int[2]*>(a) ; expr addr<func*>(f) ; expr postinc<int>(v~) ; expr assign<int>(v~, LValueToRValue<int>(c)) ; expr LValueToRValue<int>(index<int>(ArrayToPointerDecay<int*>(a), 1<int>))")
}

[test(description = "group 2, to the slot's type: scalar initializers, assignment, a prototyped argument, a return, an old-style definition's argument to its promoted parameter; a literal converted, never retyped; a qualifying NoOp")]
def test_slot_conversions(t : T?) {
    t |> run("initializers, assignment, return") @(t : T?) {
        t |> equal(ir_of("long g(char c) \{ char d = 1; double x = c; _Bool b = 3; d = x; return c; \}"),
                   "d:char=IntegralCast<char>(1<int>) ; x:double=IntegralToFloating<double>(LValueToRValue<char>(c)) ; b:_Bool=IntegralToBoolean<_Bool>(3<int>) ; expr assign<char>(d, FloatingToIntegral<char>(LValueToRValue<double>(x))) ; return IntegralCast<long>(LValueToRValue<char>(c))")
    }
    t |> run("arguments: prototyped, an old-style definition's, a qualifying NoOp") @(t : T?) {
        t |> equal(ir_of("void k(const char *s, long n); int f(a, b) char a; float b; \{ return 0; \} void g(char *m) \{ k(m, 1); f(1, 2); \}"),
                   "return 0<int> ; expr call<void>(FunctionToPointerDecay<func*>(k); NoOp<char*>(LValueToRValue<char*>(m)), IntegralCast<long>(1<int>)) ; expr call<int>(FunctionToPointerDecay<func*>(f); 1<int>, IntegralToFloating<double>(2<int>))")
    }
    t |> run("a pointer to and from void *, an integer to a pointer, a pointer to _Bool and to an integer") @(t : T?) {
        t |> equal(ir_of("void g(int *p, void *v, long l) \{ v = p; p = v; p = l; _Bool b = p; l = p; \}"),
                   "expr assign<void*>(v, BitCast<void*>(LValueToRValue<int*>(p))) ; expr assign<int*>(p, BitCast<int*>(LValueToRValue<void*>(v))) ; expr assign<int*>(p, IntegralToPointer<int*>(LValueToRValue<long>(l))) ; b:_Bool=PointerToBoolean<_Bool>(LValueToRValue<int*>(p)) ; expr assign<long>(l, PointerToIntegral<long>(LValueToRValue<int*>(p)))")
    }
}

[test(description = "group 3, null pointer constants: NullToPointer from 0, nested over an explicit (void *)0, a BitCast of (void *)0 where a comparison converts it as a pointer, an explicit cast of 0 to a pointer")]
def test_null_pointers(t : T?) {
    t |> equal(ir_of("void g(int *p, int c) \{ p = 0; p = (void *)0; p == (void *)0; 0 == p; p = c ? p : 0; (char *)0; (int *)(void *)0; p = '\\0'; \}"),
               "expr assign<int*>(p, NullToPointer<int*>(0<int>)) ; expr assign<int*>(p, NullToPointer<int*>(NullToPointer!<void*>(0<int>))) ; expr eq<int>(LValueToRValue<int*>(p), BitCast<int*>(NullToPointer!<void*>(0<int>))) ; expr eq<int>(NullToPointer<int*>(0<int>), LValueToRValue<int*>(p)) ; expr assign<int*>(p, cond<int*>(LValueToRValue<int>(c), LValueToRValue<int*>(p), NullToPointer<int*>(0<int>))) ; expr NullToPointer!<char*>(0<int>) ; expr BitCast!<int*>(NullToPointer!<void*>(0<int>)) ; expr assign<int*>(p, NullToPointer<int*>('0'<int>))")
}

[test(description = "group 4, operand conversions: promotions of binary, logical, shift, unary and switch operands and of the ?: condition, one cast for a promotion and the conversion after it, the usual arithmetic conversions by rank, width and sign, ?: arms, compound assignment, pointers")]
def test_operand_conversions(t : T?) {
    t |> run("promotions and the usual arithmetic conversions, linux") @(t : T?) {
        t |> equal(ir_of("void g(char c, short s, unsigned u, long l, float f) \{ c + s; c + l; u + l; c && s; c << s; -c; !c; f * 2.0; switch (c) \{ \} \}"),
                   "expr add<int>(IntegralCast<int>(LValueToRValue<char>(c)), IntegralCast<int>(LValueToRValue<short>(s))) ; expr add<long>(IntegralCast<long>(LValueToRValue<char>(c)), LValueToRValue<long>(l)) ; expr add<long>(IntegralCast<long>(LValueToRValue<unsigned int>(u)), LValueToRValue<long>(l)) ; expr land<int>(IntegralCast<int>(LValueToRValue<char>(c)), IntegralCast<int>(LValueToRValue<short>(s))) ; expr shl<int>(IntegralCast<int>(LValueToRValue<char>(c)), IntegralCast<int>(LValueToRValue<short>(s))) ; expr neg<int>(IntegralCast<int>(LValueToRValue<char>(c))) ; expr not<int>(LValueToRValue<char>(c)) ; expr mul<double>(FloatingCast<double>(LValueToRValue<float>(f)), 0x1p+1<double>) ; switch IntegralCast<int>(LValueToRValue<char>(c)) -")
    }
    t |> run("msvc: unsigned int and long take unsigned long") @(t : T?) {
        t |> equal(ir_of("void g(unsigned u, long l) \{ u + l; \}", true),
                   "expr add<unsigned long>(IntegralCast<unsigned long>(LValueToRValue<unsigned int>(u)), IntegralCast<unsigned long>(LValueToRValue<long>(l)))")
    }
    t |> run("?: arms, compound assignment, pointer arithmetic and comparison") @(t : T?) {
        t |> equal(ir_of("void g(char c, short s, float f, int *p, void *v, long *q) \{ c ? s : f; c ? p : v; c ? p : q; s += c; c += 1; f += c; p += c; c <<= s; p - p; p + c; p < p; \}"),
                   "expr cond<float>(IntegralCast<int>(LValueToRValue<char>(c)), IntegralToFloating<float>(IntegralCast<int>(LValueToRValue<short>(s))), LValueToRValue<float>(f)) ; expr cond<void*>(IntegralCast<int>(LValueToRValue<char>(c)), BitCast<void*>(LValueToRValue<int*>(p)), LValueToRValue<void*>(v)) ; expr cond<void*>(IntegralCast<int>(LValueToRValue<char>(c)), BitCast<void*>(LValueToRValue<int*>(p)), BitCast<void*>(LValueToRValue<long*>(q))) ; expr assignadd<short>(s, IntegralCast<int>(LValueToRValue<char>(c))) ; expr assignadd<char>(c, 1<int>) ; expr assignadd<float>(f, IntegralToFloating<float>(IntegralCast<int>(LValueToRValue<char>(c)))) ; expr assignadd<int*>(p, IntegralCast<int>(LValueToRValue<char>(c))) ; expr assignshl<char>(c, IntegralCast<int>(LValueToRValue<short>(s))) ; expr sub<long>(LValueToRValue<int*>(p), LValueToRValue<int*>(p)) ; expr add<int*>(LValueToRValue<int*>(p), IntegralCast<int>(LValueToRValue<char>(c))) ; expr lt<int>(LValueToRValue<int*>(p), LValueToRValue<int*>(p))")
    }
}

[test(description = "group 5, explicit casts: NoOp to the same type, every arithmetic kind, to void with the operand read, between pointers and integers, to _Bool")]
def test_explicit_casts(t : T?) {
    t |> equal(ir_of("void g(char c, double d, int *p, long l) \{ (char)c; (int)c; (int)d; (float)d; (void)c; (long)p; (int *)l; (char *)p; (_Bool)p; (_Bool)d; (const int *)p; \}"),
               "expr NoOp!<char>(LValueToRValue<char>(c)) ; expr IntegralCast!<int>(LValueToRValue<char>(c)) ; expr FloatingToIntegral!<int>(LValueToRValue<double>(d)) ; expr FloatingCast!<float>(LValueToRValue<double>(d)) ; expr ToVoid!<void>(LValueToRValue<char>(c)) ; expr PointerToIntegral!<long>(LValueToRValue<int*>(p)) ; expr IntegralToPointer!<int*>(LValueToRValue<long>(l)) ; expr BitCast!<char*>(LValueToRValue<int*>(p)) ; expr PointerToBoolean!<_Bool>(LValueToRValue<int*>(p)) ; expr FloatingToBoolean!<_Bool>(LValueToRValue<double>(d)) ; expr NoOp!<int*>(LValueToRValue<int*>(p))")
}

[test(description = "group 6, default argument promotions: a variadic argument and an argument of a function with no prototype promoted, a float made double")]
def test_argument_promotions(t : T?) {
    t |> equal(ir_of("int printf(const char *, ...); int h(); void g(char c, float f) \{ printf(\"%d\", c, f); h(c, f); \}"),
               "expr call<int>(FunctionToPointerDecay<func*>(printf); NoOp<char*>(ArrayToPointerDecay<char*>(str<char[3]>)), IntegralCast<int>(LValueToRValue<char>(c)), FloatingCast<double>(LValueToRValue<float>(f))) ; expr call<int>(FunctionToPointerDecay<func*>(h); IntegralCast<int>(LValueToRValue<char>(c)), FloatingCast<double>(LValueToRValue<float>(f)))")
}

[test(description = "__builtin_expect, the one builtin typed: called through a decay to its prototype, its arguments converted to long; its reference typed as clang types a builtin")]
def test_builtin(t : T?) {
    t |> equal(ir_of("void g(int x) \{ __builtin_expect(x, 0); \}"),
               "expr call<long>(FunctionToPointerDecay<func*>(__builtin_expect); IntegralCast<long>(LValueToRValue<int>(x)), IntegralCast<long>(0<int>))")
}

[test(description = "literals: an integer literal's type by base, suffix and value under both dialects, character constants plain, escaped, wide and of plain unsigned char, floating constants by suffix")]
def test_literals(t : T?) {
    t |> run("linux") @(t : T?) {
        t |> equal(ir_of("void g(void) \{ 2147483647; 2147483648; 0x80000000; 0xffffffffffffffff; 10u; 10l; 10ul; 07; 'a'; '\\xff'; L'b'; u'c'; U'd'; 1.5; 1.5f; 2.5L; \}"),
                   "expr 2147483647<int> ; expr 2147483648<long> ; expr 2147483648<unsigned int> ; expr 18446744073709551615<unsigned long> ; expr 10<unsigned int> ; expr 10<long> ; expr 10<unsigned long> ; expr 7<int> ; expr '97'<int> ; expr '255'<int> ; expr '98'<int> ; expr '99'<unsigned short> ; expr '100'<unsigned int> ; expr 0x1.8p+0<double> ; expr 0x1.8p+0<float> ; expr 0x1.4p+1<long double>")
    }
    t |> run("msvc: long is 32 bits, wchar_t unsigned short") @(t : T?) {
        t |> equal(ir_of("void g(void) \{ 2147483648; 4294967296; 0x80000000l; L'b'; \}", true),
                   "expr 2147483648<long long> ; expr 4294967296<long long> ; expr 2147483648<unsigned long> ; expr '98'<unsigned short>")
    }
}

[test(description = "sizeof of a type and of an expression: the dialect's size_t, Dumper A's sizes, the operand left unconverted")]
def test_sizeof(t : T?) {
    t |> equal(ir_of("void g(char *s) \{ int a[3]; sizeof a; sizeof(long double); sizeof s[0]; \}"),
               "a:int[3]=- ; expr sizeof<unsigned long>=12:int[3] ; expr sizeof<unsigned long>=8:long double ; expr sizeof<unsigned long>=1:char")
    t |> equal(ir_of("unsigned long long n = sizeof(int *);", true), "n=sizeof<unsigned long long>=8:int*")
}

[test(description = "initializers: a string literal typed as its character array, braced or not; a list's items converted at their positions, sorted, a later designator replacing an earlier item; a braced scalar")]
def test_initializers(t : T?) {
    t |> equal(ir_of("char s[10] = \"ab\"; char u[] = \{\"cd\"\}; short a[4] = \{1, [3] = 2, [1] = 3, [3] = 4\}; int n = \{5\}; const char *w[] = \{\"x\", 0\};"),
               "s=str<char[10]> ; u=str<char[3]> ; a=\{0:IntegralCast<short>(1<int>), 1:IntegralCast<short>(3<int>), 3:IntegralCast<short>(4<int>)\}<short[4]> ; n=5<int> ; w=\{0:NoOp<char*>(ArrayToPointerDecay<char*>(str<char[2]>)), 1:NullToPointer<char*>(0<int>)\}<char*[2]>")
}

[test(description = "statements: each kind with its expressions in Dumper A's shape, case and label markers before their statements, a hoisted static and an extern leaving a null, a GNU statement block as its compound")]
def test_statements(t : T?) {
    t |> equal(ir_of("int g(int x) \{ static int s = 1; extern int e; if (x) x = 2; else return 0; while (x) x--; do x++; while (0); for (int i = 0; i < 2; i++) ; switch (x) \{ case 'a': case 2: break; default: ; \} l: goto l; (\{ x; \}); return x; \}"),
               "g_s=1<int> ; null - - ; null - - ; if LValueToRValue<int>(x) - ; expr assign<int>(x, 2<int>) ; return 0<int> ; while LValueToRValue<int>(x) - ; expr postdec<int>(x) ; do 0<int> - ; expr postinc<int>(x) ; for lt<int>(LValueToRValue<int>(i), 2<int>) postinc<int>(i) ; i:int=0<int> ; null - - ; switch LValueToRValue<int>(x) - ; case 97c ; case 2 ; break - - ; default - - ; null - - ; label l ; goto l ; expr LValueToRValue<int>(x) ; return LValueToRValue<int>(x)")
}

[test(description = "the table order: a declaration's type, then its initializer's node types before their operands', a body's expressions where they stand")]
def test_table_order(t : T?) {
    var p : CParser
    c_parser_open_text(p, "char c = 1; void g(void) \{ (short)c; \}", "t.c")
    let u = c_unit(p)
    var r = new CIr
    c_ir_open(*r, target_lp64_linux(), "")
    t |> success(c_ir_unit(*r, p, u))
    t |> equal(join([for (ty in r.b.tu.types); c_type_key(ty)], " "), "int:8:false:char int:32:true:int void func:2::false int:16:true:short")
    delete_tu(r.b.tu)
    unsafe {
        delete r
    }
}

[test(description = "every construct not typed yet is refused at its place")]
def test_refusals(t : T?) {
    t |> equal(ir_of("void g(void) \{ y; \}"), "error: t.c:1:16: the identifier 'y', which names no variable or function the builder knows, is not typed yet")
    t |> equal(ir_of("void g(void) \{ __builtin_expect; \}"), "error: t.c:1:16: the builtin '__builtin_expect' other than as a callee is not typed yet")
    t |> equal(ir_of("void g(int x) \{ x ?: 1; \}"), "error: t.c:1:17: GNU's ?: with no middle operand is not typed yet")
    t |> equal(ir_of("void g(int *p) \{ p * 2; \}"), "error: t.c:1:18: this operator on a pointer is not typed yet")
    t |> equal(ir_of("void g(int x) \{ *x; \}"), "error: t.c:1:17: a dereference of a value that is no pointer is not typed yet")
    t |> equal(ir_of("void g(int x) \{ x(); \}"), "error: t.c:1:17: a call of a value that is no function is not typed yet")
    t |> equal(ir_of("void g(int x) \{ x[1]; \}"), "error: t.c:1:17: a subscript of a value that is no pointer is not typed yet")
    t |> equal(ir_of("void g(int x, int *p) \{ x ? p : 1.0; \}"), "error: t.c:1:25: a conditional of these arms is not typed yet")
    t |> equal(ir_of("void g(double d) \{ (int *)d; \}"), "error: t.c:1:20: this cast is not typed yet")
    t |> equal(ir_of("void g(void) \{ 'ab'; \}"), "error: t.c:1:16: the character constant 'ab' is not typed yet")
    t |> equal(ir_of("void g(void) \{ 99999999999999999999; \}"), "error: t.c:1:16: the integer literal '99999999999999999999', which no type of its list holds, is not typed yet")
    t |> equal(ir_of("void g(void) \{ sizeof(void); \}"), "error: t.c:1:16: sizeof of a type without a size is not typed yet")
    t |> equal(ir_of("void g(int x) \{ switch (x) \{ case x: ; \} \}"), "error: t.c:1:30: this case label is not typed yet")
    t |> equal(ir_of("int a[2] = \{[0 + x] = 1\};"), "error: t.c:1:18: the identifier 'x', which names no variable or function the builder knows, is not typed yet")
    t |> equal(ir_of("int a[2][2] = \{1, 2\};"), "error: t.c:1:16: an initializer of an array of arrays with elided braces is not typed yet")
    t |> equal(ir_of("int n = \{1, 2\};"), "error: t.c:1:9: a braced scalar initializer of other than one value is not typed yet")
    t |> equal(ir_of("void g(void) \{ __func__; \}"), "error: t.c:1:16: this expression is not typed yet")
    t |> equal(ir_of("void g(void) \{ asm(\"nop\"); \}"), "error: t.c:1:16: this statement is not typed yet")
}
