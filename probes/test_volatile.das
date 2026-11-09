options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../converter/tiers.das
require _daslang_child

//! A C volatile access is one load or store on every tier, none merged, dropped or hoisted
//! (docs/probe-findings.md F91). The proof is a count in the code each tier runs: the JIT's and
//! the exe's IR (`--jit-dump=<file>`), the AOT host's machine code (objdump of the linked binary).
//! The interpreter runs every access as written; it checks the values only. The three candidate
//! mechanisms, each a function of `SOURCE` reading one field four times:
//! - `ext4`: the `crt::c_volatile_load_i32` extern itself. Its bind (`modifyExternal`; a reader's
//!   `accessExternal` is the same bit) keeps every call, an opaque one under the JIT and the exe;
//! - `deref4`: a das `deref` of the field's address, which the JIT and the AOT host fold into one load;
//! - `gen4`: `c_volatile_load`, under the JIT and the exe the `[llvm_code]` generators of
//!   `c_runtime/c_volatile_jit.das`, an LLVM `load volatile` inlined, no call.
let SOURCE = "options gen2\nrequire crt\nrequire c_runtime/c_volatile\n\nstruct Frame \{\n    trap : int\n    pad : int\n\}\n\n[export]\ndef ext4(var f : Frame?) : int \{\n    unsafe \{\n        let p = addr(f.trap)\n        return crt::c_volatile_load_i32(p) + crt::c_volatile_load_i32(p) + crt::c_volatile_load_i32(p) + crt::c_volatile_load_i32(p)\n    \}\n\}\n\n[export]\ndef deref4(var f : Frame?) : int \{\n    unsafe \{\n        let p = addr(f.trap)\n        return deref(p) + deref(p) + deref(p) + deref(p)\n    \}\n\}\n\n[export]\ndef gen4(var f : Frame?) : int \{\n    return c_volatile_load(f.trap) + c_volatile_load(f.trap) + c_volatile_load(f.trap) + c_volatile_load(f.trap)\n\}\n\n[export]\ndef spin(var f : Frame?) : int \{\n    var n = 0\n    while (c_volatile_load(f.trap) == 0 && n < 1000) \{\n        n ++\n    \}\n    return n\n\}\n\n[export]\ndef slsl(var f : Frame?) : int \{\n    c_volatile_store(f.trap, 5)\n    let a = c_volatile_load(f.trap)\n    c_volatile_store(f.trap, 6)\n    return a * 10 + c_volatile_load(f.trap)\n\}\n\n[export]\ndef st2(var f : Frame?) : int \{\n    c_volatile_store(f.trap, 7)\n    c_volatile_store(f.trap, 7)\n    return c_volatile_load(f.trap)\n\}\n\n[export]\ndef main : int \{\n    var f = new Frame(trap = 1)\n    print(\"\{ext4(f)\} \{deref4(f)\} \{gen4(f)\} \{spin(f)\} \{slsl(f)\} \{st2(f)\}\\n\")\n    unsafe \{\n        delete f\n    \}\n    return 0\n\}\n"

let EXPECTED = "4 4 4 0 56 7"

// whether the block of the function's volatile load branches back to itself, the read left in its loop
def private load_in_loop(lines : array<string>) : bool {
    var head = ""
    var at = -1
    for (l, i in lines, count()) {
        if (!empty(l) && !(l |> starts_with(" ")) && find(l, ":") > 0 && !(l |> starts_with("define"))) {
            head = slice(l, 0, find(l, ":"))
        }
        if (at < 0 && l |> contains("load volatile")) {
            at = i
            break
        }
    }
    return at >= 0 && !empty([for (l in lines); l; where l |> contains(" br ") && l |> contains("label %{head},")])
}

