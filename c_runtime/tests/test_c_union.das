options gen2
require dastest/testing_boost public
require ../../probes/_daslang_child.das
require c_runtime/c_union
require strings

//! `[c_union]` as the converter emits it: the union written C-shaped, bare when the members give
//! clang's size and alignment, `size` and `align` stated when they do not.

struct GCObject {
    marked : int
}

struct Point {
    x, y : int
}

// `typedef union { GCObject *gc; void *p; double n; long long i; } Value;`
[c_union]
struct Value {
    gc : GCObject?
    p : void?
    n : double
    i : int64
}

// `union Mix { struct Point pt; char bytes[12]; int i; };`
[c_union]
struct Mix {
    pt : Point
    bytes : uint8[12]
    i : int
}

// `union Half { short s; unsigned char c[2]; };`
[c_union]
struct Half {
    s : int16
    c : uint8[2]
}

// a union clang aligns past its members (an F5 record member, or `aligned(8)`)
[c_union(size = 8, align = 8)]
struct Wide {
    s : int16
    c : uint8[3]
}

struct Tagged {
    tag : int
    m : Mix
}

// `union Pun { signed f0 : 8; unsigned f1; }`: the bitfield member a property pair at bit 0
[c_union(f0 = 8)]
struct Pun {
    f0 : int
    f1 : uint
}

// `union Odd { char c[3]; unsigned f : 20; }` under the msvc dialect, which aligns it to 1: the
// storage is bytes, so the pair assembles three of them
[c_union(f = 20, size = 4, align = 1)]
struct Odd {
    c : uint8[3]
    f : uint
}

// the converter's `union Wide { char c; long long f : 5; }` under linux: an 8-byte storage, the
// arithmetic in uint64
[c_union(f = 5)]
struct WideBits {
    c : uint8
    f : int64
}

struct HoldsPun {
    k : int
    u : Pun
}

// `union Flag { _Bool b : 1; unsigned char raw; }`: a bool bitfield member over a byte
[c_union(b = 1)]
struct Flag {
    b : bool
    raw : uint8
}

// a member spelled `size` is a member, never a width: a full-width reference into the storage
[c_union(size = 8, align = 8)]
struct Sized {
    size : int
    d : double
}

def read_pun(u : Pun) : int => u.f0

// a union holding no pointer, read through a `let` parameter
def first_byte(m : Mix) : int => int(m.bytes[0])

def bits_of(v : Value) : int64 => v.i

def bump(var p : int?) {
    *p += 100
}

// `typedef union { handler_p1 h1; handler_v h0; handler_p2 h2; } handler_t;`
[c_union]
struct handler_t {
    h1 : function<(var a0 : void?) : void>
    h0 : function<() : void>
    h2 : function<(var a0 : void?; var a1 : void?) : void>
}

// `void fire(int *ammo, int *tics)`, stored through `h1` and called through `h2`: every pointer
// position is `var` (F3), the members' over `void?`, so `fire` is stored through a reinterpret
def fire(var ammo : int?; var tics : int?) {
    (*ammo)--
    *tics = 4
}

