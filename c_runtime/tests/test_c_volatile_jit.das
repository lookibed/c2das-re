options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../../probes/_daslang_child.das
require ../../converter/tiers.das

//! The `[llvm_code]` generators of `c_volatile_jit.das` under every tier: each width of
//! `c_volatile_load` and `c_volatile_store` reads back a value with its high bit set and leaves its
//! array neighbours as they were, and under the JIT and the exe (one LLVM module, or one per das
//! module as the cached DLL) each is one inlined `load volatile` or `store volatile` of its LLVM type
//! and natural alignment; `bool` and a function value keep the forwarder calls; a signature failing
//! one check of a generator keeps its das body (docs/probe-findings.md F91).

//! One scalar width of `SOURCE`: the array `x_<name>`, which the JIT's IR spells `llvm` at `align`.
struct Width {
    name : string
    llvm : string
    align : int
}

let WIDTHS <- [
    Width(name = "i8", llvm = "i8", align = 1),
    Width(name = "u8", llvm = "i8", align = 1),
    Width(name = "i16", llvm = "i16", align = 2),
    Width(name = "u16", llvm = "i16", align = 2),
    Width(name = "i32", llvm = "i32", align = 4),
    Width(name = "u32", llvm = "i32", align = 4),
    Width(name = "i64", llvm = "i64", align = 8),
    Width(name = "u64", llvm = "i64", align = 8),
    Width(name = "f32", llvm = "float", align = 4),
    Width(name = "f64", llvm = "double", align = 8)
]

