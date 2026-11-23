options gen2
// the converter casts an address with reinterpret<void?>(addr(...)), and the calls are spelled its way
options _nolint = "STYLE034"
require dastest/testing_boost public
require c_runtime/c_builtins
require c_runtime/c_bounds
require ../../probes/_daslang_child.das

//! The GCC builtins the converter maps by name (`converter/tests/fixtures/p5_gnu_shims.c` calls
//! each the way the converter spells it): the answers C gives at both operand widths. The checked
//! arithmetic is spelled as `converter/tests/fixtures/p7_overflow_builtins.c` converts.

[test]
def test_c_builtins(t : T?) {
    t |> run("the bit counts at 32 and 64 bits") @(t : T?) {
        t |> equal(c_ffs(0), 0)
        t |> equal(c_ffs(12), 3)
        t |> equal(c_ffs(int(0x80000000u)), 32)
        t |> equal(c_ffs(1l << 40l), 41)
        t |> equal(c_ffs(0l), 0)
        t |> equal(c_ctz(0xF0u), 4)
        t |> equal(c_ctz(0x8000000000000000ul), 63)
        t |> equal(c_clz(0xF0u), 24)
        t |> equal(c_clz(1ul), 63)
        t |> equal(c_popcount(0xF0u), 4)
        t |> equal(c_popcount(0x7FFFFFFFFFFFFFFFul), 63)
        t |> equal(c_parity(7u), 1)
        t |> equal(c_parity(3ul), 0)
    }
    t |> run("clrsb counts the copies of the sign bit, every bit for 0 and -1") @(t : T?) {
        t |> equal(c_clrsb(0), 31)
        t |> equal(c_clrsb(-1), 31)
        t |> equal(c_clrsb(1), 30)
        t |> equal(c_clrsb(0l), 63)
        t |> equal(c_clrsb(-2l), 62)
    }
    t |> run("the byte swaps and the sign bit") @(t : T?) {
        t |> equal(c_bswap16(uint16(0x1234)), uint16(0x3412))
        t |> equal(c_bswap32(0x12345678u), 0x78563412u)
        t |> equal(c_bswap64(0x0102030405060708ul), 0x0807060504030201ul)
        t |> equal(c_signbit(-0.0lf), 1)
        t |> equal(c_signbit(1.5lf), 0)
        t |> equal(c_signbit(-2.0f), 1)
    }
    t |> run("prefetch evaluates its arguments and does nothing else, spelled as the converter emits p5_gnu_shims.c") @(t : T?) {
        var i = 0
        var arr : int[2]
        unsafe {
            let before = i
            i++
            c_prefetch(reinterpret<void?>(addr(arr[0]) + end_index(before, 2)))
            c_prefetch(reinterpret<void?>(addr(arr[0])), 0)
            c_prefetch(reinterpret<void?>(addr(arr[0])), 1, 3)
        }
        t |> equal(i, 1)
    }
    t |> run("a step inside the argument survives the call: F70 drops it from a call to an effect-free function, and c_prefetch is [sideeffects] for it") @(t : T?) {
        var i = 0
        var arr : int[2]
        unsafe {
            c_prefetch(addr(arr[i++]))
            c_prefetch(addr(arr[i++]), 0)
        }
        t |> equal(i, 2)
    }
    t |> run("unreachable ends the run as abort does") @(t : T?) {
        let r = runtime_child("unreachable", "options gen2\nrequire c_runtime/c_builtins\n[export]\ndef main : int \{\n    print(\"before\\n\")\n    c_unreachable()\n    return 0\n\}\n", false)
        t |> equal(r.rc, 3)
        t |> equal(r.out, "before\n")
    }
}

[test]
def test_c_overflow(t : T?) {
    t |> run("the exact result fits: no flag, whatever the operands' types") @(t : T?) {
        var r : int
        var wide : int64
        var u : uint
        var big : uint64
        unsafe {
            t |> equal(c_add_overflow(2147483647, 1, addr(wide)), false)
            t |> equal(wide, 2147483648l)
            t |> equal(c_add_overflow(-1, 1u, addr(u)), false)
            t |> equal(u, 0u)
            t |> equal(c_sub_overflow(0u, 1, addr(r)), false)
            t |> equal(r, -1)
            t |> equal(c_mul_overflow(int16(-32768), int16(-32768), addr(r)), false)
            t |> equal(r, 1073741824)
            t |> equal(c_mul_overflow(-9223372036854775807l - 1l, -1, addr(big)), false)
            t |> equal(big, 0x8000000000000000ul)
            t |> equal(c_mul_overflow(0xFFFFFFFFl, 0x100000001l, addr(big)), false)
            t |> equal(big, 0xFFFFFFFFFFFFFFFFul)
        }
    }
    t |> run("the exact result does not fit: the flag, and the result cut to its type") @(t : T?) {
        var r : int
        var wide : int64
        var u : uint
        var big : uint64
        var small : int8
        var byte : uint8
        unsafe {
            t |> equal(c_add_overflow(2147483647, 1, addr(r)), true)
            t |> equal(r, -2147483647 - 1)
            t |> equal(c_sub_overflow(0u, 1, addr(u)), true)
            t |> equal(u, 0xFFFFFFFFu)
            t |> equal(c_mul_overflow(int8(-128), int8(-128), addr(small)), true)
            t |> equal(small, int8(0))
            t |> equal(c_add_overflow('a', int8(-128), addr(byte)), true)
            t |> equal(byte, 225u8)
            // a carry out of the low 64 bits, a borrow into them, a product past 128 bits' sign
            t |> equal(c_add_overflow(0xFFFFFFFFFFFFFFFFul, 0xFFFFFFFFFFFFFFFFul, addr(big)), true)
            t |> equal(big, 0xFFFFFFFFFFFFFFFEul)
            t |> equal(c_sub_overflow(-1, 0xFFFFFFFFFFFFFFFFul, addr(wide)), true)
            t |> equal(wide, 0l)
            t |> equal(c_mul_overflow(0xFFFFFFFFFFFFFFFFul, 0xFFFFFFFFFFFFFFFFul, addr(big)), true)
            t |> equal(big, 1ul)
            t |> equal(c_mul_overflow(0xFFFFFFFFFFFFFFFFul, 0xFFFFFFFFFFFFFFFFul, addr(wide)), true)
            t |> equal(c_mul_overflow(0x100000000l, 0x100000000l, addr(big)), true)
            t |> equal(big, 0ul)
            t |> equal(c_mul_overflow(-9223372036854775807l - 1l, -1, addr(wide)), true)
            t |> equal(wide, -9223372036854775807l - 1l)
            t |> equal(c_mul_overflow(-9223372036854775807l - 1l, 0xFFFFFFFFFFFFFFFFul, addr(wide)), true)
        }
    }
    t |> run("an operand as the result, as `__builtin_add_overflow(a, n, &a)` converts") @(t : T?) {
        var a = 0xFFFFFFFEu
        unsafe {
            t |> equal(c_add_overflow(a, 1, addr(a)), false)
            t |> equal(c_add_overflow(a, 2, addr(a)), true)
        }
        t |> equal(a, 1u)
    }
}