// the counts of every function of `SOURCE` in a tier's IR
def private check_ir(t : T?; tier, dump : string) {
    let ext4 <- ir_function(dump, "ext4", 1)
    t |> equal(ir_calls(ext4), 4, "{tier} ext4: {join(ext4, "\n")}")
    let deref4 <- ir_function(dump, "deref4", 1)
    t |> equal(ir_count(deref4, "load i32"), 1, "{tier} deref4: {join(deref4, "\n")}")
    let gen4 <- ir_function(dump, "gen4", 1)
    t |> equal(ir_count(gen4, "load volatile i32"), 4, "{tier} gen4: {join(gen4, "\n")}")
    t |> equal(ir_calls(gen4), 0, "{tier} gen4: {join(gen4, "\n")}")
    let slsl <- ir_function(dump, "slsl", 1)
    t |> equal(ir_volatile_order(slsl), "SLSL", "{tier} slsl: {join(slsl, "\n")}")
    t |> equal(ir_calls(slsl), 0, "{tier} slsl: {join(slsl, "\n")}")
    let st2 <- ir_function(dump, "st2", 1)
    t |> equal(ir_volatile_order(st2), "SSL", "{tier} st2: {join(st2, "\n")}")
    let spin <- ir_function(dump, "spin", 1)
    t |> equal(ir_count(spin, "load volatile i32"), 1, "{tier} spin: {join(spin, "\n")}")
    t |> success(load_in_loop(spin), "{tier} spin keeps its loop: {join(spin, "\n")}")
}

// the instructions of the AOT binary's `name` that touch memory through a register
def private aot_memory_ops(bin, name : string) : int {
    var syms : string
    run_and_capture(["nm", bin], syms, 60.0)
    var sym = ""
    for (l in split(syms, "\n")) {
        if (l |> ends_with("_{name}") && l |> contains(" T ")) {
            sym = slice(l, find(l, " T ") + 3)
        }
    }
    var asm : string
    run_and_capture(["objdump", "-d", "--no-show-raw-insn", "--disassemble={sym}", bin], asm, 60.0)
    return length([for (l in split(asm, "\n")); l; where l |> contains("(%r") && !(l |> contains("%rip")) && !(l |> contains("lea "))])
}

// the tiers whose LLVM IR the probe reads
let IR_TIERS = fixed_array("jit", "exe", "exe-split")

[test]
def test_volatile(tt : T?) {
    let work = test_temp_dir()
    let entry = path_join(work, "volatile_probe.das")
    fwrite(entry, SOURCE)
    tt |> run("under interp the accesses give the values C gives") @(t : T?) {
        var out : string
        t |> equal(run_tier(entry, "interp", path_join(work, "interp"), out, CONVERTED_MODULES), 0, out)
        t |> success(out |> contains(EXPECTED), out)
    }
    for (tier in IR_TIERS) {
        tt |> run("under {tier} the extern is a call per read, a deref folds to one load, c_volatile_load and c_volatile_store are one volatile load or store each") @(t : T?) {
            let ir = path_join(work, "{tier}.ll")
            let r = runtime_child_ir("volatile_{tier}", SOURCE, tier, ir)
            t |> equal(r.rc, 0, r.out)
            var out = r.out
            if (tier != "jit") {
                let bin = fexist("{ir}_exe.exe") ? "{ir}_exe.exe" : "{ir}_exe"
                t |> equal(run_and_capture([bin], out, 60.0), 0, out)
            }
            t |> success(out |> contains(EXPECTED), "{tier}: {out}")
            check_ir(t, tier, fread(ir))
            remove(ir)
        }
    }
    tt |> run("under aot the extern and c_volatile_load are a volatile load per read, a deref folds to one load") @(t : T?) {
        var out : string
        t |> equal(run_tier(entry, "aot", path_join(work, "aot"), out, CONVERTED_MODULES), 0, out)
        t |> success(out |> contains(EXPECTED), out)
        let bin = aot_binary(entry, path_join(work, "aot"))
        t |> equal(aot_memory_ops(bin, "ext4"), 4)
        t |> equal(aot_memory_ops(bin, "deref4"), 1)
        t |> equal(aot_memory_ops(bin, "gen4"), 4)
        t |> equal(aot_memory_ops(bin, "st2"), 3)
    }
}
