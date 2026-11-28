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
        return "{x.enum_t}.{x.item}<{x.t}>{x.trait_v != 0ul ? "!" : ""}"
    } elif (x.e == "cast") {
        return "{x.cast_kind}{x.explicit_cast ? "!" : ""}<{x.t}>({shown(x.a)})"
    } elif (x.e == "ref") {
        return x.vol ? "{x.name}~" : x.name
    } elif (x.e == "call") {
        return "call<{x.t}>({shown(x.fn)})"
    } elif (x.e == "cond") {
        return "cond<{x.t}>({shown(x.c)}, {shown(x.a)}, {shown(x.b)})"
    } elif (x.e == "index") {
        return "index<{x.t}>({shown(x.base)}, {shown(x.i)}){x.vol ? "~" : ""}"
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
               "struct  4/4 \{u:1@0\}; int:32:true:int; struct A 8/4 \{k:1@0 :0@4\}; void; ptr:2; func:3:4,2:false | record 0 1:19 | record 2 1:8 | assign<1>(LValueToRValue<4>(p)->1<0>.0<1>, 2<1>) | LValueToRValue<1>(v~.0<1>~)")
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

[test(description = "a tag defined again in another scope takes the first free numbered name, the first definition keeping the tag")]
def test_tag_renamed(t : T?) {
    t |> equal(cir_of("int f(void) \{ union D \{ double d; \} a; return 0; \} int g(void) \{ union D \{ long u; \} b; return 0; \}"), "int:32:true:int; func:0::false; union D 8/8 \{d:3@0\}; float:64:double; union D1 8/8 \{u:5@0\}; int:64:true:long | record 2 1:21 | a:2 | 0<0> | record 4 1:72 | b:4 | 0<0>")
}

[test(description = "a block's definition of a tag an outer scope binds shadows it with a record of its own, named as a later definition; a forward declaration's tag completed in its own scope keeps the tag")]
def test_tag_shadowed(t : T?) {
    t |> equal(cir_of("struct T; struct T \{ int x; \}; int main(void) \{ struct T v; \{ struct T \{ int z; \}; \} v.x = 2; return 0; \}"), "struct T 4/4 \{x:1@0\}; int:32:true:int; func:1::false; struct T1 4/4 \{z:1@0\} | record 0 1:18 | record 3 1:70 | v:0 | assign<1>(v.0<1>, 2<1>) | 0<1>")
}

[test(description = "an enum named before its one file-scope definition takes it there; its enumerators bound at the definition")]
def test_enum_before_definition(t : T?) {
    t |> equal(cir_of("typedef enum foo E; enum foo \{ e0, e1 \}; E x = e1;"), "enum foo 'enum foo' unsigned \{e0=0,e1=1\}; typedef:E:0; int:32:true:int | enumdef 0 1:26 | x:0")
}

[test(description = "a volatile array's object is volatile, through a member too; a compound assignment to a bit-field computes in its promoted type")]
def test_volatile_and_bitfield_assignment(t : T?) {
    t |> equal(cir_of("struct S \{ volatile long u[2]; unsigned i : 6; \}; void g(struct S s) \{ s.u[0]; s.i += 3; \}"), "struct S 24/8 \{u:2@0 i:3@16/128:6\}; int:64:true:long; array:1:2; int:32:false:unsigned int; void; func:4:0:false; ptr:1; int:32:true:int | record 0 1:8 | LValueToRValue<1>(index<1>(ArrayToPointerDecay<6>(s.0<2>~), 0<7>)~) | assignadd<3>(s.1<3>, 3<7>)")
}

[test(description = "a bit-field narrower than int promotes to int whatever its type's width, one as wide as int to int or unsigned int, a wider one keeps its type")]
def test_wide_bitfields(t : T?) {
    t |> equal(cir_of("struct W \{ unsigned long a : 3; unsigned long b : 32; unsigned long c : 40; long d : 32; \}; void g(struct W w) \{ -w.a; -w.b; -w.c; -w.d; \}"), "struct W 24/8 \{a:1@0/0:3 b:1@0/3:32 c:1@8/64:40 d:2@16/128:32\}; int:64:false:unsigned long; int:64:true:long; void; func:3:0:false; int:32:true:int; int:32:false:unsigned int | record 0 1:8 | neg<5>(IntegralCast<5>(LValueToRValue<1>(w.0<1>))) | neg<6>(IntegralCast<6>(LValueToRValue<1>(w.1<1>))) | neg<1>(LValueToRValue<1>(w.2<1>)) | neg<5>(IntegralCast<5>(LValueToRValue<2>(w.3<2>)))")
}

