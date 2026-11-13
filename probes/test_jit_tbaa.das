options gen2
require dastest/testing_boost public
require _daslang_child
require strings
require daslib/fio
require daslib/strings_boost

//! The JIT's typed aliasing model (docs/probe-findings.md F95): every load and store of a jitted
//! function carries a `!tbaa` tag of its class (`float`, `double`, one class for every wider integer
//! and pointer); a function whose body holds a punning `reinterpret` is left untagged; the program
//! option `strict_aliasing` and the hints `strict_aliasing` and `no_strict_aliasing` switch it.

// a float loop whose bound and factor are int reads through pointers; with tags the reads leave the
// loop and it vectorizes, as clang's strict-aliasing build does (prints the sum of the eight scaled
// values, i + 3 each, 52); `{OPTIONS}` and `{HINT}` are where the variants put their switch
let private TYPED_LOOP = "options gen2\n\{OPTIONS\}require c_runtime/c_function\n\n[c_function\{HINT\}]\ndef scale(var fa : float?; n_ptr : int?; k_ptr : int?) \{\n    var i = 0\n    while (i < deref(n_ptr)) \{\n        deref(fa + i) = deref(fa + i) * 0.5f + float(deref(k_ptr))\n        i++\n    \}\n\}\n\n[export]\ndef main \{\n    var fa : float[8]\n    var ctl : int[2]\n    ctl[0] = 8\n    ctl[1] = 3\n    for (i in range(8)) \{\n        fa[i] = float(i * 2)\n    \}\n    unsafe \{\n        scale(addr(fa[0]), addr(ctl[0]), addr(ctl[1]))\n    \}\n    var sum = 0.0f\n    for (i in range(8)) \{\n        sum += fa[i]\n    \}\n    print(\"\{int(sum)\}\\n\")\n\}\n"

// one float written as `2.0f`, then as the bits of `1.0f`, then read: through two `void?` parameters
// reinterpreted, and through a `float?` and a `uint?` reinterpreted from another `float?`; both
// functions noinline, so the JIT cannot see the two pointers are one
let private TWO_VIEWS = "options gen2\n\n[hint(noinline)]\ndef via_void(p, q : void?) : float \{\n    unsafe \{\n        var f = reinterpret<float?>(p)\n        var u = reinterpret<uint?>(q)\n        *f = 2.0f\n        *u = 0x3f800000u\n        return *f\n    \}\n\}\n\n[hint(noinline)]\ndef via_float(var f : float?; q : float?) : float \{\n    unsafe \{\n        var u = reinterpret<uint?>(q)\n        *f = 2.0f\n        *u = 0x3f800000u\n        return *f\n    \}\n\}\n\n[export]\ndef main \{\n    var x = 0.0f\n    unsafe \{\n        print(\"\{via_void(addr(x), addr(x))\} \{via_float(addr(x), addr(x))\}\\n\")\n    \}\n\}\n"

// the loop with `options` lines and a hint spliced in
def private loop_source(option_lines, hint : string) : string =>
    TYPED_LOOP |> replace("\{OPTIONS\}", option_lines) |> replace("\{HINT\}", hint)

// the JIT run of `source` and the IR of its function `scale`, spelled `fn` in the dump (`--jit-dump=<file>`)
def private scale_ir(t : T?; name, source : string; fn : string = "scale") : string {
    let ir = "{temp_directory_result() as value}/c2das_probe_{name}.ll"
    let jit = daslang_run(name, source, jit_flags(), [for (m in RUNTIME_MODULES); m], "c2das_probe", ["--", "--jit-dump={ir}"])
    t |> equal(jit.out |> ends_with("52\n"), true, jit.out)
    let dump = fread(ir)
    remove(ir)
    let body = join(ir_function(dump, fn, 1), "\n")
    t |> success(!empty(body), "scale is not in the dump:\n{jit.out}")
    return body
}

[test]
def test_jit_tbaa(t : T?) {
    t |> run("the JIT tags typed loads and stores with `!tbaa` by class: a loop bounded by an `int?` read beside `float?` stores hoists the read and vectorizes") @(t : T?) {
        let body = scale_ir(t, "tbaa_on", loop_source("", ""))
        t |> success(body |> contains("load float, ptr"), body)
        t |> success(body |> contains("!tbaa"), body)
        t |> success(body |> contains("fmul <"), body)
    }
    t |> run("`options strict_aliasing = false` in the root module takes every tag out, and the loop stays scalar") @(t : T?) {
        let body = scale_ir(t, "tbaa_root_off", loop_source("options strict_aliasing = false\n", ""))
        t |> equal(body |> contains("!tbaa"), false, body)
        t |> equal(body |> contains("fmul <"), false, body)
    }
    t |> run("`[hint(no_strict_aliasing)]` takes one function out of the model") @(t : T?) {
        let body = scale_ir(t, "tbaa_hint_off", loop_source("", ", hint(no_strict_aliasing)"))
        t |> equal(body |> contains("!tbaa"), false, body)
    }
    t |> run("`options strict_aliasing = false` in a required module is ignored: the option is the root program's alone") @(t : T?) {
        let dir = temp_directory_result() as value
        let module_path = "{dir}/c2das_probe_tbaa_mod.das"
        let lines <- split(loop_source("options strict_aliasing = false\nmodule c2das_probe_tbaa_mod public\n", ""), "\n")
        let main_at = find_index(lines, "[export]")
        fwrite(module_path, join([for (i in range(main_at)); lines[i]], "\n"))
        let root = "options gen2\nrequire c2das_probe_tbaa_mod\n\n" + join([for (i in range(main_at, length(lines))); lines[i]], "\n")
        let body = scale_ir(t, "tbaa_module_off", root, "c2das_probe_tbaa_mod::scale")
        remove(module_path)
        t |> success(body |> contains("!tbaa"), body)
    }
    t |> run("a `reinterpret` from `void?` is a pun to the model like one from `float?`: both views of one float read `1.0f` under the JIT, both functions untagged (lookibed/daScript#44, fixed upstream)") @(t : T?) {
        let interp = daslang_run("tbaa_views", TWO_VIEWS, array<string>(), array<string>(), "c2das_probe")
        t |> equal(program_output(interp.out), "1 1\n")
        let jit = daslang_run("tbaa_views", TWO_VIEWS, jit_flags(), array<string>(), "c2das_probe")
        t |> equal(program_output(jit.out), "1 1\n", jit.out)
        t |> success(jit.out |> contains("strict aliasing - 2 of 3 functions untagged (punning 2"), jit.out)
    }
}
