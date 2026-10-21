options gen2
require dastest/testing_boost public
require ../../probes/_daslang_child.das
require c_runtime/c_bitfields

//! `[c_bitfields]` as the converter emits it: the struct written C-shaped, the annotation
//! naming each unit's widths, explicit openers and padding where clang's layout needs them.

// `struct BF { unsigned a : 3; int b : 5; short e; }` under the msvc dialect
[c_bitfields(a = 3, b = 5)]
struct BF {
    a : uint
    b : int
    e : int16
}

// `struct Two { unsigned char a : 3; unsigned : 2; signed char b : 3; short x; unsigned c : 31; _Bool f : 1; }`
// under the linux dialect
[c_bitfields(a = 3, _0 = 2, b = 3, _bits1 = "uint", c = 31, f = 1)]
struct Two {
    a : uint8
    b : int8
    x : int16
    c : uint
    f : bool
}

// `struct Lead { unsigned : 4; unsigned x : 4; short y; }` under the linux dialect: the unit
// starts before its first field, so it takes its opener
[c_bitfields(_bits0 = "uint8", _0 = 4, x = 4)]
struct Lead {
    x : uint
    y : int16
}

[c_bitfields(_bits0 = "uint64", lo = 20, big = 40, s1 = 1, flag = 1)]
struct Wide {
    lo : uint
    big : int64
    s1 : int
    flag : bool
}

// `struct Cramped { signed f0 : 16; unsigned f1 : 14; signed char f2; unsigned f3 : 12; int f4; }`
// under the linux dialect: `f3` takes bits 40 to 51, so its unit is two bytes at byte 5
[c_bitfields(f0 = 16, f1 = 14, _bits1 = "uint8[2]", f3 = 12)]
struct Cramped {
    f0 : int
    f1 : uint
    f2 : int8
    f3 : uint
    f4 : int
}

// a signed field at bit 4 of a three-byte unit, and a 40-bit field in a five-byte unit whose
// arithmetic runs in uint64
[c_bitfields(_bits0 = "uint8[3]", _0 = 4, g = 18, _bits1 = "uint8[5]", x = 40)]
struct Bytes {
    c : int8
    g : int
    x : uint64
}

let BF_FIELDS = "    a : uint\n    b : int\n    c : int\n    e : int16\n"

let SOURCE = StructSource(prefix = "c_bitfields", text = "options gen2\nrequire c_runtime/c_bitfields\nenum Color \{\n    Red\n\}\nANNOTATION\nKIND S \{\nFIELDS\}\nAFTER\n[export]\ndef main \{\n\}\n")

def compile_shape(name, annotation : string; fields : string = BF_FIELDS; after : string = ""; kind : string = "struct") : tuple<rc : int; out : string> => compile_struct(SOURCE, name, annotation, fields, after, kind)

def rejects(t : T?; name, annotation, needle : string; fields : string = BF_FIELDS; after : string = ""; kind : string = "struct") {
    struct_rejected(t, SOURCE, name, annotation, needle, fields, after, kind)
}

[test]
def test_c_bitfields(t : T?) {
    t |> run("the storage is one uint unit and the struct has MSVC's size") @(t : T?) {
        t |> equal(typeinfo sizeof(type<BF>), 8)
        t |> equal(typeinfo offsetof < e > (type<BF>), 4)
        t |> equal(typeinfo offsetof < _bits0 > (type<BF>), 0)
    }
    t |> run("an unsigned field truncates on write, a signed one sign-extends") @(t : T?) {
        var s : BF
        s.a = 9u
        t |> equal(s.a, 1u)
        s.b = 16
        t |> equal(s.b, -16)
        s.b = 15
        t |> equal(s.b, 15)
        s.b = -3
        t |> equal(s.b, -3)
        t |> equal(s._bits0, 1u | (29u << 3u))
    }
    t |> run("compound assignment goes through get and set and keeps the neighbours") @(t : T?) {
        var s : BF
        s.a = 7u
        s.b = -3
        s.e = int16(-2)
        s.a += 1u
        t |> equal(s.a, 0u)
        t |> equal(s.b, -3)
        s.b -= 1
        t |> equal(s.b, -4)
        t |> equal(s.a, 0u)
        t |> equal(int(s.e), -2)
    }
    t |> run("explicit openers and padding place the units and the bits where clang puts them") @(t : T?) {
        t |> equal(typeinfo sizeof(type<Two>), 8)
        t |> equal(typeinfo offsetof < _bits0 > (type<Two>), 0)
        t |> equal(typeinfo offsetof < x > (type<Two>), 2)
        t |> equal(typeinfo offsetof < _bits1 > (type<Two>), 4)
        t |> equal(typeinfo sizeof(type<Lead>), 4)
        t |> equal(typeinfo offsetof < y > (type<Lead>), 2)
        var lead : Lead
        lead.x = 9u
        t |> equal(lead._bits0, uint8(0x90))
        t |> equal(lead.x, 9u)
        var s : Two
        s.a = 5u8
        s.b = int8(-2)
        s.c = 0x7fffffffu
        s.f = true
        t |> equal(s._bits0, uint8(5 | (6 << 5)))
        t |> equal(s._bits1, 0xffffffffu)
        t |> equal(int(s.b), -2)
        s.f = false
        t |> equal(s.c, 0x7fffffffu)
        t |> equal(s.f, false)
        t |> equal(s._bits1, 0x7fffffffu)
    }
    t |> run("a uint64 unit carries a field across bit 32, one-bit signed fields read 0 or -1") @(t : T?) {
        var w : Wide
        w.big = -5l
        w.lo = 0xfffffu
        t |> equal(w.big, -5l)
        t |> equal(w.lo, 0xfffffu)
        w.big = 549755813887l
        t |> equal(w.big, 549755813887l)
        w.big += 1l
        t |> equal(w.big, -549755813888l)
        w.s1 = 1
        t |> equal(w.s1, -1)
        w.flag = true
        t |> equal(w.flag, true)
        t |> equal(w.lo, 0xfffffu)
        t |> equal(typeinfo sizeof(type<Wide>), 8)
    }
}

