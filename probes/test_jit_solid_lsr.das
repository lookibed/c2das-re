options gen2
require dastest/testing_boost public
require _daslang_child
require strings
require daslib/fio
require daslib/strings_boost

// the sieve of perf/kernels/sieve.c at 10000 (prints the prime count, 1229), its byte array the second
// module global: under `options solid_context` at offset 16 of the context's globals block
// (docs/probe-findings.md F92)
let private SIEVE_SOURCE = "options gen2\noptions solid_context\n\nvar private limit : int = 10000\nvar private flags : uint8[10001]\n\n[export]\ndef main \{\n    let n = limit\n    var count = 0\n    for (i in range(n + 1)) \{\n        flags[i] = uint8(1)\n    \}\n    var i = 2\n    while (i <= n) \{\n        if (flags[i] != 0u8) \{\n            var k = i + i\n            while (k <= n) \{\n                flags[k] = uint8(0)\n                k += i\n            \}\n            count++\n        \}\n        i++\n    \}\n    print(\"\{count\}\\n\")\n\}\n"

// the machine code `llc -O3 <flags>` makes of the JIT's IR of `source`; the run's output must be
// the count
def private machine_code(t : T?; name, source : string; llc_flags : array<string>) : string {
    let dir = "{temp_directory_result() as value}"
    let ir = "{dir}/c2das_probe_solid_lsr_{name}.ll"
    let s_path = "{dir}/c2das_probe_solid_lsr_{name}.s"
    let jit = daslang_run("solid_lsr_{name}", source, jit_flags(), array<string>(), "c2das_probe", ["--", "--jit-dump", "--jit-dump-to", ir])
    t |> success(jit.out |> ends_with("1229\n"), "{name}: {jit.out}")
    var args <- [pinned_llvm_tool("llc"), "-O3"]
    args |> push_from(llc_flags, [ir, "-o", s_path])
    var out : string
    let rc = run_and_capture(args, out, 120.0)
    t |> equal(rc, 0, "{name}: llc: {out}")
    let asm = fread(s_path)
    remove(ir)
    remove(s_path)
    return asm
}

[test]
def test_jit_solid_lsr(t : T?) {
    t |> run("under options solid_context LLVM's loop strength reduction gives the store into a global array at offset 16 of the globals block a pointer of its own per unrolled copy, spilled; without it the store folds the offset, `movb $0, 16(%base,%k)` (docs/probe-findings.md F92)") @(t : T?) {
        let lsr : array<string>
        let no_lsr <- ["-disable-lsr"]
        let with_lsr = machine_code(t, "solid", SIEVE_SOURCE, lsr)
        let without = machine_code(t, "solid_nolsr", SIEVE_SOURCE, no_lsr)
        // the folded stores: every unrolled copy's without LSR, fewer with it
        let folded_with = count(with_lsr, "movb\t$0, 16(%r")
        let folded_without = count(without, "movb\t$0, 16(%r")
        t |> success(folded_without > 0, without)
        t |> success(folded_with < folded_without, "{folded_with} folded stores with LSR, {folded_without} without: F92 is stale, re-read the issue")
        let stack_with = count(with_lsr, "(%rsp)")
        let stack_without = count(without, "(%rsp)")
        t |> success(stack_with > 3 * stack_without, "{stack_with} stack references with LSR against {stack_without} without: F92 is stale")
    }
    t |> run("the same sieve without solid_context (the base an opaque `jit_get_global_mnh` result) or with the array first, at offset 0, takes LSR without a spill (F92's controls)") @(t : T?) {
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
