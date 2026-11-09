options gen2
require dastest/testing_boost public
require _daslang_child
require strings
require daslib/strings_boost

//! The JIT's alignment claim on typed pointer parameters (docs/probe-findings.md F98,
//! lookibed/daScript#46): a `T?` parameter is emitted `align alignof(T)`, so a pointer value that
//! is not that aligned is poison to LLVM, which folds every test on it; the interpreter runs the
//! same program as written. gcc-torture 960116-1 and 20001101 fail under `-jit` by it.

// a load guarded by an odd-address test, reached with 0xffffffff: the guard keeps the load from
// running under the interpreter; `g`'s `[sideeffects]` keeps it a function of its own
let private GUARDED_LOAD = "options gen2\n\ndef odd_free(p : int?) : bool \{\n    return (intptr(p) & 1ul) == 0ul\n\}\n\ndef f(q : int?) : int \{\n    unsafe \{\n        if (odd_free(q) && deref(q) != 0) \{\n            return 1\n        \}\n        return 0\n    \}\n\}\n\n[sideeffects]\ndef g : int \{\n    unsafe \{\n        return f(reinterpret<int?>(0xffffffffu))\n    \}\n\}\n\n[export]\ndef main : int \{\n    return g()\n\}\n"

// a pointer parameter compared with an odd constant pointer another function stored: equal, so
// the program exits 0 under the interpreter
let private ODD_COMPARE = "options gen2\n\nstruct S \{\n    bits : uint\n\}\n\ndef dummy(var a : int?; var b : S??) : S? \{\n    unsafe \{\n        deref(a) = 1\n        deref(b) = reinterpret<S?>(uint64(7))\n        return reinterpret<S?>(uint64(1))\n    \}\n\}\n\n[sideeffects]\ndef bogus(var insn : S?; var thread : S?; var delay_list : S?) : int \{\n    unsafe \{\n        var new_thread : S?\n        var must_annul : int\n        delay_list = dummy(addr(must_annul), addr(new_thread))\n        if (delay_list == null && new_thread != null) \{\n            thread = new_thread\n        \}\n        if (delay_list != null && must_annul != 0) \{\n            insn.bits = 1u\n        \}\n        if (intptr(new_thread) != intptr(thread)) \{\n            return 3\n        \}\n        return 0\n    \}\n\}\n\n[export]\ndef main : int \{\n    var baz : S\n    unsafe \{\n        return bogus(addr(baz), reinterpret<S?>(uint64(7)), null)\n    \}\n\}\n"

[test]
def test_jit_pointer_align(t : T?) {
    t |> run("a load guarded by `(intptr(q) & 1) == 0` does not run under the interpreter; the JIT deletes the guard, loads 0xffffffff and faults") @(t : T?) {
        let interp = daslang_child_flags("align_guard_interp", GUARDED_LOAD, array<string>())
        t |> equal(interp.rc, 0, interp.out)
        let jit = daslang_child_flags("align_guard_jit", GUARDED_LOAD, jit_flags())
        t |> success(jit_ran(jit.out), jit.out)
        t |> success(jit.out |> contains("SIGSEGV"), jit.out)
        t |> success(jit.out |> contains("0xffffffff"), jit.out)
    }
    t |> run("an `S?` parameter equal to the odd pointer 7 compares equal under the interpreter; the JIT folds the comparison to unequal (exit 3)") @(t : T?) {
        let interp = daslang_child_flags("align_compare_interp", ODD_COMPARE, array<string>())
        t |> equal(interp.rc, 0, interp.out)
        let jit = daslang_child_flags("align_compare_jit", ODD_COMPARE, jit_flags())
        t |> success(jit_ran(jit.out), jit.out)
        t |> equal(jit.rc, 3, jit.out)
    }
}
