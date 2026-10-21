options gen2
require dastest/testing_boost public
require _daslang_child

//! The das facts the pointer-constness policy (docs/implementation_order.md P4.6) rests on: what
//! a `var` pointer or record parameter takes from its caller, why no copy of a `let` record's
//! pointer field is writable, that a function type carries a record position's `var`, and that
//! a write to a `var` scalar or pointer parameter stays in the callee, and which local copy of a
//! pointer parameter writes through its pointee (P4.7a's copy mode).

let PRELUDE = "options gen2
struct S \{
    p : int?
    x : int
\}
struct N \{
    x : int
\}
def bump(var p : int?) \{
    unsafe \{
        *p += 1
    \}
\}
def take_var(var s : S) : int \{
    bump(s.p)
    return s.x
\}
def mk(var p : int?) : S \{
    return S(p = p, x = 2)
\}
"

def private child_output(t : T?; name, body : string) : string {
    let r = daslang_child(name, PRELUDE + body, false)
    t |> equal(r.rc, 0, r.out)
    return program_output(r.out)
}

def private record_rejects(t : T?; name, body, needle : string) {
    child_rejects(t, name, daslang_child(name, PRELUDE + body, true), needle)
}

[test]
def test_param_constness(t : T?) {
    t |> run("a `var` pointer parameter passes on to a `var` parameter down a chain, and the last one's write lands") @(t : T?) {
        let chain = "def c(var p : int?) \{\n    bump(p)\n\}\ndef b(var p : int?) \{\n    c(p)\n\}\ndef a(var p : int?) \{\n    b(p)\n\}\n[export]\ndef main \{\n    var x = 1\n    unsafe \{\n        a(addr(x))\n    \}\n    print(\"\{x\}\\n\")\n\}\n"
        t |> equal(child_output(t, "chain_var", chain), "2\n")
    }
    t |> run("a `let` pointer the caller holds passes to no `var` parameter: a `let` local, a `let` temporary of a call") @(t : T?) {
        record_rejects(t, "let_local_ptr", "[export]\ndef main \{\n    var x = 1\n    let q = unsafe(addr(x))\n    bump(q)\n\}\n", "pointer types can only add constness")
        record_rejects(t, "let_call_ptr", "def same(var p : int?) : int? \{\n    return p\n\}\n[export]\ndef main \{\n    var x = 1\n    let q = same(unsafe(addr(x)))\n    bump(q)\n\}\n", "pointer types can only add constness")
        // the call's value passed in place, a `?:` of two `var` pointers and a sum all pass
        let in_place = "def same(var p : int?) : int? \{\n    return p\n\}\ndef pick(var p : int?; var q : int?; c : bool) \{\n    bump(same(c ? p : q))\n    bump(unsafe(p + 0))\n\}\n[export]\ndef main \{\n    var x = 1\n    unsafe \{\n        pick(addr(x), addr(x), true)\n    \}\n    print(\"\{x\}\\n\")\n\}\n"
        t |> equal(child_output(t, "in_place_ptr", in_place), "3\n")
    }
    t |> run("a `var` record parameter is the caller's object, and takes an r-value: a call's value or a literal") @(t : T?) {
        let aliased = "def touch(var s : S) \{\n    s.x = 99\n\}\n[export]\ndef main \{\n    var x = 1\n    var a = S(p = unsafe(addr(x)), x = 1)\n    touch(a)\n    print(\"\{a.x\} \{take_var(mk(unsafe(addr(x))))\} \{take_var(S(p = unsafe(addr(x)), x = 7))\} \{take_var(a)\} \{x\}\\n\")\n\}\n"
        t |> equal(child_output(t, "var_record", aliased), "99 2 7 99 4\n")
    }
    t |> run("a `let` record parameter is the caller's object too: a write through another pointer during the call shows through it") @(t : T?) {
        let seen = "def f(s : N; var q : N?) : int \{\n    q.x = 5\n    return s.x\n\}\n[export]\ndef main \{\n    var a = N(x = 1)\n    print(\"\{f(a, unsafe(addr(a)))\}\\n\")\n\}\n"
        t |> equal(child_output(t, "let_record_alias", seen), "5\n")
    }
    t |> run("a `var` record parameter takes no `let` record: a local, a global, one read through a const pointer, a `let` parameter") @(t : T?) {
        let needle = "can't ref types can only add constness"
        record_rejects(t, "let_record_local", "[export]\ndef main \{\n    let a = S(x = 1)\n    print(\"\{take_var(a)\}\\n\")\n\}\n", needle)
        record_rejects(t, "let_record_global", "let g = S(x = 2)\n[export]\ndef main \{\n    print(\"\{take_var(g)\}\\n\")\n\}\n", needle)
        record_rejects(t, "const_pointee_record", "def via(var sp : S const?) : int \{\n    return unsafe(take_var(*sp))\n\}\n", needle)
        record_rejects(t, "let_record_param", "def via(s : S) : int \{\n    return take_var(s)\n\}\n", needle)
        // through a `var` pointer the record is writable and passes
        let through = "def via(var sp : S?) : int \{\n    return unsafe(take_var(*sp))\n\}\n[export]\ndef main \{\n    var x = 1\n    var a = S(p = unsafe(addr(x)), x = 5)\n    let r = via(unsafe(addr(a)))\n    print(\"\{r\} \{x\}\\n\")\n\}\n"
        t |> equal(child_output(t, "var_pointee_record", through), "5 2\n")
    }
    t |> run("no copy of a `let` record's pointer field is writable without a reinterpret") @(t : T?) {
        let needle = "pointer types can only add constness"
        record_rejects(t, "field_direct", "def f(s : S) \{\n    bump(s.p)\n\}\n", needle)
        record_rejects(t, "field_var_copy", "def f(s : S) \{\n    var q = s.p\n    bump(q)\n\}\n", "expecting 'int? -const', passing 'int const?&'")
        record_rejects(t, "field_address", "def f(s : S) \{\n    unsafe \{\n        bump(addr(*s.p))\n    \}\n\}\n", needle)
        record_rejects(t, "field_typed_copy", "def f(s : S) \{\n    var q : int? = s.p\n    bump(q)\n\}\n", "initialization type mismatch")
        record_rejects(t, "field_store", "def f(s : S) \{\n    var c : S\n    c.p = s.p\n\}\n", "can't copy constant to non-constant pointer")
        record_rejects(t, "field_return", "def f(s : S) : int? \{\n    return s.p\n\}\n", "incompatible return type")
        // the copies say why: the pointee of every one is const
        let types = "def f(s : S) : string \{\n    var q = s.p\n    let r = unsafe(addr(*s.p))\n    return \"\{typeinfo typename(q)\}|\{typeinfo typename(r)\}\"\n\}\n[export]\ndef main \{\n    var x = 1\n    print(\"\{f(S(p = unsafe(addr(x))))\}\\n\")\n\}\n"
        t |> equal(child_output(t, "field_types", types), "int const?|int const? const\n")
    }
    t |> run("a `let` record holding a pointer copies into no `var` record; one holding none copies") @(t : T?) {
        record_rejects(t, "record_copy", "def f(s : S) : int \{\n    var c = s\n    return c.x\n\}\n", "initialization type mismatch")
        record_rejects(t, "record_clone", "def f(s : S) : int \{\n    var c := s\n    return c.x\n\}\n", "initialization type mismatch")
        let plain = "def f(s : N) : int \{\n    var c = s\n    c.x++\n    return c.x\n\}\n[export]\ndef main \{\n    print(\"\{f(N(x = 1))\}\\n\")\n\}\n"
        t |> equal(child_output(t, "plain_copy", plain), "2\n")
        let var_copy = "def f(var s_in : S) : int \{\n    var s = s_in\n    s.x++\n    bump(s.p)\n    return s.x\n\}\n[export]\ndef main \{\n    var x = 1\n    var a = S(p = unsafe(addr(x)), x = 1)\n    print(\"\{f(a)\} \{a.x\} \{x\}\\n\")\n\}\n"
        t |> equal(child_output(t, "var_record_copy", var_copy), "2 1 2\n")
    }
    t |> run("a function value with a `var` position takes no `let` record's pointer field; a `var` record's passes") @(t : T?) {
        record_rejects(t, "invoke_field", "def f(s : S; fn : function<(var a0 : int?) : void>) \{\n    invoke(fn, s.p)\n\}\n", "pointer types can only add constness")
        record_rejects(t, "invoke_field_copy", "def f(s : S; fn : function<(var a0 : int?) : void>) \{\n    var q = s.p\n    invoke(fn, q)\n\}\n", "expecting 'int? -const', passing 'int const?&'")
        let through = "def f(var s : S; fn : function<(var a0 : int?) : void>) \{\n    invoke(fn, s.p)\n\}\n[export]\ndef main \{\n    var x = 1\n    f(S(p = unsafe(addr(x))), @@bump)\n    print(\"\{x\}\\n\")\n\}\n"
        t |> equal(child_output(t, "invoke_var_field", through), "2\n")
    }
    t |> run("a function type carries a record position's `var`, and `invoke` passes the caller's record by reference") @(t : T?) {
        let records = "def touch(var s : S) \{\n    s.x = 100\n\}\n[export]\ndef main \{\n    let f : function<(var a0 : S) : void> = @@touch\n    var a = S(x = 1)\n    invoke(f, a)\n    var x = 1\n    invoke(f, mk(unsafe(addr(x))))\n    invoke(f, S(x = 3))\n    print(\"\{a.x\}\\n\")\n\}\n"
        t |> equal(child_output(t, "fn_var_record", records), "100\n")
        record_rejects(t, "fn_let_record", "def look(s : S) : int => s.x\n[export]\ndef main \{\n    let f : function<(var a0 : S) : int> = @@look\n\}\n", "not the same type")
        record_rejects(t, "invoke_let_record", "def touch(var s : S) \{\n    s.x = 100\n\}\n[export]\ndef main \{\n    let f : function<(var a0 : S) : void> = @@touch\n    let a = S(x = 1)\n    invoke(f, a)\n\}\n", "expecting 'S -const'")
    }
    t |> run("a `$(var a, b : void?)` block of the runtime's sort makes both parameters `var`") @(t : T?) {
        let sort = "def less(var a : int?; var b : int?) : bool => unsafe(*a < *b)\n[export]\ndef main \{\n    var arr = fixed_array(3, 1, 2)\n    unsafe \{\n        __builtin_sort_any_cblock(addr<void?>(arr[0]), 4, 3) $(var a, b : void?) : bool \{\n            return less(reinterpret<int?>(a), reinterpret<int?>(b))\n        \}\n    \}\n    print(\"\{arr[0]\}\{arr[1]\}\{arr[2]\}\\n\")\n\}\n"
        t |> equal(child_output(t, "sort_var_block", sort), "123\n")
        record_rejects(t, "block_let_param", "def w(var p : int?) \{\n    pass\n\}\n[export]\ndef main \{\n    let blk = $(a : int?; var c : int?) \{\n        w(a)\n        w(c)\n    \}\n\}\n", "pointer types can only add constness")
    }
    t |> run("a write to a `var` scalar or pointer parameter stays in the callee, under the interpreter and the JIT") @(t : T?) {
        let src = PRELUDE + "def set(var q : int?) \{\n    unsafe \{\n        *q = 9\n    \}\n\}\ndef f(var n : int; var p : int?) \{\n    n += 1\n    set(unsafe(addr(n)))\n    p = null\n\}\nvar g = 1\n[export]\ndef main \{\n    var x = 1\n    var s = S(p = unsafe(addr(x)), x = 5)\n    f(g, s.p)\n    f(s.x, s.p)\n    print(\"\{g\} \{s.x\} \{s.p != null\}\\n\")\n\}\n"
        let interp = daslang_child_flags("byval_interp", src, array<string>())
        t |> equal(program_output(interp.out), "1 5 true\n", interp.out)
        let jit = daslang_child_flags("byval_jit", src, jit_flags())
        t |> equal(jit_ran(jit.out), true, jit.out)
        t |> equal(program_output(jit.out), "1 5 true\n", jit.out)
    }
}

[test]
def test_param_copy(t : T?) {
    t |> run("a `var` local copied from a `let` pointer parameter keeps the const pointee; one copied from a `var` parameter writes through it, and its own writes stay in the callee") @(t : T?) {
        record_rejects(t, "let_param_copy_store", "def f(p_in : int?) \{\n    var p = p_in\n    unsafe \{\n        *p = 5\n    \}\n\}\n", "can't write to a constant value")
        record_rejects(t, "let_param_copy_pass", "def f(p_in : int?) \{\n    var p = p_in\n    bump(p)\n\}\n", "no matching functions or generics: bump(int const?&)")
        let copied = "def f(var p_in : int?; n_in : int) : int \{\n    var p = p_in\n    var n = n_in\n    unsafe \{\n        *p = 5\n    \}\n    bump(p)\n    n++\n    p = null\n    return n\n\}\n[export]\ndef main \{\n    var x = 1\n    var q = unsafe(addr(x))\n    var k = 3\n    let r = f(q, k)\n    print(\"\{r\} \{k\} \{x\} \{q != null\}\\n\")\n\}\n"
        t |> equal(child_output(t, "var_param_copy", copied), "4 3 6 true\n")
    }
}
