options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require ../c_layout.das
require ../../converter/cir.das
require ../../converter/bit_units.das

//! `frontend/c_layout.das`: every rule of the `linux` record layout with clang 22's numbers for
//! `x86_64-unknown-linux-gnu`, each case named by its record in `compare/layout/fixtures/rules.c`,
//! whose C it quotes; the refusals with their messages; and the layout written into the C-IR with
//! the `packed` verdict of the layout law.

def private plain(name : string; size : int64; align : int) : CLayoutMember => CLayoutMember(name = name, size = size, align = align)

def private bits(name : string; size : int64; width : int) : CLayoutMember => CLayoutMember(name = name, size = size, align = int(size), is_bitfield = true, width = width)

def private flexible(name : string; align : int) : CLayoutMember => CLayoutMember(name = name, size = 1024l, align = align, is_flexible = true)

def private packed(m : CLayoutMember) : CLayoutMember {
    var r = m
    r.packed = true
    return r
}

def private aligned(m : CLayoutMember; n : int) : CLayoutMember {
    var r = m
    r.aligned = n
    return r
}

def private record(var members : array<CLayoutMember>) : CLayoutRecord => CLayoutRecord(dialect = "linux", members <- members)

def private union_of(var members : array<CLayoutMember>) : CLayoutRecord => CLayoutRecord(dialect = "linux", is_union = true, members <- members)

def private with_packed(var rec : CLayoutRecord) : CLayoutRecord {
    rec.packed = true
    return <- rec
}

def private with_aligned(var rec : CLayoutRecord; n : int) : CLayoutRecord {
    rec.aligned = n
    return <- rec
}

def private with_pack(var rec : CLayoutRecord; n : int) : CLayoutRecord {
    rec.pack = n
    return <- rec
}

// the layout as `size S align A at o1 o2 ...` (bit offsets), or the refusal's text
def private laid(rec : CLayoutRecord) : string {
    let layout <- c_record_layout(rec)
    if (layout.failed) {
        return layout.err
    }
    let offsets = join([for (o in layout.offsets); "{o}"], " ")
    return "size {layout.size} align {layout.align} at {offsets}"
}

[test(description = "plain members sit at their type's alignment and the size is padded to the record's alignment")]
def test_natural(t : T?) {
    t |> run("Natural, Tail, LongDouble, Array, Nested") @(t : T?) {
        // struct Natural { char a; int b; char c; };
        t |> equal(laid(record([plain("a", 1l, 1), plain("b", 4l, 4), plain("c", 1l, 1)])), "size 12 align 4 at 0 32 64")
        // struct Tail { double d; char c; };
        t |> equal(laid(record([plain("d", 8l, 8), plain("c", 1l, 1)])), "size 16 align 8 at 0 64")
        // struct LongDouble { char c; long double x; };
        t |> equal(laid(record([plain("c", 1l, 1), plain("x", 16l, 16)])), "size 32 align 16 at 0 128")
        // struct Array { char c; short s[3]; };
        t |> equal(laid(record([plain("c", 1l, 1), plain("s", 6l, 2)])), "size 8 align 2 at 0 16")
        // struct Nested { char c; struct Natural n; };
        t |> equal(laid(record([plain("c", 1l, 1), plain("n", 12l, 4)])), "size 16 align 4 at 0 32")
    }
    t |> run("Empty is 0 bytes, as GNU C has it") @(t : T?) {
        // struct Empty {};
        t |> equal(laid(record(array<CLayoutMember>())), "size 0 align 1 at ")
    }
    t |> run("Anonymous: an anonymous member is laid out as a member of its record's type") @(t : T?) {
        // struct Anonymous { int x; union { char c; short s; }; struct { int y; } named; };
        t |> equal(laid(record([plain("x", 4l, 4), plain("", 2l, 2), plain("named", 4l, 4)])), "size 12 align 4 at 0 32 64")
    }
}

