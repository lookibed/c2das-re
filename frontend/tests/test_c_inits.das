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
               "error: t.c:1:147: an initializer into a subobject an earlier one gave a whole value is not typed yet")
    t |> equal(inits_of(RECORDS + "struct P g; struct Q a = \{.a = g, .a = 1\};"),
               "error: t.c:1:133: an initializer into a subobject an earlier one gave a whole value is not typed yet")
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

[test(description = "a designator that opens another member of a union drops the member an earlier item filled: a nested designator, a string member replaced and reopened, a union reopened by elided braces")]
def test_union_member_replaced(t : T?) {
    t |> equal(inits_of("struct P \{ int x, y; \}; union V \{ struct P s; int i; \}; union V v = \{.i = 5, .s.x = 1\};"), "v:union V=\{0:\{0:1\}\}")
    t |> equal(inits_of("union U \{ int a; float b; char c[4]; \} u = \{.c = \"ab\", .a = 3, .c[1] = 'q'\};"), "u:union U=\{2:\{1:IntegralCast<char>(113)\}\}")
    t |> equal(inits_of("struct P \{ int x, y; \}; union V \{ struct P s; int i; \}; struct T \{ union V v; int d; \} t = \{.v.i = 1, .v = 7, 3\};"),
               "t:struct T=\{0:\{0:\{0:7, 1:3\}\}\}")
}

[test(description = "a union a later designator reopens keeps its member filled: the next positional item goes past the union, an anonymous one and a named one")]
def test_union_reopened(t : T?) {
    t |> equal(inits_of("struct P \{ int x, y; \}; struct S \{ union \{ struct P s; int i; \}; int d; \}; struct S g = \{.s.x = 1, .s.y = 2, 3\};"),
               "g:struct S=\{0:\{0:\{0:1, 1:2\}\}, 1:3\}")
    t |> equal(inits_of("struct P \{ int x, y; \}; union V \{ struct P s; int i; \}; struct T \{ union V v; int d; \} t = \{.v.s.x = 1, .v.s.y = 2, 3\};"),
               "t:struct T=\{0:\{0:\{0:1, 1:2\}\}, 1:3\}")
}

[test(description = "a GNU range whose value opens elided braces shares the subobject: the items after it fill every element of the range; a later designator updates one element alone")]
def test_range_elided(t : T?) {
    t |> equal(inits_of("struct P \{ int x, y; \}; struct P a[3] = \{[0 ... 1] = 1, 2, 3\};"), "a:struct P[3]=\{0:\{0:1, 1:2\}, 1:\{0:1, 1:2\}, 2:\{0:3\}\}")
    t |> equal(inits_of("int a[3][2] = \{[0 ... 1] = 1, 2, 3\};"), "a:int[2][3]=\{0:\{0:1, 1:2\}, 1:\{0:1, 1:2\}, 2:\{0:3\}\}")
    t |> equal(inits_of("struct P \{ int x, y; \}; struct P a[2] = \{[0 ... 1] = 1, 2, [0].y = 9\};"), "a:struct P[2]=\{0:\{0:1, 1:9\}, 1:\{0:1, 1:2\}\}")
}

// the type of the last item of the first global's initializer list in unit `text`, as C spells it
def private last_item_type(text : string) : string {
    var p : CParser
    c_parser_open_text(p, text, "t.c", false)
    let u = c_unit(p)
    return "parse error: {p.err}" if (p.failed)
    var r = new CIr
    c_ir_open(*r, target_lp64_linux(), "")
    var out = ""
    if (c_ir_unit(*r, p, u)) {
        for (d in r.tu.decls) {
            if (empty(out) && d.k == "global" && d.init != null && d.init.e == "init_list" && !empty(d.init.init_items)) {
                out = spelled(r.tu.types, d.init.init_items[length(d.init.init_items) - 1].v.t)
            }
        }
    } else {
        out = "error: {r.err}"
    }
    delete_tu(r.tu)
    unsafe {
        delete r
    }
    return out
}