[test]
def test_c_bitfields_bytes(t : T?) {
    t |> run("a byte unit sits at the byte its bits start in, alignment 1") @(t : T?) {
        t |> equal(typeinfo offsetof < f2 > (type<Cramped>), 4)
        t |> equal(typeinfo offsetof < _bits1 > (type<Cramped>), 5)
        t |> equal(typeinfo offsetof < f4 > (type<Cramped>), 8)
        t |> equal(typeinfo sizeof(type<Cramped>), 12)
        t |> equal(typeinfo offsetof < _bits0 > (type<Bytes>), 1)
        t |> equal(typeinfo offsetof < _bits1 > (type<Bytes>), 4)
        t |> equal(typeinfo sizeof(type<Bytes>), 9)
    }
    t |> run("a byte unit's pair assembles and stores its bytes little-endian, keeping the neighbouring bits") @(t : T?) {
        var s : Cramped
        s._bits1[1] = 0xf0u8
        s.f3 = 0x1abcu
        t |> equal(s.f3, 0xabcu)
        t |> equal(s._bits1[0], 0xbcu8)
        t |> equal(s._bits1[1], 0xfau8)
        s.f3 += 0x545u
        t |> equal(s.f3, 1u)
        t |> equal(s._bits1[1], 0xf0u8)
        s.f2 = int8(-1)
        s.f0 = -2
        t |> equal(s.f0, -2)
        t |> equal(int(s.f2), -1)
    }
    t |> run("a signed field at a nonzero bit of a byte unit sign-extends; a five-byte unit runs in uint64") @(t : T?) {
        var b : Bytes
        b._bits0[0] = 0x0fu8
        b.g = -131072
        t |> equal(b.g, -131072)
        b.g -= 1
        t |> equal(b.g, 131071)
        t |> equal(uint(b._bits0[0]) & 0xfu, 0xfu)
        b.x = 0xfffffffffful
        b.x += 2ul
        t |> equal(b.x, 1ul)
        b.c = int8(7)
        t |> equal(b.g, 131071)
    }
    t |> run("the converter's byte unit initializer: c_unit_bytes of the folded word") @(t : T?) {
        let s = Cramped(_bits0 = (uint(-5) & 0xffffu) | ((uint(1000) & 0x3fffu) << 16u), f2 = int8(-7), _bits1 = c_unit_bytes(uint(4000) & 0xfffu, default<uint8[2]>), f4 = 9)
        t |> equal(s.f0, -5)
        t |> equal(s.f1, 1000u)
        t |> equal(s.f3, 4000u)
        let b = Bytes(c = int8(1), _bits0 = c_unit_bytes((uint(-1) & 0x3ffffu) << 4u, default<uint8[3]>), _bits1 = c_unit_bytes(0x123456789aul, default<uint8[5]>))
        t |> equal(b.g, -1)
        t |> equal(b.x, 0x123456789aul)
    }
    t |> run("the compiler rejects a byte unit of no byte, past eight, with no count, with an unclosed count or of another element type") @(t : T?) {
        rejects(t, "bytes_zero", "[c_bitfields(_bits0 = \"uint8[0]\", a = 3)]", "names storage `uint8[0]`")
        rejects(t, "bytes_nine", "[c_bitfields(_bits0 = \"uint8[9]\", a = 3)]", "names storage `uint8[9]`")
        rejects(t, "bytes_letter", "[c_bitfields(_bits0 = \"uint8[x]\", a = 3)]", "names storage `uint8[x]`")
        rejects(t, "bytes_unclosed", "[c_bitfields(_bits0 = \"uint8[3x\", a = 3)]", "names storage `uint8[3x`")
        rejects(t, "bytes_int16", "[c_bitfields(_bits0 = \"int16[2]\", a = 3)]", "names storage `int16[2]`")
        rejects(t, "bytes_overflow", "[c_bitfields(_bits0 = \"uint8[2]\", a = 17)]", "does not fit unit `_bits0` of 16 bits")
    }
    t |> run("the compiler takes a byte unit of three bytes holding three fields") @(t : T?) {
        let ok = compile_shape("bytes_ok", "[c_bitfields(_bits0 = \"uint8[3]\", a = 3, b = 5, c = 2)]")
        t |> equal(ok.rc, 0, ok.out)
    }
}