[test(description = "bitfields pack into units of their declared type and move to the next unit only when they would cross one")]
def test_bitfields(t : T?) {
    t |> run("Bits, Straddle, CharBits, WideStraddle, WideFits") @(t : T?) {
        // struct Bits { unsigned a : 3; unsigned b : 5; unsigned c : 24; char d; };
        t |> equal(laid(record([bits("a", 4l, 3), bits("b", 4l, 5), bits("c", 4l, 24), plain("d", 1l, 1)])), "size 8 align 4 at 0 3 8 32")
        // struct Straddle { char c; int x : 30; };
        t |> equal(laid(record([plain("c", 1l, 1), bits("x", 4l, 30)])), "size 8 align 4 at 0 32")
        // struct CharBits { char a : 4; char b : 6; };
        t |> equal(laid(record([bits("a", 1l, 4), bits("b", 1l, 6)])), "size 2 align 1 at 0 8")
        // struct WideStraddle { int a : 30; long long b : 40; };
        t |> equal(laid(record([bits("a", 4l, 30), bits("b", 8l, 40)])), "size 16 align 8 at 0 64")
        // struct WideFits { int a : 20; long long b : 40; };
        t |> equal(laid(record([bits("a", 4l, 20), bits("b", 8l, 40)])), "size 8 align 8 at 0 20")
    }
    t |> run("Bools and EnumBits: `_Bool` is a 1-byte unit, an enum its 4-byte type's") @(t : T?) {
        // struct Bools { _Bool a : 1; _Bool b : 1; char c; };
        t |> equal(laid(record([bits("a", 1l, 1), bits("b", 1l, 1), plain("c", 1l, 1)])), "size 2 align 1 at 0 1 8")
        // struct EnumBits { enum E e : 2; char c; };
        t |> equal(laid(record([bits("e", 4l, 2), plain("c", 1l, 1)])), "size 4 align 4 at 0 8")
    }
}

[test(description = "a zero-width bitfield moves the next member to its type's alignment and, unnamed like every unnamed bitfield, leaves the record's alignment alone")]
def test_unnamed_bitfields(t : T?) {
    t |> run("ZeroWidth, ZeroAfterBits, ZeroTail") @(t : T?) {
        // struct ZeroWidth { char a; int : 0; char b; };
        t |> equal(laid(record([plain("a", 1l, 1), bits("", 4l, 0), plain("b", 1l, 1)])), "size 5 align 1 at 0 32 32")
        // struct ZeroAfterBits { char x : 3; long long : 0; char d; };
        t |> equal(laid(record([bits("x", 1l, 3), bits("", 8l, 0), plain("d", 1l, 1)])), "size 9 align 1 at 0 64 64")
        // struct ZeroTail { char c; int : 0; };
        t |> equal(laid(record([plain("c", 1l, 1), bits("", 4l, 0)])), "size 4 align 1 at 0 32")
    }
    t |> run("Unnamed, UnnamedWide, UnnamedOnly: an unnamed bitfield takes bits and adds no alignment") @(t : T?) {
        // struct Unnamed { char a; int : 20; };
        t |> equal(laid(record([plain("a", 1l, 1), bits("", 4l, 20)])), "size 4 align 1 at 0 8")
        // struct UnnamedWide { char c; long long : 40; };
        t |> equal(laid(record([plain("c", 1l, 1), bits("", 8l, 40)])), "size 6 align 1 at 0 8")
        // struct UnnamedOnly { int : 3; };
        t |> equal(laid(record([bits("", 4l, 3)])), "size 1 align 1 at 0")
    }
}

[test(description = "`packed` on the record or a member drops the member's alignment to 1, a zero-width bitfield's excepted")]
def test_packed(t : T?) {
    t |> run("Packed, PackedMember, PackedNested") @(t : T?) {
        // struct __attribute__((packed)) Packed { char a; int b; short c; };
        t |> equal(laid(with_packed(record([plain("a", 1l, 1), plain("b", 4l, 4), plain("c", 2l, 2)]))), "size 7 align 1 at 0 8 40")
        // struct PackedMember { char a; int b __attribute__((packed)); char c; };
        t |> equal(laid(record([plain("a", 1l, 1), packed(plain("b", 4l, 4)), plain("c", 1l, 1)])), "size 6 align 1 at 0 8 40")
        // struct __attribute__((packed)) PackedNested { char c; struct Natural n; };
        t |> equal(laid(with_packed(record([plain("c", 1l, 1), plain("n", 12l, 4)]))), "size 13 align 1 at 0 8")
    }
    t |> run("PackedBits, PackedCharBits: a packed bitfield never moves to a unit; PackedZero: a zero-width one still aligns") @(t : T?) {
        // struct __attribute__((packed)) PackedBits { char c; int x : 30; };
        t |> equal(laid(with_packed(record([plain("c", 1l, 1), bits("x", 4l, 30)]))), "size 5 align 1 at 0 8")
        // struct __attribute__((packed)) PackedCharBits { char a : 3; char b : 7; };
        t |> equal(laid(with_packed(record([bits("a", 1l, 3), bits("b", 1l, 7)]))), "size 2 align 1 at 0 3")
        // struct __attribute__((packed)) PackedZero { char a; int : 0; char b; };
        t |> equal(laid(with_packed(record([plain("a", 1l, 1), bits("", 4l, 0), plain("b", 1l, 1)]))), "size 5 align 1 at 0 32 32")
    }
}