// whether the first global's initializer in unit `text` is marked as written in parentheses
def private paren_string(text : string) : string {
    var p : CParser
    c_parser_open_text(p, text, "t.c", false)
    let u = c_unit(p)
    return "parse error: {p.err}" if (p.failed)
    var r = new CIr
    c_ir_open(*r, target_lp64_linux(), "")
    let out = c_ir_unit(*r, p, u) ? "{r.tu.decls[0].init.paren}" : "error: {r.err}"
    delete_tu(r.tu)
    unsafe {
        delete r
    }
    return out
}

[test(description = "a static object's flexible array member given a braced list, a string or a member designator is typed as clang types it, sized by its value; elided braces, an automatic object and a nested record refused; a designator into its elements invalid C")]
def test_flexible_member(t : T?) {
    let flex = "struct F \{ int n; int a[]; \}; "
    t |> equal(inits_of(flex + "struct F f = \{2, \{3, 4\}\}; struct F g = \{.a = \{5\}, .n = 1\};"), "f:struct F=\{0:2, 1:\{0:3, 1:4\}\} ; g:struct F=\{0:1, 1:\{0:5\}\}")
    t |> equal(last_item_type(flex + "struct F f = \{2, \{3, 4\}\};"), "int[2]")
    t |> equal(last_item_type("struct C \{ int n; char a[]; \}; struct C c = \{2, \"ab\"\};"), "char[3]")
    t |> equal(inits_of(flex + "struct F f = \{.a[2] = 7\};"), "error: t.c:1:45: a designator into a flexible array member's elements is invalid C, which clang rejects")
    t |> equal(inits_of(flex + "void h(void) \{ struct F f = \{2, \{3\}\}; \}"), "error: t.c:1:63: an initializer of a flexible array member is not typed yet")
    t |> equal(inits_of(flex + "struct G \{ struct F f; \}; struct G g = \{1, \{2\}\};"), "error: t.c:1:74: an initializer of a flexible array member is not typed yet")
    t |> equal(inits_of(flex + "struct F *p = &(struct F)\{2, \{3\}\};"), "error: t.c:1:60: an initializer of a flexible array member is not typed yet")
    t |> equal(inits_of(flex + "struct G \{ struct F f; \}; struct G g = \{\{1, \{2\}\}\};"), "error: t.c:1:75: an initializer of a flexible array member is not typed yet")
}

[test(description = "a character array's string literal in parentheses, and a braced string followed by excess items, initialize it as clang does")]
def test_string_forms(t : T?) {
    t |> equal(inits_of("char s[4] = (\"ab\"); char u[4] = \{\"ab\", 'c'\}; struct \{ char s[4]; int x; \} g = \{(\"ab\"), 1\};"),
               "s:char[4]=str<char[4]> ; u:char[4]=str<char[4]> ; g:struct =\{0:str<char[4]>, 1:1\}")
    t |> equal(paren_string("char s[4] = (\"ab\");"), "true")
    t |> equal(paren_string("char s[4] = \"ab\";"), "false")
    t |> equal(inits_of("char u[4] = \{\"ab\", zz\};"), "error: t.c:1:20: the identifier 'zz', which names no variable or function the builder knows, is not typed yet")
    t |> equal(inits_of("char u[4] = \{\"ab\", [3] = 'c'\};"), "error: t.c:1:20: a designator after a character array's string is not typed yet")
}

