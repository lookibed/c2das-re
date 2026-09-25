options gen2
require dastest/testing_boost public

struct BF {
    _bits0 : uint
    e : int16
}

def operator . a(s : BF) : uint {
    return s._bits0 & 7u
}

def operator . a :=(var s : BF; v : uint) {
    s._bits0 = (s._bits0 & ~7u) | (v & 7u)
}

def operator . b(s : BF) : int {
    return int(s._bits0 << 24u) >> 27
}

def operator . b :=(var s : BF; v : int) {
    s._bits0 = (s._bits0 & ~(31u << 3u)) | ((uint(v) & 31u) << 3u)
}

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
}
