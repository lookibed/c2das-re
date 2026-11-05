options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../../probes/_daslang_child.das
require ../../converter/tiers.das

//! The `[llvm_code]` generators of `c_volatile_jit.das` under every tier: each width of
//! `c_volatile_load` and `c_volatile_store` reads back what it stored, and under the JIT and the
//! exe (one LLVM module, or one per das module as the cached DLL) each is one inlined `load volatile` or
//! `store volatile` of its LLVM type, `bool` a forwarder call (docs/probe-findings.md F91).
//! One scalar width of `widths_source`: the field `name` of das type `das_type`, which the JIT's
//! IR spells `llvm`.
struct Width {
    name : string
    das_type : string
    llvm : string
}

let WIDTHS <- [
    Width(name = "i8", das_type = "int8", llvm = "i8"), Width(name = "u8", das_type = "uint8", llvm = "i8"),
    Width(name = "i16", das_type = "int16", llvm = "i16"), Width(name = "u16", das_type = "uint16", llvm = "i16"),
    Width(name = "i32", das_type = "int", llvm = "i32"), Width(name = "u32", das_type = "uint", llvm = "i32"),
    Width(name = "i64", das_type = "int64", llvm = "i64"), Width(name = "u64", das_type = "uint64", llvm = "i64"),
    Width(name = "f32", das_type = "float", llvm = "float"), Width(name = "f64", das_type = "double", llvm = "double")
]

// per width a store, a load, a store of the load plus one and a load, printed as an `int`; `bool`
// and a pointer the same way; `declined` and `declined_store` signatures the generators decline
def private widths_source : string {
    return build_string() $(var w) {
        w |> write("options gen2\nrequire daslib/tune\nrequire c_runtime/c_volatile\n\nstruct Cells \{\n")
        for (c in WIDTHS) {
            w |> write("    {c.name} : {c.das_type}\n")
        }
        w |> write("    b : bool\n    p : int?\n\}\n\n")
        for (c in WIDTHS) {
            w |> write("[export]\ndef rw_{c.name}(var c : Cells?) : int \{\n    c_volatile_store(c.{c.name}, {c.das_type}(5))\n")
            w |> write("    let a = c_volatile_load(c.{c.name})\n    c_volatile_store(c.{c.name}, {c.das_type}(int(a) + 1))\n")
            w |> write("    return int(c_volatile_load(c.{c.name}))\n\}\n\n")
        }
        w |> write("[export]\ndef rw_b(var c : Cells?) : int \{\n    c_volatile_store(c.b, true)\n    let a = c_volatile_load(c.b)\n")
        w |> write("    c_volatile_store(c.b, !a)\n    return c_volatile_load(c.b) ? 1 : 0\n\}\n\n")
        w |> write("[export]\ndef rw_p(var c : Cells?) : int \{\n    c_volatile_store(c.p, unsafe(addr(c.i32)))\n    let a = c_volatile_load(c.p)\n")
        w |> write("    c_volatile_store(c.p, a)\n    return *c_volatile_load(c.p)\n\}\n\n")
        w |> write("[llvm_code(name = \"c_volatile::load\")]\ndef declined(a, b : int) : int => a + b\n\n")
        w |> write("[llvm_code(name = \"c_volatile::store\")]\ndef declined_store(a, b : int) : int => a * b\n\n")
        let calls = join([for (c in WIDTHS); "\{rw_{c.name}(c)\}"], " ")
        w |> write("[export]\ndef main : int \{\n    var c = new Cells()\n")
        w |> write("    print(\"{calls} \{rw_b(c)\} \{rw_p(c)\} \{declined(2, 3)\} \{declined_store(2, 3)\}\\n\")\n")
        w |> write("    unsafe \{\n        delete c\n    \}\n    return 0\n\}\n")
    }
}

let WIDTHS_EXPECTED = "6 6 6 6 6 6 6 6 6 6 0 6 5 6"

[test]
def test_c_volatile_jit(tt : T?) {
    let work = test_temp_dir()
    let entry = path_join(work, "volatile_widths.das")
    let source = widths_source()
    fwrite(entry, source)
    for (tier in ["interp", "aot"]) {
        tt |> run("under {tier} every width, bool and a pointer read back what was stored, through the crt forwarders") @(t : T?) {
            var out : string
            t |> equal(run_tier(entry, tier, path_join(work, tier), out, CONVERTED_MODULES), 0, out)
            t |> success(out |> contains(WIDTHS_EXPECTED), out)
        }
    }
    for (tier in ["jit", "exe", "exe-split"]) {
        tt |> run("under {tier} every width and a pointer is an inlined volatile store, load, store, load of its LLVM type, bool four forwarder calls, and a declined signature compiles its body") @(t : T?) {
            let ir = path_join(work, "{tier}.ll")
            let r = runtime_child_ir("volatile_widths_{tier}", source, tier, ir)
            t |> equal(r.rc, 0, r.out)
            var out = r.out
            if (tier != "jit") {
                let bin = fexist("{ir}_exe.exe") ? "{ir}_exe.exe" : "{ir}_exe"
                t |> equal(run_and_capture([bin], out, 60.0), 0, out)
            }
            t |> success(out |> contains(WIDTHS_EXPECTED), out)
            let dump = fread(ir)
            var cases <- [for (c in WIDTHS); (name = c.name, llvm = c.llvm)]
            cases |> push((name = "p", llvm = "ptr"))
            for (c in cases) {
                var inscope body <- ir_function(dump, "rw_{c.name}", 1)
                t |> equal(ir_volatile_order(body), "SLSL", "{c.name}: {join(body, "\n")}")
                t |> equal(ir_count(body, "load volatile {c.llvm},") + ir_count(body, "store volatile {c.llvm} "), 4, "{c.name}: {join(body, "\n")}")
                t |> equal(ir_calls(body), 0, "{c.name}: {join(body, "\n")}")
            }
            // `bool` keeps the forwarders: one call per access, none merged
            var inscope flag <- ir_function(dump, "rw_b", 1)
            t |> equal(ir_calls(flag), 4, "b: {join(flag, "\n")}")
            remove(ir)
        }
    }
}