[test(description = "a member of a call's record result is read like an lvalue's; a pointer to an enum and one to its integer type make the integer's pointer in a conditional")]
def test_rvalue_member_and_enum_pointers(t : T?) {
    t |> equal(cir_of("struct S \{ int h; \}; struct S f(void); enum e \{ a = -1 \}; int *p; enum e *q; void g(void) \{ f().h; 1 ? q : p; \}"), "struct S 4/4 \{h:1@0\}; int:32:true:int; func:0::false; enum e 'enum e' \{a=-1\}; ptr:1; ptr:3; void; func:6::false; ptr:2 | record 0 1:8 | enumdef 3 1:45 | p:4 | q:5 | LValueToRValue<1>(call<0>(FunctionToPointerDecay<8>(f)).0<1>) | cond<4>(1<1>, BitCast<4>(LValueToRValue<5>(q)), LValueToRValue<4>(p))")
}

[test(description = "a record's member may name a typedef the unit declares before the record's definition and after its first use")]
def test_typedef_ahead(t : T?) {
    t |> equal(cir_of("typedef struct P P; typedef unsigned char u8; struct P \{ u8 b; P *next; \};"), "struct P 16/8 \{b:1@0 next:2@8\}; int:8:false:unsigned char; ptr:0; typedef:P:0; typedef:u8:1 | record 0 1:54")
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
    t |> equal(cir_of("struct S \{ int a; \} __attribute__((ms_struct));"), "error: t.c:1:36: the attribute 'ms_struct' is not typed yet, which Dumper A neither drops nor reads")
    t |> equal(cir_of("int f(void) \{ enum E \{ A \} a; return 0; \} enum E \{ B \};"), "error: t.c:1:43: an enum tag defined again in another scope is not typed yet")
    t |> equal(cir_of("struct __jmp_buf_tag \{ int a; \};"), "")
}

[test(description = "a record built at an earlier use in a block reads its members in its definition's file scope: the file's typedef, tag and enumerator, not the block's")]
def test_early_scope(t : T?) {
    t |> equal(cir_of("typedef int T; int f(void)\{ typedef double T; struct S *p = 0; return p == 0; \} struct S \{ T x; \}; struct S gs;"), "int:32:true:int; typedef:T:0; func:0::false; float:64:double; struct S 4/4 \{x:0@0\}; ptr:4 | p:5=NullToPointer<5>(0<0>) | eq<0>(LValueToRValue<5>(p), NullToPointer<5>(0<0>)) | record 4 1:88 | gs:4")
    t |> equal(cir_of("struct In \{int i;\}; int f(void)\{ struct In \{double d;\}; struct S *p = 0; return p == 0; \} struct S \{ struct In in; \}; struct S gs;"), "struct In 4/4 \{i:1@0\}; int:32:true:int; func:1::false; struct In1 8/8 \{d:4@0\}; float:64:double; struct S 4/4 \{in:0@0\}; ptr:5 | record 0 1:8 | record 3 1:41 | p:6=NullToPointer<6>(0<1>) | eq<1>(LValueToRValue<6>(p), NullToPointer<6>(0<1>)) | record 5 1:98 | gs:5")
    t |> equal(cir_of("enum \{N=2\}; int f(void)\{ enum \{N=5\}; struct S *p = 0; return p == 0; \} struct S \{ int a[N]; \}; struct S gs;"), "enum  'enum (unnamed at t.c:1:1)' unsigned \{N=2\}; int:32:true:int; func:1::false; enum  'enum (unnamed at t.c:1:26)' unsigned \{N=5\}; struct S 8/4 \{a:5@0[0.N]\}; array:1:2; ptr:4 | enumdef 0 1:1 | enumdef 3 1:26 | p:6=NullToPointer<6>(0<1>) | eq<1>(LValueToRValue<6>(p), NullToPointer<6>(0<1>)) | record 4 1:79 | gs:4")
}