[test]
def test_c_bitfields_shapes(t : T?) {
    t |> run("the initializer the converter folds names the storage") @(t : T?) {
        let s = BF(_bits0 = (9u & 7u) | ((uint(-3) & 31u) << 3u), e = int16(7))
        t |> equal(s.a, 1u)
        t |> equal(s.b, -3)
        t |> equal(int(s.e), 7)
        let two = Two(_bits0 = uint8((uint(5u8) & 7u) | ((uint(int8(-1)) & 7u) << 5u)), x = int16(3), _bits1 = (1u & 0x7fffffffu) | ((true ? 1u : 0u) << 31u))
        t |> equal(two.a, 5u8)
        t |> equal(int(two.b), -1)
        t |> equal(two.c, 1u)
        t |> equal(two.f, true)
    }
    t |> run("the default unit of an int8 field is uint8") @(t : T?) {
        t |> equal(typeinfo sizeof(type<Small>), 2)
        var s : Small
        s.n = int8(-4)
        t |> equal(int(s.n), -4)
        t |> equal(s._bits0, uint8(0x1c))
    }
    t |> run("the compiler takes the emitted shape") @(t : T?) {
        let ok = compile_shape("ok", "[c_bitfields(a = 3, b = 5)]")
        t |> equal(ok.rc, 0, ok.out)
    }
    t |> run("the compiler rejects an annotation the struct contradicts") @(t : T?) {
        rejects(t, "overflow", "[c_bitfields(a = 30, b = 5)]", "does not fit unit `_bits0`")
        rejects(t, "unknown", "[c_bitfields(a = 3, zz = 5)]", "has no field `zz`")
        rejects(t, "enum", "[c_bitfields(a = 3, b = 2, c = 2)]", "is not a bitfield type", "    a : uint\n    b : int\n    c : Color\n")
        rejects(t, "apart", "[c_bitfields(a = 3, e = 5)]", "a unit's fields are adjacent")
        rejects(t, "twice", "[c_bitfields(a = 3, a = 2)]", "is named twice")
        rejects(t, "bool_width", "[c_bitfields(f = 2)]", "bool field `f` is 1 bit wide, not 2", "    f : bool\n")
        rejects(t, "init", "[c_bitfields(a = 3)]", "field `a` has an initializer", "    a : uint = 1u\n")
        rejects(t, "class", "[c_bitfields(a = 3)]", "S is a class", "    a : uint\n", "", "class")
        rejects(t, "none", "[c_bitfields]", "S names no bitfield")
        rejects(t, "getter", "[c_bitfields(a = 3)]", "function is already defined .`a", "    a : uint\n", "def operator . a(s : S) : uint => 0u\n")
        rejects(t, "setter", "[c_bitfields(a = 3)]", "function is already defined .`a`clone", "    a : uint\n", "def operator . a :=(var s : S; v : uint) \{\n\}\n")
    }
    t |> run("the compiler rejects an argument list the grammar does not read") @(t : T?) {
        rejects(t, "storage", "[c_bitfields(_bits0 = \"int\", a = 3)]", "names storage `int`")
        rejects(t, "not_width", "[c_bitfields(a = \"x\")]", "argument `a` is not a width")
        rejects(t, "pad_first", "[c_bitfields(_0 = 2, a = 3)]", "padding `_0` before any unit")
        rejects(t, "pad_past", "[c_bitfields(a = 3, _0 = 40)]", "padding `_0` runs past unit `_bits0`")
        rejects(t, "pad_negative", "[c_bitfields(a = 3, _0 = -2)]", "padding `_0` of -2 bits is negative")
        rejects(t, "empty_unit", "[c_bitfields(a = 3, _bits1 = \"uint\")]", "unit `_bits1` holds no field")
    }
    t |> run("a unit name, opened or implied, never takes a field's name or another unit's") @(t : T?) {
        rejects(t, "opener_field", "[c_bitfields(_bits0 = \"uint\", a = 3)]", "unit `_bits0` collides with a field of S", "    _bits0 : uint\n    a : uint\n")
        rejects(t, "implied_field", "[c_bitfields(a = 3)]", "unit `_bits0` collides with a field of S", "    a : uint\n    _bits0 : uint\n")
        rejects(t, "opened_twice", "[c_bitfields(_bits0 = \"uint\", a = 3, _bits0 = \"uint\", b = 5)]", "unit `_bits0` is opened twice")
    }
}

[c_bitfields(n = 5)]
struct Small {
    n : int8
    tail : int8
}