// per width a store, a load, a store of the load and a load of element 1 of a three-element array
// whose ends hold 7, the value 0 when an end changed; `bool`, a pointer and a function value; one
// fixture per check each generator makes (`load_arity` and the rest)
let SOURCE = "options gen2\nrequire daslib/tune\nrequire c_runtime/c_volatile\n\nstruct Cells \{\n    x_i8 : int8[3]\n    x_u8 : uint8[3]\n    x_i16 : int16[3]\n    x_u16 : uint16[3]\n    x_i32 : int[3]\n    x_u32 : uint[3]\n    x_i64 : int64[3]\n    x_u64 : uint64[3]\n    x_f32 : float[3]\n    x_f64 : double[3]\n    b : bool[3]\n    p : int?\n    f : function<(v : int) : int>\n\}\n\nvar total = 0\n\ndef twice(v : int) : int => v * 2\n\ndef thrice(v : int) : int => v * 3\n\n[export]\ndef rw_i8(var c : Cells?) : int8 \{\n    c.x_i8[0] = int8(7)\n    c.x_i8[2] = int8(7)\n    c_volatile_store(c.x_i8[1], int8(-3))\n    let a = c_volatile_load(c.x_i8[1])\n    c_volatile_store(c.x_i8[1], a)\n    let b = c_volatile_load(c.x_i8[1])\n    return c.x_i8[0] == int8(7) && c.x_i8[2] == int8(7) ? b : int8(0)\n\}\n\n[export]\ndef rw_u8(var c : Cells?) : uint8 \{\n    c.x_u8[0] = uint8(7)\n    c.x_u8[2] = uint8(7)\n    c_volatile_store(c.x_u8[1], uint8(200))\n    let a = c_volatile_load(c.x_u8[1])\n    c_volatile_store(c.x_u8[1], a)\n    let b = c_volatile_load(c.x_u8[1])\n    return c.x_u8[0] == uint8(7) && c.x_u8[2] == uint8(7) ? b : uint8(0)\n\}\n\n[export]\ndef rw_i16(var c : Cells?) : int16 \{\n    c.x_i16[0] = int16(7)\n    c.x_i16[2] = int16(7)\n    c_volatile_store(c.x_i16[1], int16(-300))\n    let a = c_volatile_load(c.x_i16[1])\n    c_volatile_store(c.x_i16[1], a)\n    let b = c_volatile_load(c.x_i16[1])\n    return c.x_i16[0] == int16(7) && c.x_i16[2] == int16(7) ? b : int16(0)\n\}\n\n[export]\ndef rw_u16(var c : Cells?) : uint16 \{\n    c.x_u16[0] = uint16(7)\n    c.x_u16[2] = uint16(7)\n    c_volatile_store(c.x_u16[1], uint16(60000))\n    let a = c_volatile_load(c.x_u16[1])\n    c_volatile_store(c.x_u16[1], a)\n    let b = c_volatile_load(c.x_u16[1])\n    return c.x_u16[0] == uint16(7) && c.x_u16[2] == uint16(7) ? b : uint16(0)\n\}\n\n[export]\ndef rw_i32(var c : Cells?) : int \{\n    c.x_i32[0] = int(7)\n    c.x_i32[2] = int(7)\n    c_volatile_store(c.x_i32[1], -70000)\n    let a = c_volatile_load(c.x_i32[1])\n    c_volatile_store(c.x_i32[1], a)\n    let b = c_volatile_load(c.x_i32[1])\n    return c.x_i32[0] == int(7) && c.x_i32[2] == int(7) ? b : int(0)\n\}\n\n[export]\ndef rw_u32(var c : Cells?) : uint \{\n    c.x_u32[0] = uint(7)\n    c.x_u32[2] = uint(7)\n    c_volatile_store(c.x_u32[1], 0x80000000u)\n    let a = c_volatile_load(c.x_u32[1])\n    c_volatile_store(c.x_u32[1], a)\n    let b = c_volatile_load(c.x_u32[1])\n    return c.x_u32[0] == uint(7) && c.x_u32[2] == uint(7) ? b : uint(0)\n\}\n\n[export]\ndef rw_i64(var c : Cells?) : int64 \{\n    c.x_i64[0] = int64(7)\n    c.x_i64[2] = int64(7)\n    c_volatile_store(c.x_i64[1], -5000000000l)\n    let a = c_volatile_load(c.x_i64[1])\n    c_volatile_store(c.x_i64[1], a)\n    let b = c_volatile_load(c.x_i64[1])\n    return c.x_i64[0] == int64(7) && c.x_i64[2] == int64(7) ? b : int64(0)\n\}\n\n[export]\ndef rw_u64(var c : Cells?) : uint64 \{\n    c.x_u64[0] = uint64(7)\n    c.x_u64[2] = uint64(7)\n    c_volatile_store(c.x_u64[1], 0x8000000000000001ul)\n    let a = c_volatile_load(c.x_u64[1])\n    c_volatile_store(c.x_u64[1], a)\n    let b = c_volatile_load(c.x_u64[1])\n    return c.x_u64[0] == uint64(7) && c.x_u64[2] == uint64(7) ? b : uint64(0)\n\}\n\n[export]\ndef rw_f32(var c : Cells?) : float \{\n    c.x_f32[0] = float(7)\n    c.x_f32[2] = float(7)\n    c_volatile_store(c.x_f32[1], -2.5f)\n    let a = c_volatile_load(c.x_f32[1])\n    c_volatile_store(c.x_f32[1], a)\n    let b = c_volatile_load(c.x_f32[1])\n    return c.x_f32[0] == float(7) && c.x_f32[2] == float(7) ? b : float(0)\n\}\n\n[export]\ndef rw_f64(var c : Cells?) : double \{\n    c.x_f64[0] = double(7)\n    c.x_f64[2] = double(7)\n    c_volatile_store(c.x_f64[1], -1.0e300lf)\n    let a = c_volatile_load(c.x_f64[1])\n    c_volatile_store(c.x_f64[1], a)\n    let b = c_volatile_load(c.x_f64[1])\n    return c.x_f64[0] == double(7) && c.x_f64[2] == double(7) ? b : double(0)\n\}\n\n[export]\ndef rw_b(var c : Cells?) : int \{\n    c.b[0] = true\n    c.b[2] = true\n    c_volatile_store(c.b[1], true)\n    let a = c_volatile_load(c.b[1])\n    c_volatile_store(c.b[1], !a)\n    return c.b[0] && c.b[2] && !c_volatile_load(c.b[1]) ? 1 : 0\n\}\n\n[export]\ndef rw_p(var c : Cells?) : int \{\n    c_volatile_store(c.p, unsafe(addr(c.x_i32[0])))\n    let a = c_volatile_load(c.p)\n    c_volatile_store(c.p, a)\n    return *c_volatile_load(c.p)\n\}\n\n[export]\ndef rw_f(var c : Cells?) : int \{\n    c_volatile_store(c.f, @@twice)\n    let a = c_volatile_load(c.f)\n    c_volatile_store(c.f, a == @@twice ? @@thrice : @@twice)\n    return c_volatile_load(c.f) == @@thrice ? 1 : 0\n\}\n\n// each fails one check of its generator, which declines: the das body runs\n[llvm_code(name = \"c_volatile::load\")]\ndef load_arity(a : int const&; b : int) : int => a + b\n\n[llvm_code(name = \"c_volatile::load\")]\ndef load_object(a : int) : int => a + 1\n\n[llvm_code(name = \"c_volatile::load\")]\ndef load_kind(a : bool const&) : bool => !a\n\n[llvm_code(name = \"c_volatile::store\")]\ndef store_arity(var a : int&) \{\n    a = 4\n\}\n\n[llvm_code(name = \"c_volatile::store\")]\ndef store_object(a, b : int) \{\n    total = a + b\n\}\n\n[llvm_code(name = \"c_volatile::store\")]\ndef store_kind(var a : bool&; b : bool) \{\n    a = !b\n\}\n\n[llvm_code(name = \"c_volatile::store\")]\ndef store_result(var a : int&; b : int) : int \{\n    a = b\n    return a + 1\n\}\n\n[export]\ndef main : int \{\n    var c = new Cells()\n    print(\"\{rw_i8(c)\} \{rw_u8(c)\} \{rw_i16(c)\} \{rw_u16(c)\} \{rw_i32(c)\} \{rw_u32(c)\} \{rw_i64(c)\} \{rw_u64(c)\} \{rw_f32(c)\} \{rw_f64(c)\}\\n\")\n    print(\"\{rw_b(c)\} \{rw_p(c)\} \{rw_f(c)\}\\n\")\n    var i = 2\n    var flag = false\n    store_arity(i)\n    store_object(5, 6)\n    store_kind(flag, false)\n    var j = 0\n    print(\"\{load_arity(i, 3)\} \{load_object(5)\} \{load_kind(flag)\} \{i\} \{total\} \{flag\} \{store_result(j, 8)\} \{j\}\\n\")\n    unsafe \{\n        delete c\n    \}\n    return 0\n\}\n"

