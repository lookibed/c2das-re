options gen2
options stack = 262144
require dastest/testing_boost public
require strings
require daslib/strings_boost
require ../c_ir.das

//! `frontend/c_records.das` with its uses in `c_types.das`, `c_exprs.das` and `c_ir.das`: records,
//! unions and enums as Dumper A writes them - the table entries in its order with their layout, the
//! `record` and `enumdef` anchors, the tags' uses, member access through anonymous members, the
//! enum and bit-field promotions, `dims`, under both dialects - and every refusal with its place.

// a table entry as one word: a record its kind, name, size, alignment, `packed` and fields; an enum
// its name, spelling, sign and items; any other its key
def private entry(t : CirType) : string {
    if (t.k == "struct" || t.k == "union") {
        let fields = join([for (f in t.fields); "{f.name}:{f.t}@{f.off}" + (f.is_bitfield ? "/{f.bit_off}:{f.bit_w}" : "") + (empty(f.dims) ? "" : "[" + join([for (d in f.dims); "{d.enum_t}.{d.item}"], ",") + "]")], " ")
        return "{t.k} {t.name} {t.size}/{t.align}{t.packed ? " packed" : ""} \{{fields}\}"
    } elif (t.k == "enum") {
        let items = join([for (it in t.items); "{it.name}={it.v}"], ",")
        return "enum {t.name} '{t.spell}'{t.is_signed ? "" : " unsigned"} \{{items}\}"
    }
    return t.k == "typedef" ? "typedef:{t.name}:{t.to}" : c_type_key(t)
}

// expression `x` as one line: a member its field and `->`, an enum constant its enum and item
def private shown(x : CirExpr?) : string {
    return "-" if (x == null)
    if (x.e == "member") {
        return "{shown(x.base)}{x.arrow ? "->" : "."}{x.field}<{x.t}>{x.vol ? "~" : ""}"
    } elif (x.e == "enum_ref") {
        return "{x.enum_t}.{x.item}<{x.t}>"
    } elif (x.e == "cast") {
        return "{x.cast_kind}{x.explicit_cast ? "!" : ""}<{x.t}>({shown(x.a)})"
    } elif (x.e == "ref") {
        return x.name
    } elif (x.e == "int_lit") {
        return "{x.v}<{x.t}>"
    } elif (x.e == "sizeof_v") {
        return "sizeof<{x.t}>={int64(x.trait_v)}:{x.of_t}"
    } elif (x.e == "un") {
        return "{x.op}<{x.t}>({shown(x.a)})"
    }
    let op = x.e == "assign" ? "assign{x.op}" : x.op
    return "{op}<{x.t}>({shown(x.a)}, {shown(x.b)})"
}

// the C-IR of unit `text` (named `t.c`): the table's entries, `;`-separated, then `|` and each
// declaration - an anchor its kind, type and place, a global its name, type and `dims`, a function
// its body's expressions; `error: ` and the builder's error, or `parse error: ` and the parser's;
// `library` is the own headers' folder
def private cir_of(text : string; msvc : bool = false; library : string = "") : string {
    var p : CParser
    c_parser_open_text(p, text, "t.c", msvc)
    let u = c_unit(p)
    return "parse error: {p.err}" if (p.failed)
    var r = new CIr
    c_ir_open(*r, msvc ? target_llp64_msvc() : target_lp64_linux(), library)
    var out : array<string>
    if (c_ir_unit(*r, p, u)) {
        out |> push(join([for (t in r.tu.types); entry(t)], "; "))
        for (d in r.tu.decls) {
            if (d.k == "record" || d.k == "enumdef") {
                out |> push("{d.k} {d.t} {d.loc.line}:{d.loc.col}")
            } elif (d.k == "global") {
                out |> push("{d.name}:{d.t}" + (empty(d.dims) ? "" : "[" + join([for (dim in d.dims); "{dim.enum_t}.{dim.item}"], ",") + "]"))
            } elif (d.k == "func" && d.body != null) {
                for (st in d.body.body) {
                    if (st.s == "decl") {
                        out |> push("{st.name}:{st.t}" + (empty(st.dims) ? "" : "[" + join([for (dim in st.dims); "{dim.enum_t}.{dim.item}"], ",") + "]") + (st.init != null ? "={shown(st.init)}" : ""))
                    } elif (st.e != null) {
                        out |> push(shown(st.e))
                    }
                }
            }
        }
    } else {
        out |> push("error: {r.err}")
    }
    let listed = join(out, " | ")
    delete_tu(r.tu)
    unsafe {
        delete r
    }
    return listed
}

