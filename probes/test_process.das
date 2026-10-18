options gen2
require dastest/testing_boost public
require daslib/fio
require strings

def child_path(name : string) : string => "{temp_directory_result() as value}/c2das_probe_{name}.das"

def run_child(name, source : string) : tuple<rc : int; out : string> {
    let path = child_path(name)
    fopen(path, "wb") $(f) {
        fwrite(f, source)
    }
    var out : string
    let rc = run_and_capture([get_das_root() + "/bin/daslang", path], out, 60.0)
    remove(path)
    return (rc, out)
}

def compile_child(name, source : string) : tuple<rc : int; out : string> {
    let path = child_path(name)
    fopen(path, "wb") $(f) {
        fwrite(f, source)
    }
    var out : string
    let rc = run_and_capture([get_das_root() + "/bin/daslang", "-compile-only", path], out, 60.0)
    remove(path)
    return (rc, out)
}

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
        let r = run_child("return", "options gen2\n[export]\ndef main : int \{\n    return 42\n\}\n")
        t |> equal(r.rc, 42)
    }
    t |> run("exit(N) from a deep stack reports exit code 1 and prints its call stack on stdout") @(t : T?) {
        let r = run_child("exit", deep_exit |> replace("EXIT_CALL", "exit(42)"))
        t |> equal(r.rc, 1)
        t |> equal(r.out |> find("deep\n") >= 0, true)
        t |> equal(r.out |> find("after") < 0, true)
        let so = stdout_of("exit_stdout", deep_exit |> replace("EXIT_CALL", "exit(42)"))
        t |> equal(so |> find("CALL STACK") >= 0, true)
    }
    t |> run("exit_now(N) from a deep stack flushes stdout and sets the process exit code") @(t : T?) {
        let r = run_child("exit_now", deep_exit |> replace("EXIT_CALL", "exit_now(42)"))
        t |> equal(r.rc, 42)
        t |> equal(r.out, "deep\n")
    }
    t |> run("[finalize] runs after main; exit() skips it") @(t : T?) {
        let r = run_child("finalize", "options gen2\nvar lst : array<function<() : void>>\ndef a \{\n    print(\"a\\n\")\n\}\ndef b \{\n    print(\"b\\n\")\n\}\n[finalize]\ndef shut \{\n    var i = length(lst) - 1\n    while (i >= 0) \{\n        invoke(lst[i])\n        i--\n    \}\n\}\n[export]\ndef main \{\n    lst |> push(@@a)\n    lst |> push(@@b)\n    print(\"main\\n\")\n\}\n")
        t |> equal(r.rc, 0)
        t |> equal(r.out, "main\nb\na\n")
        let skipped = run_child("finalize_exit", "options gen2\nrequire daslib/fio\n[finalize]\ndef shut \{\n    print(\"finalize ran\\n\")\n\}\n[export]\ndef main \{\n    unsafe \{\n        exit(3)\n    \}\n\}\n")
        t |> equal(skipped.out |> find("finalize ran") < 0, true)
    }
    t |> run("options stack in the main module carries 128KB frames; without it the recursion overflows") @(t : T?) {
        let ok = run_child("stack", "options gen2\noptions stack = 400000\n" + recursion_arena)
        t |> equal(ok.rc, 0)
        t |> equal(ok.out, "rec=3\n")
        let overflow = run_child("nostack", "options gen2\n" + recursion_arena)
        t |> equal(overflow.rc != 0, true)
        t |> equal(overflow.out |> find("stack overflow") >= 0, true)
    }
    t |> run("shapes the converter must never emit are compile errors") @(t : T?) {
        let control = compile_child("ok", "options gen2\n[export]\ndef main \{\n    var a : int[3] = fixed_array(1, 2, 3)\n\}\n")
        t |> equal(control.rc, 0)
        let small = compile_child("i8", "options gen2\n[export]\ndef main \{\n    var b : int8 = int8(1)\n    b = b + int8(1)\n\}\n")
        t |> equal(small.rc != 0, true)
        t |> equal(small.out |> find("not defined for storage types") >= 0, true)
        let mismatch = compile_child("fa", "options gen2\n[export]\ndef main \{\n    var part : int[6] = fixed_array(1, 2)\n\}\n")
        t |> equal(mismatch.rc != 0, true)
        let bracket = compile_child("dyn", "options gen2\n[export]\ndef main \{\n    var a : int[3] = [1, 2, 3]\n\}\n")
        t |> equal(bracket.rc != 0, true)
        let relational = compile_child("enum", "options gen2\nenum E \{\n    A\n    B\n\}\n[export]\ndef main \{\n    let e = E.A\n    if (e < E.B) \{\n    \}\n\}\n")
        t |> equal(relational.rc != 0, true)
        let no_zero = compile_child("enum0", "options gen2\nenum E \{\n    A = 3\n\}\n[export]\ndef main \{\n    let e = default<E>\n\}\n")
        t |> equal(no_zero.rc != 0, true)
        t |> equal(no_zero.out |> find("missing 0 value") >= 0, true)
        let inlined = compile_child("inl", "options gen2\nstruct S \{\n    v : int\n\}\n[inline]\ndef operator . a(s : S) : int \{\n    return s.v\n\}\n[export]\ndef main \{\n    var s : S\n    print(\"\{s.a\}\")\n\}\n")
        t |> equal(inlined.rc != 0, true)
        t |> equal(inlined.out |> find("[inline] does not support operator") >= 0, true)
    }
}
