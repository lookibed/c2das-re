options gen2
require dastest/testing_boost public
require _daslang_child

def record(var trace : array<int>; v : int) : int {
    trace |> push(v)
    return v
}

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
    t |> run("a ternary evaluates only the taken arm") @(t : T?) {
        var trace : array<int>
        let pick = true
        let v = pick ? record(trace, 1) : record(trace, 2)
        t |> equal(v, 1)
        t |> equal("{trace}", "[ 1]")
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

// the das facts the csmith differential found (docs/probe-findings.md F40 to F46)
[test]
def test_csmith_scalars(t : T?) {
    t |> run("a shift takes a count of its value's own type alone; the count converted shifts") @(t : T?) {
        child_rejects(t, "shift_int_uint", daslang_child("shift_int_uint", "options gen2\n[export]\ndef main \{\n    let a = 5\n    let n = 1u\n    assert(a << n == 10)\n\}\n", true), "int << uint is not defined")
        child_rejects(t, "shift_int64_int", daslang_child("shift_int64_int", "options gen2\n[export]\ndef main \{\n    let a = 5l\n    let n = 1\n    assert(a >> n == 2l)\n\}\n", true), "int64 >> int is not defined")
        let a = 5
        let n = 1u
        t |> equal(a << int(n), 10)
        t |> equal(127 >> int(3u), 15)
        t |> equal(5l << int64(n), 10l)
        t |> equal(0xFFFFul >> uint64(n), 0x7FFFul)
    }
    t |> run("a local that shadows an enclosing local is refused, `_` included; sibling blocks reuse a name") @(t : T?) {
        child_rejects(t, "shadow_nested", daslang_child("shadow_nested", "options gen2\n[export]\ndef main \{\n    var i = 1\n    \{\n        var i = 2\n        assert(i == 2)\n    \}\n    assert(i == 1)\n\}\n", true), "local variable i is shadowed by another local variable")
        child_rejects(t, "shadow_discard", daslang_child("shadow_discard", "options gen2\n[export]\ndef main \{\n    let _ = 1\n    \{\n        let _ = 2\n    \}\n\}\n", true), "local variable _ is shadowed by another local variable")
        let siblings = daslang_child("shadow_siblings", "options gen2\n[export]\ndef main \{\n    \{\n        var i = 1\n        assert(i == 1)\n    \}\n    \{\n        var i = 2\n        assert(i == 2)\n    \}\n\}\n", false)
        t |> equal(siblings.rc, 0, siblings.out)
    }
}