[test(description = "`aligned` raises an alignment and never lowers one; packed then aligned is the attribute's")]
def test_aligned(t : T?) {
    t |> run("AlignedRecord, AlignedMember, AlignedLower, PackedAligned, AlignedBits") @(t : T?) {
        // struct __attribute__((aligned(16))) AlignedRecord { int a; };
        t |> equal(laid(with_aligned(record([plain("a", 4l, 4)]), 16)), "size 16 align 16 at 0")
        // struct AlignedMember { char a; int b __attribute__((aligned(8))); };
        t |> equal(laid(record([plain("a", 1l, 1), aligned(plain("b", 4l, 4), 8)])), "size 16 align 8 at 0 64")
        // struct AlignedLower { char a; int b __attribute__((aligned(2))); };
        t |> equal(laid(record([plain("a", 1l, 1), aligned(plain("b", 4l, 4), 2)])), "size 8 align 4 at 0 32")
        // struct __attribute__((packed)) PackedAligned { char a; int b __attribute__((aligned(2))); };
        t |> equal(laid(with_packed(record([plain("a", 1l, 1), aligned(plain("b", 4l, 4), 2)]))), "size 6 align 2 at 0 16")
        // struct AlignedBits { char c; int x : 3 __attribute__((aligned(4))); };
        t |> equal(laid(record([plain("c", 1l, 1), aligned(bits("x", 4l, 3), 4)])), "size 8 align 4 at 0 32")
    }
    t |> run("TypedefAligned, TypedefLowered: a typedef's `aligned` is the type's alignment the caller passes") @(t : T?) {
        // typedef int int_a8 __attribute__((aligned(8))); struct TypedefAligned { char c; int_a8 x; };
        t |> equal(laid(record([plain("c", 1l, 1), plain("x", 4l, 8)])), "size 16 align 8 at 0 64")
        // typedef int int_a1 __attribute__((aligned(1))); struct TypedefLowered { char c; int_a1 x; };
        t |> equal(laid(record([plain("c", 1l, 1), plain("x", 4l, 1)])), "size 5 align 1 at 0 8")
    }
}

[test(description = "`#pragma pack(n)` caps every member's alignment, an `aligned` one's too, and stops a bitfield moving to a unit; the record's own `aligned` stays")]
def test_pragma_pack(t : T?) {
    t |> run("Pack2, Pack2Bits") @(t : T?) {
        // #pragma pack(2) struct Pack2 { char a; int b; char c; };
        t |> equal(laid(with_pack(record([plain("a", 1l, 1), plain("b", 4l, 4), plain("c", 1l, 1)]), 2)), "size 8 align 2 at 0 16 48")
        // #pragma pack(2) struct Pack2Bits { char a; int b : 20; int c; };
        t |> equal(laid(with_pack(record([plain("a", 1l, 1), bits("b", 4l, 20), plain("c", 4l, 4)]), 2)), "size 8 align 2 at 0 8 32")
    }
    t |> run("Pack1Aligned, Pack1Record, Pack1Zero") @(t : T?) {
        // #pragma pack(1) struct Pack1Aligned { char a; int b __attribute__((aligned(8))); };
        t |> equal(laid(with_pack(record([plain("a", 1l, 1), aligned(plain("b", 4l, 4), 8)]), 1)), "size 5 align 1 at 0 8")
        // #pragma pack(1) struct __attribute__((aligned(8))) Pack1Record { char a; int b; };
        t |> equal(laid(with_aligned(with_pack(record([plain("a", 1l, 1), plain("b", 4l, 4)]), 1), 8)), "size 8 align 8 at 0 8")
        // #pragma pack(1) struct Pack1Zero { char a; int : 0; char b; };
        t |> equal(laid(with_pack(record([plain("a", 1l, 1), bits("", 4l, 0), plain("b", 1l, 1)]), 1)), "size 5 align 1 at 0 32 32")
    }
    t |> run("Pack2PackedBits: under `#pragma pack` a packed bitfield aligns by its type up to the pack") @(t : T?) {
        // #pragma pack(2) struct __attribute__((packed)) Pack2PackedBits { char c; int x : 20; };
        t |> equal(laid(with_pack(with_packed(record([plain("c", 1l, 1), bits("x", 4l, 20)])), 2)), "size 4 align 2 at 0 8")
    }
    t |> run("Pack2AlignedBits, Pack4AlignedBits: a bitfield's own `aligned` places it only up to the pack") @(t : T?) {
        // #pragma pack(2) struct Pack2AlignedBits { char c; int x : 3 __attribute__((aligned(4))); };
        t |> equal(laid(with_pack(record([plain("c", 1l, 1), aligned(bits("x", 4l, 3), 4)]), 2)), "size 2 align 2 at 0 8")
        // #pragma pack(4) struct Pack4AlignedBits { char c; int x : 3 __attribute__((aligned(4))); };
        t |> equal(laid(with_pack(record([plain("c", 1l, 1), aligned(bits("x", 4l, 3), 4)]), 4)), "size 8 align 4 at 0 32")
    }
}

