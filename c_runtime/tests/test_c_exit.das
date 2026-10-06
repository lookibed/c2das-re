options gen2
require dastest/testing_boost public
require daslib/fio

def run_child(name, source : string) : tuple<rc : int; out : string> {
    let path = "{temp_directory_result() as value}/c2das_c_exit_{name}.das"
    fopen(path, "wb") $(f) {
        fwrite(f, source)
    }
    var out : string
    let rc = run_and_capture([get_das_root() + "/bin/daslang", "-load_module", "c_runtime", path], out, 60.0)
    remove(path)
    return (rc, out)
}

def program(tail : string) : string {
    return "options gen2\nrequire c_runtime/c_exit\ndef first \{\n    print(\"first\\n\")\n\}\ndef second \{\n    print(\"second\\n\")\n\}\n[export]\ndef main : int \{\n    c_atexit(@@first)\n    c_atexit(@@second)\n    print(\"main\\n\")\n" + tail + "\}\n"
}

[test]
def test_c_exit(t : T?) {
    t |> run("c_exit runs the handlers LIFO and the process exits with the code") @(t : T?) {
        let r = run_child("exit", program("    c_exit(42)\n    return 0\n"))
        t |> equal(r.rc, 42)
        t |> equal(r.out, "main\nsecond\nfirst\n")
    }
    t |> run("a normal return from main runs the handlers once through [finalize]") @(t : T?) {
        let r = run_child("return", program("    return 7\n"))
        t |> equal(r.rc, 7)
        t |> equal(r.out, "main\nsecond\nfirst\n")
    }
    t |> run("c_abort exits 3 and runs no handler") @(t : T?) {
        let r = run_child("abort", program("    c_abort()\n    return 0\n"))
        t |> equal(r.rc, 3)
        t |> equal(r.out, "main\n")
    }
}
