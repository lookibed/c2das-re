options gen2
require dastest/testing_boost public
require strings
require _daslang_child

struct BF {
    _bits0 : uint
    e : int16
}

def operator . a(s : BF) : uint => s._bits0 & 7u

def operator . a :=(var s : BF; v : uint) {
    s._bits0 = (s._bits0 & ~7u) | (v & 7u)
}

def operator . b(s : BF) : int => int(s._bits0 << 24u) >> 27

def operator . b :=(var s : BF; v : int) {
    s._bits0 = (s._bits0 & ~(31u << 3u)) | ((uint(v) & 31u) << 3u)
}

// `struct { signed f0 : 16; unsigned f1 : 14; signed char f2; unsigned f3 : 12; int f4; }` under
// the linux dialect: `f3` takes bits 40 to 51, which no naturally aligned unsigned storage clear
// of `f2` covers, so its unit is two bytes at byte 5, assembled little-endian
struct ByteUnit {
    _bits0 : uint
    f2 : int8
    _bits1 : uint8[2]
    f4 : int
}

def operator . f3(s : ByteUnit) : uint => (uint(s._bits1[0]) | (uint(s._bits1[1]) << 8u)) & 0xfffu

def operator . f3 :=(var s : ByteUnit; v : uint) {
    let w = ((uint(s._bits1[0]) | (uint(s._bits1[1]) << 8u)) & 0xfffff000u) | (v & 0xfffu)
    s._bits1[0] = uint8(w)
    s._bits1[1] = uint8(w >> 8u)
}

// a signed field of 30 bits at bit 4 of a five-byte unit: the arithmetic runs in uint64
struct WideBytes {
    c : int8
    _bits1 : uint8[5]
}

def operator . g(s : WideBytes) : int {
    let w = uint64(s._bits1[0]) | (uint64(s._bits1[1]) << 8ul) | (uint64(s._bits1[2]) << 16ul) | (uint64(s._bits1[3]) << 24ul) | (uint64(s._bits1[4]) << 32ul)
    return int(int64(w << 30ul) >> 34l)
}

def operator . g :=(var s : WideBytes; v : int) {
    let w = ((uint64(s._bits1[0]) | (uint64(s._bits1[1]) << 8ul) | (uint64(s._bits1[2]) << 16ul) | (uint64(s._bits1[3]) << 24ul) | (uint64(s._bits1[4]) << 32ul)) & ~(0x3ffffffful << 4ul)) | ((uint64(v) & 0x3ffffffful) << 4ul)
    s._bits1[0] = uint8(w)
    s._bits1[1] = uint8(w >> 8ul)
    s._bits1[2] = uint8(w >> 16ul)
    s._bits1[3] = uint8(w >> 24ul)
    s._bits1[4] = uint8(w >> 32ul)
}

// natural storage cannot sit at an odd offset: das moves it to its alignment
struct OddNatural {
    c : int8
    u : uint16
}

// the initializer of a byte unit: its bytes from the folded word, little-endian; the type
// parameter is `UnitBytesT`, since a generic's `auto(T)` binds a struct `T` visible where the
// generic is declared
def unit_bytes(w : uint64; t : auto(UnitBytesT)) : UnitBytesT {
    var r : UnitBytesT
    for (i in range(length(r))) {
        r[i] = uint8(w >> uint64(8 * i))
    }
    return r
}

var g_byte_units = fixed_array(ByteUnit(_bits0 = 1u, f2 = int8(2), _bits1 = unit_bytes(0xabcul, default<uint8[2]>), f4 = 4), ByteUnit(_bits1 = unit_bytes(0x123ul, default<uint8[2]>)))

let GENERIC_NAME_CLASH = "options gen2\nstruct T \{\n    x : int\n\}\ndef unit_bytes(w : uint64; t : auto(T)) : T \{\n    var r : T\n    for (i in range(length(r))) \{\n        r[i] = uint8(w >> uint64(8 * i))\n    \}\n    return r\n\}\n[export]\ndef main \{\n    let b = unit_bytes(1ul, default<uint8[2]>)\n    print(\"\{b\}\")\n\}\n"