[test(description = "a union holds every member at 0, its size the largest member rounded to its alignment")]
def test_unions(t : T?) {
    t |> run("Union, PackedUnion, UnionBits, UnionUnnamed") @(t : T?) {
        // union Union { char a; int b : 9; long double ld; };
        t |> equal(laid(union_of([plain("a", 1l, 1), bits("b", 4l, 9), plain("ld", 16l, 16)])), "size 16 align 16 at 0 0 0")
        // union __attribute__((packed)) PackedUnion { char a; int b; };
        t |> equal(laid(with_packed(union_of([plain("a", 1l, 1), plain("b", 4l, 4)]))), "size 4 align 1 at 0 0")
        // union UnionBits { char a; int b : 9; };
        t |> equal(laid(union_of([plain("a", 1l, 1), bits("b", 4l, 9)])), "size 4 align 4 at 0 0")
        // union UnionUnnamed { char a; int : 9; };
        t |> equal(laid(union_of([plain("a", 1l, 1), bits("", 4l, 9)])), "size 2 align 1 at 0 0")
    }
}

[test(description = "a flexible array member adds no bytes but its alignment")]
def test_flexible(t : T?) {
    t |> run("Flexible, FlexibleChar") @(t : T?) {
        // struct Flexible { char c; double d[]; };
        t |> equal(laid(record([plain("c", 1l, 1), flexible("d", 8)])), "size 8 align 8 at 0 64")
        // struct FlexibleChar { int n; char s[]; };
        t |> equal(laid(record([plain("n", 4l, 4), flexible("s", 1)])), "size 4 align 4 at 0 32")
    }
}

[test(description = "what the layout does not take is refused at its place, never laid out by guess")]
def test_refusals(t : T?) {
    t |> run("the msvc dialect, an unknown dialect and an ms_struct record") @(t : T?) {
        var rec = record([plain("a", 1l, 1)])
        rec.at = "r.c:1:8"
        rec.dialect = "msvc"
        t |> equal(laid(rec), "r.c:1:8: the msvc record layout is not implemented")
        rec.dialect = "win"
        t |> equal(laid(rec), "r.c:1:8: unknown dialect 'win': linux or msvc")
        rec.dialect = "linux"
        rec.ms_struct = true
        t |> equal(laid(rec), "r.c:1:8: an `ms_struct` record is not laid out")
    }
    t |> run("a pack or record alignment that is no power of two") @(t : T?) {
        t |> equal(laid(with_pack(record([plain("a", 1l, 1)]), 3)), "`#pragma pack(3)` is not a power of two")
        t |> equal(laid(with_aligned(record([plain("a", 1l, 1)]), 6)), "`aligned(6)` is not a power of two")
    }
    t |> run("a vector or 128-bit member, at the member's place, else the record's") @(t : T?) {
        var vec = plain("v", 16l, 16)
        vec.type_class = CLayoutClass.vector
        vec.at = "r.c:2:3"
        t |> equal(laid(record([vec])), "r.c:2:3: member `v` has a vector type, which the C-IR has no type for")
        var wide = plain("", 16l, 16)
        wide.type_class = CLayoutClass.int128
        var rec = record([wide])
        rec.at = "r.c:1:8"
        t |> equal(laid(rec), "r.c:1:8: an unnamed member has a 128-bit integer type, which the C-IR has no type for")
    }
    t |> run("a malformed member: alignment, `aligned`, incomplete type, flexible array not last, bitfield width") @(t : T?) {
        t |> equal(laid(record([plain("a", 4l, 3)])), "member `a` has an alignment of 3, not a power of two")
        t |> equal(laid(record([plain("a", 4l, 0)])), "member `a` has an alignment of 0, not a power of two")
        t |> equal(laid(record([aligned(plain("a", 4l, 4), 12)])), "member `a` is `aligned(12)`, not a power of two")
        t |> equal(laid(record([plain("a", -1l, 4)])), "member `a` has an incomplete type")
        t |> equal(laid(record([flexible("d", 8), plain("c", 1l, 1)])), "member `d`, an array of unknown size, is not the last member")
        var flex_bits = flexible("f", 4)
        flex_bits.is_bitfield = true
        t |> equal(laid(record([flex_bits])), "member `f`, an array of unknown size, is not the last member")
        t |> equal(laid(record([bits("b", 4l, 33)])), "member `b` is 33 bits wide, outside its type of 32 bits")
        t |> equal(laid(record([bits("b", 4l, -1)])), "member `b` is -1 bits wide, outside its type of 32 bits")
        t |> equal(laid(record([bits("b", 4l, 0)])), "member `b` is a named bitfield of width 0")
    }
}

