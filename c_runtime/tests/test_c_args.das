options gen2
require dastest/testing_boost public
require ../../probes/_daslang_child.das
require strings

// the wrapper the converter writes for `int main(int argc, char **argv)` (the converted
// `converter/tests/fixtures/p4_main_args.c`), around a `c_main` that prints what it got and
// writes into its first argument
let PROGRAM = "options gen2\nrequire c_runtime/c_args\nrequire c_runtime/c_function\n[c_function]\ndef c_main(argc : int; var argv : uint8 ??) : int \{\n    for (i in range(argc)) \{\n        print(\"[\{reinterpret<string>(deref(argv + i))\}]\")\n    \}\n    print(\" \{deref(argv + argc) == null\}\")\n    if (argc > 1) \{\n        deref(deref(argv + 1)) = uint8('X')\n        print(\" \{reinterpret<string>(deref(argv + 1))\}\")\n    \}\n    c_runtime_init(\"again\")\n    print(\" \{reinterpret<string>(deref(c_argv()))\} \{c_argc()\}\\n\")\n    return argc\n\}\n[export]\ndef main : int \{\n    c_runtime_init(\"p4_main_args\")\n    return c_main(c_argc(), c_argv())\n\}\n"

def run_program(name : string; args : array<string>) : tuple<rc : int; out : string> {
    let no_flags : array<string>
    return daslang_run(name, PROGRAM, no_flags, [for (m in RUNTIME_MODULES); m], "c2das_c_runtime", args)
}

[test]
def test_c_args(t : T?) {
    t |> run("argv is the program's name, each argument after `--`, then null; argc counts the name") @(t : T?) {
        let r = run_program("args", ["--", "one", "two words", ""])
        t |> equal(r.rc, 4, r.out)
        t |> equal(r.out, "[p4_main_args][one][two words][] true Xne p4_main_args 4\n")
    }
    t |> run("with no arguments argv holds the name alone") @(t : T?) {
        let no_args : array<string>
        let r = run_program("no_args", no_args)
        t |> equal(r.rc, 1, r.out)
        t |> equal(r.out, "[p4_main_args] true p4_main_args 1\n")
    }
    t |> run("control: the wrapper without the piece does not compile") @(t : T?) {
        let r = runtime_child("no_piece", PROGRAM |> replace("require c_runtime/c_args\n", ""), true)
        child_rejects(t, "no_piece", r, "c_runtime_init")
    }
}
