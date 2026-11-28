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

// literal or `sizeof` node `x` as `shown` writes it, "" for any other node
def private shown_leaf(types : array<CirType>; x : CirExpr?) : string {
    let t = spelled(types, x.t)
    if (x.e == "int_lit") {
        return x.is_char ? "'{x.v}'<{t}>" : "{x.v}<{t}>"
    } elif (x.e == "float_lit") {
        return "{x.v}<{t}>"
    } elif (x.e == "str_lit") {
        return "str<{t}>"
    } elif (x.e == "sizeof_v") {
        return "sizeof<{t}>={int64(x.trait_v)}:{spelled(types, x.of_t)}"
    }
    return ""
}

// expression `x` as one line: each node its kind and type, a cast its kind (`!` explicit); with
// `marks`, `^` after a volatile subscript or dereference and `()` after a parenthesized node
def private shown(types : array<CirType>; x : CirExpr?; marks : bool = false) : string {
    return "-" if (x == null)
    let leaf = shown_leaf(types, x)
    return leaf if (!empty(leaf))
    let t = spelled(types, x.t)
    let vol_mark = marks && x.vol && x.e != "ref" ? "^" : ""
    let mark = vol_mark + (marks && x.paren ? "()" : "")
    if (x.e == "cast") {
        return "{x.cast_kind}{x.explicit_cast ? "!" : ""}<{t}>({shown(types, x.a, marks)}){mark}"
    } elif (x.e == "ref") {
        return (x.vol ? "{x.name}~" : x.name) + mark
    } elif (x.e == "init_list") {
        return "\{" + join([for (it in x.init_items); "{it.pos}:{shown(types, it.v, marks)}"], ", ") + "\}<{t}>"
    } elif (x.e == "call") {
        let args = join([for (a in x.args); shown(types, a, marks)], ", ")
        return "call<{t}>({shown(types, x.fn, marks)}; {args}){mark}"
    } elif (x.e == "index") {
        return "index<{t}>({shown(types, x.base, marks)}, {shown(types, x.i, marks)}){mark}"
    } elif (x.e == "cond") {
        return "cond<{t}>({shown(types, x.c, marks)}, {shown(types, x.a, marks)}, {shown(types, x.b, marks)}){mark}"
    } elif (x.e == "un") {
        return "{x.op}<{t}>({shown(types, x.a, marks)}){mark}"
    }
    let op = x.e == "assign" ? "assign{x.op}" : x.e == "comma" ? "comma" : x.op
    return "{op}<{t}>({shown(types, x.a, marks)}, {shown(types, x.b, marks)}){mark}"
}

// the statements of `st` and under it as lines into `out`: each kind with its expressions
def private statements(types : array<CirType>; st : CirStmt?; var out : array<string>; marks : bool = false) {
    return if (st == null)
    if (st.s == "decl") {
        out |> push("{st.name}:{spelled(types, st.t)}={shown(types, st.init, marks)}")
    } elif (st.s == "expr" || st.s == "return") {
        out |> push("{st.s} {shown(types, st.e, marks)}")
    } elif (st.s == "case") {
        out |> push("case {st.v}{st.is_char ? "c" : ""}")
    } elif (st.s == "label" || st.s == "goto") {
        out |> push("{st.s} {st.label_name}")
    } elif (st.s != "compound") {
        let parts = "{shown(types, st.cond, marks)} {shown(types, st.inc, marks)}"
        out |> push("{st.s} {parts}")
    }
    statements(types, st.init_s, out, marks)
    for (kid in st.body) {
        statements(types, kid, out, marks)
    }
    statements(types, st.then_s, out, marks)
    statements(types, st.else_s, out, marks)
    statements(types, st.body_s, out, marks)
}

// the C-IR of unit `text` (named `unit`, `library` the own headers' folder) as lines joined by
// ` ; `: each global's initializer and each function's statements, with `names` every global's and
// function's name and a function's parameters' too; `error: ` and the builder's error, or `parse
// error: `. With `full`, the marks of `shown`, every global as `G <name>:<type>` (`extern` when it
// is one) with its initializer, and the type table last as `TABLE` and its keys
def private ir_of(text : string; msvc : bool = false; unit : string = "t.c"; names : bool = false; full : bool = false;
                  library : string = "") : string {
    var p : CParser
    c_parser_open_text(p, text, unit, msvc)
    return ir_listed(p, msvc, names, full, library)
}

// `ir_of` over C source `text` named `main.c`, read with macro expansion and no clang
def private source_ir_of(text : string; full : bool = false) : string {
    var mem = new PpMemoryProvider()
    mem->add("main.c", text)
    var p : CParser
    c_parser_open_source(p, mem, "main.c", array<string>(), array<string>())
    return ir_listed(p, false, false, full, "")
}

