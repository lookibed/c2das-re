options gen2
require dastest/testing_boost public
require c_runtime/c_builtins
require ../../probes/_daslang_child.das

//! The GCC builtins the converter maps by name (`converter/tests/fixtures/p5_gnu_shims.c` calls
//! each the way the converter spells it): the answers C gives at both operand widths.

[test]
def test_c_builtins(t : T?) {
    t |> run("the bit counts at 32 and 64 bits") @(t : T?) {
        t |> equal(c_ffs(0), 0)
        t |> equal(c_ffs(12), 3)
        t |> equal(c_ffs(int(0x80000000u)), 32)
        t |> equal(c_ffs(1l << 40l), 41)
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
    t |> run("prefetch evaluates its arguments and does nothing else") @(t : T?) {
        var i = 0
        var arr : int[2]
        unsafe {
            c_prefetch(addr(arr[i++]))
            c_prefetch(addr(arr[0]), 1, 3)
        }
        t |> equal(i, 1)
    }
    t |> run("unreachable ends the run as abort does") @(t : T?) {
        let r = runtime_child("unreachable", "options gen2\nrequire c_runtime/c_builtins\n[export]\ndef main : int \{\n    print(\"before\\n\")\n    c_unreachable()\n    return 0\n\}\n", false)
        t |> equal(r.rc, 3)
        t |> equal(r.out, "before\n")
    }
}