[test(description = "designator indices clang rejects: below 0 (sized and unsized), past a sized array's bound, an empty GNU range; a range past 2^31 - 1 refused")]
def test_index_bounds(t : T?) {
    t |> equal(inits_of("int a[4] = \{[-1] = 1\};"), "error: t.c:1:13: an array index below 0 is invalid C, which clang rejects")
    t |> equal(inits_of("struct P \{ int x, y; \}; struct P a[] = \{[-1].x = 1\};"), "error: t.c:1:41: an array index below 0 is invalid C, which clang rejects")
    t |> equal(inits_of("int a[2] = \{[5] = 1\};"), "error: t.c:1:13: an array index past the array's bound is invalid C, which clang rejects")
    t |> equal(inits_of("int a[4] = \{[1 ... 4] = 1\};"), "error: t.c:1:13: an array index past the array's bound is invalid C, which clang rejects")
    t |> equal(inits_of("int a[4] = \{[3 ... 1] = 1\};"), "error: t.c:1:13: an empty array index range is invalid C, which clang rejects")
    t |> equal(inits_of("int a[] = \{[0 ... 2147483647] = 1\};"), "error: t.c:1:12: an array sized past 2^31 - 1 is not typed yet")
}

[test(description = "a record's first position and a reopened record's skip a leading unnamed bit-field; a union reopened at its last member hands on past it; every sublist sorted by position")]
def test_positions_reopened(t : T?) {
    let bits = "struct B \{ int : 3; int a; int b; \}; "
    t |> equal(inits_of(bits + "struct B g = \{1, 2\};"), "g:struct B=\{1:1, 2:2\}")
    t |> equal(inits_of(bits + "struct Q \{ struct B s; int c; \}; struct Q q = \{.s.b = 4, .s = 7\};"), "q:struct Q=\{0:\{1:7, 2:4\}\}")
    t |> equal(inits_of("struct P \{ int x, y; \}; union U \{ int i; struct P p; \}; struct T \{ union U u; int d; \}; struct T t = \{.u.p.x = 1, .u.p.y = 2, 3\};"),
               "t:struct T=\{0:\{1:\{0:1, 1:2\}\}, 1:3\}")
    t |> equal(inits_of("struct P \{ int x, y; \}; struct Q \{ struct P a; int b; \}; struct Q a = \{.a.y = 1, .a.x = 2\};"), "a:struct Q=\{0:\{0:2, 1:1\}\}")
}

[test(description = "compound literals refused: a type name the builder does not type, a record defined only after the use (clang's incomplete type), a scalar's designated value (invalid C)")]
def test_compound_literal_refusals(t : T?) {
    t |> equal(inits_of("int f(void) \{ return (_Complex double)\{1\}; \}"), "error: t.c:1:23: a complex type is not typed yet")
    t |> equal(inits_of("int f(void) \{ return (struct L)\{1\}.a; \} struct L \{ int a; \};"), "error: t.c:1:32: an initializer of an incomplete record is not typed yet")
    t |> equal(inits_of("int f(void) \{ return (int)\{[0] = 1\}; \}"), "error: t.c:1:22: a designated initializer of a scalar is invalid C, which clang rejects")
}

[test(description = "a value whose braces would open an aggregate with no elements is invalid C, as clang rejects it: an empty union or struct, a zero-length array")]
def test_empty_aggregates(t : T?) {
    t |> equal(inits_of("union E \{\}; struct T \{ union E e; int d; \} t = \{5\};"), "error: t.c:1:49: a value in an aggregate with no elements, whose braces clang requires, is invalid C, which clang rejects")
    t |> equal(inits_of("struct E \{\}; struct T \{ struct E e; int d; \} t = \{5\};"), "error: t.c:1:51: a value in an aggregate with no elements, whose braces clang requires, is invalid C, which clang rejects")
    t |> equal(inits_of("struct T \{ int z[0]; int d; \} t = \{5\};"), "error: t.c:1:36: a value in an aggregate with no elements, whose braces clang requires, is invalid C, which clang rejects")
    t |> equal(inits_of("union E \{\}; struct T \{ union E e; int d; \} t = \{\{\}, 6\};"), "t:struct T=\{0:\{\}, 1:6\}")
    t |> equal(inits_of("union E \{\}; union E e = \{5\};"), "e:union E=\{\}")
}
