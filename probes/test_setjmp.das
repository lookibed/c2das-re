options gen2
require dastest/testing_boost public
require _daslang_child

struct CJmpBuf {
    val : int
}

var _c_jmp_target : CJmpBuf?
var outer_buf : CJmpBuf
var inner_buf : CJmpBuf
var finally_ran = false

def c_longjmp(var buf : CJmpBuf; v : int) {
    buf.val = v == 0 ? 1 : v
    _c_jmp_target = unsafe(addr(buf))
    panic("longjmp")
}

def deep(n : int; var target : CJmpBuf) {
    if (n == 0) {
        c_longjmp(target, 7)
    }
    deep(n - 1, target)
}

def inner_site(var log : array<string>; jump_outer : bool) {
    try {
        {
            if (jump_outer) {
                deep(3, outer_buf)
            } else {
                deep(3, inner_buf)
            }
        } finally {
            finally_ran = true
        }
    } recover {
        if (_c_jmp_target != unsafe(addr(inner_buf))) {
            panic("longjmp")
        }
        _c_jmp_target = null
        log |> push("inner caught {inner_buf.val}")
    }
}

[test]
def test_setjmp(t : T?) {
    t |> run("the nearest site catches its own buffer with the value; finally is skipped on panic") @(t : T?) {
        var log : array<string>
        finally_ran = false
        try {
            inner_site(log, false)
            log |> push("continued")
        } recover {
            log |> push("outer ran")
        }
        t |> equal("{log}", "[ inner caught 7, continued]")
        t |> equal(finally_ran, false)
    }
    t |> run("a targeted jump passes an inner recover by rethrow") @(t : T?) {
        var log : array<string>
        try {
            inner_site(log, true)
        } recover {
            if (_c_jmp_target != unsafe(addr(outer_buf))) {
                panic("longjmp")
            }
            _c_jmp_target = null
            log |> push("outer caught {outer_buf.val}")
        }
        t |> equal("{log}", "[ outer caught 7]")
    }
    t |> run("a genuine panic passes through with a null target") @(t : T?) {
        var log : array<string>
        try {
            try {
                panic("genuine")
            } recover {
                if (_c_jmp_target != unsafe(addr(inner_buf))) {
                    panic("rethrow")
                }
                log |> push("wrong")
            }
        } recover {
            log |> push("passed target_null={_c_jmp_target == null}")
        }
        t |> equal("{log}", "[ passed target_null=true]")
    }
    t |> run("longjmp value 0 coerces to 1") @(t : T?) {
        var zero : CJmpBuf
        try {
            c_longjmp(zero, 0)
        } recover {
            _c_jmp_target = null
        }
        t |> equal(zero.val, 1)
    }
}

// a panic crossing between a JIT-compiled function and a `[no_jit]` one, which the JIT leaves to
// the interpreter, each way: `5 6` when both recovers catch
let MIXED_TIERS = "options gen2\n[no_jit]\ndef interp_thrower \{\n    panic(\"i\")\n\}\ndef jit_thrower \{\n    panic(\"j\")\n\}\ndef jit_catches : int \{\n    var r = 0\n    try \{\n        interp_thrower()\n    \} recover \{\n        r = 5\n    \}\n    return r\n\}\n[no_jit]\ndef interp_catches : int \{\n    var r = 0\n    try \{\n        jit_thrower()\n    \} recover \{\n        r = 6\n    \}\n    return r\n\}\n[export]\ndef main \{\n    print(\"\{jit_catches()\} \{interp_catches()\}\\n\")\n\}\n"

// a `return` inside a try block after a call, with no panic, and inside a recover block, which
// daslang refuses on every tier (lookibed/daScript#30, upstream #4472)
let RETURN_IN_TRY = "options gen2\ndef thrower(n : int) \{\n    if (n > 0) \{\n        panic(\"x\")\n    \}\n\}\ndef in_try : int \{\n    try \{\n        thrower(0)\n        return 1\n    \} recover \{\n        pass\n    \}\n    return 10\n\}\ndef in_recover : int \{\n    try \{\n        thrower(1)\n    \} recover \{\n        return 7\n    \}\n    return 20\n\}\n[export]\ndef main \{\n    print(\"\{in_try()\} \{in_recover()\}\\n\")\n\}\n"

// the lowering of a return inside an arm (F96): the arm is a block invoked for whether it
// returned, the value left in a local the function returns after the pair; `in_loop` returns
// from inside a loop of the block
let RETURN_IN_BLOCK = "options gen2\ndef thrower(n : int) \{\n    if (n > 0) \{\n        panic(\"x\")\n    \}\n\}\ndef in_try : int \{\n    var ret : int\n    var returned = false\n    try \{\n        returned = invoke($() : bool \{\n            thrower(0)\n            ret = 1\n            return true\n        \})\n    \} recover \{\n        pass\n    \}\n    if (returned) \{\n        return ret\n    \}\n    return 10\n\}\ndef in_recover : int \{\n    var ret : int\n    var returned = false\n    try \{\n        thrower(1)\n    \} recover \{\n        returned = invoke($() : bool \{\n            ret = 7\n            return true\n        \})\n    \}\n    if (returned) \{\n        return ret\n    \}\n    return 20\n\}\ndef in_loop : int \{\n    var ret : int\n    var returned = false\n    try \{\n        returned = invoke($() : bool \{\n            for (i in range(10)) \{\n                if (i == 3) \{\n                    ret = i * 10\n                    return true\n                \}\n            \}\n            return false\n        \})\n    \} recover \{\n        pass\n    \}\n    if (returned) \{\n        return ret\n    \}\n    return 40\n\}\n[export]\ndef main \{\n    print(\"\{in_try()\} \{in_recover()\} \{in_loop()\}\\n\")\n\}\n"

[test]
def test_setjmp_tiers(t : T?) {
    t |> run("under the JIT a panic crosses from a [no_jit] function to a JIT-compiled recover and back") @(t : T?) {
        let interp = daslang_child_flags("setjmp_mixed", MIXED_TIERS, array<string>())
        t |> equal(interp.out, "5 6\n", interp.out)
        let jit = daslang_child_flags("setjmp_mixed_jit", MIXED_TIERS, jit_flags())
        t |> success(jit_ran(jit.out), jit.out)
        t |> equal(program_output(jit.out), "5 6\n", jit.out)
    }
    t |> run("a return inside a try or a recover arm is compile error 30299 under the interpreter and the JIT alike (docs/probe-findings.md F75, F96)") @(t : T?) {
        child_rejects(t, "setjmp_return", daslang_child_flags("setjmp_return", RETURN_IN_TRY, array<string>()), "error[30299]: return inside a try/recover arm")
        child_rejects(t, "setjmp_return_jit", daslang_child_flags("setjmp_return_jit", RETURN_IN_TRY, jit_flags()), "error[30299]: return inside a try/recover arm")
    }
    t |> run("a return inside a block an arm invokes leaves the block, which answers whether it returned, under the interpreter and the JIT (docs/probe-findings.md F96)") @(t : T?) {
        let interp = daslang_child_flags("setjmp_block_return", RETURN_IN_BLOCK, array<string>())
        t |> equal(interp.out, "1 7 30\n", interp.out)
        let jit = daslang_child_flags("setjmp_block_return_jit", RETURN_IN_BLOCK, jit_flags())
        t |> success(jit_ran(jit.out), jit.out)
        t |> equal(program_output(jit.out), "1 7 30\n", jit.out)
    }
}