// the same union and calls as a program, run under the JIT
let FN_UNION_SOURCE = "options gen2
require c_runtime/c_union
[c_union]
struct handler_t \{
    h1 : function<(var a0 : void?) : void>
    h0 : function<() : void>
    h2 : function<(var a0 : void?; var a1 : void?) : void>
\}
def fire(var ammo : int?; var tics : int?) \{
    *ammo -= 1
    *tics = 4
\}
[export]
def main \{
    var u : handler_t
    var ammo = 5
    var tics = 0
    unsafe \{
        u.h1 = reinterpret<function<(var a0 : void?) : void>>(@@fire)
        invoke(u.h2, reinterpret<void?>(addr(ammo)), reinterpret<void?>(addr(tics)))
    \}
    print(\"\{typeinfo sizeof(u)\} \{ammo\} \{tics\} \{u.h0 != null\}\\n\")
\}
"

let U_FIELDS = "    i : int\n    d : double\n"

let SOURCE = StructSource(prefix = "c_union", text = "options gen2\nrequire c_runtime/c_union\nANNOTATION\nKIND U \{\nFIELDS\}\nAFTER\n[export]\ndef main \{\n\}\n")

def compile_shape(name, annotation : string; fields : string = U_FIELDS; after : string = ""; kind : string = "struct") : tuple<rc : int; out : string> => compile_struct(SOURCE, name, annotation, fields, after, kind)

def rejects(t : T?; name, annotation, needle : string; fields : string = U_FIELDS; after : string = ""; kind : string = "struct") {
    struct_rejected(t, SOURCE, name, annotation, needle, fields, after, kind)
}

[test]
def test_c_union(t : T?) {
    t |> run("the members share one storage of the union's size and alignment") @(t : T?) {
        t |> equal(typeinfo sizeof(type<Value>), 8)
        t |> equal(typeinfo alignof(type<Value>), 8)
        t |> equal(typeinfo offsetof < _storage > (type<Value>), 0)
        t |> equal(typeinfo sizeof(type<Mix>), 12)
        t |> equal(typeinfo alignof(type<Mix>), 4)
        t |> equal(typeinfo sizeof(type<Half>), 2)
        t |> equal(typeinfo alignof(type<Half>), 2)
        t |> equal(typeinfo sizeof(type<Wide>), 8)
        t |> equal(typeinfo alignof(type<Wide>), 8)
        t |> equal(typeinfo offsetof < m > (type<Tagged>), 4)
    }
    t |> run("a store through one member reads back as the bits of another") @(t : T?) {
        var v : Value
        v.n = 3.5lf
        t |> equal(v.i, int64(0x400C000000000000ul))
        v.i = 0l
        t |> equal(v.n, 0.0lf)
        v.p = unsafe(reinterpret<void?>(0x10ul))
        t |> equal(v.i, 16l)
        var h : Half
        h.c[0] = 1u8
        h.c[1] = 2u8
        t |> equal(int(h.s), 513)
    }
    t |> run("a record member serves a nested store, a compound store and its address") @(t : T?) {
        var m : Mix
        m.pt.x = 7
        m.pt.y = 9
        t |> equal(m.i, 7)
        m.pt.x += 2
        t |> equal(m.pt.x, 9)
        var pp = unsafe(addr(m.pt))
        pp.y = 100
        t |> equal(m.pt.y, 100)
        t |> equal(int(m.bytes[4]), 100)
    }
    t |> run("an integer member steps, takes compound stores and passes its address") @(t : T?) {
        var m : Mix
        m.i = 5
        m.i++
        m.i--
        m.i++
        m.i *= 3
        t |> equal(m.i, 18)
        bump(unsafe(addr(m.i)))
        t |> equal(m.i, 118)
        var p = unsafe(addr(m))
        p.i++
        t |> equal(m.i, 119)
    }
    t |> run("a union reads through a let parameter and copies by value") @(t : T?) {
        var m : Mix
        m.i = 16909060
        t |> equal(first_byte(m), 4)
        var copy = m
        copy.bytes[0] = 9u8
        t |> equal(m.i, 16909060)
        t |> equal(copy.i, 16909065)
        var v : Value
        v.n = 1.0lf
        t |> equal(bits_of(v), int64(0x3FF0000000000000ul))
    }
    t |> run("the converter's initializer shape: the record without the union, then stores") @(t : T?) {
        var tg = Tagged(tag = 5)
        tg.m.i = 9
        t |> equal(tg.tag, 5)
        t |> equal(tg.m.i, 9)
        var arr : Mix[2] = fixed_array(Mix(), Mix())
        arr[1].pt = Point(x = 5, y = 6)
        t |> equal(arr[1].i, 5)
        t |> equal(arr[0].i, 0)
    }
}

[test]
def test_c_union_functions(t : T?) {
    t |> run("function members share one pointer-sized storage: a call through another member calls the stored function") @(t : T?) {
        t |> equal(typeinfo sizeof(type<handler_t>), 8)
        var u : handler_t
        t |> equal(u.h1 == null && u.h0 == null, true)
        var ammo = 5
        var tics = 0
        unsafe {
            u.h1 = reinterpret<function<(var a0 : void?) : void>>(@@fire)
            invoke(u.h2, addr<void?>(ammo), addr<void?>(tics))
            t |> equal(u.h0 == reinterpret<function<() : void>>(@@fire), true)
            u.h0 = reinterpret<function<() : void>>(uint64(-1))
            t |> equal(u.h1 == reinterpret<function<(var a0 : void?) : void>>(uint64(-1)), true)
        }
        t |> equal(ammo, 4)
        t |> equal(tics, 4)
        let r = runtime_child_flags("fn_union_jit", FN_UNION_SOURCE, jit_flags())
        t |> equal(r.rc, 0, r.out)
        t |> equal(jit_ran(r.out), true, r.out)
        t |> equal(r.out |> find("8 4 4 true") >= 0, true, r.out)
    }
}

[test]
def test_c_union_bitfields(t : T?) {
    t |> run("a bitfield member truncates and sign-extends at bit 0 and puns with the plain member") @(t : T?) {
        var u : Pun
        u.f1 = 0x12345678u
        t |> equal(u.f0, 120)
        u.f0 = 511
        t |> equal(u.f0, -1)
        t |> equal(u.f1, 0x123456ffu)
        t |> equal(typeinfo sizeof(type<Pun>), 4)
        t |> equal(typeinfo alignof(type<Pun>), 4)
    }
    t |> run("a bitfield member steps through += 1, reads through a let parameter, a nested union and a pointer") @(t : T?) {
        var u : Pun
        u.f0 = 127
        u.f0 += 1
        t |> equal(u.f0, -128)
        t |> equal(read_pun(u), -128)
        var h = HoldsPun(k = 1)
        h.u.f0 = -100
        var p = unsafe(addr(h))
        p.u.f0 -= 1
        t |> equal(h.u.f0, -101)
        t |> equal(h.u.f1, 155u)
    }
    t |> run("a storage narrower than the width: the pair assembles and stores several elements") @(t : T?) {
        var o : Odd
        o.f = 0xfffffu
        o.c[0] = 1u8
        t |> equal(o.f, 0xfff01u)
        t |> equal(o.c[2], 0x0fu8)
        o.c[2] = 0xffu8
        t |> equal(o.f, 0xfff01u)
        o.f += 0xffu
        t |> equal(o.f, 0u)
        t |> equal(o.c[2], 0xf0u8)
        t |> equal(typeinfo sizeof(type<Odd>), 4)
        t |> equal(typeinfo alignof(type<Odd>), 1)
    }
    t |> run("a bitfield of an 8-byte storage runs in uint64 and keeps the other bytes") @(t : T?) {
        var w : WideBits
        w.c = 0xffu8
        w.f = -1l
        t |> equal(w.f, -1l)
        w.f = 15l
        t |> equal(w.f, 15l)
        t |> equal(w.c, 0xefu8)
        t |> equal(typeinfo sizeof(type<WideBits>), 8)
    }
    t |> run("a bool bitfield member stores true and false as bit 0 and reads only that bit") @(t : T?) {
        var f : Flag
        f.b = true
        t |> equal(f.b, true)
        t |> equal(f.raw, 1u8)
        f.raw = 2u8
        t |> equal(f.b, false)
        f.raw = 3u8
        f.b = false
        t |> equal(f.raw, 2u8)
        t |> equal(typeinfo sizeof(type<Flag>), 1)
    }
    t |> run("a member spelled size beside the stated size is a full-width reference into the storage") @(t : T?) {
        var u : Sized
        u.size = 300
        t |> equal(u.size, 300)
        var p = unsafe(addr(u.size))
        *p = 70000
        t |> equal(u.size, 70000)
        t |> equal(typeinfo sizeof(type<Sized>), 8)
    }
}

[test]
def test_c_union_bitfield_shapes(t : T?) {
    t |> run("the compiler rejects a width the member's type or the storage cannot hold") @(t : T?) {
        rejects(t, "width_type", "[c_union(d = 3)]", "bitfield `d` is of type double, not an integer or bool", "    d : double\n    i : int\n")
        rejects(t, "width_wide", "[c_union(i = 33)]", "bitfield `i` of 33 bits does not fit its type int")
        rejects(t, "width_zero", "[c_union(i = 0)]", "bitfield `i` of 0 bits holds no bit")
        rejects(t, "width_bool", "[c_union(b = 2)]", "bool bitfield `b` is 1 bit wide, not 2", "    b : bool\n    i : int\n")
        rejects(t, "width_storage", "[c_union(c = 16, size = 1, align = 1)]", "bitfield `c` needs 2 bytes, the storage has 1", "    c : int16\n")
        rejects(t, "width_string", "[c_union(i = \"3\")]", "the width of `i` is not an integer")
        rejects(t, "width_getter", "[c_union(i = 3)]", "function is already defined .`i", U_FIELDS, "def operator . i(s : U) : int => 0\n")
    }
    t |> run("the compiler takes a width on an integer or bool member, and a member spelled size beside the stated size") @(t : T?) {
        let ok = compile_shape("width_ok", "[c_union(i = 3)]")
        t |> equal(ok.rc, 0, ok.out)
        let flag = compile_shape("width_flag", "[c_union(b = 1)]", "    b : bool\n    i : int\n")
        t |> equal(flag.rc, 0, flag.out)
        let size_member = compile_shape("size_member", "[c_union(size = 8, align = 8)]", "    size : int\n    d : double\n")
        t |> equal(size_member.rc, 0, size_member.out)
    }
}

[test]
def test_c_union_shapes(t : T?) {
    t |> run("the compiler takes the emitted shapes") @(t : T?) {
        let bare = compile_shape("bare", "[c_union]")
        t |> equal(bare.rc, 0, bare.out)
        let stated = compile_shape("stated", "[c_union(size = 16, align = 8)]")
        t |> equal(stated.rc, 0, stated.out)
        let fn_member = compile_shape("function", "[c_union]", "    f : function<(a : int) : int>\n    n : int64\n")
        t |> equal(fn_member.rc, 0, fn_member.out)
    }
    t |> run("the compiler rejects a union the annotation does not lower") @(t : T?) {
        rejects(t, "class", "[c_union]", "U is a class", U_FIELDS, "", "class")
        rejects(t, "empty", "[c_union]", "U has no member", "")
        rejects(t, "storage", "[c_union]", "U has a member named `_storage`", "    _storage : int\n")
        rejects(t, "init", "[c_union]", "member `i` has an initializer", "    i : int = 1\n")
    }
    t |> run("an operator the source spells beside the union is the parser's error, before the annotation runs") @(t : T?) {
        rejects(t, "operator", "[c_union]", "function is already defined .`i", U_FIELDS, "def operator . i(s : U) : int => 0\n")
    }
    t |> run("the compiler rejects size and alignment the storage cannot spell or the members do not fit") @(t : T?) {
        rejects(t, "one_of", "[c_union(size = 8)]", "gives one of `size` and `align`")
        rejects(t, "unknown_arg", "[c_union(bytes = 8)]", "unknown argument `bytes`")
        rejects(t, "not_int", "[c_union(size = \"8\", align = 8)]", "`size` is not an integer")
        rejects(t, "align_not_int", "[c_union(size = 8, align = \"8\")]", "`align` is not an integer")
        rejects(t, "zero", "[c_union(size = 0, align = 4)]", "size 0 of U is not a positive multiple of its alignment 4")
        rejects(t, "align16", "[c_union(size = 16, align = 16)]", "alignment 16 of U is not 1, 2, 4 or 8")
        rejects(t, "ragged", "[c_union(size = 12, align = 8)]", "size 12 of U is not a positive multiple of its alignment 8")
        rejects(t, "too_small", "[c_union(size = 4, align = 4)]", "member `d` of U does not fit the storage of size 4 and alignment 4")
        rejects(t, "under_aligned", "[c_union(size = 16, align = 4)]", "member `d` of U does not fit the storage of size 16 and alignment 4")
    }
    t |> run("the bare form needs every member type known where the union is declared") @(t : T?) {
        rejects(t, "later", "[c_union]", "a member type of U is not known where it is declared", "    p : Later\n    n : int64\n", "struct Later \{\n    x : int\n\}\n")
        rejects(t, "later_inside", "struct Holder \{\n    l : Later\n\}\n[c_union]", "a member type of U is not known where it is declared", "    h : Holder\n", "struct Later \{\n    x : int\n\}\n")
        rejects(t, "constant_dim", "let N = 3\n[c_union]", "a member type of U is not known where it is declared", "    a : int[N]\n")
        let stated = compile_shape("later_stated", "[c_union(size = 4, align = 4)]", "    p : Later\n", "struct Later \{\n    x : int\n\}\n")
        t |> equal(stated.rc, 0, stated.out)
        let pointer = compile_shape("later_pointer", "[c_union]", "    p : Later?\n    n : int64\n", "struct Later \{\n    x : int\n\}\n")
        t |> equal(pointer.rc, 0, pointer.out)
        let holder = compile_shape("later_function", "struct Holder \{\n    f : function<(a : Later?) : int>\n\}\n[c_union]", "    h : Holder\n    n : int64\n", "struct Later \{\n    x : int\n\}\n")
        t |> equal(holder.rc, 0, holder.out)
    }
}
