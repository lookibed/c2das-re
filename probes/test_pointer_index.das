options gen2
require dastest/testing_boost public
require _daslang_child
require strings
require daslib/fio
require daslib/strings_boost

// das's pointer index `p[i]` beside `deref(p + i)` (docs/probe-findings.md F100): the same element for
// every index type and sign, one `PtrAt` node where the sum is an `i_das_ptr_add` call under a
// null-checked dereference; prints the reads, then reads a null pointer at index 0 by the spelling
// the last argument names
let private SPELLINGS = "options gen2\nrequire c_runtime/c_function\nrequire daslib/fio\n\n[c_function]\ndef rd_idx(p : int?; i : int) : int \{\n    return p[i]\n\}\n\n[c_function]\ndef rd_deref(p : int?; i : int) : int \{\n    return deref(p + i)\n\}\n\n[c_function]\ndef rd_u(p : int?; i : uint) : int \{\n    return p[i]\n\}\n\n[c_function]\ndef rd_l(p : int?; i : int64) : int \{\n    return p[i]\n\}\n\n[c_function]\ndef wr_idx(var p : int?; i : int; v : int) \{\n    p[i] = v\n\}\n\n[c_function]\ndef sum_idx(p : int?; n : int) : int \{\n    var s = 0\n    var i = 0\n    while (i < n) \{\n        s += p[i]\n        i++\n    \}\n    return s\n\}\n\n[c_function]\ndef sum_deref(p : int?; n : int) : int \{\n    var s = 0\n    var i = 0\n    while (i < n) \{\n        s += deref(p + i)\n        i++\n    \}\n    return s\n\}\n\n[export]\ndef main \{\n    var a : int[8]\n    for (k in range(8)) \{\n        a[k] = k * 10\n    \}\n    unsafe \{\n        let p = addr(a[4])\n        print(\"\{rd_idx(p, -2)\} \{rd_deref(p, -2)\} \{rd_idx(p, 3)\} \{rd_deref(p, 3)\} \{rd_u(p, 2u)\} \{rd_l(p, -3l)\}\\n\")\n        var q = addr(a[0])\n        wr_idx(q, 7, 99)\n        print(\"\{a[7]\} \{sum_idx(q, 8)\} \{sum_deref(q, 8)\}\\n\")\n        let args = get_command_line_arguments()\n        let z : int? = null\n        if (args[length(args) - 1] == \"idx\") \{\n            print(\"\{rd_idx(z, 0)\}\\n\")\n        \} elif (args[length(args) - 1] == \"deref\") \{\n            print(\"\{rd_deref(z, 0)\}\\n\")\n        \}\n    \}\n\}\n"

// the lines of the JIT IR function compiled for the das function `name`
def private jit_body(dump, name : string) : array<string> {
    var body : array<string>
    var inside = false
    for (l in split(dump, "\n")) {
        inside = inside || (l |> starts_with("define ") && l |> contains("`{name} "))
        if (inside) {
            body |> push(l)
            if (l == "\}") {
                break
            }
        }
    }
    return <- body
}

[test]
def test_pointer_index(t : T?) {
    t |> run("`p[i]` reads and writes the element `deref(p + i)` does for an int, uint and int64 index, negative ones included, under the interpreter and the JIT (F100)") @(t : T?) {
        let interp = runtime_child_flags("ptr_index_interp", SPELLINGS, array<string>())
        t |> equal(program_output(interp.out), "20 20 70 70 60 10\n99 309 309\n", interp.out)
        let jit = runtime_child_flags("ptr_index_jit", SPELLINGS, jit_flags())
        t |> success(jit_ran(jit.out), jit.out)
        t |> equal(program_output(jit.out), "20 20 70 70 60 10\n99 309 309\n", jit.out)
    }
    t |> run("a null `deref(p + i)` at index 0 panics naming the `i_das_ptr_add` call the sum is; the JIT's `p[i]` panics naming `p` (F100)") @(t : T?) {
        let modules <- [for (m in RUNTIME_MODULES); m]
        let interp = daslang_run("ptr_index_null", SPELLINGS, array<string>(), modules, "c2das_probe", ["--", "deref"])
        t |> success(interp.rc != 0, interp.out)
        t |> success(interp.out |> contains("i_das_ptr_add(p,i,4) is null"), interp.out)
        let jit = daslang_run("ptr_index_null_jit", SPELLINGS, jit_flags(), modules, "c2das_probe", ["--", "idx"])
        t |> success(jit.rc != 0, jit.out)
        t |> success(jit.out |> contains("p is null"), jit.out)
    }
    t |> run("the JIT null-checks `p` once before a `p[i]` loop and the computed pointer per element in a `deref(p + i)` loop (F100)") @(t : T?) {
        let ir = "{test_temp_dir()}/c2das_probe_ptr_index.ll"
        let r = runtime_child_ir("ptr_index_ir", SPELLINGS, "jit", ir)
        t |> success(program_output(r.out) |> contains("99 309 309"), r.out)
        let dump = fread(ir)
        let idx <- jit_body(dump, "sum_idx")
        let der <- jit_body(dump, "sum_deref")
        t |> success(!empty(idx) && !empty(der), "sum_idx or sum_deref is not in the dump")
        t |> equal(ir_count(idx, "icmp eq ptr %arg_value_0, null"), 1, join(idx, "\n"))
        t |> equal(ir_count(der, "icmp eq ptr %arg_value_0, null"), 0, join(der, "\n"))
        t |> success(ir_count(der, "is null") > 0, join(der, "\n"))
        remove(ir)
    }
}