// a unit of `int` (type 0), `char` (1), `short` (2) and one struct (3) of `fields`
def private unit_with(var fields : array<CirField>) : CirTu {
    return <- CirTu(target = CirTarget(triple = "x86_64-unknown-linux-gnu", int_w = 32, long_w = 64, llong_w = 64, ptr_w = 64),
                    types <- [CirType(k = "int", w = 32, is_signed = true), CirType(k = "int", w = 8), CirType(k = "int", w = 16, is_signed = true),
                              CirType(k = "struct", name = "S", fields <- fields)])
}

// record 3 of `tu` laid out by `rec` and written in: `packed P size S align A at off/bit_off ...`,
// or the error
def private into_cir(var tu : CirTu; rec : CLayoutRecord) : string {
    var memo : LayoutMemo
    var err : string
    let layout <- c_record_layout(rec)
    if (!c_layout_into_cir(tu, memo, 3, layout, err)) {
        return err
    }
    let at = join([for (f in tu.types[3].fields); "{f.off}/{f.bit_off}"], " ")
    return "packed {tu.types[3].packed} size {tu.types[3].size} align {tu.types[3].align} at {at}"
}

[test(description = "a layout written into the C-IR sets size, alignment, every field's offsets, and `packed` by the layout law")]
def test_into_cir(t : T?) {
    t |> run("Natural is no packed record, Packed is one") @(t : T?) {
        let natural = record([plain("a", 1l, 1), plain("b", 4l, 4), plain("c", 1l, 1)])
        var tu <- unit_with([CirField(name = "a", t = 1), CirField(name = "b", t = 0), CirField(name = "c", t = 1)])
        t |> equal(into_cir(tu, natural), "packed false size 12 align 4 at 0/0 4/32 8/64")
        let packed_rec = with_packed(record([plain("a", 1l, 1), plain("b", 4l, 4), plain("c", 2l, 2)]))
        var tu2 <- unit_with([CirField(name = "a", t = 1), CirField(name = "b", t = 0), CirField(name = "c", t = 2)])
        t |> equal(into_cir(tu2, packed_rec), "packed true size 7 align 1 at 0/0 1/8 5/40")
    }
    t |> run("F5: `struct \{ unsigned a : 3; int b : 5; short e; \}` is natural through a byte unit") @(t : T?) {
        let f5 = record([bits("a", 4l, 3), bits("b", 4l, 5), plain("e", 2l, 2)])
        var tu <- unit_with([CirField(name = "a", t = 0, is_bitfield = true, bit_w = 3), CirField(name = "b", t = 0, is_bitfield = true, bit_w = 5), CirField(name = "e", t = 2)])
        t |> equal(into_cir(tu, f5), "packed false size 4 align 4 at 0/0 0/3 2/16")
    }
    t |> run("a refused layout, a field count other than the layout's, a size past the bit offsets") @(t : T?) {
        var tu <- unit_with([CirField(name = "a", t = 1)])
        t |> equal(into_cir(tu, with_pack(record([plain("a", 1l, 1)]), 3)), "`#pragma pack(3)` is not a power of two")
        t |> equal(into_cir(tu, record([plain("a", 1l, 1), plain("b", 1l, 1)])), "record type 3 has 1 fields, its layout 2")
        t |> equal(into_cir(tu, record([plain("a", 300000000l, 1)])), "record type 3 is 300000000 bytes, past the C-IR's bit offsets")
    }
}