[test(description = "while an enum's body is read an enumerator int does not hold has its initializer's type, one with none the one before's; under msvc an initializer is an int at once")]
def test_enum_body_types(t : T?) {
    t |> equal(cir_of("enum E \{ ALL = 0xFFFFFFFF, Q = ALL / 16, R = (ALL > 0) \}; int arr[R + 1];"), "enum E 'enum E' unsigned \{ALL=4294967295,Q=268435455,R=1\}; int:32:true:int; array:1:2 | enumdef 0 1:6 | arr:2")
    t |> equal(cir_of("enum E \{ ALL = 0xFFFFFFFF, Q = ALL / 16, R = (ALL > 0) \}; int arr[R + 1];", true), "enum E 'enum E' \{ALL=-1,Q=0,R=0\}; int:32:true:int; array:1:1 | enumdef 0 1:6 | arr:2")
    t |> equal(cir_of("enum E2 \{ A = 2147483647, B, C = B / 2 \}; int arr2[C > 0 ? 1 : 2];"), "enum E2 'enum E2' unsigned \{A=2147483647,B=2147483648,C=1073741824\}; int:32:true:int; array:1:1 | enumdef 0 1:6 | arr2:2")
    t |> equal(cir_of("enum E2 \{ A = 2147483647, B, C = B / 2 \}; int arr2[C > 0 ? 1 : 2];", true), "enum E2 'enum E2' \{A=2147483647,B=-2147483648,C=1073741824\}; int:32:true:int; array:1:1 | enumdef 0 1:6 | arr2:2")
    t |> equal(cir_of("enum E3 \{ L = 4294967295, M = L / 16, N = (L > 0) \}; int arr3[N + 1];"), "enum E3 'enum E3' unsigned \{L=4294967295,M=268435455,N=1\}; int:32:true:int; array:1:2 | enumdef 0 1:6 | arr3:2")
    t |> equal(cir_of("enum E3 \{ L = 4294967295, M = L / 16, N = (L > 0) \}; int arr3[N + 1];", true), "enum E3 'enum E3' \{L=-1,M=0,N=0\}; int:32:true:int; array:1:1 | enumdef 0 1:6 | arr3:2")
}

[test(description = "a bit-field promotes through an assignment, a compound assignment, a comma's right operand and a prefix ++ or --, as clang's getSourceBitField sees it")]
def test_bitfield_sources(t : T?) {
    t |> equal(cir_of("struct S \{ unsigned b : 3; \} s; long f(void)\{ return (s.b = 7) - 8; \} long g(void)\{ return (0, s.b) - 8; \} long h(void)\{ return ++s.b - 8; \} long k(void)\{ return (s.b += 1) - 8; \}"), "struct S 4/4 \{b:1@0/0:3\}; int:32:false:unsigned int; int:64:true:long; func:2::false; int:32:true:int | record 0 1:8 | s:0 | IntegralCast<2>(sub<4>(IntegralCast<4>(assign<1>(s.0<1>, IntegralCast<1>(7<4>))), 8<4>)) | IntegralCast<2>(sub<4>(IntegralCast<4>(<1>(0<4>, LValueToRValue<1>(s.0<1>))), 8<4>)) | IntegralCast<2>(sub<4>(IntegralCast<4>(preinc<1>(s.0<1>)), 8<4>)) | IntegralCast<2>(sub<4>(IntegralCast<4>(assignadd<1>(s.0<1>, 1<4>)), 8<4>))")
    t |> equal(cir_of("struct S \{ unsigned b : 3; long l : 40; \} s; long f(void)\{ return (s.l = 1) - 8; \} long g(void)\{ return --s.b - 8; \} long h(void)\{ return s.b++ - 8; \}"), "struct S 8/8 \{b:1@0/0:3 l:2@0/3:40\}; int:32:false:unsigned int; int:64:true:long; func:2::false; int:32:true:int | record 0 1:8 | s:0 | sub<2>(assign<2>(s.1<2>, IntegralCast<2>(1<4>)), IntegralCast<2>(8<4>)) | IntegralCast<2>(sub<4>(IntegralCast<4>(predec<1>(s.0<1>)), 8<4>)) | IntegralCast<2>(sub<1>(postinc<1>(s.0<1>), IntegralCast<1>(8<4>)))")
}

[test(description = "a record with no tag is named by a typedef's first declarator that is the name alone, parenthesized too, also when built early at a use; a qualified typedef names none")]
def test_untagged_names(t : T?) {
    t |> equal(cir_of("typedef struct N N; typedef struct \{ int a; \} Q; struct N \{ Q q; int v; \}; N gn;"), "struct N 8/4 \{q:1@0 v:2@4\}; struct Q 4/4 \{a:2@0\}; int:32:true:int; typedef:N:0; typedef:Q:1 | record 1 1:29 | record 0 1:57 | gn:0")
    t |> equal(cir_of("typedef const struct \{ int a; \} CQ; CQ cq; typedef volatile enum \{ E1 \} VE; VE ve;"), "struct  4/4 \{a:1@0\}; int:32:true:int; typedef:CQ:0; enum  'enum (unnamed at t.c:1:61)' unsigned \{E1=0\}; typedef:VE:3 | record 0 1:15 | cq:0 | enumdef 3 1:61 | ve:3")
    t |> equal(cir_of("typedef struct \{ int a; \} (PQ); PQ pq;"), "struct PQ 4/4 \{a:1@0\}; int:32:true:int; typedef:PQ:0 | record 0 1:9 | pq:0")
    t |> equal(cir_of("typedef struct \{ int a; \} *P, Q; Q q; P p;"), "struct Q 4/4 \{a:1@0\}; int:32:true:int; ptr:0; typedef:P:2; typedef:Q:0 | record 0 1:9 | q:0 | p:2")
}

