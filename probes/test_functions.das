options gen2
require dastest/testing_boost public
require strings
require _daslang_child

//! Function values as the converter spells C function pointers: a cast between function types
//! is a `reinterpret`, a call through any type passes the arguments it is given, a parameter's
//! constness is part of the type, and why a C union of function pointers is a storage pun and
//! not a das variant.

// the run-time facts, each a line the child prints; run under the interpreter and the JIT
let CALLS_SOURCE = "options gen2
def first_byte(p : uint8?) : int \{
    unsafe \{
        return int(deref(p))
    \}
\}
def seventy_seven() : int \{
    return 77
\}
def sum3(a, b, c : int) : int \{
    return a + b + c
\}
def bump(var p : int?) \{
    unsafe \{
        deref(p) += 1
    \}
\}
[export]
def main \{
    var x = int(0x01020304)
    unsafe \{
        let by_int = reinterpret<function<(a0 : int?) : int>>(@@first_byte)
        print(\"pointee \{invoke(by_int, addr(x))\}\\n\")
        let erased = reinterpret<function<() : void>>(@@sum3)
        let restored = reinterpret<function<(a0 : int; a1 : int; a2 : int) : int>>(erased)
        print(\"round trip \{invoke(restored, 1, 2, 3)\} \{restored == @@sum3\}\\n\")
        let extra = reinterpret<function<(a0 : int) : int>>(@@seventy_seven)
        print(\"extra argument \{invoke(extra, 5)\}\\n\")
        var y = 1
        let through_var : function<(var a0 : int?) : void> = @@bump
        invoke(through_var, addr(y))
        print(\"var position \{y\}\\n\")
        let sentinel = reinterpret<function<() : void>>(uint64(-1))
        print(\"sentinel \{sentinel == reinterpret<function<() : void>>(uint64(-1))\} \{sentinel != null\}\\n\")
    \}
\}
"

let CALLS_OUTPUT = "pointee 4\nround trip 6 true\nextra argument 77\nvar position 2\nsentinel true true\n"

// an `invoke` whose callee is an `invoke` through a local function value
let NESTED_INVOKE = "options gen2
def inc(v : int) : int \{
    return v + 1
\}
def get(k : int) : function<(a0 : int) : int> \{
    return @@inc
\}
[export]
def main \{
    let gp = @@get
    print(\"\{CALL\}\\n\")
\}
"

variant Action {
    h1 : function<(var a0 : int?) : void>
    h0 : function<() : void>
}

def step(var p : int?) {
    deref(p)++
}

def idle() {
    pass
}

let BUMP = "options gen2\ndef bump(var p : int?) \{\n    unsafe \{\n        deref(p) += 1\n    \}\n\}\ndef reads(p : int?) : int => unsafe(deref(p))\n"

[test]
def test_functions(t : T?) {
    t |> run("a reinterpreted function value calls the function with the arguments the call passes, under the interpreter and the JIT") @(t : T?) {
        let interp = daslang_child_flags("fn_calls", CALLS_SOURCE, array<string>())
        t |> equal(interp.rc, 0, interp.out)
        t |> equal(program_output(interp.out), CALLS_OUTPUT)
        let jit = daslang_child_flags("fn_calls_jit", CALLS_SOURCE, jit_flags())
        t |> equal(jit.rc, 0, jit.out)
        t |> equal(jit_ran(jit.out), true, jit.out)
        t |> equal(program_output(jit.out), CALLS_OUTPUT)
    }
    t |> run("a parameter's constness is part of a function type and its name is not") @(t : T?) {
        child_rejects(t, "fn_let_type", daslang_child("fn_let_type", BUMP + "[export]\ndef main \{\n    let f : function<(a0 : int?) : void> = @@bump\n\}\n", true), "not the same type")
        child_rejects(t, "fn_var_type", daslang_child("fn_var_type", BUMP + "[export]\ndef main \{\n    let f : function<(var a0 : int?) : int> = @@reads\n\}\n", true), "not the same type")
        let named = daslang_child("fn_names", BUMP + "[export]\ndef main \{\n    let f : function<(var q : int?) : void> = @@bump\n    let g : function<(a0 : int?) : int> = @@reads\n\}\n", true)
        t |> equal(named.rc, 0, named.out)
    }
    t |> run("a pointer that is not `var` does not pass to a `var` pointer parameter, by a call or an invoke") @(t : T?) {
        child_rejects(t, "fn_let_call", daslang_child("fn_let_call", BUMP + "def pass_on(p : int?) \{\n    bump(p)\n\}\n", true), "pointer types can only add constness")
        child_rejects(t, "fn_let_invoke", daslang_child("fn_let_invoke", BUMP + "def pass_on(p : int?; f : function<(var a0 : int?) : void>) \{\n    invoke(f, p)\n\}\n", true), "pointer types can only add constness")
    }
    t |> run("the JIT crashes on an invoke whose callee is an invoke of a local function value; a temporary between them runs") @(t : T?) {
        let nested = NESTED_INVOKE |> replace("CALL", "invoke(invoke(gp, 1), 5)")
        let interp = daslang_child_flags("fn_nested_interp", nested, array<string>())
        t |> equal(program_output(interp.out), "6\n", interp.out)
        // the crash comes while the JIT compiles, before it reports; the interpreter runs the same
        let jit = daslang_child_flags("fn_nested_jit", nested, jit_flags())
        t |> equal(jit.out |> find("SIGSEGV") >= 0, true, jit.out)
        let hoisted = NESTED_INVOKE |> replace("    print(\"\{CALL\}\\n\")", "    let g = invoke(gp, 1)\n    print(\"\{invoke(g, 5)\}\\n\")")
        let fixed = daslang_child_flags("fn_hoisted_jit", hoisted, jit_flags())
        t |> equal(jit_ran(fixed.out), true, fixed.out)
        t |> equal(program_output(fixed.out), "6\n", fixed.out)
    }
    t |> run("a variant of function values is twice a C function pointer, and a member store keeps the tag") @(t : T?) {
        t |> equal(typeinfo sizeof(type<Action>), 16)
        var a = Action(h1 = @@step)
        t |> equal(variant_index(a), 0)
        unsafe {
            a.h0 = @@idle
        }
        t |> equal(variant_index(a), 0)
        a = Action(h0 = @@idle)
        t |> equal(variant_index(a), 1)
    }
}

def private empty_hint(_x : int?) {
    pass
}

[sideeffects]
def private kept_hint(_x : int?) {
    pass
}

[test]
def test_empty_call_effects(t : T?) {
    t |> run("a call to an empty function whose argument hides an effect inside `addr` keeps the effect (F70, fixed upstream); [sideeffects] keeps it too (c_prefetch)") @(t : T?) {
        var i = 0
        var arr : int[3]
        empty_hint(unsafe(addr(arr[i++])))
        t |> equal(i, 1)
        kept_hint(unsafe(addr(arr[i++])))
        t |> equal(i, 2)
    }
}

// two mutually recursive functions, one reading a global, the outer called with a constant
let FOLDED_RECURSION = "options gen2\nvar step : int = 4\n\ndef through(n : int) : int => n <= 0 ? 1 : looks_pure(n - 1) + step\n\ndef looks_pure(n : int) : int => n <= 0 ? 2 : through(n - 1) * 2\n\n[export]\ndef main \{\n    let a = looks_pure(2)\n    print(\"\{a\}\\n\")\n\}\n"

[test]
def test_folded_global_read(t : T?) {
    t |> run("a constant-argument call into mutually recursive functions reading a global computes what -no-optimization computes (docs/probe-findings.md F73, fixed upstream)") @(t : T?) {
        // looks_pure(2) = through(1) * 2 = (looks_pure(0) + 4) * 2 = 12
        let honest = daslang_child_flags("folded_recursion_noopt", FOLDED_RECURSION, ["-no-optimization"])
        t |> equal(honest.rc, 0, honest.out)
        t |> equal(honest.out, "12\n")
        let folded = daslang_child_flags("folded_recursion", FOLDED_RECURSION, array<string>())
        t |> equal(folded.rc, 0, folded.out)
        t |> equal(folded.out, "12\n")
    }
}
