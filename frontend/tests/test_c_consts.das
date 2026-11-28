options gen2
options stack = 262144
require dastest/testing_boost public
require strings
require daslib/strings_boost
require ../c_ir.das

//! `frontend/c_consts.das` with `c_fold` of `c_exprs.das`: the `offsetof` node, `_Alignof` and
//! `__alignof__`, `__builtin_types_compatible_p`, `__builtin_constant_p` with clang's answers, the
//! integer constant expressions' edges, the `case` value checked against Dumper A's fold, the
//! constant check of a static object's initializer, and every refusal with its place.

// a table entry as C spells it, short: a record its kind and name
def private spelled(types : array<CirType>; t : int) : string {
    return "?" if (t < 0)
    assume ty = types[t]
    if (ty.k == "int" || ty.k == "float") {
        return ty.spell
    } elif (ty.k == "ptr") {
        return "{spelled(types, ty.to)}*"
    } elif (ty.k == "array") {
        return "{spelled(types, ty.elem)}[{ty.count}]"
    } elif (ty.k == "struct" || ty.k == "union") {
        return "{ty.k} {ty.name}"
    }
    return ty.k
}

// expression `x` as one line: a constant node its value and operand type, a cast its kind, any
// other node its kind and operands
def private shown(types : array<CirType>; x : CirExpr?) : string {
    return "-" if (x == null)
    let t = spelled(types, x.t)
    if (x.e == "offsetof") {
        return "offsetof<{t}>({spelled(types, x.of_t)}, {x.field})" + (x.trait_v != 0ul ? "={int64(x.trait_v)}" : "")
    } elif (x.e == "alignof_v" || x.e == "sizeof_v") {
        return "{x.e}<{t}>={int64(x.trait_v)}:{spelled(types, x.of_t)}"
    } elif (x.e == "int_lit" || x.e == "float_lit") {
        return "{x.v}<{t}>"
    } elif (x.e == "cast") {
        return "{x.cast_kind}<{t}>({shown(types, x.a)})"
    } elif (x.e == "ref") {
        return x.name
    } elif (x.e == "init_list") {
        return "\{" + join([for (it in x.init_items); shown(types, it.v)], ", ") + "\}"
    }
    return "{x.e}{x.op}<{t}>({shown(types, x.a)}, {shown(types, x.b)})"
}