[test(description = "a record's slot before its fields' types, so a pointer to it among them resolves; its layout and `packed` verdict; its anchor at its tag, a union's too")]
def test_record_order(t : T?) {
    t |> equal(cir_of("struct P \{ int x; struct P *next; \}; union U \{ char c; short s; \};"),
               "struct P 16/8 \{x:1@0 next:2@8\}; int:32:true:int; ptr:0; union U 2/2 \{c:4@0 s:5@0\}; int:8:false:char; int:16:true:short | record 0 1:8 | record 3 1:44")
}

[test(description = "the definitions among a record's members first, interned and anchored, then the record; an anonymous member a field named \"\" of its record, anchored at its keyword")]
def test_nested(t : T?) {
    t |> equal(cir_of("struct A \{ int k; struct \{ int u; \}; union \{ long l; \} w; \};"),
               "struct  4/4 \{u:1@0\}; int:32:true:int; union  8/8 \{l:3@0\}; int:64:true:long; struct A 16/8 \{k:1@0 :0@4 w:2@8\} | record 0 1:19 | record 2 1:38 | record 4 1:8")
}

[test(description = "a record with no tag named by the typedef that declares it alone; a typedef of a pointer to one leaves it unnamed")]
def test_typedef_names(t : T?) {
    t |> equal(cir_of("typedef struct \{ char c; \} Q, *QP;"),
               "struct Q 1/1 \{c:1@0\}; int:8:false:char; typedef:Q:0; ptr:0; typedef:QP:3 | record 0 1:9")
    t |> equal(cir_of("typedef struct \{ char c; \} *R;"), "struct  1/1 \{c:1@0\}; int:8:false:char; ptr:0; typedef:R:2 | record 0 1:9")
}

[test(description = "a tag used before its one file-scope definition: the definition's fields where the use first reaches the type, the anchor at the definition; one never defined an incomplete record of size -1, anchored nowhere")]
def test_use_before_definition(t : T?) {
    t |> equal(cir_of("typedef struct node node; struct node \{ node *next; double d; \}; struct S *gp; struct S \{ long l; \};"),
               "struct node 16/8 \{next:1@0 d:2@8\}; ptr:0; float:64:double; typedef:node:0; struct S 8/8 \{l:5@0\}; int:64:true:long; ptr:4 | record 0 1:34 | gp:6 | record 4 1:87")
    t |> equal(cir_of("struct Opaque *op; struct Opaque;"), "struct Opaque -1/-1 \{\}; ptr:0 | op:1")
}

[test(description = "a block's tag ends with the block: a later use outside it is a record of its own")]
def test_block_tags(t : T?) {
    t |> equal(cir_of("void f(void) \{ struct L \{ int q; \} l; \} struct L *after;"),
               "void; func:0::false; struct L 4/4 \{q:3@0\}; int:32:true:int; struct L -1/-1 \{\}; ptr:4 | record 2 1:23 | l:2 | after:5")
}

[test(description = "an own header's record built where the header defines it and anchored where the unit first uses it; an incomplete one never anchored")]
def test_library_records(t : T?) {
    let lib = "# 1 \"/lib/time.h\" 1\nstruct tm \{ int tm_sec; long off; \};\ntypedef struct _IO_FILE FILE;\ntypedef struct \{ int quot; \} div_t;\n# 2 \"t.c\" 2\n"
    t |> equal(cir_of(lib + "int h(struct tm *tp, FILE *f, div_t d);\n", false, "/lib/"),
               "int:32:true:int; struct tm 16/8 \{tm_sec:0@0 off:2@8\}; int:64:true:long; ptr:1; struct _IO_FILE -1/-1 \{\}; ptr:4; struct div_t 4/4 \{quot:0@0\}; func:0:3,5,6:false | record 1 2:5 | record 6 2:5")
}

