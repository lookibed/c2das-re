options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require daslib/fio
require _daslang_child
require ../converter/tiers.das

//! Pointer comparisons without `intptr` (owner ruling 38 addendum 32: the generic `intptr` was 17%
//! of Doom's interpreted self time): das's `==` and `!=` take two data pointers of one type and
//! give C's answer, a relation over the two addresses read as `uint64` through `reinterpret` gives
//! C's order, and `p - q` C's difference, under the interpreter, the JIT, the `-exe` binary and the
//! AOT host alike. das has no relation between pointers, and `==` between pointers of two
//! constnesses is refused (`docs/probe-findings.md` F44).

let private PROGRAM = "probes/_pointer_compare.das"
let private PROBE_TIERS = fixed_array("interp", "jit", "exe", "aot")
let private NO_MODULES : array<string>

// the program's lines of `out`, the tier's own `[I]` lines and blank lines left out
def private program_lines(out : string) : string =>
    join([for (l in split(out, "\n")); strip(l); where !empty(strip(l)) && !starts_with(strip(l), "[")], "|")

// a pair of `int?` compared by `cmp`, in a program the compiler checks
def private relation(cmp : string) : string =>
    "options gen2\nvar g : int[4]\ndef f(p, q : int?) : bool \{\n    unsafe \{\n        return {cmp}\n    \}\n\}\n[export]\ndef main \{\n    unsafe \{\n        print(\"\{f(addr(g[0]), addr(g[1]))\}\\n\")\n    \}\n\}\n"

[test(timeout = 1200)]
def test_pointer_compare(tt : T?) {
    let work = test_temp_dir()
    for (tier in PROBE_TIERS) {
        tt |> run("`==`, `!=` and a relation over `reinterpret<uint64>` give C's answer between two pointers into an array, one past its end, null, two records, two `void?`, a circular list's anchor, a scan to the last pointer, a `let` copy and a field read through a `let` pointer, and `p - q` C's difference, under {tier}") @(t : T?) {
            var out : string
            let rc = run_tier(PROGRAM, tier, path_join(work, "compare_{tier}"), out, NO_MODULES, 600.0)
            t |> equal(rc, 0, "{tier}: {out}")
            t |> equal(program_lines(out), "ints 14 50 41 50 50 41|nodes 14 50 41|void 6 34 33|walk 10|find 3 16 0|let 3 5|diff 3 -3 5 0", "{tier}: {out}")
        }
    }
    tt |> run("das has no `<` between two pointers: the relation reads both addresses as `uint64`") @(t : T?) {
        let refused = daslang_child("pointer_less", relation("p < q"), true)
        t |> success(refused.rc != 0, refused.out)
        t |> success(refused.out |> contains("no matching functions or generics: _::<(int? const&, int? const&)"), refused.out)
        let taken = daslang_child("pointer_less_bits", relation("reinterpret<uint64>(p) < reinterpret<uint64>(q)"), false)
        t |> equal(taken.rc, 0, taken.out)
        t |> equal(strip(taken.out), "true", taken.out)
    }
    tt |> run("a pointer copied out of a field read through a `let` pointer is `T const?` and does not compare with a `T?`; its `reinterpret<uint64>` does") @(t : T?) {
        let source = "options gen2\nstruct N \{\n    next : N?\n\}\nvar g : N\ndef f(s : N?) : bool \{\n    var p = s.next\n    unsafe \{\n        return @CMP@\n    \}\n\}\n[export]\ndef main \{\n    unsafe \{\n        g.next = addr(g)\n        print(\"\{f(addr(g))\}\\n\")\n    \}\n\}\n"
        let refused = daslang_child("pointer_const_copy", replace(source, "@CMP@", "p == addr(g)"), true)
        t |> success(refused.rc != 0, refused.out)
        t |> success(refused.out |> contains("operations on incompatible pointers are prohibited; N const? vs N -const?"), refused.out)
        let taken = daslang_child("pointer_const_copy_bits", replace(source, "@CMP@", "reinterpret<uint64>(p) == reinterpret<uint64>(addr(g))"), false)
        t |> equal(taken.rc, 0, taken.out)
        t |> equal(strip(taken.out), "true", taken.out)
    }
    tt |> run("the interpreter refuses `reinterpret<uint64>` over a `reinterpret<void?>` of a pointer sum (lookibed/daScript#64); over the sum itself it takes it") @(t : T?) {
        let source = "options gen2\nvar g : int[4]\n[export]\ndef main \{\n    unsafe \{\n        var p : int? = addr(g[0])\n        print(\"\{reinterpret<uint64>(@SUM@) == reinterpret<uint64>(addr(g[1]))\}\\n\")\n    \}\n\}\n"
        let nested = daslang_child("pointer_sum_nested", replace(source, "@SUM@", "reinterpret<void?>(p + 1)"), false)
        t |> success(nested.out |> contains("typed eval on wrong extern return kind, i_das_ptr_add"), nested.out)
        let plain = daslang_child("pointer_sum_plain", replace(source, "@SUM@", "p + 1"), false)
        t |> equal(plain.rc, 0, plain.out)
        t |> equal(strip(plain.out), "true", plain.out)
    }
}
