options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../converter/tiers.das

//! `[c_function, unsafe_deref, hint(unsafe_range_check)]`, the converter's `--checks off` spelling
//! (P7.0o, docs/very-detailed-plan.md O2 and O3): `unsafe_deref` drops the null check of a pointer
//! dereference, the hint the range check of an index, in the function's own body. Under the
//! interpreter, the JIT and the JIT-linked executable an index one past a fixed array inside a
//! struct reads the next field as C does, where the checked function panics; the AOT host of
//! `converter/tiers.das` keeps the range check (its C++ spells `das_index::at`, the hint unread).
//! Under every tier a null dereference kills the process with SIGSEGV, where the checked function
//! panics and `recover` catches it (docs/probe-findings.md F84).

// one struct with a field right after its array, the index a global so nothing folds it, a null
// pointer global; each access once checked under `try`, once unchecked, the null one last
let SOURCE = "options gen2\nrequire c_runtime/c_function\n\nstruct S \{\n    a : int[4]\n    b : int\n\}\n\nvar private idx = 4\nvar private nowhere : int? = null\n\n[c_function]\ndef checked_at(var s : S; i : int) : int \{\n    return s.a[i]\n\}\n\n[c_function, unsafe_deref, hint(unsafe_range_check)]\ndef unchecked_at(var s : S; i : int) : int \{\n    return s.a[i]\n\}\n\n[c_function]\ndef checked_deref(p : int?) : int \{\n    return *p\n\}\n\n[c_function, unsafe_deref, hint(unsafe_range_check)]\ndef unchecked_deref(p : int?) : int \{\n    return *p\n\}\n\n[export]\ndef main : int \{\n    var s = S(a = fixed_array(1, 2, 3, 4), b = 77)\n    try \{\n        print(\"unchecked range \{unchecked_at(s, idx)\}\\n\")\n    \} recover \{\n        print(\"unchecked range panicked\\n\")\n    \}\n    try \{\n        print(\"checked range \{checked_at(s, idx)\}\\n\")\n    \} recover \{\n        print(\"checked range panicked\\n\")\n    \}\n    try \{\n        print(\"checked null \{checked_deref(nowhere)\}\\n\")\n    \} recover \{\n        print(\"checked null panicked\\n\")\n    \}\n    print(\"unchecked null next\\n\")\n    print(\"unchecked null \{unchecked_deref(nowhere)\}\\n\")\n    return 0\n\}\n"

let UNCHECKED_TIERS = fixed_array("interp", "jit", "exe", "aot")

[test]
def test_unchecked(tt : T?) {
    let work = test_temp_dir()
    let entry = path_join(work, "unchecked.das")
    fwrite(entry, SOURCE)
    for (tier in UNCHECKED_TIERS) {
        tt |> run("under {tier} an unchecked index past the array reads the next field (the AOT host keeps the check), an unchecked null dereference dies by SIGSEGV; the checked ones panic") @(t : T?) {
            var out : string
            let rc = run_tier(entry, tier, path_join(work, tier), out, CONVERTED_MODULES)
            to_log(LOG_INFO, "{tier}: rc {rc}\n{out}")
            let lines <- [for (l in split(out, "\n")); strip(l); where !empty(strip(l))]
            // the AOT host's C++ keeps the range check (aot_cpp spells `das_index::at` whatever
            // the hint says); the null check it drops
            let range_line = tier == "aot" ? "unchecked range panicked" : "unchecked range 77"
            t |> success(has_value(lines, range_line), "{tier}: {out}")
            t |> success(has_value(lines, "checked range panicked"), "{tier}: {out}")
            t |> success(has_value(lines, "checked null panicked"), "{tier}: {out}")
            t |> success(has_value(lines, "unchecked null next"), "{tier}: {out}")
            t |> success(!(out |> contains("unchecked null 0")) && rc != 0, "{tier}: rc {rc}: {out}")
            // the runner reads a death by signal 11 as exit code 11 (lookibed/daScript#37)
            t |> equal(rc, 11, "{tier}: {out}")
        }
    }
}