let EXPECTED = "-3 0xc8 -300 0xea60 -70000 0x80000000 -5000000000 0x8000000000000001 -2.5 -1e+300\n1 7 1\n7 6 false 4 11 true 9 8\n"

// every access the generators emitted through their object `%x` with an alignment other than
// the width's own
def private misaligned(dump : string; c : Width) : int {
    let lines <- [for (l in split(dump, "\n")); l; where l |> contains(" volatile {c.llvm}") && l |> contains("ptr %x, align")]
    return length([for (l in lines); l; where !(l |> ends_with("align {c.align}"))])
}

[test]
def test_c_volatile_jit(tt : T?) {
    let work = test_temp_dir()
    let entry = path_join(work, "volatile_widths.das")
    fwrite(entry, SOURCE)
    for (tier in ["interp", "aot"]) {
        tt |> run("under {tier} every width, bool, a pointer and a function value read back what was stored, the neighbours kept, through the crt forwarders") @(t : T?) {
            var out : string
            t |> equal(run_tier(entry, tier, path_join(work, tier), out, CONVERTED_MODULES), 0, out)
            t |> success(out |> contains(EXPECTED), out)
        }
    }
    for (tier in ["jit", "exe", "exe-split"]) {
        tt |> run("under {tier} every width and a pointer is an inlined volatile store, load, store, load of its LLVM type and alignment, bool and a function value forwarder calls, and a signature failing one check compiles its body") @(t : T?) {
            let ir = path_join(work, "{tier}.ll")
            let r = runtime_child_ir("volatile_widths_{tier}", SOURCE, tier, ir)
            t |> equal(r.rc, 0, r.out)
            var out = r.out
            if (tier != "jit") {
                let bin = "{ir}_exe"
                t |> equal(run_and_capture([bin], out, 60.0), 0, out)
            }
            t |> success(out |> contains(EXPECTED), out)
            let dump = fread(ir)
            var cases <- [for (c in WIDTHS); (name = c.name, llvm = c.llvm)]
            cases |> push((name = "p", llvm = "ptr"))
            for (c in cases) {
                var inscope body <- ir_function(dump, "rw_{c.name}", 1)
                t |> equal(ir_volatile_order(body), "SLSL", "{c.name}: {join(body, "\n")}")
                t |> equal(ir_count(body, "load volatile {c.llvm},") + ir_count(body, "store volatile {c.llvm} "), 4, "{c.name}: {join(body, "\n")}")
                t |> equal(ir_calls(body), 0, "{c.name}: {join(body, "\n")}")
            }
            for (c in WIDTHS) {
                t |> equal(misaligned(dump, c), 0, "{c.name}: an access aligned past {c.align}")
            }
            if (tier == "exe-split") {
                // the generated functions stay beside their inlined copies in the split build
                t |> success(dump |> contains("load volatile i16, ptr %x, align 2"), "the split dump holds the generated load")
            }
            // `bool` and a function value keep the forwarders: a call per access, none volatile
            for (name in ["b", "f"]) {
                var inscope body <- ir_function(dump, "rw_{name}", 1)
                t |> equal(ir_volatile_order(body), "", "{name}: {join(body, "\n")}")
                t |> success(ir_calls(body) >= 4, "{name}: {join(body, "\n")}")
            }
            remove(ir)
        }
    }
    tt |> run("the cached JIT, its DLL built and then loaded from a scratch cache, reads every value back") @(t : T?) {
        let cache_dir = path_join(work, "cached")
        mkdir_rec(cache_dir)
        let root = getcwd()
        let cmd = "cd '{cache_dir}' && '{get_das_root()}/bin/daslang' -load_module '{root}/dasCRuntime' -load_module '{root}/c_runtime' -jit '{entry}'"
        for (step in ["build", "load"]) {
            var out : string
            t |> equal(run_and_capture(["sh", "-c", cmd], out, 300.0), 0, "{step}: {out}")
            t |> success(out |> contains(EXPECTED), "{step}: {out}")
        }
        t |> success(fexist(path_join(cache_dir, ".cache/daslang")), "the run cached its DLL under the scratch folder")
    }
}
