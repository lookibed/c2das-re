options gen2
require dastest/testing_boost public
require _daslang_child
require strings

// das's storage integers against a bare literal and its enums' direct integer conversions
// (docs/probe-findings.md F106), the facts the emitter's narrow `==` and its enum conversions take

enum Signed {
    NEG = -1
    THREE = 3
    BIG = 300
    TOP = 2147483647
}

// the narrow compares and the enum conversions as one program, run under the JIT too
let private SOURCE = "options gen2\n\nenum Signed \{\n    NEG = -1\n    BIG = 300\n\}\n\n[export]\ndef main \{\n    var c : uint8 = 255u8\n    var s : int8 = int8(-128)\n    var w : uint16 = uint16(65535)\n    var h : int16 = int16(-1)\n    let n = Signed.NEG\n    let b = Signed.BIG\n    print(\"\{c == 255\} \{c != 0\} \{c == '\\xff'\} \{s == -128\} \{w == 65535\} \{h == -1\} \{c == 5u\}\\n\")\n    print(\"\{uint(n)\} \{int64(n)\} \{uint64(n)\} \{uint8(b)\} \{int16(n)\}\\n\")\n\}\n"

[test]
def test_conversions(t : T?) {
    t |> run("a storage integer compares with `==` and `!=` against a bare literal in its range, a character and a `u` literal included (F106)") @(t : T?) {
        let c = 255u8
        let low = 0u8
        let s = int8(-128)
        let w = uint16(65535)
        let h = int16(-1)
        t |> equal(c == 255, true)
        t |> equal(c != 0, true)
        t |> equal(low == 0, true)
        t |> equal(c == '\xff', true)
        t |> equal(c == 'a', false)
        t |> equal(s == -128, true)
        t |> equal(s != 127, true)
        t |> equal(w == 65535, true)
        t |> equal(h == -1, true)
        t |> equal(c == 5u, false)
    }
    t |> run("a literal outside the storage type's range is a compile error, and so is an ordering compare (F106)") @(t : T?) {
        let past = daslang_child("narrow_past", "options gen2\ndef f(c : uint8) : bool \{\n    return c == 256\n\}\n", true)
        t |> equal(past.rc != 0, true, "c == 256 compiled")
        let negative = daslang_child("narrow_negative", "options gen2\ndef f(c : uint8) : bool \{\n    return c == -1\n\}\n", true)
        t |> equal(negative.rc != 0, true, "c == -1 compiled")
        let order = daslang_child("narrow_order", "options gen2\ndef f(c : uint8) : bool \{\n    return c < 5\n\}\n", true)
        child_rejects(t, "narrow_order", order, "30230")
    }
    t |> run("an enum converts to every integer type directly, with the bits `int(e)` gives (F106)") @(t : T?) {
        let n = Signed.NEG
        let b = Signed.BIG
        let top = Signed.TOP
        t |> equal(uint(n), uint(int(n)))
        t |> equal(uint(n), 0xffffffffu)
        t |> equal(int64(n), int64(int(n)))
        t |> equal(uint64(n), uint64(int(n)))
        t |> equal(int64(uint(n)), 4294967295l)
        t |> equal(uint64(uint(n)), uint64(uint(int(n))))
        t |> equal(uint8(b), uint8(int(b)))
        t |> equal(int8(b), int8(int(b)))
        t |> equal(int16(n), int16(int(n)))
        t |> equal(uint16(n), uint16(int(n)))
        t |> equal(uint(top), 2147483647u)
        let floating = daslang_child("enum_float", "options gen2\nenum E \{\n    A = 3\n\}\ndef f(e : E) : float \{\n    return float(e)\n\}\n", true)
        child_rejects(t, "enum_float", floating, "30341")
    }
    t |> run("the compares and the conversions agree under the interpreter and the JIT (F106)") @(t : T?) {
        let expected = "true true true true true true false\n0xffffffff -1 0xffffffffffffffff 0x2c -1"
        let interp = daslang_child("conversions_interp", SOURCE, false)
        t |> equal(program_output(interp.out) |> strip(), expected, interp.out)
        let jit = daslang_child_flags("conversions_jit", SOURCE, jit_flags())
        t |> success(jit_ran(jit.out), jit.out)
        t |> equal(program_output(jit.out) |> strip(), expected, jit.out)
    }
}