[test(description = "numbered tags as Dumper A gives them: definitions of one struct or union spelling in source order, avoiding every tag, typedef, variable and function name of the unit but parameters")]
def test_numbered_names(t : T?) {
    t |> equal(cir_of("struct S *gp; int f(void)\{ struct S \{int a;\} s; s.a = 1; return s.a; \} struct S \{char c;\}; struct S gs;"), "struct S1 1/1 \{c:1@0\}; int:8:false:char; ptr:0; int:32:true:int; func:3::false; struct S 4/4 \{a:3@0\} | gp:2 | record 5 1:35 | s:5 | assign<3>(s.0<3>, 1<3>) | LValueToRValue<3>(s.0<3>) | record 0 1:79 | gs:0")
    t |> equal(cir_of("struct T \{ char c; \}; int f(void)\{ struct T \{int a;\} t; t.a = 1; return t.a; \} struct T1 \{ int z; \}; struct T gt; struct T1 g1;"), "struct T 1/1 \{c:1@0\}; int:8:false:char; int:32:true:int; func:2::false; struct T2 4/4 \{a:2@0\}; struct T1 4/4 \{z:2@0\} | record 0 1:8 | record 4 1:43 | t:4 | assign<2>(t.0<2>, 1<2>) | LValueToRValue<2>(t.0<2>) | record 5 1:87 | gt:0 | g1:5")
    t |> equal(cir_of("struct T \{ char c; \}; int f(void)\{ struct T \{int a;\} t; t.a = 1; return t.a; \} typedef long T1; T1 g1; struct T gt;"), "struct T 1/1 \{c:1@0\}; int:8:false:char; int:32:true:int; func:2::false; struct T2 4/4 \{a:2@0\}; int:64:true:long; typedef:T1:5 | record 0 1:8 | record 4 1:43 | t:4 | assign<2>(t.0<2>, 1<2>) | LValueToRValue<2>(t.0<2>) | g1:5 | gt:0")
    t |> equal(cir_of("struct T \{ char c; \} gt; int f(int T1)\{ struct T \{double d;\} t; t.d = T1; return (int)t.d; \}"), "struct T 1/1 \{c:1@0\}; int:8:false:char; int:32:true:int; func:2:2:false; struct T1 8/8 \{d:5@0\}; float:64:double | record 0 1:8 | gt:0 | record 4 1:48 | t:4 | assign<5>(t.0<5>, IntegralToFloating<5>(LValueToRValue<2>(T1))) | FloatingToIntegral!<2>(LValueToRValue<5>(t.0<5>))")
    t |> equal(cir_of("struct S \{ int a; \} gs; int f(void)\{ union S \{ int a; char c; \} u; u.a = 1; return u.a; \}"), "struct S 4/4 \{a:1@0\}; int:32:true:int; func:1::false; union S 4/4 \{a:1@0 c:4@0\}; int:8:false:char | record 0 1:8 | gs:0 | record 3 1:44 | u:3 | assign<1>(u.0<1>, 1<1>) | LValueToRValue<1>(u.0<1>)")
    t |> equal(cir_of("enum S \{ SA \} ge; int f(void)\{ struct S \{ int a; \} s; s.a = 1; return s.a; \}"), "enum S 'enum S' unsigned \{SA=0\}; int:32:true:int; func:1::false; struct S 4/4 \{a:1@0\} | enumdef 0 1:6 | ge:0 | record 3 1:39 | s:3 | assign<1>(s.0<1>, 1<1>) | LValueToRValue<1>(s.0<1>)")
    t |> equal(cir_of("struct S \{ int a; \} gs; int f(void)\{ int S1 = 2; struct S \{ char c; \} s; s.c = 1; return s.c + S1; \}"), "struct S 4/4 \{a:1@0\}; int:32:true:int; func:1::false; struct S2 1/1 \{c:4@0\}; int:8:false:char | record 0 1:8 | gs:0 | record 3 1:57 | S1:1=2<1> | s:3 | assign<4>(s.0<4>, IntegralCast<4>(1<1>)) | add<1>(IntegralCast<1>(LValueToRValue<4>(s.0<4>)), LValueToRValue<1>(S1))")
    t |> equal(cir_of("struct U \{ int a; \} gu; int f(void)\{ struct U \{ char c; \} u; u.c = 1; return u.c; \} int g(void)\{ struct U \{ short h; \} v; v.h = 1; return v.h; \}"), "struct U 4/4 \{a:1@0\}; int:32:true:int; func:1::false; struct U1 1/1 \{c:4@0\}; int:8:false:char; struct U2 2/2 \{h:6@0\}; int:16:true:short | record 0 1:8 | gu:0 | record 3 1:45 | u:3 | assign<4>(u.0<4>, IntegralCast<4>(1<1>)) | IntegralCast<1>(LValueToRValue<4>(u.0<4>)) | record 5 1:105 | v:5 | assign<6>(v.0<6>, IntegralCast<6>(1<1>)) | IntegralCast<1>(LValueToRValue<6>(v.0<6>))")
    t |> equal(cir_of("struct T \{ char c; \} gt; int T1(void)\{ struct T \{ int a; \} t; t.a = 1; return t.a; \}"), "struct T 1/1 \{c:1@0\}; int:8:false:char; int:32:true:int; func:2::false; struct T2 4/4 \{a:2@0\} | record 0 1:8 | gt:0 | record 4 1:47 | t:4 | assign<2>(t.0<2>, 1<2>) | LValueToRValue<2>(t.0<2>)")
}