[test(description = "an enum under linux: unsigned int with no negative value, int with one; its items read in order, the one before plus one where none is written, a later one folding an earlier; an anonymous one spelled by its place, one a typedef declares named by it")]
def test_enums_linux(t : T?) {
    t |> equal(cir_of("enum color \{ RED, GREEN = 5, BLUE \}; enum neg \{ N1 = -1, N2 = N1 + 5, N3 = sizeof(int) \}; enum \{ LONE \}; typedef enum \{ TA \} te;"),
               "enum color 'enum color' unsigned \{RED=0,GREEN=5,BLUE=6\}; enum neg 'enum neg' \{N1=-1,N2=4,N3=4\}; enum  'enum (unnamed at t.c:1:91)' unsigned \{LONE=0\}; enum te 'enum te' unsigned \{TA=0\}; typedef:te:3 | enumdef 0 1:6 | enumdef 1 1:43 | enumdef 2 1:91 | enumdef 3 1:114")
}

[test(description = "an enumerator is an int, or under linux the enum's unsigned int when one of its values is past INT_MAX; under msvc every enum is an int, its values wrapped into it")]
def test_enumerator_types(t : T?) {
    let text = "enum big \{ S1 = 1, BIGV = 0x80000000u, S3 \}; int x = S1;"
    t |> equal(cir_of(text), "enum big 'enum big' unsigned \{S1=1,BIGV=2147483648,S3=2147483649\}; int:32:true:int; int:32:false:unsigned int | enumdef 0 1:6 | x:1")
    t |> equal(cir_of("enum big \{ S1 = 1, BIGV = 0x80000000u \}; void f(void) \{ S1; \}"),
               "enum big 'enum big' unsigned \{S1=1,BIGV=2147483648\}; void; func:1::false; int:32:false:unsigned int | enumdef 0 1:6 | 0.S1<3>")
    t |> equal(cir_of("enum big \{ S1 = 1, BIGV = 0x80000000u, S3 \}; void f(void) \{ S3; \}", true),
               "enum big 'enum big' \{S1=1,BIGV=-2147483648,S3=-2147483647\}; void; func:1::false; int:32:true:int | enumdef 0 1:6 | 0.S3<3>")
}

[test(description = "an enum value promotes to its type's integer and an enumerator assigns through IntegralCast; a bit-field narrower than int promotes to int, an unsigned one as wide as int to unsigned int")]
def test_promotions(t : T?) {
    t |> equal(cir_of("enum E \{ A, B \}; struct R \{ int x : 3; unsigned y : 4; enum E e : 2; unsigned w : 32; \}; void g(struct R *p, enum E v) \{ v = B; p->y + 1; p->e + v; p->w + 1; \}"),
               "enum E 'enum E' unsigned \{A=0,B=1\}; struct R 8/4 \{x:2@0/0:3 y:3@0/3:4 e:0@0/7:2 w:3@4/32:32\}; int:32:true:int; int:32:false:unsigned int; void; ptr:1; func:4:5,0:false | enumdef 0 1:6 | record 1 1:25 | assign<0>(v, IntegralCast<0>(0.B<2>)) | add<2>(IntegralCast<2>(LValueToRValue<3>(LValueToRValue<5>(p)->1<3>)), 1<2>) | add<3>(IntegralCast<3>(LValueToRValue<0>(LValueToRValue<5>(p)->2<0>)), IntegralCast<3>(LValueToRValue<0>(v))) | add<3>(LValueToRValue<3>(LValueToRValue<5>(p)->3<3>), IntegralCast<3>(1<2>))")
}

[test(description = "a member through the anonymous members that make it visible, `->` on the first access alone; a member's type takes its record's qualifiers, `volatile` marking the lvalue")]
def test_member_access(t : T?) {
    t |> equal(cir_of("struct A \{ int k; struct \{ int u; \}; \}; void g(struct A *p, volatile struct A v) \{ p->u = 2; v.k; \}"),
               "struct  4/4 \{u:1@0\}; int:32:true:int; struct A 8/4 \{k:1@0 :0@4\}; void; ptr:2; func:3:4,2:false | record 0 1:19 | record 2 1:8 | assign<1>(LValueToRValue<4>(p)->1<0>.0<1>, 2<1>) | LValueToRValue<1>(v.0<1>~)")
}

