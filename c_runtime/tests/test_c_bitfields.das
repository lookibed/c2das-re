options gen2
require dastest/testing_boost public
require strings
require _daslang_child
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

let SHAPE = "options gen2\nrequire c_runtime/c_bitfields\nenum Color \{\n    Red\n\}\nANNOTATION\nKIND S \{\nFIELDS\}\nAFTER\n[export]\ndef main \{\n\}\n"

let BF_FIELDS = "    a : uint\n    b : int\n    c : int\n    e : int16\n"

// the compiler's verdict on `SHAPE` with the annotation, the fields, the declarations after the
// struct and the keyword (`struct`, `class`) filled in
def compile_shape(name, annotation : string; fields : string = BF_FIELDS; after : string = ""; kind : string = "struct") : tuple<rc : int; out : string> {
    let source = SHAPE |> replace("ANNOTATION", annotation) |> replace("FIELDS", fields) |> replace("AFTER", after) |> replace("KIND", kind)
    return daslang_child("c_bitfields_{name}", source, true)
}

// a control: the shape is rejected and the compiler's message carries `needle`
def rejects(t : T?; name, annotation, needle : string; fields : string = BF_FIELDS; after : string = ""; kind : string = "struct") {
    let r = compile_shape(name, annotation, fields, after, kind)
    t |> equal(r.rc != 0, true, "{name} compiled")
    t |> equal(r.out |> find(needle) >= 0, true, "{name}: {r.out}")
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