[test(description = "a level with no size shifts the sizes after it to the levels before theirs; a size whose value is not its level's count names none")]
def test_dims_unsized(t : T?) {
    t |> equal(cir_of("enum \{ N = 4 \}; int a[][N] = \{ \{1\}, \{2\} \}; extern int e[][N]; int f(void)\{ return e[0][1]; \}"), "enum  'enum (unnamed at t.c:1:1)' unsigned \{N=4\}; int:32:true:int; array:1:4; array:2:2; array:2:-1; func:1::false; ptr:1; ptr:2 | enumdef 0 1:1 | a:3 | e:4 | LValueToRValue<1>(index<1>(ArrayToPointerDecay<6>(index<2>(ArrayToPointerDecay<7>(e), 0<1>)), 1<1>))")
    t |> equal(cir_of("enum \{ N = 4 \}; struct F \{ int n; int d[][N]; \}; struct F *fp; int f(void)\{ return fp->n; \}"), "enum  'enum (unnamed at t.c:1:1)' unsigned \{N=4\}; struct F 4/4 \{n:2@0 d:4@4\}; int:32:true:int; array:2:4; array:3:-1; ptr:1; func:2::false | enumdef 0 1:1 | record 1 1:24 | fp:5 | LValueToRValue<2>(LValueToRValue<5>(fp)->0<2>)")
}

[test(description = "a record defined in a type name inside a member's array size is refused at its keyword")]
def test_type_name_definition(t : T?) {
    t |> equal(cir_of("struct S \{ char a[sizeof(struct Z \{ int a; long b; \})]; \}; struct S gs;"), "error: t.c:1:26: a struct defined in this place is not typed yet")
}

[test(description = "a pointer to an enum assigns to one to its integer type, and under msvc, where the enum is an int, to one to unsigned int with the pointer-sign warning")]
def test_enum_pointer_assign(t : T?) {
    t |> equal(cir_of("enum E \{ A \}; unsigned f(unsigned *p); unsigned g(void) \{ enum E e = A; return f(&e); \}"), "enum E 'enum E' unsigned \{A=0\}; int:32:false:unsigned int; ptr:1; func:1:2:false; func:1::false; int:32:true:int; ptr:3; ptr:0 | enumdef 0 1:6 | e:0=IntegralCast<0>(0.A<5>) | call<1>(FunctionToPointerDecay<6>(f))")
    t |> equal(cir_of("enum E \{ A \}; unsigned f(unsigned *p); unsigned g(void) \{ enum E e = A; return f(&e); \}", true), "enum E 'enum E' \{A=0\}; int:32:false:unsigned int; ptr:1; func:1:2:false; func:1::false; int:32:true:int; ptr:3; ptr:0 | enumdef 0 1:6 | e:0=IntegralCast<0>(0.A<5>) | call<1>(FunctionToPointerDecay<6>(f))")
}

