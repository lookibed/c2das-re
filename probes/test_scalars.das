options gen2
require dastest/testing_boost public
require _daslang_child

def record(var trace : array<int>; v : int) : int {
    trace |> push(v)
    return v
}

struct Wide {
    sum : int
}

// the sums run on values the optimizer cannot see: an argument and a global the program sets
let WRAP_SOURCE = "options gen2\nvar g = 0\nvar h = 0l\ndef sum(a, b : int) : int => a + b\ndef diff(a, b : int) : int => a - b\n[export]\ndef main \{\n    g = 2147483647\n    h = 9223372036854775807l\n    var c = g\n    c += 5\n    print(\"\{sum(g, 5)\} \{diff(-g, 5)\} \{h + 2l\} \{-h - 3l\} \{c\} \{g + 5\}\\n\")\n\}\n"

// the products and bitwise operators on values the optimizer cannot see, past the type's range
let WRAP_PRODUCT_SOURCE = "options gen2\nvar g = 0\nvar h = 0l\ndef mul(a, b : int) : int => a * b\ndef mul64(a, b : int64) : int64 => a * b\n[export]\ndef main \{\n    g = 65537\n    h = 9223372036854775807l\n    var c = h\n    c *= 3l\n    print(\"\{mul(g, g)\} \{mul(g, -g)\} \{mul64(h, 3l)\} \{mul64(4294967297l, 4294967297l)\} \{c\} \{h ^ int64(-1)\} \{(h | 1l) & int64(g)\}\\n\")\n\}\n"

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
}

[test]
def test_wrap_and_compound(t : T?) {
    t |> run("int and int64 + and - wrap as C's sum through the unsigned type does, interpreted and jitted") @(t : T?) {
        for (flags in [array<string>(), jit_flags()]) {
            let r = daslang_child_flags("wrap_sum{length(flags)}", WRAP_SOURCE, flags)
            t |> equal(r.rc, 0, r.out)
            t |> equal(jit_ran(r.out), !empty(flags), r.out)
            t |> equal(program_output(r.out), "-2147483644 2147483644 -9223372036854775807 9223372036854775806 -2147483644 -2147483644\n", r.out)
        }
    }
    t |> run("int and int64 * wrap as C's product through the unsigned type does, interpreted and jitted; & | ^ take the bits") @(t : T?) {
        for (flags in [array<string>(), jit_flags()]) {
            let r = daslang_child_flags("wrap_product{length(flags)}", WRAP_PRODUCT_SOURCE, flags)
            t |> equal(r.rc, 0, r.out)
            t |> equal(jit_ran(r.out), !empty(flags), r.out)
            t |> equal(program_output(r.out), "131073 -131073 9223372036854775805 8589934593 9223372036854775805 -9223372036854775808 65537\n", r.out)
        }
    }
    t |> run("x op= y on a local, a field and an element, each operator and type the emitter spells") @(t : T?) {
        var x = 1
        x += 4
        x -= 2
        x *= 3
        x &= 255
        x |= 256
        x ^= 1
        var y = 3l
        y *= 5l
        var u = 7u
        u += 3u
        var d = 0.5lf
        d *= 4.0lf
        var cells = fixed_array(0, 0, 0)
        cells[1] += 7
        var w = Wide(sum = 2)
        w.sum += x
        t |> equal(x, 264)
        t |> equal(y, 15l)
        t |> equal(u, 10u)
        t |> equal(d, 2.0lf)
        t |> equal(cells[1], 7)
        t |> equal(w.sum, 266)
    }
}

[test]
def test_scalar_basics(t : T?) {
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

[test]
def test_bit_intrinsics(t : T?) {
    t |> run("clz, ctz and popcnt count at the operand's width and return it; clz of zero is not the width (c_builtins)") @(t : T?) {
        t |> equal(clz(1u), 31u)
        t |> equal(clz(1ul), 63ul)
        t |> equal(ctz(8u), 3u)
        t |> equal(ctz(0u), 32u)
        t |> equal(ctz(0ul), 64ul)
        t |> equal(popcnt(0xFFul), 8ul)
        t |> equal(clz(0u), 31u)
        var bits = 0xF0F0u
        t |> equal(popcnt(bits), 8u)
        bits = 0u
        t |> equal(popcnt(bits), 0u)
    }
    t |> run("reinterpret between double and uint64, float and uint copies the bits both ways, a NaN payload and the negative zero's sign included (c_builtins c_signbit)") @(t : T?) {
        var d = -0.0lf
        t |> equal(unsafe(reinterpret<uint64>(d)), 0x8000000000000000ul)
        d = 1.0lf
        t |> equal(unsafe(reinterpret<uint64>(d)), 0x3FF0000000000000ul)
        var dbits = 0x7FF8000000000123ul
        let dnan = unsafe(reinterpret<double>(dbits))
        t |> equal(dnan != dnan, true)
        t |> equal(unsafe(reinterpret<uint64>(dnan)), 0x7FF8000000000123ul)
        dbits = 0xC000000000000000ul
        t |> equal(unsafe(reinterpret<double>(dbits)), -2.0lf)
        var f = -0.0f
        t |> equal(unsafe(reinterpret<uint>(f)), 0x80000000u)
        f = 1.0f
        t |> equal(unsafe(reinterpret<uint>(f)), 0x3F800000u)
        var fbits = 0x7FC00123u
        let fnan = unsafe(reinterpret<float>(fbits))
        t |> equal(fnan != fnan, true)
        t |> equal(unsafe(reinterpret<uint>(fnan)), 0x7FC00123u)
        fbits = 0xC0000000u
        t |> equal(unsafe(reinterpret<float>(fbits)), -2.0f)
    }
}