// the lines `ir_of` writes for the unit parser `p` opened
def private ir_listed(var p : CParser; msvc, names, full : bool; library : string) : string {
    let u = c_unit(p)
    return "parse error: {p.err}" if (p.failed)
    var r = new CIr
    c_ir_open(*r, msvc ? target_llp64_msvc() : target_lp64_linux(), library)
    var out : array<string>
    if (c_ir_unit(*r, p, u)) {
        for (d in r.tu.decls) {
            if (full && d.k == "global") {
                out |> push("G {d.name}:{spelled(r.tu.types, d.t)}{d.is_extern ? " extern" : ""}={shown(r.tu.types, d.init, true)}")
            } elif (names && d.k == "global") {
                out |> push(d.init != null ? "{d.name}={shown(r.tu.types, d.init)}" : "{d.name}")
            } elif (d.k == "global" && d.init != null) {
                out |> push("{d.name}={shown(r.tu.types, d.init)}")
            } elif (d.k == "func") {
                if (names) {
                    out |> push("{d.name}(" + join([for (q in d.params); q.name], ",") + ")")
                }
                statements(r.tu.types, d.body, out, full)
            }
        }
        if (full) {
            out |> push("TABLE " + join([for (ty in r.tu.types); c_type_key(ty)], " "))
        }
    } else {
        out |> push("error: {r.err}")
    }
    let listed = join(out, " ; ")
    delete_tu(r.tu)
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
    t |> run("a pointer to and from void *, a pointer to _Bool") @(t : T?) {
        t |> equal(ir_of("void g(int *p, void *v) \{ v = p; p = v; _Bool b = p; \}"),
                   "expr assign<void*>(v, BitCast<void*>(LValueToRValue<int*>(p))) ; expr assign<int*>(p, BitCast<int*>(LValueToRValue<void*>(v))) ; b:_Bool=PointerToBoolean<_Bool>(LValueToRValue<int*>(p))")
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

[test(description = "the builtins typed, __builtin_expect and __builtin_abort: called through a decay to its prototype, __builtin_expect's arguments converted to long; the reference typed as clang types a builtin")]
def test_builtin(t : T?) {
    t |> equal(ir_of("void g(int x) \{ __builtin_expect(x, 0); \}"),
               "expr call<long>(FunctionToPointerDecay<func*>(__builtin_expect); IntegralCast<long>(LValueToRValue<int>(x)), IntegralCast<long>(0<int>))")
    t |> equal(ir_of("void g(void) \{ __builtin_abort(); \}"), "expr call<void>(FunctionToPointerDecay<func*>(__builtin_abort); )")
}

[test(description = "literals: an integer literal's type by base, suffix and value under both dialects, character constants plain, escaped, wide and of plain unsigned char, a wide one of a numeric escape, floating constants by suffix")]
def test_literals(t : T?) {
    t |> run("linux") @(t : T?) {
        t |> equal(ir_of("void g(void) \{ 2147483647; 2147483648; 0x80000000; 0xffffffffffffffff; 10u; 10l; 10ul; 07; 'a'; '\\xff'; L'b'; u'c'; U'd'; 1.5; 1.5f; 2.5L; \}"),
                   "expr 2147483647<int> ; expr 2147483648<long> ; expr 2147483648<unsigned int> ; expr 18446744073709551615<unsigned long> ; expr 10<unsigned int> ; expr 10<long> ; expr 10<unsigned long> ; expr 7<int> ; expr '97'<int> ; expr '255'<int> ; expr '98'<int> ; expr '99'<unsigned short> ; expr '100'<unsigned int> ; expr 0x1.8p+0<double> ; expr 0x1.8p+0<float> ; expr 0x1.4p+1<long double>")
    }
    t |> run("msvc: long is 32 bits, wchar_t unsigned short, an ll literal past long long a wrapped long long") @(t : T?) {
        t |> equal(ir_of("void g(void) \{ 2147483648; 4294967296; 0x80000000l; L'b'; \}", true),
                   "expr 2147483648<long long> ; expr 4294967296<long long> ; expr 2147483648<unsigned long> ; expr '98'<unsigned short>")
        t |> equal(ir_of("void g(void) \{ 0xc000000080000000LL; 0xc000000080000000ULL; 0xc000000080000000; 0x7fffffffffffffffLL; \}", true),
                   "expr -4611686016279904256<long long> ; expr 13835058057429647360<unsigned long long> ; expr 13835058057429647360<unsigned long long> ; expr 9223372036854775807<long long>")
    }
    t |> run("a prefixed constant's one octal or hexadecimal escape: a code unit, not a byte; one past its type's range refused") @(t : T?) {
        t |> equal(ir_of("void g(void) \{ L'\\400'; U'\\x41'; \}"), "expr '256'<int> ; expr '65'<unsigned int>")
        t |> equal(ir_of("void g(void) \{ L'\\400'; \}", true), "expr '256'<unsigned short>")
        t |> equal(ir_of("void g(void) \{ U'\\x80000000'; \}"), "expr '2147483648'<unsigned int>")
        t |> equal(ir_of("void g(void) \{ L'\\x80000000'; \}"), "error: t.c:1:16: the character constant L'\\x80000000' is not typed yet")
        t |> equal(ir_of("void g(void) \{ L'\\4000'; \}"), "error: t.c:1:16: the character constant L'\\4000' is not typed yet")
        t |> equal(ir_of("void g(void) \{ L'\\4a'; \}"), "error: t.c:1:16: the character constant L'\\4a' is not typed yet")
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

// the places the builder gives unit `text`: each declaration's `name@file:line:col`, then its body's
// statements' `kind@line:col`, the top level of each block in order
def private places_of(text : string; source : bool = false) : string {
    var p : CParser
    if (source) {
        var mem = new PpMemoryProvider()
        mem->add("main.c", text)
        c_parser_open_source(p, mem, "main.c", array<string>(), array<string>())
    } else {
        c_parser_open_text(p, text, "t.c")
    }
    let u = c_unit(p)
    return "parse error: {p.err}" if (p.failed)
    var r = new CIr
    c_ir_open(*r, target_lp64_linux(), "")
    var out : array<string>
    if (c_ir_unit(*r, p, u)) {
        out |> reserve(length(r.tu.decls))
        for (d in r.tu.decls) {
            out |> push("{d.name}@{d.loc.file}:{d.loc.line}:{d.loc.col}")
            if (d.body != null) {
                out |> reserve(length(out) + length(d.body.body))
                for (st in d.body.body) {
                    out |> push("{st.s}@{st.loc.line}:{st.loc.col}")
                }
            }
        }
    } else {
        out |> push("error: {r.err}")
    }
    delete_tu(r.tu)
    unsafe {
        delete r
    }
    return join(out, " ")
}

[test(description = "places from the builder's own tokens: the file and line a line marker gives, the column the token stands at in the text; a declaration at its name, a statement at its first token, a GNU statement block used as a statement at its expression statement's, a hoisted static's and a block extern's null at its name")]
def test_places(t : T?) {
    t |> equal(places_of("# 7 \"s.c\"\nint  g;\nint f(int x) \{\n  x = 1;\n   (\{ x; \});\n\}\n"),
               "g@s.c:7:6 f@s.c:8:5 expr@9:3 compound@10:4")
    t |> equal(places_of("int v;\nvoid f(void) \{\n  static int s;\n   extern int v;\n\}\n"), "v@t.c:1:5 f_s@t.c:3:14 f@t.c:2:6 null@3:14 null@4:15")
}

[test(description = "places from C source read with macro expansion: a node an expansion made at the outermost macro name, line and column, as clang's expansion location puts it, and every place in the file as read, `#line` aside, as Dumper A gives it")]
def test_source_places(t : T?) {
    t |> equal(places_of("#define SET(v) x = v\n#define DECL(n) int n;\nint g;\n  DECL(h)\nint f(int x) \{\n  SET(\n1);\n#line 50 \"q.c\"\n  x = 2;\n\}\n", true),
               "g@main.c:3:5 h@main.c:4:3 f@main.c:5:5 expr@6:3 expr@9:3")
}

[test(description = "a macro expansion's parentheses are marked only around a shift or a bitwise operator, as Dumper A marks them; the source's own all")]
def test_macro_parens(t : T?) {
    t |> equal(source_ir_of("#define SQ(x) ((x) * (x))\n#define OR(a, b) ((a) | (b))\nint f(int a) \{ return SQ(a) + OR(a, 1) + (a); \}", true),
               "return add<int>(add<int>(mul<int>(LValueToRValue<int>(a), LValueToRValue<int>(a)), bor<int>(LValueToRValue<int>(a), 1<int>)()), LValueToRValue<int>(a())) ; TABLE int:32:true:int func:0:0:false")
}

[test(description = "the table order: a declaration's type, then its initializer's node types before their operands', a body's expressions where they stand")]
def test_table_order(t : T?) {
    var p : CParser
    c_parser_open_text(p, "char c = 1; void g(void) \{ (short)c; \}", "t.c")
    let u = c_unit(p)
    var r = new CIr
    c_ir_open(*r, target_lp64_linux(), "")
    t |> success(c_ir_unit(*r, p, u))
    t |> equal(join([for (ty in r.tu.types); c_type_key(ty)], " "), "int:8:false:char int:32:true:int void func:2::false int:16:true:short")
    delete_tu(r.tu)
    unsafe {
        delete r
    }
}

[test(description = "every construct not typed yet is refused at its place")]
def test_refusals(t : T?) {
    t |> equal(ir_of("void g(void) \{ y; \}"), "error: t.c:1:16: the identifier 'y', which names no variable or function the builder knows, is not typed yet")
    t |> equal(ir_of("void g(void) \{ __builtin_expect; \}"), "error: t.c:1:16: the builtin '__builtin_expect' other than as a callee is not typed yet")
    t |> equal(ir_of("long __builtin_expect(long, long); void g(void) \{ __builtin_expect; \}"), "error: t.c:1:51: the builtin '__builtin_expect' other than as a callee is not typed yet")
    t |> equal(ir_of("void g(int x) \{ x ?: 1; \}"), "error: t.c:1:17: GNU's ?: with no middle operand is not typed yet")
    t |> equal(ir_of("void g(int *p) \{ p * 2; \}"), "error: t.c:1:18: this operator on operands of these types is invalid C, which clang rejects")
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
    t |> equal(ir_of("int n = \{1, 2\};"), "error: t.c:1:9: a braced scalar initializer of other than one value is not typed yet")
    t |> equal(ir_of("void g(void) \{ __func__; \}"), "expr ArrayToPointerDecay<char*>(str<char[2]>)")
    t |> equal(ir_of("void g(void) \{ asm(\"nop\"); \}"), "error: t.c:1:16: inline asm with template text is not typed yet, which is machine code")
}

[test(description = "names as Dumper A gives them: a file static's <stem>__<name>, a digit stem led by _, a later declaration without static keeping it; a hoisted static's <fn>_<name>, numbered past a file-scope name, a local and an earlier hoisted static; a parameter and a local renamed past a block-scope extern or prototype of their name; every reference bound to its declaration's name")]
def test_names(t : T?) {
    t |> run("file statics") @(t : T?) {
        t |> equal(ir_of("static int n; extern int n; static int f(void); int f(void) \{ return n; \}", false, "dir/9lives.c", true),
                   "_9lives__n ; _9lives__f() ; _9lives__f() ; return LValueToRValue<int>(_9lives__n)")
    }
    t |> run("hoisted statics") @(t : T?) {
        t |> equal(ir_of("int g_a; int g(int g_b) \{ static int a = 1; static int b; \{ static int a; \} int g_c; static int c; return a + b; \}", false, "t.c", true),
                   "g_a ; g_a1=1<int> ; g_b1 ; g_a2 ; g_c1 ; g(g_b) ; null - - ; null - - ; null - - ; g_c:int=- ; null - - ; return add<int>(LValueToRValue<int>(g_a1), LValueToRValue<int>(g_b1))")
    }
    t |> run("locals and parameters past a block-scope extern or prototype") @(t : T?) {
        t |> equal(ir_of("int x; int y(void); int f(int x) \{ int y = x; \{ extern int x; int y(void); return x + y(); \} \}", false, "t.c", true),
                   "x ; y() ; f(x1) ; y1:int=LValueToRValue<int>(x1) ; null - - ; return add<int>(LValueToRValue<int>(x), call<int>(FunctionToPointerDecay<func*>(y); ))")
    }
}
[test(description = "a block declaration of a function declared before rebinds its prototype for the calls in its scope, adding no declaration")]
def test_block_prototype(t : T?) {
    t |> equal(ir_of("int f(); void g(void) \{ int f(double); f(1); \} void h(void) \{ f(1); \}"),
               "expr call<int>(FunctionToPointerDecay<func*>(f); IntegralToFloating<double>(1<int>)) ; expr call<int>(FunctionToPointerDecay<func*>(f); 1<int>)")
}

[test(description = "a wide character constant's numeric escape keeps its whole value; one past its type's range is refused")]
def test_wide_escapes(t : T?) {
    t |> equal(ir_of("void g(void) \{ L'\\x100'; u'\\400'; U'\\x10000'; \}"), "expr '256'<int> ; expr '256'<unsigned short> ; expr '65536'<unsigned int>")
    t |> equal(ir_of("void g(void) \{ u'\\x10000'; \}"), "error: t.c:1:16: the character constant u'\\x10000' is not typed yet")
}

[test(description = "?: of pointers to compatible types has their composite type, the other arm cast to it; one to a function of no parameter is refused")]
def test_conditional_composite(t : T?) {
    t |> equal(ir_of("void g(int c, int (*p)[3], int (*q)[]) \{ c ? p : q; c ? q : p; \}"), "expr cond<int[3]*>(LValueToRValue<int>(c), LValueToRValue<int[3]*>(p), BitCast<int[3]*>(LValueToRValue<int[-1]*>(q))) ; expr cond<int[3]*>(LValueToRValue<int>(c), BitCast<int[3]*>(LValueToRValue<int[-1]*>(q)), LValueToRValue<int[3]*>(p))")
    t |> equal(ir_of("void h(int c, int (*f)(), int (*k)(double)) \{ c ? f : k; \}"), "error: t.c:1:47: a conditional of function pointers one of which takes no parameter is not typed yet (whether it has a prototype is not in its type)")
}

[test(description = "invalid C clang rejects is refused at its place, never built: an assignment or initializer of incompatible types, operands of the wrong kind, a call's argument count against its prototype, a false _Static_assert")]
def test_invalid_c(t : T?) {
    t |> equal(ir_of("void g(void) \{ int *p = 1.5; \}"), "error: t.c:1:25: a value of this type in a slot of that type is invalid C, which clang rejects")
    t |> equal(ir_of("int x = (void)0;"), "error: t.c:1:9: a value of this type in a slot of that type is invalid C, which clang rejects")
    t |> equal(ir_of("int *p = 1;"), "error: t.c:1:10: a value of this type in a slot of that type is invalid C, which clang rejects")
    t |> equal(ir_of("int *q = (int)4294967296.0;"), "error: t.c:1:10: a value of this type in a slot of that type is invalid C, which clang rejects")
    t |> equal(ir_of("int *q = (int)0.0;"), "q=NullToPointer<int*>(FloatingToIntegral!<int>(0x0p+0<double>))")
    t |> equal(ir_of("void g(int x) \{ return x; \}"), "error: t.c:1:17: a value returned from a void function is invalid C, which clang rejects")
    t |> equal(ir_of("int f(void) \{ return; \}"), "error: t.c:1:15: a return with no value from a function that returns one is invalid C, which clang rejects")
    t |> equal(ir_of("void f(void); void g(void) \{ return f(); \}"), "return call<void>(FunctionToPointerDecay<func*>(f); )")
    t |> equal(ir_of("void g(int x) \{ switch (x) \{ case 1: case 1: ; \} \}"), "error: t.c:1:38: a duplicate case value is invalid C, which clang rejects")
    t |> equal(ir_of("void g(int x) \{ switch (x) \{ case 1: switch (x) \{ case 1: ; \} \} \}"), "switch LValueToRValue<int>(x) - ; case 1 ; switch LValueToRValue<int>(x) - ; case 1 ; null - -")
    t |> equal(ir_of("void f(long *); void g(void) \{ unsigned long b; f(&b); \}"), "b:unsigned long=- ; expr call<void>(FunctionToPointerDecay<func*>(f); BitCast<long*>(addr<unsigned long*>(b)))")
    t |> equal(ir_of("unsigned **pp; int **q = pp;"), "error: t.c:1:26: a value of this type in a slot of that type is invalid C, which clang rejects")
    t |> equal(ir_of("char *c; int *q = c;"), "error: t.c:1:19: a value of this type in a slot of that type is invalid C, which clang rejects")
    t |> equal(ir_of("void g(int *q) \{ long l; l = q; \}"), "error: t.c:1:26: a value of this type in a slot of that type is invalid C, which clang rejects")
    t |> equal(ir_of("int *h(void) \{ return 1; \}"), "error: t.c:1:23: a value of this type in a slot of that type is invalid C, which clang rejects")
    t |> equal(ir_of("void k(int *); void g(void) \{ k(2); \}"), "error: t.c:1:33: a value of this type in a slot of that type is invalid C, which clang rejects")
    t |> equal(ir_of("int x = 1.0 << 1;"), "error: t.c:1:9: this operator on operands of these types is invalid C, which clang rejects")
    t |> equal(ir_of("void g(int *p) \{ p + p; \}"), "error: t.c:1:18: this operator on operands of these types is invalid C, which clang rejects")
    t |> equal(ir_of("void g(double d) \{ d % 2; \}"), "error: t.c:1:20: this operator on operands of these types is invalid C, which clang rejects")
    t |> equal(ir_of("void g(int *p, long *q) \{ p - q; \}"), "error: t.c:1:27: a difference of pointers to incompatible types is invalid C, which clang rejects")
    t |> equal(ir_of("void f(void); void g(void) \{ f(1); \}"), "error: t.c:1:30: a call with 1 arguments of a function whose prototype has 0 is invalid C, which clang rejects")
    t |> equal(ir_of("void f(double); void g(void) \{ f(); \}"), "error: t.c:1:32: a call with 0 arguments of a function whose prototype has 1 is invalid C, which clang rejects")
    t |> equal(ir_of("void g(int (*fp)(double)) \{ fp(); \}"), "error: t.c:1:29: a call with 0 arguments of a function whose prototype has 1 is invalid C, which clang rejects")
    t |> equal(ir_of("void g(int (*fp)(double)) \{ fp(1, 2); \}"), "error: t.c:1:29: a call with 2 arguments of a function whose prototype has 1 is invalid C, which clang rejects")
    t |> equal(ir_of("int pr(const char *, ...); void g(void) \{ pr(); \}"), "error: t.c:1:43: a call with 0 arguments of a function whose prototype has 1 is invalid C, which clang rejects")
    t |> equal(ir_of("int h(); void g(void) \{ h(1, 2); \}"), "expr call<int>(FunctionToPointerDecay<func*>(h); 1<int>, 2<int>)")
    t |> equal(ir_of("void g(void) \{ _Static_assert(0, \"bad\"); \}"), "error: t.c:1:16: a _Static_assert whose condition is 0 is invalid C, which clang rejects")
    t |> equal(ir_of("_Static_assert(1 + 1 == 3, \"bad\");"), "error: t.c:1:1: a _Static_assert whose condition is 0 is invalid C, which clang rejects")
    t |> equal(ir_of("_Static_assert(sizeof(int) == 4, \"ok\"); int x = 1;"), "x=1<int>")
    t |> equal(ir_of("int y; _Static_assert(y, \"v\");"), "error: t.c:1:8: a _Static_assert whose condition the builder cannot fold is not typed yet")
}

[test(description = "a floating constant cast at once to an integer type is an integer constant: (int)0.0 is a null pointer constant")]
def test_float_cast_null(t : T?) {
    t |> equal(ir_of("int *p = (int)0.0; int *q = (int)0.5;"), "p=NullToPointer<int*>(FloatingToIntegral!<int>(0x0p+0<double>)) ; q=NullToPointer<int*>(FloatingToIntegral!<int>(0x1p-1<double>))")
    t |> equal(ir_of("int *n = (int)1.0;"), "error: t.c:1:10: a value of this type in a slot of that type is invalid C, which clang rejects")
}

[test(description = "a long double literal: under linux through x87's 64-bit value and clang's 21-digit text, under msvc a double")]
def test_long_double_literal(t : T?) {
    t |> equal(ir_of("long double x = 0x1.00000000000008001p0L;"), "x=0x1p+0<long double>")
    t |> equal(ir_of("long double x = 0x1.00000000000008001p0L;", true), "x=0x1.0000000000001p+0<long double>")
}


[test(description = "qualifiers below a pointer: a function type's parameters and result keep theirs, so such function pointers are incompatible; a data pointer's nested ones only warn (NoOp); ?: of pointers takes both pointees' qualifiers, or void * for incompatible ones, arrays of differently qualified elements among them")]
def test_pointer_qualifiers(t : T?) {
    t |> run("assignment and initialization") @(t : T?) {
        t |> equal(ir_of("void g(char **pp) \{ const char **q = pp; char *const *r = pp; \}"), "q:char**=NoOp<char**>(LValueToRValue<char**>(pp)) ; r:char**=NoOp<char**>(LValueToRValue<char**>(pp))")
        t |> equal(ir_of("void g(int (**p)[3], const int (**q)[3], int (*f)(const int), int (*h)(int)) \{ p = q; f = h; \}"), "expr assign<int[3]**>(p, NoOp<int[3]**>(LValueToRValue<int[3]**>(q))) ; expr assign<func*>(f, LValueToRValue<func*>(h))")
        t |> equal(ir_of("void g(int (*f)(const int *), int (*h)(int *)) \{ f = h; \}"), "error: t.c:1:50: a value of this type in a slot of that type is invalid C, which clang rejects")
        t |> equal(ir_of("void g(const int (*f)(void), int (*h)(void)) \{ f = h; \}"), "error: t.c:1:48: a value of this type in a slot of that type is invalid C, which clang rejects")
        t |> equal(ir_of("void g(int (*f)(int *const *), int (*h)(int **)) \{ f = h; \}"), "error: t.c:1:52: a value of this type in a slot of that type is invalid C, which clang rejects")
        t |> equal(ir_of("void g(int (**f)(int *), int (**h)(const int *)) \{ f = h; \}"), "error: t.c:1:52: a value of this type in a slot of that type is invalid C, which clang rejects")
        t |> equal(ir_of("void g(long *l) \{ long long *q = l; \}"), "error: t.c:1:34: a value of this type in a slot of that type is invalid C, which clang rejects")
    }
    t |> run("explicit casts and a pointer difference") @(t : T?) {
        t |> equal(ir_of("void g(int (*h)(int *), int (*k)(void), char **pp) \{ (int (*)(const int *))h; (const int (*)(void))k; (const char **)pp; \}"), "expr BitCast!<func*>(LValueToRValue<func*>(h)) ; expr BitCast!<func*>(LValueToRValue<func*>(k)) ; expr NoOp!<char**>(LValueToRValue<char**>(pp))")
        t |> equal(ir_of("void g(int (*p)[3], const int (*q)[3]) \{ p - q; \}"), "expr sub<long>(LValueToRValue<int[3]*>(p), LValueToRValue<int[3]*>(q))")
        t |> equal(ir_of("void g(char **p, const char **q) \{ p - q; \}"), "error: t.c:1:36: a difference of pointers to incompatible types is invalid C, which clang rejects")
    }
    t |> run("?: of pointers") @(t : T?) {
        t |> equal(ir_of("void g(int c, int (*p)[3], const int (*q)[3], int (*u)[], char **s, const char **cs) \{ c ? p : q; c ? q : u; c ? s : cs; \}"),
                   "expr cond<void*>(LValueToRValue<int>(c), BitCast<void*>(LValueToRValue<int[3]*>(p)), BitCast<void*>(LValueToRValue<int[3]*>(q))) ; expr cond<void*>(LValueToRValue<int>(c), BitCast<void*>(LValueToRValue<int[3]*>(q)), BitCast<void*>(LValueToRValue<int[-1]*>(u))) ; expr cond<void*>(LValueToRValue<int>(c), BitCast<void*>(LValueToRValue<char**>(s)), BitCast<void*>(LValueToRValue<char**>(cs)))")
        t |> equal(ir_of("void g(int c, int *p, const int *q, volatile int *v, char **s, char *const *cs) \{ c ? p : q; c ? v : q; c ? s : cs; \}"),
                   "expr cond<int*>(LValueToRValue<int>(c), BitCast<int*>(LValueToRValue<int*>(p)), LValueToRValue<int*>(q)) ; expr cond<int*>(LValueToRValue<int>(c), BitCast<int*>(LValueToRValue<int*>(v)), BitCast<int*>(LValueToRValue<int*>(q))) ; expr cond<char**>(LValueToRValue<int>(c), BitCast<char**>(LValueToRValue<char**>(s)), LValueToRValue<char**>(cs))")
        t |> equal(ir_of("void g(int c, void *v, const int *q, void *const *w) \{ c ? v : q; c ? v : w; \}"),
                   "expr cond<void*>(LValueToRValue<int>(c), NoOp<void*>(LValueToRValue<void*>(v)), BitCast<void*>(LValueToRValue<int*>(q))) ; expr cond<void*>(LValueToRValue<int>(c), NoOp<void*>(LValueToRValue<void*>(v)), BitCast<void*>(LValueToRValue<void**>(w)))")
        t |> equal(ir_of("void g(int c, int (*const **p)[3], int (*const **q)[]) \{ c ? p : q; \}"),
                   "expr cond<int[3]***>(LValueToRValue<int>(c), LValueToRValue<int[3]***>(p), BitCast<int[3]***>(LValueToRValue<int[-1]***>(q)))")
    }
}

[test(description = "integer constant expressions: a cast wraps to its width and sign-extends, _Bool folds to 0 or 1, each unary, binary, logical and conditional operator folds in its operands' signedness, a division by zero does not fold")]
def test_constant_folding(t : T?) {
    t |> equal(ir_of("int *p = (char)256;"), "p=NullToPointer<int*>(IntegralCast!<char>(256<int>))")
    t |> equal(ir_of("int *p = (_Bool)256;"), "error: t.c:1:10: a value of this type in a slot of that type is invalid C, which clang rejects")
    t |> equal(ir_of("_Static_assert(1 / 0, \"z\");"), "error: t.c:1:1: a _Static_assert whose condition the builder cannot fold is not typed yet")
    t |> equal(ir_of("void g(int x) \{ switch (x) \{ case (signed char)-1: case -1 + 10: case ~1: case !0: case +3: case 1 ? 4 : 5: case 0 ? 4 : 6: ; \} \}"),
               "switch LValueToRValue<int>(x) - ; case -1 ; case 9 ; case -2 ; case 1 ; case 3 ; case 4 ; case 6 ; null - -")
    t |> equal(ir_of("void g(int x) \{ switch (x) \{ case 2 + 3: case 7 - 3: case 3 * 4: case -7 / 2: case -7 % 2: case 4294967295u / 2u: case 4294967295u % 7u: case 1 << 3: case -16 >> 2: case 4294967295u >> 28: ; \} \}"),
               "switch LValueToRValue<int>(x) - ; case 5 ; case 4 ; case 12 ; case -3 ; case -1 ; case 2147483647 ; case 3 ; case 8 ; case -4 ; case 15 ; null - -")
    t |> equal(ir_of("_Static_assert((0xffffffffffffffffu >> 60) == 15 && 0xffffffffffffffffu / 0x2000000000000000u == 7 && 0xffffffffffffffffu % 10u == 5 && (-1l < 0ul) == 0, \"u\");"), "")
    t |> equal(ir_of("_Static_assert((0xffffffffffffffffu >> 60) == 16, \"u\");"), "error: t.c:1:1: a _Static_assert whose condition is 0 is invalid C, which clang rejects")
    t |> equal(ir_of("void g(int x) \{ switch (x) \{ case 6 & 3: case 6 | 3: case 6 ^ 3 + 10: case 0 || 1: case 0 && 1: ; \} \}"),
               "switch LValueToRValue<int>(x) - ; case 2 ; case 7 ; case 11 ; case 1 ; case 0 ; null - -")
    t |> equal(ir_of("void g(int x) \{ switch (x) \{ case (-1 < 0u) + 20: case (1 < 2) + 30: case (2 > 1) + 40: case (2 <= 1) + 50: case (2 >= 1) + 60: case (1 != 1) + 70: case (1 == 1) + 80: ; \} \}"),
               "switch LValueToRValue<int>(x) - ; case 20 ; case 31 ; case 41 ; case 50 ; case 61 ; case 70 ; case 81 ; null - -")
}

[test(description = "the usual arithmetic conversions by rank, sign and floating width; a shift and a compound shift promote each operand alone; a comma has its right operand's type")]
def test_conversion_ranks(t : T?) {
    t |> equal(ir_of("void g(long l, long long ll, unsigned long ul, int i, double d, long double ld) \{ l + ll; ul + i; d + ld; \}"),
               "expr add<long long>(IntegralCast<long long>(LValueToRValue<long>(l)), LValueToRValue<long long>(ll)) ; expr add<unsigned long>(LValueToRValue<unsigned long>(ul), IntegralCast<unsigned long>(LValueToRValue<int>(i))) ; expr add<long double>(FloatingCast<long double>(LValueToRValue<double>(d)), LValueToRValue<long double>(ld))")
    t |> equal(ir_of("void g(long l, int i, char c, int x) \{ l << i; l <<= c; x, c; \}"),
               "expr shl<long>(LValueToRValue<long>(l), LValueToRValue<int>(i)) ; expr assignshl<long>(l, IntegralCast<int>(LValueToRValue<char>(c))) ; expr comma<char>(LValueToRValue<int>(x), LValueToRValue<char>(c))")
}

[test(description = "pointer operands: an integer compared with a pointer either side, a null pointer constant on the left converted to the right's type, an array operand, integer + pointer with the integer promoted, msvc's ptrdiff_t")]
def test_pointer_operands(t : T?) {
    t |> equal(ir_of("void g(int *p, char c) \{ p == 1; 1 == p; (void *)0 == p; 1 + p; c + p; \}"),
               "expr eq<int>(LValueToRValue<int*>(p), IntegralToPointer<int*>(1<int>)) ; expr eq<int>(IntegralToPointer<int*>(1<int>), LValueToRValue<int*>(p)) ; expr eq<int>(BitCast<int*>(NullToPointer!<void*>(0<int>)), LValueToRValue<int*>(p)) ; expr add<int*>(1<int>, LValueToRValue<int*>(p)) ; expr add<int*>(IntegralCast<int>(LValueToRValue<char>(c)), LValueToRValue<int*>(p))")
    t |> equal(ir_of("void g(void) \{ int b[2]; b + 1; \}"), "b:int[2]=- ; expr add<int*>(ArrayToPointerDecay<int*>(b), 1<int>)")
    t |> equal(ir_of("void g(int *p) \{ p - p; \}", true), "expr sub<long long>(LValueToRValue<int*>(p), LValueToRValue<int*>(p))")
}

[test(description = "operands and slots of types clang rejects: integer - pointer, && of void, a pointer compared with or added to a floating value, * of void; pointers to incompatible types, integer types of other ranks, function results, parameter lists and variadics; pointers to integer types of one rank and the other sign assign")]
def test_incompatible_types(t : T?) {
    let rejected = "this operator on operands of these types is invalid C, which clang rejects"
    t |> equal(ir_of("void g(int *p) \{ 1 - p; \}"), "error: t.c:1:18: {rejected}")
    t |> equal(ir_of("void g(int c) \{ c && (void)0; \}"), "error: t.c:1:17: {rejected}")
    t |> equal(ir_of("void g(int *p) \{ p < 1.0; \}"), "error: t.c:1:18: {rejected}")
    t |> equal(ir_of("void g(int *p) \{ p + 1.0; \}"), "error: t.c:1:18: {rejected}")
    t |> equal(ir_of("void g(int x) \{ x * (void)0; \}"), "error: t.c:1:17: {rejected}")
    let slot = "a value of this type in a slot of that type is invalid C, which clang rejects"
    t |> equal(ir_of("void g(int **pp) \{ int *p = pp; \}"), "error: t.c:1:29: {slot}")
    t |> equal(ir_of("void g(double *d) \{ long *l = d; \}"), "error: t.c:1:31: {slot}")
    t |> equal(ir_of("void g(int c, int (*p)[3], int (*q)[4]) \{ p = q; \}"), "error: t.c:1:43: {slot}")
    t |> equal(ir_of("void g(long (*f)(void), int (*h)(void)) \{ f = h; \}"), "error: t.c:1:43: {slot}")
    t |> equal(ir_of("void g(int (*f)(int, ...), int (*h)(int)) \{ f = h; \}"), "error: t.c:1:45: {slot}")
    t |> equal(ir_of("void g(int (*f)(int, int), int (*h)(int)) \{ f = h; \}"), "error: t.c:1:45: {slot}")
    t |> equal(ir_of("void g(int (*f)(int), int (*h)(long)) \{ f = h; \}"), "error: t.c:1:41: {slot}")
    t |> equal(ir_of("void g(short *s) \{ char *c = s; \}"), "error: t.c:1:30: {slot}")
    t |> equal(ir_of("void g(_Bool *b) \{ unsigned char *c = b; \}"), "error: t.c:1:39: {slot}")
    t |> equal(ir_of("void g(unsigned short *u) \{ short *s = u; \}"), "s:short*=BitCast<short*>(LValueToRValue<unsigned short*>(u))")
}

[test(description = "compatible function pointers: one with no parameter takes a prototype by BitCast, ?: of them takes the prototype; arrays of different counts are incompatible under ?:")]
def test_function_composites(t : T?) {
    t |> equal(ir_of("void g(int (*f)(), int (*h)(double)) \{ f = h; \}"), "expr assign<func*>(f, BitCast<func*>(LValueToRValue<func*>(h)))")
    t |> equal(ir_of("void g(int c, int (**f)(), int (**h)(double)) \{ c ? f : h; \}"),
               "expr cond<func**>(LValueToRValue<int>(c), BitCast<func**>(LValueToRValue<func**>(f)), LValueToRValue<func**>(h))")
    t |> equal(ir_of("void g(int c, int (*p)[3], int (*q)[4]) \{ c ? p : q; \}"),
               "expr cond<void*>(LValueToRValue<int>(c), BitCast<void*>(LValueToRValue<int[3]*>(p)), BitCast<void*>(LValueToRValue<int[4]*>(q)))")
}

[test(description = "literals: integer suffixes ll and ull, u past 32 bits, msvc's decimal l, octal; octal and other escapes, universal character names and adjacent strings; wide constants' escapes and UTF-8 characters; the refusals of a prefixed string and of wide constants past their range")]
def test_literal_forms(t : T?) {
    t |> equal(ir_of("void g(void) \{ 10ll; 0xffffffffffffffffll; 10ull; 4294967296u; 010; \}"),
               "expr 10<long long> ; expr 18446744073709551615<unsigned long long> ; expr 10<unsigned long long> ; expr 4294967296<unsigned long> ; expr 8<int>")
    t |> equal(ir_of("void g(void) \{ 4294967296u; 2147483648l; \}", true), "expr 4294967296<unsigned long long> ; expr 2147483648<long long>")
    t |> equal(ir_of("void g(void) \{ sizeof \"\\1234\"; '\\101'; sizeof \"é\"; sizeof \"\\u0800\"; sizeof \"\\U0001F600\"; '\\''; '\\\\'; sizeof(\"a\" \"b\"); \}"),
               "expr sizeof<unsigned long>=3:char[3] ; expr '65'<int> ; expr sizeof<unsigned long>=3:char[3] ; expr sizeof<unsigned long>=4:char[4] ; expr sizeof<unsigned long>=5:char[5] ; expr '39'<int> ; expr '92'<int> ; expr sizeof<unsigned long>=3:char[3]")
    t |> equal(ir_of("void g(void) \{ L'\\n'; L'\\u00e9'; L'\\''; L'é'; \}"), "expr '10'<int> ; expr '233'<int> ; expr '39'<int> ; expr '233'<int>")
    t |> equal(ir_of("void g(void) \{ L\"x\"; \}"), "error: t.c:1:16: a prefixed string literal is not typed yet")
    t |> equal(ir_of("void g(void) \{ L'\\1234'; \}"), "error: t.c:1:16: the character constant L'\\1234' is not typed yet")
    t |> equal(ir_of("void g(void) \{ U'\\x10000000000000000'; \}"), "error: t.c:1:16: the character constant U'\\x10000000000000000' is not typed yet")
    t |> equal(ir_of("void g(void) \{ L'\\x80000000'; \}"), "error: t.c:1:16: the character constant L'\\x80000000' is not typed yet")
}

[test(description = "unary operators, a dereference read, i[a], __extension__, a function's sizeof, a call through a dereferenced function pointer with and without a prototype, ?: of void arms, a null constant on the left, one pointer type and a qualified void *; a scope's binding ends with it; casts clang refuses")]
def test_operator_forms(t : T?) {
    t |> equal(ir_of("void g(int x, int *p) \{ ++x; --x; +x; ~x; *p; __extension__ x; \}"),
               "expr preinc<int>(x) ; expr predec<int>(x) ; expr plus<int>(LValueToRValue<int>(x)) ; expr bnot<int>(LValueToRValue<int>(x)) ; expr LValueToRValue<int>(deref<int>(LValueToRValue<int*>(p))) ; expr LValueToRValue<int>(x)")
    t |> equal(ir_of("void f(void); void g(void) \{ int a[2]; 1[a]; sizeof f; \}"), "a:int[2]=- ; expr LValueToRValue<int>(index<int>(1<int>, ArrayToPointerDecay<int*>(a))) ; expr sizeof<unsigned long>=8:func")
    t |> equal(ir_of("void g(int (*h)()) \{ (*h)(1); \}"), "expr call<int>(FunctionToPointerDecay<func*>(deref<func>(LValueToRValue<func*>(h))); 1<int>)")
    t |> equal(ir_of("void g(void (*f)(double)) \{ (*f)(); \}"), "error: t.c:1:29: a call with 0 arguments of a function whose prototype has 1 is invalid C, which clang rejects")
    t |> equal(ir_of("void g(int c, int *p, const void *cv) \{ c ? (void)0 : (void)0; c ? 0 : p; c ? p : p; c ? cv : p; c ? p : cv; \}"),
               "expr cond<void>(LValueToRValue<int>(c), ToVoid!<void>(0<int>), ToVoid!<void>(0<int>)) ; expr cond<int*>(LValueToRValue<int>(c), NullToPointer<int*>(0<int>), LValueToRValue<int*>(p)) ; expr cond<int*>(LValueToRValue<int>(c), LValueToRValue<int*>(p), LValueToRValue<int*>(p)) ; expr cond<void*>(LValueToRValue<int>(c), LValueToRValue<void*>(cv), BitCast<void*>(LValueToRValue<int*>(p))) ; expr cond<void*>(LValueToRValue<int>(c), BitCast<void*>(LValueToRValue<int*>(p)), LValueToRValue<void*>(cv))")
    t |> equal(ir_of("int *p = (const void *)0; int (*q)[2]; const int (*cq)[2]; void h(void) \{ cq = q; \}"),
               "p=BitCast<int*>(NullToPointer!<void*>(0<int>)) ; expr assign<int[2]*>(cq, NoOp<int[2]*>(LValueToRValue<int[2]*>(q)))")
    t |> equal(ir_of("void g(void) \{ \{ int y; \} y; \}"), "error: t.c:1:27: the identifier 'y', which names no variable or function the builder knows, is not typed yet")
    t |> equal(ir_of("void g(int *p) \{ (double)p; \}"), "error: t.c:1:18: this cast is not typed yet")
    t |> equal(ir_of("void g(void) \{ (int)(void)0; \}"), "error: t.c:1:16: this cast is not typed yet")
}

[test(description = "the marks and the table: vol on a volatile dereference and subscript, paren on a parenthesized operand; a conditional's and a subscript's types enter the table before their operands', a builtin's entry unnamed")]
def test_marks_and_order(t : T?) {
    t |> equal(ir_of("void g(volatile int *vp) \{ *vp; \}", full = true), "expr LValueToRValue<int>(deref<int>(LValueToRValue<int*>(vp))^) ; TABLE void int:32:true:int ptr:1 func:0:2:false")
    t |> equal(ir_of("volatile int a[2]; void g(void) \{ a[0]; \}", full = true),
               "G a:int[2]=- ; expr LValueToRValue<int>(index<int>(ArrayToPointerDecay<int*>(a~), 0<int>)^) ; TABLE int:32:true:int array:0:2 void func:2::false ptr:0")
    t |> equal(ir_of("void g(int x) \{ (x); \}", full = true), "expr LValueToRValue<int>(x()) ; TABLE void int:32:true:int func:0:1:false")
    t |> equal(ir_of("int g(void) \{ return (short)1 ? (char)2 : 3; \}", full = true),
               "return cond<int>(IntegralCast<int>(IntegralCast!<short>(1<int>)), IntegralCast<int>(IntegralCast!<char>(2<int>)), 3<int>) ; TABLE int:32:true:int func:0::false int:16:true:short int:8:false:char")
    t |> equal(ir_of("int a[2]; int g(void) \{ return a[(char)1]; \}", full = true),
               "G a:int[2]=- ; return LValueToRValue<int>(index<int>(ArrayToPointerDecay<int*>(a), IntegralCast!<char>(1<int>))) ; TABLE int:32:true:int array:0:2 func:0::false ptr:0 int:8:false:char")
    t |> equal(ir_of("void g(int x) \{ __builtin_expect(x, 0); \}", full = true),
               "expr call<long>(FunctionToPointerDecay<func*>(__builtin_expect); IntegralCast<long>(LValueToRValue<int>(x)), IntegralCast<long>(0<int>)) ; TABLE void int:32:true:int func:0:1:false int:64:true:long func:3:3,3:false ptr:4 func:0::true")
}

[test(description = "the walk: a designated braced scalar refused, a tentative definition taking a later initializer, a prototype kept by a later () declaration and declared through a typedef, a block extern's global, a file-scope extern definition, an empty label, continue, a for's expression initializer, statement expressions through parentheses, a cast and __extension__, a label under a branch")]
def test_walk_forms(t : T?) {
    let few = "a call with 0 arguments of a function whose prototype has 1 is invalid C, which clang rejects"
    t |> equal(ir_of("int n = \{[0] = 1\};"), "error: t.c:1:9: a braced scalar initializer of other than one value is not typed yet")
    t |> equal(ir_of("int x; int x = 1;"), "x=1<int>")
    t |> equal(ir_of("int f(double); int f(); void g(void) \{ f(); \}"), "error: t.c:1:40: {few}")
    t |> equal(ir_of("typedef int F(double); F f; void g(void) \{ f(); \}"), "error: t.c:1:44: {few}")
    t |> equal(ir_of("void g(void) \{ extern int e; \}", full = true), "G e:int extern=- ; null - - ; TABLE void func:0::false int:32:true:int")
    t |> equal(ir_of("int e; void g(void) \{ extern int e; \}", full = true), "G e:int=- ; null - - ; TABLE int:32:true:int void func:1::false")
    t |> equal(ir_of("extern int x = 1;", full = true), "G x:int=1<int> ; TABLE int:32:true:int")
    t |> equal(ir_of("void g(int x) \{ l: \} void h(int x) \{ while (x) continue; for (x = 0; x < 2; x++) ; \}"),
               "label l ; null - - ; while LValueToRValue<int>(x) - ; continue - - ; for lt<int>(LValueToRValue<int>(x), 2<int>) postinc<int>(x) ; expr assign<int>(x, 0<int>) ; null - -")
    t |> equal(ir_of("void g(int x) \{ ((\{ x; \})); (void)(\{ x; \}); __extension__ (\{ x; \}); if (x) l: x = 1; \}"),
               "expr LValueToRValue<int>(x) ; expr LValueToRValue<int>(x) ; expr LValueToRValue<int>(x) ; if LValueToRValue<int>(x) - ; label l ; expr assign<int>(x, 1<int>)")
}

[test(description = "the own headers' declarations: a library function, variable and definition bound for the unit; a name a later header declaration leaves untyped unbound")]
def test_library_bindings(t : T?) {
    t |> equal(ir_of("# 1 \"/lib/h.h\" 1\nint puts(const char *);\nextern int lib_v;\n# 2 \"t.c\" 2\nint f(void) \{ puts(\"x\"); return lib_v; \}\n", library = "/lib/"),
               "expr call<int>(FunctionToPointerDecay<func*>(puts); NoOp<char*>(ArrayToPointerDecay<char*>(str<char[2]>))) ; return LValueToRValue<int>(lib_v)")
    t |> equal(ir_of("# 1 \"/lib/h.h\" 1\nint lib_f(int);\nint lib_f(int) __attribute__((mode(DI)));\n# 2 \"t.c\" 2\nint f(void) \{ return lib_f(1); \}\n", library = "/lib/"),
               "error: t.c:2:22: the identifier 'lib_f', which names no variable or function the builder knows, is not typed yet")
    t |> equal(ir_of("# 1 \"/lib/h.h\" 1\nstatic int lib_def(int a) \{ return a; \}\n# 2 \"t.c\" 2\nint f(void) \{ return lib_def(2.5); \}\n", library = "/lib/"),
               "return call<int>(FunctionToPointerDecay<func*>(lib_def); FloatingToIntegral<int>(0x1.4p+1<double>))")
}

[test(description = "declared types seen through expressions: a const array decays to a const pointer, a function type takes no qualifier, restrict is not volatile, an array parameter's and a pointer declarator's qualifiers on the pointer")]
def test_declared_qualifiers(t : T?) {
    t |> equal(ir_of("const int a[2]; void g(void) \{ int *p = a; \}"), "p:int*=NoOp<int*>(ArrayToPointerDecay<int*>(a))")
    t |> equal(ir_of("typedef int F(void); volatile F f; void g(void) \{ f(); \}"), "expr call<int>(FunctionToPointerDecay<func*>(f); )")
    t |> equal(ir_of("void g(int *restrict p) \{ p; \}"), "expr LValueToRValue<int*>(p)")
    t |> equal(ir_of("void f(int a[volatile 2]) \{ a; \}"), "expr LValueToRValue<int*>(a~)")
    t |> equal(ir_of("int * volatile p; void g(void) \{ p; \}"), "expr LValueToRValue<int*>(p~)")
}