[test(description = "`dims`: per array level from the outermost, the enumerator a size names alone when its value is the level's count, else 0 and no item; none when no size names one; a field's too")]
def test_dims(t : T?) {
    t |> equal(cir_of("enum A \{ A3 = 3, A2 = 2 \}; int m1[A3][3]; int m2[3][A2]; int m3[A2 + 0]; struct W \{ int n[A2]; \};"),
               "enum A 'enum A' unsigned \{A3=3,A2=2\}; int:32:true:int; array:1:3; array:2:3; array:1:2; array:4:3; struct W 8/4 \{n:4@0[0.A2]\} | enumdef 0 1:6 | m1:3[0.A3,0.] | m2:5[0.,0.A2] | m3:4 | record 6 1:81")
}

[test(description = "`packed` and `aligned(N)` on a record and on a member, `aligned` alone 16; a flexible array member sized 0")]
def test_attributes(t : T?) {
    t |> equal(cir_of("struct P1 \{ char c; int i; \} __attribute__((packed)); struct P2 \{ char c; int i __attribute__((aligned(16))); \}; struct P4 \{ char c; \} __attribute__((aligned)); struct F \{ int n; int d[]; \};"),
               "struct P1 5/1 packed \{c:1@0 i:2@1\}; int:8:false:char; int:32:true:int; struct P2 32/16 packed \{c:1@0 i:2@16\}; struct P4 16/16 packed \{c:1@0\}; struct F 4/4 \{n:2@0 d:6@4\}; array:2:-1 | record 0 1:8 | record 3 1:62 | record 4 1:121 | record 5 1:169")
}

[test(description = "every record and enum construct the builder does not type is refused at its place")]
def test_refusals(t : T?) {
    t |> equal(cir_of("struct S \{ int a; \}; struct S \{ int b; \};"), "error: t.c:1:22: a struct tag defined again is not typed yet")
    t |> equal(cir_of("enum E \{ A \}; enum E \{ B \};"), "error: t.c:1:15: an enum tag defined again is not typed yet")
    t |> equal(cir_of("union U *u; struct U *p;"), "error: t.c:1:13: a struct tag of another kind's is not typed yet")
    t |> equal(cir_of("enum E e;"), "error: t.c:1:1: an enum used before its definition is not typed yet")
    t |> equal(cir_of("void f(struct S \{ int a; \} s);"), "error: t.c:1:8: a struct defined in this place is not typed yet")
    t |> equal(cir_of("struct S \{ int; \};"), "error: t.c:1:12: a member declaration that declares no member is not typed yet")
    t |> equal(cir_of("struct S \{ float f : 3; \};"), "error: t.c:1:18: a bit-field of other than an integer type is not typed yet")
    t |> equal(cir_of("int n; struct S \{ int f : n; \};"), "error: t.c:1:27: a bit-field width other than an integer constant from 0 to 64 is not typed yet")
    t |> equal(cir_of("struct S \{ int a; \} __attribute__((aligned(sizeof(int))));"), "error: t.c:1:36: an `aligned` attribute of other than an integer literal is not typed yet")
    t |> equal(cir_of("enum E \{ A \} __attribute__((packed));"), "error: t.c:1:1: a packed or aligned enum is not typed yet")
    t |> equal(cir_of("int n; enum E \{ A = n \};"), "error: t.c:1:21: an enumerator value other than an integer constant expression is not typed yet")
    t |> equal(cir_of("enum E \{ A = -1, B = 0x80000000u \};"), "error: t.c:1:1: an enum whose values no 32-bit type holds is not typed yet")
    t |> equal(cir_of("enum E \{ A = 0x100000000 \};"), "error: t.c:1:1: an enum whose values no 32-bit type holds is not typed yet")
    t |> equal(cir_of("struct S \{ int a; \}; void f(struct S s) \{ s.b; \}"), "error: t.c:1:43: a member 'b' its record does not have, which is not typed yet")
    t |> equal(cir_of("struct S; void f(struct S *s) \{ s->a; \}"), "error: t.c:1:33: a member access of other than a complete struct or union is not typed yet")
    t |> equal(cir_of("struct S; int n = sizeof(struct S);"), "error: t.c:1:19: sizeof of a type without a size is not typed yet")
    t |> equal(cir_of("struct S \{ struct T t; \};"), "error: t.c:1:21: member `t` has an incomplete type")
    t |> equal(cir_of("struct S \{ int a; \} __attribute__((ms_struct));"), "error: t.c:1:1: an `ms_struct` record is not laid out")
}
