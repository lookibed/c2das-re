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
    t |> run("++ and -- are rejected on a property: a bitfield steps through += 1") @(t : T?) {
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
}
