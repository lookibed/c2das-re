options gen2
options stack = 262144
require dastest/testing_boost public
require strings
require daslib/strings_boost
require ../c_ir.das

//! `frontend/c_inits.das` with its uses in `c_types.das`, `c_exprs.das` and `c_ir.das`:
//! initializers as clang's semantic form holds them - designators resolved to positions, elided
//! braces opened as the subobjects' lists, the union's one member, braced scalars, character arrays
//! from string literals, compound literals, the count an unsized array takes - and every refusal
//! with its place.

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

// expression `x` as one line: a list its items `pos:value` and type, a literal its value, a cast
// its kind, a compound literal its type and list
def private shown(types : array<CirType>; x : CirExpr?) : string {
    return "-" if (x == null)
    let t = spelled(types, x.t)
    if (x.e == "init_list") {
        return "\{" + join([for (it in x.init_items); "{it.pos}:{shown(types, it.v)}"], ", ") + "\}"
    } elif (x.e == "compound_lit") {
        return "({t})" + shown(types, x.init)
    } elif (x.e == "cast") {
        return "{x.cast_kind}<{t}>({shown(types, x.a)})"
    } elif (x.e == "int_lit") {
        return x.v
    } elif (x.e == "str_lit") {
        return "str<{t}>"
    } elif (x.e == "ref") {
        return x.name
    } elif (x.e == "member") {
        return "{shown(types, x.base)}{x.arrow ? "->" : "."}{x.field}"
    } elif (x.e == "index") {
        return "{shown(types, x.base)}[{shown(types, x.i)}]"
    } elif (x.e == "un") {
        return "{x.op}<{t}>({shown(types, x.a)})"
    }
    return "{x.e}<{t}>({shown(types, x.a)}, {shown(types, x.b)})"
}

