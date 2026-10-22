options gen2
require dastest/testing_boost public
require ../../probes/_daslang_child.das

//! A label with nothing after it at the end of an `if` branch and of a function body, as the
//! converter emits it: a goto reaches it with `c_label_end()` after it, and without it the
//! interpreter fails the jump.

def private program(tail : string) : string => "options gen2\nrequire c_runtime/c_label\nvar r = 0\ndef f(c : int) \{\n    if (c == 1) \{\n        goto label 1\n    \}\n    r += 100\n    label 1:  // done\n{tail}\}\ndef g(c : int) : int \{\n    var q = 0\n    if (c > 0) \{\n        if (c == 1) \{\n            goto label 1\n        \}\n        q += 10\n        label 1:  // skip\n    {tail}\}\n    return q\n\}\n[export]\ndef main : int \{\n    f(1)\n    f(2)\n    print(\"\{r\} \{g(1)\} \{g(2)\}\\n\")\n    return 0\n\}\n"

[test]
def test_c_label(t : T?) {
    t |> run("a goto reaches a label that c_label_end() follows at a branch's and a function's end") @(t : T?) {
        let r = runtime_child("label_end", program("    c_label_end()\n"), false)
        t |> equal(r.rc, 0, r.out)
        t |> equal(program_output(r.out), "100 0 10\n")
    }
    t |> run("control: the same label with nothing after it fails the jump under the interpreter") @(t : T?) {
        let r = runtime_child("label_bare", program(""), false)
        child_rejects(t, "label_bare", r, "jump to label 1 failed")
    }
}
