options gen2
require dastest/testing_boost public

[test]
def test_scalars(t : T?) {
    t |> run("small-int arithmetic computes in int and truncates on store") @(t : T?) {
        var b : int8 = int8(127)
        b = int8(int(b) + 1)
        t |> equal(int(b), -128)
        var ub : uint8 = uint8(255)
        ub = uint8(uint(ub) + 1u)
        t |> equal(uint(ub), 0u)
        var s : int16 = int16(32767)
        s = int16(int(s) + 1)
        t |> equal(int(s), -32768)
        var us : uint16 = uint16(0)
        us = uint16(uint(us) - 1u)
        t |> equal(uint(us), 65535u)
    }
    t |> run("usual arithmetic conversions emitted as explicit casts") @(t : T?) {
        let i = -1
        let u = 3u
        t |> equal(uint(i) < u, false)
        t |> equal(int64(i) * 10l, -10l)
    }
    t |> run("signed division, remainder and shift match C99 on x86") @(t : T?) {
        t |> equal(-7 / 2, -3)
        t |> equal(-7 % 2, -1)
        t |> equal(-8 >> 1, -4)
        t |> equal(0xFFFFFFF8 >> 1u, 0x7FFFFFFC)
    }
    t |> run("float to int truncates toward zero") @(t : T?) {
        t |> equal(int(2.9f), 2)
        t |> equal(int(-2.9lf), -2)
    }
    t |> run("int64 to int truncates mod 2^32 and uint(-1) is all ones") @(t : T?) {
        t |> equal(int(0x1_0000_0005l), 5)
        t |> equal(uint(-1), 0xFFFFFFFF)
    }
    t |> run("signed overflow wraps") @(t : T?) {
        var big = 2147483647
        big = big + 1
        t |> equal(big, -2147483647 - 1)
    }
    t |> run("char literal is int") @(t : T?) {
        t |> equal('a', 97)
        t |> equal(typeinfo typename('a'), "int const")
    }
    t |> run("float promotes to double through an explicit cast") @(t : T?) {
        let d = 1.5lf
        let f = 0.5f
        t |> equal(d * double(f), 0.75lf)
    }
    t |> run("bool never silently int; ternary is native") @(t : T?) {
        let n = 7
        let ok : bool = n != 0
        let x = ok ? 1 : 0
        t |> equal(x, 1)
        let a = 3
        let b = 9
        t |> equal(a > b ? "gt" : "le", "le")
    }
    t |> run("statement-only ++ and ||= on bool") @(t : T?) {
        var i = 0
        i++
        t |> equal(i, 1)
        var flag = false
        flag ||= i == 1
        t |> equal(flag, true)
        flag ||= false
        t |> equal(flag, true)
    }
}