// the initializers of unit `text` (named `t.c`) joined by ` ; `: each global's `name:type=value`,
// each local's in a function body, each return's value; `error: ` and the builder's error
def private inits_of(text : string; msvc : bool = false) : string {
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
                for (st in d.body.body) {
                    if (st.s == "decl") {
                        out |> push("{st.name}:{spelled(r.tu.types, st.t)}={shown(r.tu.types, st.init)}")
                    } elif (st.s == "return") {
                        out |> push("return {shown(r.tu.types, st.e)}")
                    }
                }
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

let RECORDS = "struct P \{ int x, y; \}; struct Q \{ struct P a; int b; \}; union U \{ int i; float f; struct P p; \}; "

[test(description = "a struct's list: each item at its field, a designator naming the field, the old GNU `member:` too; an unnamed bit-field takes no item; `\{0\}` and `\{\}`")]
def test_struct_lists(t : T?) {
    t |> equal(inits_of(RECORDS + "struct P a = \{1, 2\}; struct P b = \{.y = 5\}; struct P c = \{y: 2, x: 1\}; struct P d = \{0\}; struct P e = \{\};"),
               "a:struct P=\{0:1, 1:2\} ; b:struct P=\{1:5\} ; c:struct P=\{0:1, 1:2\} ; d:struct P=\{0:0\} ; e:struct P=\{\}")
    t |> equal(inits_of("struct B \{ int a : 3; int : 2; int b : 4; \}; struct B g = \{1, 2\};"), "g:struct B=\{0:1, 2:2\}")
}

[test(description = "a union's list holds one member: the first with no designator, the designated one, the last of several designators; a member whose list ran out leaves no position for the next item")]
def test_union_lists(t : T?) {
    t |> equal(inits_of(RECORDS + "union U a = \{3\}; union U b = \{.f = 1\}; union U c = \{.p = \{1, 2\}\}; union U d = \{.i = 1, .f = 2\};"),
               "a:union U=\{0:3\} ; b:union U=\{1:IntegralToFloating<float>(1)\} ; c:union U=\{2:\{0:1, 1:2\}\} ; d:union U=\{1:IntegralToFloating<float>(2)\}")
    t |> equal(inits_of("struct P \{ int x, y; \}; union V \{ struct P p; int i; \}; union V a = \{1, 2, 3\}; union V b = \{.p.y = 1, 5\};"),
               "a:union V=\{0:\{0:1, 1:2\}\} ; b:union V=\{0:\{1:1\}\}")
}

[test(description = "elided braces: a subobject with no braces of its own takes the items after it while it has positions - an array of records, a record's array and string, an array of arrays, a union's first member")]
def test_elided_braces(t : T?) {
    t |> equal(inits_of(RECORDS + "struct P a[3] = \{1, 2, 3\}; struct Q b = \{1, 2, 3\}; int m[2][3] = \{1, 2, 3, 4\}; union U u[2] = \{1, 2\};"),
               "a:struct P[3]=\{0:\{0:1, 1:2\}, 1:\{0:3\}\} ; b:struct Q=\{0:\{0:1, 1:2\}, 1:3\} ; m:int[3][2]=\{0:\{0:1, 1:2, 2:3\}, 1:\{0:4\}\} ; u:union U[2]=\{0:\{0:1\}, 1:\{0:2\}\}")
    t |> equal(inits_of("struct S \{ char s[4]; int n; \}; struct S a[] = \{\"ab\", 1, \"cd\", 2\}; struct S b = \{\{'a'\}, 2\}; char c[2][4] = \{\"ab\", \"cd\"\};"),
               "a:struct S[2]=\{0:\{0:str<char[4]>, 1:1\}, 1:\{0:str<char[4]>, 1:2\}\} ; b:struct S=\{0:\{0:IntegralCast<char>(97)\}, 1:2\} ; c:char[4][2]=\{0:str<char[4]>, 1:str<char[4]>\}")
}

[test(description = "a record value initializes a record subobject whole, in a list and under a designator; any other value opens its braces")]
def test_record_values(t : T?) {
    t |> equal(inits_of(RECORDS + "struct P g; int f(void) \{ struct Q a = \{g, 1\}; struct Q b = \{.a = g, .b = 2\}; return 0; \}"),
               "g:struct P=- ; a:struct Q=\{0:LValueToRValue<struct P>(g), 1:1\} ; b:struct Q=\{0:LValueToRValue<struct P>(g), 1:2\} ; return 0")
}

[test(description = "designators: a nested path opens each subobject, the items after it go on from the designated position at its depth, a later item for a position replaces the earlier one, a GNU range fills each index (opening each element's braces), a second designator goes into the list the first opened, a member an anonymous member makes visible goes through it")]
def test_designators(t : T?) {
    t |> equal(inits_of("struct P \{ int x, y, z; \}; struct Q \{ struct P a; int b; \}; struct Q a = \{.a.y = 4, 5\}; struct Q b = \{.a.z = 4, 5\}; struct P c = \{1, 2, .x = 3\}; struct Q d[2] = \{[1].a.x = 1, 2, 3, 4\};"),
               "a:struct Q=\{0:\{1:4, 2:5\}\} ; b:struct Q=\{0:\{2:4\}, 1:5\} ; c:struct P=\{0:3, 1:2\} ; d:struct Q[2]=\{1:\{0:\{0:1, 1:2, 2:3\}, 1:4\}\}")
    t |> equal(inits_of("int a[6] = \{[1] = 1, 2, [4] = 4, 5\}; int b[5] = \{[0 ... 2] = 9\}; int c[4] = \{[3] = 1, [1] = 2\}; int d[2][2] = \{[1] = \{1\}, [0][1] = 2\}; int e[2][2] = \{[1][0] = 3, 4\};"),
               "a:int[6]=\{1:1, 2:2, 4:4, 5:5\} ; b:int[5]=\{0:9, 1:9, 2:9\} ; c:int[4]=\{1:2, 3:1\} ; d:int[2][2]=\{0:\{1:2\}, 1:\{0:1\}\} ; e:int[2][2]=\{1:\{0:3, 1:4\}\}")
    t |> equal(inits_of(RECORDS + "struct Q a = \{.a.x = 1, .a.y = 2\}; union U b = \{.p.y = 1\}; struct P c[3] = \{[0 ... 1] = 5\};"),
               "a:struct Q=\{0:\{0:1, 1:2\}\} ; b:union U=\{2:\{1:1\}\} ; c:struct P[3]=\{0:\{0:5\}, 1:\{0:5\}\}")
    t |> equal(inits_of("struct A \{ int k; struct \{ int u, v; \}; union \{ int w; float q; \}; \}; struct A a = \{1, 2, 3, 4\}; struct A b = \{.v = 7, .w = 8\};"),
               "a:struct A=\{0:1, 1:\{0:2, 1:3\}, 2:\{0:4\}\} ; b:struct A=\{1:\{1:7\}, 2:\{0:8\}\}")
}

[test(description = "an item past the object's last position is dropped, as clang drops it")]
def test_excess(t : T?) {
    t |> equal(inits_of(RECORDS + "int a[2] = \{1, 2, 3\}; struct P b = \{1, 2, 3\};"), "a:int[2]=\{0:1, 1:2\} ; b:struct P=\{0:1, 1:2\}")
}

[test(description = "an unsized array takes one past the last position its list fills: elided braces of records and rows, a range, a nested designator")]
def test_unsized(t : T?) {
    t |> equal(inits_of(RECORDS + "struct P a[] = \{1, 2, 3\}; int b[] = \{[1 ... 3] = 4\}; int c[][2] = \{[1][0] = 1, 2, 3\}; struct P d[] = \{\{1, 2\}, [3] = \{.y = 9\}\};"),
               "a:struct P[2]=\{0:\{0:1, 1:2\}, 1:\{0:3\}\} ; b:int[4]=\{1:4, 2:4, 3:4\} ; c:int[2][3]=\{1:\{0:1, 1:2\}, 2:\{0:3\}\} ; d:struct P[4]=\{0:\{0:1, 1:2\}, 3:\{1:9\}\}")
}

[test(description = "compound literals: a record's, an unsized array's sized by its list, a scalar's one value or none, each an lvalue - its address taken, decayed, read; a character array's lone string at file scope a list over it, in a body the string")]
def test_compound_literals(t : T?) {
    t |> equal(inits_of(RECORDS + "char *s = (char[])\{\"ab\"\}; int f(void) \{ struct P *p = &(struct P)\{.y = 3\}; int *q = (int[])\{1, 2\}; int n = (int)\{5\}; int z = (int)\{\}; char *c = (char[])\{\"ab\"\}; return (struct P)\{1, 2\}.y; \}"),
               "s:char*=ArrayToPointerDecay<char*>((char[3])\{0:str<char[3]>\}) ; p:struct P*=addr<struct P*>((struct P)\{1:3\}) ; q:int*=ArrayToPointerDecay<int*>((int[2])\{0:1, 1:2\}) ; n:int=LValueToRValue<int>((int)\{0:5\}) ; z:int=LValueToRValue<int>((int)\{\}) ; c:char*=ArrayToPointerDecay<char*>((char[3])str<char[3]>) ; return LValueToRValue<int>((struct P)\{0:1, 1:2\}.1)")
}

[test(description = "every initializer construct the builder does not type is refused at its place")]
def test_refusals(t : T?) {
    t |> equal(inits_of(RECORDS + "struct P g; int f(void) \{ struct Q a = \{.a = g, .a.x = 1\}; return 0; \}"),
               "error: t.c:1:147: a designator into a subobject an earlier initializer gave a whole value is not typed yet")
    t |> equal(inits_of("struct F \{ int n; int a[]; \}; struct F f = \{1, 2\};"), "error: t.c:1:48: an initializer of a flexible array member is not typed yet")
    t |> equal(inits_of("int a[2] = \{.x = 1\};"), "error: t.c:1:13: a member designator of other than a struct or union is not typed yet")
    t |> equal(inits_of(RECORDS + "struct P a = \{.w = 1\};"), "error: t.c:1:113: a designator of a member 'w' its record does not have, which is not typed yet")
    t |> equal(inits_of(RECORDS + "struct P a = \{[0] = 1\};"), "error: t.c:1:113: an index designator of other than an array is not typed yet")
    t |> equal(inits_of("int n; int a[2] = \{[n] = 1\};"), "error: t.c:1:20: an array index other than an integer constant expression is not typed yet")
    t |> equal(inits_of("int n; int a[4] = \{[0 ... n] = 1\};"), "error: t.c:1:20: an array index other than an integer constant expression is not typed yet")
    t |> equal(inits_of("int a[2][2] = \{[0 ... 1][0] = 1\};"), "error: t.c:1:16: a range designator followed by another designator is not typed yet")
    t |> equal(inits_of("struct S; struct S s = \{1\};"), "error: t.c:1:24: an initializer of an incomplete record is not typed yet")
    t |> equal(inits_of("int n; int *p = (int[])\{[n] = 1\};"), "error: t.c:1:25: an array index other than an integer constant expression is not typed yet")
    t |> equal(inits_of("int f(void) \{ return (int)\{1, 2\}; \}"), "error: t.c:1:22: a scalar compound literal of other than one value is not typed yet")
    t |> equal(inits_of("int n = \{1, 2\};"), "error: t.c:1:9: a braced scalar initializer of other than one value is not typed yet")
}
