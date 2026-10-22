options gen2
require dastest/testing_boost public
require ../../probes/_daslang_child.das

def program(tail : string) : string =>
    "options gen2\nrequire c_runtime/c_exit\ndef first \{\n    print(\"first\\n\")\n\}\ndef second \{\n    print(\"second\\n\")\n\}\n[export]\ndef main : int \{\n    c_atexit(@@first)\n    c_atexit(@@second)\n    print(\"main\\n\")\n" + tail + "\}\n"

[test]
def test_c_exit(t : T?) {
    t |> run("c_exit runs the handlers LIFO and the process exits with the code") @(t : T?) {
        let r = runtime_child("exit", program("    c_exit(42)\n    return 0\n"), false)
        t |> equal(r.rc, 42)
        t |> equal(r.out, "main\nsecond\nfirst\n")
    }
    t |> run("a normal return from main runs the handlers once through [finalize]") @(t : T?) {
        let r = runtime_child("return", program("    return 7\n"), false)
        t |> equal(r.rc, 7)
        t |> equal(r.out, "main\nsecond\nfirst\n")
    }
    t |> run("a normal return from main flushes every C stream while the context lives, a buffer setvbuf took from das memory included") @(t : T?) {
        let body = "options gen2\nrequire crt\nrequire c_runtime/c_exit\nvar buf : uint8[4096]\n[export]\ndef main : int \{\n    unsafe \{\n        crt::setvbuf(crt::c_stdout(), addr(buf[0]), 0, 4096ul)\n        crt::fputs(reinterpret<uint8?>(\"buffered line\\n\"), crt::c_stdout())\n    \}\n    return 0\n\}\n"
        let r = runtime_child("setvbuf_flush", body, false)
        t |> equal(r.rc, 0)
        t |> equal(r.out, "buffered line\n")
    }
    t |> run("c_abort exits 3 and runs no handler") @(t : T?) {
        let r = runtime_child("abort", program("    c_abort()\n    return 0\n"), false)
        t |> equal(r.rc, 3)
        t |> equal(r.out, "main\n")
    }
}
