options gen2
require dastest/testing_boost public
require _daslang_child
require strings
require daslib/fio
require daslib/strings_boost

// the sieve of perf/kernels/sieve.c at 10000 (prints the prime count, 1229), its byte array the second
// module global: under `options solid_context` at offset 16 of the context's globals block
// (docs/probe-findings.md F93)
let private SIEVE_SOURCE = "options gen2\noptions solid_context\n\nvar private limit : int = 10000\nvar private flags : uint8[10001]\n\n[export]\ndef main \{\n    let n = limit\n    var count = 0\n    for (i in range(n + 1)) \{\n        flags[i] = uint8(1)\n    \}\n    var i = 2\n    while (i <= n) \{\n        if (flags[i] != 0u8) \{\n            var k = i + i\n            while (k <= n) \{\n                flags[k] = uint8(0)\n                k += i\n            \}\n            count++\n        \}\n        i++\n    \}\n    print(\"\{count\}\\n\")\n\}\n"

// the libclang archive's `llc` (VERSIONS.md), the LLVM dasLLVM links; "" when `PATH_TO_LIBCLANG` is
// unset or holds none
def private pinned_llc : string {
    let llc = has_env_variable("PATH_TO_LIBCLANG") ? get_env_variable("PATH_TO_LIBCLANG") + "/bin/llc" : ""
    return !empty(llc) && stat(llc).is_reg ? llc : ""
}

// the machine code `llc -O3 <flags>` makes of the JIT's IR of `source`; the run's output must be
// the count
def private machine_code(t : T?; name, source : string; llc_flags : array<string>) : string {
    let dir = "{test_temp_dir()}"
    let ir = "{dir}/c2das_probe_solid_lsr_{name}.ll"
    let s_path = "{dir}/c2das_probe_solid_lsr_{name}.s"
    let jit = daslang_run("solid_lsr_{name}", source, jit_flags(), array<string>(), "c2das_probe", ["--", "--jit-dump={ir}"])
    t |> success(jit.out |> ends_with("1229\n"), "{name}: {jit.out}")
    let llc = pinned_llc()
    if (empty(llc)) {
        t |> failure("llc is missing: the probe needs $PATH_TO_LIBCLANG/bin/llc (scripts/env.sh, VERSIONS.md)")
        remove(ir)
        return ""
    }
    var args <- [llc, "-O3"]
    args |> push_from(llc_flags, [ir, "-o", s_path])
    var out : string
    let rc = run_and_capture(args, out, 120.0)
    t |> equal(rc, 0, "{name}: llc: {out}")
    let asm = rc == 0 ? fread(s_path) : ""
    remove(ir)
    remove(s_path)
    return asm
}

[test]
def test_jit_solid_lsr(t : T?) {
    t |> run("under options solid_context LLVM's loop strength reduction takes the store into a global array at offset 16 of the globals block without a spill: the code holds the stack references it holds under `-disable-lsr` (docs/probe-findings.md F93, lookibed/daScript#43, fixed upstream by daScript 911fa62771)") @(t : T?) {
        let lsr : array<string>
        let no_lsr <- ["-disable-lsr"]
        let with_lsr = machine_code(t, "solid", SIEVE_SOURCE, lsr)
        let without = machine_code(t, "solid_nolsr", SIEVE_SOURCE, no_lsr)
        let stack_with = count(with_lsr, "(%rsp)")
        let stack_without = count(without, "(%rsp)")
        t |> equal(stack_with, stack_without, "{stack_with} stack references with LSR against {stack_without} without: F93's spill is back")
    }
    t |> run("the same sieve without solid_context (the base an opaque `jit_get_global_mnh` result) or with the array first, at offset 0, takes LSR without a spill (F93's controls)") @(t : T?) {
        let lsr : array<string>
        let no_lsr <- ["-disable-lsr"]
        let nosolid = SIEVE_SOURCE |> replace("options solid_context\n", "")
        let first = SIEVE_SOURCE |> replace("var private limit : int = 10000\nvar private flags : uint8[10001]\n", "var private flags : uint8[10001]\nvar private limit : int = 10000\n")
        t |> success(first != SIEVE_SOURCE, "the declarations moved")
        for (name, source in ["nosolid", "first"], [nosolid, first]) {
            let with_lsr = machine_code(t, name, source, lsr)
            let without = machine_code(t, "{name}_nolsr", source, no_lsr)
            t |> equal(count(with_lsr, "(%rsp)"), count(without, "(%rsp)"), "{name}: LSR changed the spills")
        }
    }
}