// a property pair reached through a field of `deref(p + 2)`; `STORE` is the statement under test
let POINTER_STEP = "options gen2\nstruct U \{\n    x : int\n\}\ndef operator . s(u : U) : int => u.x\ndef operator . s :=(var u : U; v : int) \{\n    u.x = v\n\}\nstruct S \{\n    u : U\n\}\nvar arr : S[4]\n[export]\ndef main : int \{\n    unsafe \{\n        var p : S? = addr(arr[0])\n        STORE\n    \}\n    return arr[2].u.s\n\}\n"

let PROPERTY_PAIR = "struct BF \{\n    _bits0 : uint\n\}\ndef operator . a(s : BF) : uint => s._bits0 & 7u\ndef operator . a :=(var s : BF; v : uint) \{\n    s._bits0 = (s._bits0 & ~7u) | (v & 7u)\n\}\n"

[test]
def test_bitfields(t : T?) {
    t |> run("unsigned field truncates on write") @(t : T?) {
        var s : BF
        s.a = 9u
        t |> equal(s.a, 1u)
        t |> equal(s._bits0, 1u)
    }
    t |> run("signed field sign-extends through shl/sar") @(t : T?) {
        var s : BF
        s.b = -3
        t |> equal(s.b, -3)
        s.b = 15
        t |> equal(s.b, 15)
        s.b = 16
        t |> equal(s.b, -16)
    }
    t |> run("compound assignment routes through get and set without touching neighbours") @(t : T?) {
        var s : BF
        s.a = 7u
        s.b = -3
        s.a += 1u
        t |> equal(s.a, 0u)
        t |> equal(s.b, -3)
        s.e = int16(-2)
        t |> equal(int(s.e), -2)
        t |> equal(typeinfo sizeof(type<BF>), 8)
    }
    t |> run("the storage types have no shift: bit math runs in uint or uint64") @(t : T?) {
        let r = daslang_child("shift", "options gen2\n[export]\ndef main \{\n    let a = 3u8\n    let b = a << 1u8\n    assert(b != a)\n\}\n", true)
        t |> equal(r.rc != 0, true)
        t |> equal(r.out |> find("is not defined for storage types") >= 0, true, r.out)
    }
    t |> run("++ and -- are rejected on a property") @(t : T?) {
        let r = daslang_child("step", "options gen2\n" + PROPERTY_PAIR + "[export]\ndef main \{\n    var s : BF\n    s.a++\n    --s.a\n\}\n", true)
        t |> equal(r.rc != 0, true)
        t |> equal(r.out |> find("+++ can't be applied to non reference") >= 0, true, r.out)
        t |> equal(r.out |> find("-- can't be applied to non reference") >= 0, true, r.out)
    }
    t |> run("every compound operator and a pointer base route through the property pair") @(t : T?) {
        var s : BF
        var p = unsafe(addr(s))
        p.a = 5u
        p.a |= 8u
        p.a <<= 1u
        p.a ^= 3u
        p.a *= 3u
        p.a -= 1u
        t |> equal(s.a, 2u)
        var arr : BF[2]
        arr[1].a = 3u
        arr[1].a += 1u
        t |> equal(arr[1].a, 4u)
    }
    t |> run("a global fixed_array of struct literals naming a property crashes before main; a local one and a single global literal work") @(t : T?) {
        let crash = daslang_child("literal_array", "options gen2\n" + PROPERTY_PAIR + "var ga = fixed_array(BF(a = 3u), BF(a = 2u))\n[export]\ndef main : int \{\n    print(\"main\\n\")\n    return int(ga[1].a)\n\}\n", false)
        t |> equal(crash.rc != 0, true, crash.out)
        t |> equal(crash.out |> find("SIGSEGV") >= 0 && crash.out |> find("Context::~Context") >= 0, true, crash.out)
        t |> equal(crash.out |> find("main") < 0, true, crash.out)
        let local = daslang_child("literal_local", "options gen2\n" + PROPERTY_PAIR + "[export]\ndef main : int \{\n    var la = fixed_array(BF(a = 3u), BF(a = 2u))\n    return int(la[1].a)\n\}\n", false)
        t |> equal(local.rc, 2, local.out)
        let single = daslang_child("literal_single", "options gen2\n" + PROPERTY_PAIR + "var g = BF(a = 2u)\n[export]\ndef main : int \{\n    return int(g.a)\n\}\n", false)
        t |> equal(single.rc, 2, single.out)
    }
    t |> run("a compound store to a property through a field of deref(p + k) passes -compile-only and crashes before main (lookibed/daScript#17)") @(t : T?) {
        // https://github.com/lookibed/daScript/issues/17
        let source = POINTER_STEP |> replace("STORE", "deref(p + 2).u.s += 1")
        let checked = daslang_child("pointer_step_check", source, true)
        t |> equal(checked.rc, 0, checked.out)
        let crash = daslang_child("pointer_step_crash", source, false)
        t |> equal(crash.rc != 0, true, crash.out)
        t |> equal(crash.out |> find("SIGSEGV") >= 0, true, crash.out)
    }
    t |> run("the same store with the getter and the setter spelled apart, x = x + 1, runs") @(t : T?) {
        let apart = daslang_child("pointer_step_apart", POINTER_STEP |> replace("STORE", "deref(p + 2).u.s = deref(p + 2).u.s + 1"), false)
        t |> equal(apart.rc, 1, apart.out)
    }
}

