options gen2
require dastest/testing_boost public
require _daslang_child
require strings
require daslib/fio
require daslib/strings_boost

// the TBAA shape of docs/probe-findings.md F89: a float loop whose bound and factor are int reads through
// pointers; clang hoists both under strict aliasing (a float store cannot alias an int) and vectorizes; without
// TBAA the bound reloads after every store and the loop is uncountable (prints the sum of the eight scaled values, i + 3 each, 52)
let private TYPED_LOOP = "options gen2\nrequire c_runtime/c_function\n\n[c_function]\ndef scale(var fa : float?; n_ptr : int?; k_ptr : int?) \{\n    var i = 0\n    while (i < deref(n_ptr)) \{\n        deref(fa + i) = deref(fa + i) * 0.5f + float(deref(k_ptr))\n        i++\n    \}\n\}\n\n[export]\ndef main \{\n    var fa : float[8]\n    var ctl : int[2]\n    ctl[0] = 8\n    ctl[1] = 3\n    for (i in range(8)) \{\n        fa[i] = float(i * 2)\n    \}\n    unsafe \{\n        scale(addr(fa[0]), addr(ctl[0]), addr(ctl[1]))\n    \}\n    var sum = 0.0f\n    for (i in range(8)) \{\n        sum += fa[i]\n    \}\n    print(\"\{int(sum)\}\\n\")\n\}\n"

[test]
def test_jit_tbaa(t : T?) {
    t |> run("the JIT's IR carries no `!tbaa` on loads and stores through typed pointers, so a loop bounded by an `int?` read reloads it after every `float?` store and stays scalar (docs/probe-findings.md F89)") @(t : T?) {
        let ir = "{temp_directory_result() as value}/c2das_probe_jit_tbaa.ll"
        let jit = daslang_run("jit_tbaa", TYPED_LOOP, jit_flags(), [for (m in RUNTIME_MODULES); m], "c2das_probe", ["--", "--jit-dump", "--jit-dump-to", ir])
        t |> equal(jit.out |> ends_with("52\n"), true, jit.out)
        let dump = fread(ir)
        let at = dump |> find("`scale ")
        let body = at >= 0 ? slice(dump, at, dump |> find("\n\}\n", at)) : ""
        t |> success(at >= 0, "scale is not in the dump")
        // the typed accesses are there, and none carries TBAA metadata
        t |> success(body |> contains("load float, ptr"), body)
        t |> success(body |> contains("load i32, ptr"), body)
        t |> equal(dump |> contains("!tbaa"), false, "the JIT now emits TBAA metadata: F89 is stale, re-read the issue")
        // the consequence: scalar arithmetic only (clang's TBAA build of the same loop has `fmul <4 x float>`;
        // daslib's own float4 math elsewhere in the dump is why the check is on the body)
        t |> equal(body |> contains("fmul <"), false, body)
        remove(ir)
    }
}
