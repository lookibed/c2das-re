options gen2
require dastest/testing_boost public
require daslib/fio
require strings
require _daslang_child

def child_path(name : string) : string => "{temp_directory_result() as value}/c2das_probe_{name}.das"

def stdout_of(name, source : string) : string {
    let path = child_path(name)
    fopen(path, "wb") $(f) {
        fwrite(f, source)
    }
    var out = ""
    unsafe(popen("{get_das_root()}/bin/daslang {path} 2>/dev/null", $(f) {
        if (f != null) {
            out = fread(f)
        }
    }))
    remove(path)
    return out
}

let deep_exit = "options gen2\nrequire daslib/fio\ndef deep(n : int) \{\n    if (n == 0) \{\n        print(\"deep\\n\")\n        unsafe \{\n            EXIT_CALL\n        \}\n    \}\n    deep(n - 1)\n\}\n[export]\ndef main \{\n    deep(5)\n    print(\"after\\n\")\n\}\n"

let recursion_arena = "def rec(n : int) : int \{\n    var arena : uint8[131072]\n    arena[n] = uint8(n)\n    if (n == 0) \{\n        return int(arena[0])\n    \}\n    return rec(n - 1) + int(arena[n])\n\}\n[export]\ndef main \{\n    print(\"rec=\{rec(2)\}\\n\")\n\}\n"

[test]
def test_process(t : T?) {
    t |> run("return N from main sets the process exit code") @(t : T?) {
        let r = daslang_child("return", "options gen2\n[export]\ndef main : int \{\n    return 42\n\}\n", false)
        t |> equal(r.rc, 42)
    }
    t |> run("exit(N) from a deep stack reports exit code 1 and prints its call stack on stdout") @(t : T?) {
        let r = daslang_child("exit", deep_exit |> replace("EXIT_CALL", "exit(42)"), false)
        t |> equal(r.rc, 1)
        t |> equal(r.out |> find("deep\n") >= 0, true)
        t |> equal(r.out |> find("after") < 0, true)
        let so = stdout_of("exit_stdout", deep_exit |> replace("EXIT_CALL", "exit(42)"))
        t |> equal(so |> find("CALL STACK") >= 0, true)
    }
    t |> run("exit_now(N) from a deep stack flushes stdout and sets the process exit code") @(t : T?) {
        let r = daslang_child("exit_now", deep_exit |> replace("EXIT_CALL", "exit_now(42)"), false)
        t |> equal(r.rc, 42)
        t |> equal(r.out, "deep\n")
    }
    t |> run("[finalize] runs after main; exit() skips it") @(t : T?) {
        let r = daslang_child("finalize", "options gen2\nvar lst : array<function<() : void>>\ndef a \{\n    print(\"a\\n\")\n\}\ndef b \{\n    print(\"b\\n\")\n\}\n[finalize]\ndef shut \{\n    var i = length(lst) - 1\n    while (i >= 0) \{\n        invoke(lst[i])\n        i--\n    \}\n\}\n[export]\ndef main \{\n    lst |> push(@@a)\n    lst |> push(@@b)\n    print(\"main\\n\")\n\}\n", false)
        t |> equal(r.rc, 0)
        t |> equal(r.out, "main\nb\na\n")
        let skipped = daslang_child("finalize_exit", "options gen2\nrequire daslib/fio\n[finalize]\ndef shut \{\n    print(\"finalize ran\\n\")\n\}\n[export]\ndef main \{\n    unsafe \{\n        exit(3)\n    \}\n\}\n", false)
        t |> equal(skipped.out |> find("finalize ran") < 0, true)
    }
    t |> run("options stack in the main module carries 128KB frames and a 1.2 MB record copy; without it the 16 KiB default overflows") @(t : T?) {
        let ok = daslang_child("stack", "options gen2\noptions stack = 400000\n" + recursion_arena, false)
        t |> equal(ok.rc, 0)
        t |> equal(ok.out, "rec=3\n")
        let overflow = daslang_child("nostack", "options gen2\n" + recursion_arena, false)
        t |> equal(overflow.rc != 0, true)
        t |> equal(overflow.out |> find("stack overflow") >= 0, true)
        // the default context stack is 16 KiB: a record parameter's 20000-byte copy overflows it,
        // and the converter's 8 MiB carries a 1.2 MB one
        let copy = "struct Big \{\n    i : int[SIZE]\n\}\nvar g : Big\ndef rd(b_in : Big) : int \{\n    var b = b_in\n    return b.i[3]\n\}\n[export]\ndef main \{\n    g.i[3] = 7\n    print(\"\{rd(g)\}\\n\")\n\}\n"
        let small_default = daslang_child("copy_default", "options gen2\n" + (copy |> replace("SIZE", "5000")), false)
        t |> equal(small_default.out |> find("stack overflow") >= 0, true, small_default.out)
        let big_raised = daslang_child("copy_raised", "options gen2\noptions stack = 8388608\n" + (copy |> replace("SIZE", "300000")), false)
        t |> equal(big_raised.rc, 0, big_raised.out)
        t |> equal(big_raised.out, "7\n")
    }
    t |> run("shapes the converter must never emit are compile errors") @(t : T?) {
        let control = daslang_child("ok", "options gen2\n[export]\ndef main \{\n    var a : int[3] = fixed_array(1, 2, 3)\n\}\n", true)
        t |> equal(control.rc, 0)
        let small = daslang_child("i8", "options gen2\n[export]\ndef main \{\n    var b : int8 = int8(1)\n    b = b + int8(1)\n\}\n", true)
        t |> equal(small.rc != 0, true)
        t |> equal(small.out |> find("not defined for storage types") >= 0, true)
        let mismatch = daslang_child("fa", "options gen2\n[export]\ndef main \{\n    var part : int[6] = fixed_array(1, 2)\n\}\n", true)
        t |> equal(mismatch.rc != 0, true)
        let bracket = daslang_child("dyn", "options gen2\n[export]\ndef main \{\n    var a : int[3] = [1, 2, 3]\n\}\n", true)
        t |> equal(bracket.rc != 0, true)
        let relational = daslang_child("enum", "options gen2\nenum E \{\n    A\n    B\n\}\n[export]\ndef main \{\n    let e = E.A\n    if (e < E.B) \{\n    \}\n\}\n", true)
        t |> equal(relational.rc != 0, true)
        let fn_null = daslang_child("fnnull", "options gen2\n[export]\ndef main \{\n    var f : function<() : int>\n    f = null\n\}\n", true)
        t |> equal(fn_null.rc != 0, true)
        let no_zero = daslang_child("enum0", "options gen2\nenum E \{\n    A = 3\n\}\n[export]\ndef main \{\n    let e = default<E>\n\}\n", true)
        t |> equal(no_zero.rc != 0, true)
        t |> equal(no_zero.out |> find("missing 0 value") >= 0, true)
        let inlined = daslang_child("inl", "options gen2\nstruct S \{\n    v : int\n\}\n[inline]\ndef operator . a(s : S) : int \{\n    return s.v\n\}\n[export]\ndef main \{\n    var s : S\n    print(\"\{s.a\}\")\n\}\n", true)
        t |> equal(inlined.rc != 0, true)
        t |> equal(inlined.out |> find("[inline] does not support operator") >= 0, true)
    }
}