[test]
def test_byte_units(t : T?) {
    t |> run("a uint8[k] unit sits at the byte its bits start in, alignment 1; natural storage cannot sit at an odd offset") @(t : T?) {
        t |> equal(typeinfo offsetof < f2 > (type<ByteUnit>), 4)
        t |> equal(typeinfo offsetof < _bits1 > (type<ByteUnit>), 5)
        t |> equal(typeinfo offsetof < f4 > (type<ByteUnit>), 8)
        t |> equal(typeinfo sizeof(type<ByteUnit>), 12)
        t |> equal(typeinfo alignof(type<uint8[5]>), 1)
        t |> equal(typeinfo offsetof < _bits1 > (type<WideBytes>), 1)
        t |> equal(typeinfo offsetof < u > (type<OddNatural>), 2)
    }
    t |> run("a byte unit assembles its bytes little-endian: the property pair truncates, keeps the neighbouring bits and matches the bytes as memory holds the word") @(t : T?) {
        var s : ByteUnit
        s._bits1[1] = 0xf0u8
        s.f3 = 0x1abcu
        t |> equal(s.f3, 0xabcu)
        t |> equal(uint(s._bits1[0]), 0xbcu)
        t |> equal(uint(s._bits1[1]), 0xfau)
        s.f3 += 0x545u
        t |> equal(s.f3, 1u)
        t |> equal(uint(s._bits1[1]), 0xf0u)
        var w : WideBytes
        w.c = int8(-1)
        w._bits1[0] = 0x0fu8
        w._bits1[4] = 0xc0u8
        w.g = -536870912
        t |> equal(w.g, -536870912)
        w.g -= 1
        t |> equal(w.g, 536870911)
        t |> equal(uint(w._bits1[0]) & 0xfu, 0xfu)
        t |> equal(uint(w._bits1[4]) & 0xc0u, 0xc0u)
        var word = 0ul
        unsafe {
            memcpy(addr(word), addr(w._bits1), 5)
        }
        t |> equal(int(int64(word << 30ul) >> 34l), w.g)
        t |> equal(int(w.c), -1)
    }
    t |> run("uint8(w) keeps the low byte of a wider word: the byte unit's store narrows each byte") @(t : T?) {
        let w = 0x12345678u
        let w8 = 0x1122334455667788ul
        t |> equal(uint8(w), 0x78u8)
        t |> equal(uint8(w >> 8u), 0x56u8)
        t |> equal(uint8(w8 >> 56ul), 0x11u8)
    }
    t |> run("a generic over default<uint8[k]> builds a byte unit's bytes, little-endian") @(t : T?) {
        let b = unit_bytes(0x030201ul, default<uint8[3]>)
        t |> equal(int(b[0]) + int(b[1]) * 10 + int(b[2]) * 100, 321)
    }
    t |> run("a global fixed_array of struct literals takes the generic's bytes as a byte unit's item") @(t : T?) {
        t |> equal(g_byte_units[0].f3, 0xabcu)
        t |> equal(int(g_byte_units[0].f2), 2)
        t |> equal(g_byte_units[1].f3, 0x123u)
    }
    t |> run("a generic's auto(T) binds a struct T visible where the generic is declared") @(t : T?) {
        let clash = daslang_child("generic_name_clash", GENERIC_NAME_CLASH, true)
        t |> equal(clash.rc != 0, true, clash.out)
        t |> equal(clash.out |> find("can't locate variable 'i'") >= 0, true, clash.out)
    }
}