// the C-IR of unit `text` (named `t.c`) joined by ` ; `: each global's `name:type=value`, each
// function's returns, expression statements and case values; `error: ` and the builder's error
def private consts_of(text : string; msvc : bool = false) : string {
    var p : CParser
    c_parser_open_text(p, text, "t.c", msvc)
    let u = c_unit(p)
    return "parse error: {p.err}" if (p.failed)
    var r = new CIr
    c_ir_open(*r, msvc ? target_llp64_msvc() : target_lp64_linux(), "")
    var out : array<string>
    if (c_ir_unit(*r, p, u)) {
        for (d in r.tu.decls) {
            if (d.k == "global") {
                out |> push("{d.name}:{spelled(r.tu.types, d.t)}={shown(r.tu.types, d.init)}")
            } elif (d.k == "func" && d.body != null) {
                statements(r.tu.types, d.body, out)
            }
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

// the returns, expression statements and case values of `st` and under it into `out`
def private statements(types : array<CirType>; st : CirStmt?; var out : array<string>) {
    return if (st == null)
    if (st.s == "return" || st.s == "expr") {
        out |> push("{st.s} {shown(types, st.e)}")
    } elif (st.s == "case") {
        out |> push("case {st.v}")
    }
    for (kid in st.body) {
        statements(types, kid, out)
    }
    statements(types, st.body_s, out)
}

// `shown`'s left-leaning sum of `count` int literals `v`
def private sum_of(count : int; v : string) : string => repeat("binadd<int>(", count - 1) + "{v}<int>" + repeat(", {v}<int>)", count - 1)

let RECORD = "struct S \{ char c; int i; double d; int bits : 3; struct \{ int in; \}; \}; typedef struct \{ short s; long l; \} T; union U \{ char c; int i; \}; "

[test(description = "offsetof: Dumper A's node, the record (a typedef's resolved) and its direct field's index typed size_t, the byte offset the evaluator folds in an array size, under both dialects")]
def test_offsetof(t : T?) {
    t |> equal(consts_of(RECORD + "int a[__builtin_offsetof(struct S, d)]; unsigned long g = __builtin_offsetof(T, l); int f(void) \{ return __builtin_offsetof(union U, i); \}"),
               "a:int[8]=- ; g:unsigned long=offsetof<unsigned long>(struct T, 1) ; return IntegralCast<int>(offsetof<unsigned long>(union U, 1))")
    t |> equal(consts_of(RECORD + "char a[__builtin_offsetof(T, l) + 1]; unsigned long long g = __builtin_offsetof(struct S, i);", true),
               "a:char[5]=- ; g:unsigned long long=offsetof<unsigned long long>(struct S, 1)")
}

[test(description = "offsetof refused where Dumper A does not lower it - a member path, a member an anonymous member holds - and invalid C where clang rejects it: other than a complete record, no such member, a bit-field")]
def test_offsetof_refusals(t : T?) {
    t |> equal(consts_of(RECORD + "unsigned long g = __builtin_offsetof(struct S, d.x);"), "error: t.c:1:159: an offsetof of a member path (`a.b`, `a[i]`) is not typed yet, which Dumper A does not lower")
    t |> equal(consts_of(RECORD + "unsigned long g = __builtin_offsetof(struct S, in);"), "error: t.c:1:188: an offsetof of a member 'in' an anonymous member holds is not typed yet, which Dumper A does not lower")
    t |> equal(consts_of("unsigned long g = __builtin_offsetof(int, x);"), "error: t.c:1:19: an offsetof of other than a complete struct or union is invalid C, which clang rejects")
    t |> equal(consts_of("struct Z; unsigned long g = __builtin_offsetof(struct Z, x);"), "error: t.c:1:29: an offsetof of other than a complete struct or union is invalid C, which clang rejects")
    t |> equal(consts_of(RECORD + "unsigned long g = __builtin_offsetof(struct S, zz);"), "error: t.c:1:188: an offsetof of a member 'zz' its record does not have is invalid C, which clang rejects")
    t |> equal(consts_of(RECORD + "unsigned long g = __builtin_offsetof(struct S, bits);"), "error: t.c:1:188: an offsetof of a bit-field is invalid C, which clang rejects")
}

[test(description = "__builtin_types_compatible_p: the int literal of clang's answer, the types' own qualifiers dropped, an enum compatible with its integer type but not with another enum, an array of unknown size with a sized one, typedefs and typeof resolved; a function type with no parameter refused")]
def test_types_compatible(t : T?) {
    let enums = "enum E \{ e0 \}; enum F \{ f0 \}; typedef float F1; typedef float F2; int i; double d; "
    t |> equal(consts_of(enums + "int g[__builtin_types_compatible_p(int, const int) + __builtin_types_compatible_p(enum E, unsigned int) + __builtin_types_compatible_p(int[5], int[]) + __builtin_types_compatible_p(F1, F2) + __builtin_types_compatible_p(typeof(i), int)];"),
               "i:int=- ; d:double=- ; g:int[5]=-")
    t |> equal(consts_of(enums + "int f(void) \{ return __builtin_types_compatible_p(int, long) + __builtin_types_compatible_p(enum E, enum F) + __builtin_types_compatible_p(char *, const char *) + __builtin_types_compatible_p(char, signed char) + __builtin_types_compatible_p(typeof(i), typeof(d)); \}"),
               "i:int=- ; d:double=- ; return {sum_of(5, "0")}")
    t |> equal(consts_of("int f(void) \{ return __builtin_types_compatible_p(long double, double); \}", true), "return 0<int>")
    t |> equal(consts_of("int f(void) \{ return __builtin_types_compatible_p(int (*)(), int (*)(void)); \}"),
               "error: t.c:1:22: a type trait over a function type with no parameter is not typed yet (whether it has a prototype is not in its type)")
}

[test(description = "_Alignof and __alignof__: Dumper A's alignof_v typed size_t with the type's alignment and the operand's type; an expression's type; GNU's preferred 16 for linux's long double, msvc's 8; a function's own aligned(N) for GNU")]
def test_alignof(t : T?) {
    t |> equal(consts_of("struct S \{ char c; double d; \}; int a[_Alignof(struct S)]; int f(double x) \{ return _Alignof(int) + __alignof__(char[3]) + _Alignof(x + 1) + __alignof__(x); \}"),
               "a:int[8]=- ; return IntegralCast<int>(binadd<unsigned long>(binadd<unsigned long>(binadd<unsigned long>(alignof_v<unsigned long>=4:int, alignof_v<unsigned long>=1:char[3]), alignof_v<unsigned long>=8:double), alignof_v<unsigned long>=8:double))")
    t |> equal(consts_of("unsigned long g = __alignof__(long double);"), "g:unsigned long=alignof_v<unsigned long>=16:long double")
    t |> equal(consts_of("unsigned long long g = _Alignof(long double[2]);", true), "g:unsigned long long=alignof_v<unsigned long long>=8:long double[2]")
    t |> equal(consts_of("void h(void) __attribute__((aligned(256))); __attribute__((aligned(64))) void h(void); unsigned long g = __alignof__(h);"),
               "g:unsigned long=alignof_v<unsigned long>=256:func")
}

[test(description = "alignments refused: _Alignof of linux's long double (clang's 16, Dumper A's 8), a type without one, a member, a typedef or an expression in a unit that spells aligned, a function with no aligned(N) or under _Alignof")]
def test_alignof_refusals(t : T?) {
    t |> equal(consts_of("unsigned long g = _Alignof(long double);"),
               "error: t.c:1:19: `_Alignof` of linux's `long double` is not typed yet: clang's 16 is not the 8 Dumper A gives from the C-IR's 64-bit type")
    t |> equal(consts_of("unsigned long g = __alignof__(void);"), "error: t.c:1:19: an alignment of a type without one is not typed yet")
    t |> equal(consts_of("extern int e[]; unsigned long g = __alignof__(e);"), "error: t.c:1:35: an alignment of a type without one is not typed yet")
    t |> equal(consts_of("struct S \{ int i; \} s; unsigned long g = __alignof__(s.i);"),
               "error: t.c:1:42: an alignment of a member, or of an expression in a unit that spells `aligned` or `_Alignas` is not typed yet")
    t |> equal(consts_of("typedef int A __attribute__((aligned(16))); unsigned long g = _Alignof(A);"),
               "error: t.c:1:63: an alignment of a type a typedef or `typeof` names in a unit that spells `aligned` or `_Alignas` is not typed yet")
    t |> equal(consts_of("int v __attribute__((aligned(16))); unsigned long g = _Alignof(v);"),
               "error: t.c:1:55: an alignment of a member, or of an expression in a unit that spells `aligned` or `_Alignas` is not typed yet")
    t |> equal(consts_of("void h(void); unsigned long g = __alignof__(h);"),
               "error: t.c:1:33: an alignment of a function other than GNU's of one an `aligned(N)` attribute aligns is not typed yet")
    t |> equal(consts_of("void h(void) __attribute__((aligned(16))); void (__attribute__((aligned(512))) h)(void); unsigned long g = __alignof__(h);"),
               "error: t.c:1:108: an alignment of a function other than GNU's of one an `aligned(N)` attribute aligns is not typed yet")
    t |> equal(consts_of("void h(void) __attribute__((aligned(16))); unsigned long g = _Alignof(h);"),
               "error: t.c:1:62: an alignment of a function other than GNU's of one an `aligned(N)` attribute aligns is not typed yet")
}

[test(description = "__builtin_constant_p: the int literal of the pinned clang's answer - 1 for what its evaluator folds (overflow, a shift past the width, a NaN, a string literal, a null or integer pointer, a short-circuited variable), 0 for a variable read, an effect, a call, a division by zero, an address, an aggregate; the argument never written")]
def test_constant_p(t : T?) {
    let unit = "int g; int arr[4]; struct P \{ int a; \} ps; int f(void); "
    let globals = "g:int=- ; arr:int[4]=- ; ps:struct P=- ; "
    let folds = ["1 && 2", "0 && g", "1 || g", "2147483647 + 1", "1 << 40", "-1 << 2", "1 ? 2 : g", "(int)2.5", "(_Bool)0.5", "sizeof g"]
    t |> equal(consts_of(unit + "int h(void) \{ return " + join([for (e in folds); "__builtin_constant_p({e})"], " + ") + "; \}"), globals + "return {sum_of(length(folds), "1")}")
    t |> equal(consts_of(unit + "int h(void) \{ return __builtin_constant_p(0.0 / 0.0) + __builtin_constant_p(\"hi\") + __builtin_constant_p(\"hi\"[1]) + __builtin_constant_p((void *)0) + __builtin_constant_p((int *)4); \}"),
               globals + "return {sum_of(5, "1")}")
    t |> equal(consts_of(unit + "int h(int x) \{ return __builtin_constant_p(g) + __builtin_constant_p(x++) + __builtin_constant_p(g * 0) + __builtin_constant_p(f()) + __builtin_constant_p(1 / 0) + __builtin_constant_p(&g) + __builtin_constant_p(arr) + __builtin_constant_p(ps) + __builtin_constant_p(f) + __builtin_constant_p(g ? 1 : 1) + __builtin_constant_p(arr[1]) + __builtin_constant_p(g = 1) + __builtin_constant_p((long)&g); \}"),
               globals + "return {sum_of(13, "0")}")
}

[test(description = "__builtin_constant_p refused where the -O0 answer is the code generator's (a comma, a nested call) or the evaluator's alone (a const object), invalid C with other than one argument")]
def test_constant_p_refusals(t : T?) {
    t |> equal(consts_of("const int c = 3; int h(void) \{ return __builtin_constant_p(c); \}"),
               "error: t.c:1:39: a `__builtin_constant_p` whose answer clang's evaluator gives and the builder cannot is not typed yet")
    t |> equal(consts_of("int h(int x) \{ return __builtin_constant_p((x, 1)); \}"),
               "error: t.c:1:23: a `__builtin_constant_p` over a comma operator, another such call, a compound literal or a statement expression is not typed yet (the -O0 answer is the code generator's)")
    t |> equal(consts_of("int h(int x) \{ return __builtin_constant_p(__builtin_constant_p(x)); \}"),
               "error: t.c:1:23: a `__builtin_constant_p` over a comma operator, another such call, a compound literal or a statement expression is not typed yet (the -O0 answer is the code generator's)")
    t |> equal(consts_of("int h(void) \{ return __builtin_constant_p(\"hi\"[7]); \}"),
               "error: t.c:1:22: a `__builtin_constant_p` whose answer clang's evaluator gives and the builder cannot is not typed yet")
    t |> equal(consts_of("int h(void) \{ return __builtin_constant_p(\"hi\" + 1); \}"),
               "error: t.c:1:22: a `__builtin_constant_p` whose answer clang's evaluator gives and the builder cannot is not typed yet")
    t |> equal(consts_of("int h(void) \{ return __builtin_constant_p(1, 2); \}"),
               "error: t.c:1:22: a `__builtin_constant_p` call of other than one argument is invalid C, which clang rejects")
    t |> equal(consts_of("long l; int h(void) \{ return __builtin_constant_p((long)&l); \}", true),
               "error: t.c:1:30: a `__builtin_constant_p` whose answer clang's evaluator gives and the builder cannot is not typed yet")
}

[test(description = "integer constant expressions: LLONG_MIN / -1 wraps and % -1 is 0 with no trap, as clang folds them; a shift count past the width or below 0 has no value")]
def test_constant_edges(t : T?) {
    t |> equal(consts_of("_Static_assert((-9223372036854775807L - 1) / -1 < 0, \"w\"); _Static_assert((-9223372036854775807L - 1) % -1 == 0, \"r\"); int a[(-2147483647 - 1) / -1 < 0];"), "a:int[1]=-")
    t |> equal(consts_of("int a[1 << 40];"), "error: t.c:1:7: an array size other than an integer constant expression is not typed yet")
    t |> equal(consts_of("int a[4 >> -1];"), "error: t.c:1:7: an array size other than an integer constant expression is not typed yet")
}

[test(description = "a case value is clang's, refused where Dumper A's own fold (casts dropped, every step in 64 bits) gives another: a narrowing cast, an int overflow, a literal past 63 bits")]
def test_case_values(t : T?) {
    t |> equal(consts_of("void g(int x) \{ switch (x) \{ case (char)200: case 1 < 2: case sizeof(int): case 1 ? 5 : 6: ; \} \}"), "case 200 ; case 1 ; case 4 ; case 5")
    t |> equal(consts_of("void g(int x) \{ switch (x) \{ case (signed char)255: ; \} \}"),
               "error: t.c:1:30: a case value Dumper A folds apart from clang's is not typed yet (its fold drops the casts and holds every step in 64 bits)")
    t |> equal(consts_of("void g(int x) \{ switch (x) \{ case 1 << 31: ; \} \}"),
               "error: t.c:1:30: a case value Dumper A folds apart from clang's is not typed yet (its fold drops the casts and holds every step in 64 bits)")
    t |> equal(consts_of("void g(int x) \{ switch (x) \{ case (int)0xffffffffffffffffu: ; \} \}"),
               "error: t.c:1:30: a case value Dumper A folds apart from clang's is not typed yet (its fold drops the casts and holds every step in 64 bits)")
    t |> equal(consts_of("void g(unsigned long x) \{ switch (x) \{ case 9223372036854775808u: ; \} \}"),
               "error: t.c:1:40: a case value Dumper A folds apart from clang's is not typed yet (its fold drops the casts and holds every step in 64 bits)")
    t |> equal(consts_of("void g(unsigned long x) \{ switch (x) \{ case 0xffffffffffffffffu >> 60: ; \} \}"),
               "error: t.c:1:40: a case value Dumper A folds apart from clang's is not typed yet (its fold drops the casts and holds every step in 64 bits)")
}

[test(description = "a static object's initializer: an arithmetic constant, an address constant - an object, a member, an element, a string literal, a function, a pointer step, a file-scope compound literal, an address as a pointer-wide integer - taken")]
def test_static_constants(t : T?) {
    let unit = "struct S \{ int a, b; \} s; int arr[4]; int g; int f(void); "
    t |> equal(consts_of(unit + "int *p1 = &s.b; int *p2 = &arr[2]; int *p3 = arr + 1; char *p4 = \"ab\"; int (*p5)(void) = f; double d = 1.0 / 3; long l = (long)&g; struct S *p6 = &(struct S)\{1, 2\}; int n = 0 && g;"),
               "s:struct S=- ; arr:int[4]=- ; g:int=- ; p1:int*=unaddr<int*>(member<int>(-, -), -) ; p2:int*=unaddr<int*>(index<int>(-, -), -) ; p3:int*=binadd<int*>(ArrayToPointerDecay<int*>(arr), 1<int>) ; p4:char*=ArrayToPointerDecay<char*>(str_lit<char[3]>(-, -)) ; p5:func*=FunctionToPointerDecay<func*>(f) ; d:double=bindiv<double>(0x1p+0<double>, IntegralToFloating<double>(3<int>)) ; l:long=PointerToIntegral<long>(unaddr<int*>(g, -)) ; p6:struct S*=unaddr<struct S*>(compound_lit<struct S>(-, -), -) ; n:int=binland<int>(0<int>, LValueToRValue<int>(g))")
    t |> equal(consts_of("int f(void) \{ static int k; static int *p = &k; static const char *q = \"xy\" + 1; return 0; \}"), "f_k:int=- ; f_p:int*=unaddr<int*>(f_k, -) ; f_q:char*=NoOp<char*>(binadd<char*>(ArrayToPointerDecay<char*>(str_lit<char[3]>(-, -)), 1<int>)) ; return 0<int>")
}

[test(description = "a static object's initializer that is no constant is invalid C - a variable read, a call, a division by zero, an automatic object's address; refused where clang's evaluator decides - a const object, an address narrowed, a block's compound literal")]
def test_static_refusals(t : T?) {
    t |> equal(consts_of("int g; int h = g;"), "error: t.c:1:16: a static object's initializer that is no constant is invalid C, which clang rejects")
    t |> equal(consts_of("int f(void); int h = f();"), "error: t.c:1:22: a static object's initializer that is no constant is invalid C, which clang rejects")
    t |> equal(consts_of("int h = 1 / 0;"), "error: t.c:1:9: a static object's initializer that is no constant is invalid C, which clang rejects")
    t |> equal(consts_of("void f(int x) \{ static int *p = &x; \}"), "error: t.c:1:33: a static object's initializer that is no constant is invalid C, which clang rejects")
    t |> equal(consts_of("void f(x) int x; \{ static int *p = &x; \}"), "error: t.c:1:36: a static object's initializer that is no constant is invalid C, which clang rejects")
    t |> equal(consts_of("void f(void) \{ int y; static int *q = &y; \}"), "error: t.c:1:39: a static object's initializer that is no constant is invalid C, which clang rejects")
    t |> equal(consts_of("const int c = 1; int h = c;"),
               "error: t.c:1:26: a static object's initializer whose constancy clang's evaluator decides and the builder cannot is not typed yet")
    t |> equal(consts_of("int g; int h = (int)&g;"),
               "error: t.c:1:16: a static object's initializer whose constancy clang's evaluator decides and the builder cannot is not typed yet")
    t |> equal(consts_of("void f(void) \{ static int *p = (int[])\{1\}; \}"),
               "error: t.c:1:32: a static object's initializer whose constancy clang's evaluator decides and the builder cannot is not typed yet")
}

[test(description = "__builtin_constant_p of a string literal's element 0 is 1, through a cast and a folded index too, as clang's evaluator takes a string literal at offset 0; element 1 is an address, 0")]
def test_constant_p_first_character(t : T?) {
    t |> equal(consts_of("int h(void) \{ return __builtin_constant_p(&\"abc\"[0]) + __builtin_constant_p((const char *)&\"abc\"[0]) + __builtin_constant_p(&\"abc\"[2 - 2]); \}"), "return binadd<int>(binadd<int>(1<int>, 1<int>), 1<int>)")
    t |> equal(consts_of("int h(void) \{ return __builtin_constant_p(&\"abc\"[1]); \}"), "return 0<int>")
    t |> equal(consts_of("char *p = &\"abc\"[0]; char *q = &\"abc\"[1];"), "p:char*=unaddr<char*>(index<char>(-, -), -) ; q:char*=unaddr<char*>(index<char>(-, -), -)")
}

[test(description = "__builtin_types_compatible_p drops an array's element qualifiers at every level, as clang does for GCC; a pointer to a qualified array keeps them")]
def test_types_compatible_arrays(t : T?) {
    t |> equal(consts_of("int f(void) \{ return __builtin_types_compatible_p(const int[3], int[3]) + __builtin_types_compatible_p(volatile char[2][3], char[2][3]) + __builtin_types_compatible_p(const volatile int[2][2], int[2][2]); \}"), "return binadd<int>(binadd<int>(1<int>, 1<int>), 1<int>)")
    t |> equal(consts_of("int f(void) \{ return __builtin_types_compatible_p(int (*)[3], const int (*)[3]); \}"), "return 0<int>")
}

[test(description = "_Alignof and __alignof__ of a record or an array of records holding linux's long double: the layout's 16")]
def test_alignof_long_double_records(t : T?) {
    t |> equal(consts_of("struct LD \{ char c; long double x; \}; int a[_Alignof(struct LD)]; typedef struct \{ long double x; \} TLD; TLD arr[2]; int b[__alignof__(arr)];"), "a:int[16]=- ; arr:struct TLD[2]=- ; b:int[16]=-")
}

[test(description = "GNU __alignof__ of a function is refused in a definition that spells aligned before the operand, where a block's redeclaration can give clang another answer")]
def test_function_alignment_block(t : T?) {
    t |> equal(consts_of("int fa(void) __attribute__((aligned(8))); int use(void) \{ int fa(void) __attribute__((aligned(32))); return __alignof__(fa); \}"), "error: t.c:1:109: an alignment of a function other than GNU's of one an `aligned(N)` attribute aligns is not typed yet")
    t |> equal(consts_of("int fa(void) __attribute__((aligned(8))); int use(void) \{ return __alignof__(fa); \}"), "return IntegralCast<int>(alignof_v<unsigned long>=8:func)")
}

[test(description = "the address of a thread-local object is no address constant: invalid C in a static object's initializer, file-scope or block-scope, _Thread_local or __thread")]
def test_thread_local_address(t : T?) {
    t |> equal(consts_of("_Thread_local int tl; int *ptl = &tl;"), "error: t.c:1:34: a static object's initializer that is no constant is invalid C, which clang rejects")
    t |> equal(consts_of("__thread int t2; int *p2 = &t2;"), "error: t.c:1:28: a static object's initializer that is no constant is invalid C, which clang rejects")
    t |> equal(consts_of("void f(void) \{ static _Thread_local int t; static int *p = &t; \}"), "error: t.c:1:60: a static object's initializer that is no constant is invalid C, which clang rejects")
}

[test(description = "an automatic object is told by the reference's own identifier, not by its C-IR name: a parameter spelled as a file static's C-IR name leaves the static's address a constant")]
def test_automatic_by_reference(t : T?) {
    t |> equal(consts_of("static int x; int f(int t__x) \{ static int *p = &x; return *p + t__x; \}"), "t__x:int=- ; f_p:int*=unaddr<int*>(t__x, -) ; return binadd<int>(LValueToRValue<int>(underef<int>(LValueToRValue<int*>(f_p), -)), LValueToRValue<int>(t__x))")
    t |> equal(consts_of("static int x; int f(int t__x) \{ static int *p = &t__x; return *p; \}"), "error: t.c:1:49: a static object's initializer that is no constant is invalid C, which clang rejects")
}

[test(description = "typeof of a bit-field is invalid C, through -> too")]
def test_typeof_bitfield(t : T?) {
    t |> equal(consts_of("struct BF \{ int f : 3; \} bs; typeof(bs.f) t7;"), "error: t.c:1:37: typeof of a bit-field is invalid C, which clang rejects")
    t |> equal(consts_of("struct BF \{ int f : 3; \} *bp; typeof(bp->f) t8;"), "error: t.c:1:38: typeof of a bit-field is invalid C, which clang rejects")
    t |> equal(consts_of("struct BF \{ int f : 3; int g; \} bs; typeof(bs.g) t9;"), "bs:struct BF=- ; t9:int=-")
}

[test(description = "case values are compared in the switch's promoted type, as clang converts them, while the C-IR keeps the label's value; a nested switch's type ends with it; a case outside a switch is invalid C")]
def test_case_conversion(t : T?) {
    t |> equal(consts_of("int f(int c) \{ switch (c) \{ case 0: return 1; case 4294967296L: return 2; \} return 0; \}"), "error: t.c:1:47: a duplicate case value is invalid C, which clang rejects")
    t |> equal(consts_of("int f(long c) \{ switch (c) \{ case 0: return 1; case 4294967296L: return 2; \} return 0; \}"), "case 0 ; return 1<int> ; case 4294967296 ; return 2<int> ; return 0<int>")
    t |> equal(consts_of("int f(int c) \{ switch (c) \{ case 0: switch ((long)c) \{ case 4294967296L: ; \} case 4294967296L: ; \} return 0; \}"), "error: t.c:1:78: a duplicate case value is invalid C, which clang rejects")
    t |> equal(consts_of("void f(int c) \{ switch (c) \{ case 1: ; \} case 2: ; \}"), "error: t.c:1:42: a case label outside a switch is invalid C, which clang rejects")
}
