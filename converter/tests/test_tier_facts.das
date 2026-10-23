options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../tiers.das

//! The das facts the emitter relies on at every tier, each run as a program under the
//! interpreter, the JIT, the JIT-linked executable and the AOT host: `int` and `int64` `+` and `-`
//! wrap (the emitter folds C's sum through the unsigned type to the plain one), and a
//! `c_volatile_load` in a loop is a read per pass where the plain read of the same global is
//! folded out of the loop (the emitter's volatile access), as is a `c_volatile_store`, at every
//! width `c_runtime/c_volatile` overloads (`_volatile_widths.das`).

let FACT_TIERS = fixed_array("interp", "jit", "exe", "aot")

// the sums run on values the optimizer cannot see: arguments and globals the program sets
let WRAP_SOURCE = "options gen2\nvar g = 0\nvar h = 0l\ndef sum(a, b : int) : int => a + b\ndef diff(a, b : int) : int => a - b\n[export]\ndef main : int \{\n    g = 2147483647\n    h = 9223372036854775807l\n    print(\"\{sum(g, 5)\} \{diff(-g, 5)\} \{h + 2l\} \{-h - 3l\}\\n\")\n    return 0\n\}\n"

// a loop of `n` reads of a global: plain, which no store in the loop keeps from being hoisted and
// the sum computed at once, and through `c_volatile_load`; each timed by the wall clock
let FOLD_SOURCE = "options gen2\nrequire c_runtime/c_volatile\n\nvar private g : int = 3\nvar private count : int = 20000000\n\ndef private plain_sum(n : int) : int \{\n    var s = 0\n    for (_i in range(n)) \{\n        s += g\n    \}\n    return s\n\}\n\ndef private volatile_sum(n : int) : int \{\n    var s = 0\n    for (_i in range(n)) \{\n        s += c_volatile_load(g)\n    \}\n    return s\n\}\n\n[export]\ndef main : int \{\n    let n = c_volatile_load(count)\n    var t0 = ref_time_ticks()\n    let a = plain_sum(n)\n    let plain_ns = get_time_nsec(t0)\n    t0 = ref_time_ticks()\n    let b = volatile_sum(n)\n    let volatile_ns = get_time_nsec(t0)\n    print(\"\{plain_ns\} \{volatile_ns\} \{a\} \{b\}\\n\")\n    return 0\n\}\n"

// `a[g()] = a[g()] + 10` over a local array in a `[c_function]`, the converted program's shape:
// which of the two calls runs first decides which element is written
let ORDER_SOURCE = "options gen2\nrequire c_runtime/c_function\nvar private calls = 0\n\ndef private g : int \{\n    calls++\n    return calls\n\}\n\n[c_function]\ndef c_main : int \{\n    var arr : int[4]\n    arr[g()] = arr[g()] + 10\n    print(\"\{arr[1]\} \{arr[2]\}\\n\")\n    return 0\n\}\n\n[export]\ndef main : int => c_main()\n"

var work : string

// `source` written as `<work>/<name>.das` and run under `tier`: its exit code and the program's last line
def run_source(name, source, tier : string; var line : string&) : int {
    let path = path_join(work, "{name}.das")
    fwrite(path, source)
    var out : string
    let rc = run_tier(path, tier, path_join(work, "{name}_{tier}"), out, CONVERTED_MODULES)
    let lines <- [for (l in split(out, "\n")); strip(l); where !empty(strip(l))]
    line = empty(lines) ? out : lines[length(lines) - 1]
    return rc
}

[test]
def test_tier_facts(t : T?) {
    var dir_error : string
    work = create_temp_directory("c2das_tier_facts", dir_error)
    if (!empty(dir_error)) {
        t |> failure(dir_error)
        return
    }
    for (tier in FACT_TIERS) {
        t |> run("int and int64 + and - wrap under {tier}") @(t : T?) {
            var line : string
            t |> equal(run_source("wrap", WRAP_SOURCE, tier, line), 0, line)
            t |> equal(line, "-2147483644 2147483644 -9223372036854775807 9223372036854775806")
        }
        t |> run("in a [c_function] an assignment's value is evaluated before its target's index under {tier}, but for AOT (docs/probe-findings.md F69)") @(t : T?) {
            var line : string
            t |> equal(run_source("order", ORDER_SOURCE, tier, line), 0, line)
            t |> equal(line, tier == "aot" ? "10 0" : "0 10", "{tier}: {line}")
        }
        t |> run("every c_volatile_load and c_volatile_store overload accesses the global on every pass under {tier}; the plain access folds where the tier optimizes") @(t : T?) {
            var out : string
            let rc = run_tier("converter/tests/_volatile_widths.das", tier, path_join(work, "widths_{tier}"), out, CONVERTED_MODULES)
            t |> equal(rc, 0, out)
            let lines <- [for (l in split(out, "\n")); strip(l); where !starts_with(strip(l), "[") && length(split(strip(l), " ")) == 7]
            t |> equal(length(lines), 12, out)
            for (l in lines) {
                var inscope fields <- split(l, " ")
                t |> equal(fields[5], "4000000", l)
                t |> equal(fields[6], "4000000", l)
                if (tier != "interp") {
                    // four million accesses take at least 0.25 ns each; a folded one takes none
                    let plain_load_ns = to_int64(fields[1])
                    let volatile_load_ns = to_int64(fields[2])
                    let plain_store_ns = to_int64(fields[3])
                    let volatile_store_ns = to_int64(fields[4])
                    t |> success(volatile_load_ns >= 1000000l && plain_load_ns * 100l < volatile_load_ns, "{tier} load: {l}")
                    t |> success(volatile_store_ns >= 1000000l && plain_store_ns * 100l < volatile_store_ns, "{tier} store: {l}")
                }
            }
        }
        t |> run("c_volatile_load reads the global on every pass under {tier}; the plain loop folds where the tier optimizes") @(t : T?) {
            var line : string
            t |> equal(run_source("fold", FOLD_SOURCE, tier, line), 0, line)
            let fields <- split(line, " ")
            t |> equal(length(fields), 4, line)
            if (length(fields) != 4) {
                return
            }
            let plain_ns = to_int64(fields[0])
            let volatile_ns = to_int64(fields[1])
            t |> equal(fields[2], "60000000", line)
            t |> equal(fields[3], "60000000", line)
            // twenty million reads take at least 0.25 ns each on any machine this runs on; a read
            // hoisted out of the loop would let the sum be computed at once, as the plain one is
            t |> success(volatile_ns >= 5000000l, "{tier}: {line}")
            if (tier == "interp") {
                // the interpreter folds neither loop
                t |> success(plain_ns >= 5000000l, "{tier}: {line}")
            } else {
                t |> success(plain_ns * 100l < volatile_ns, "{tier}: {line}")
            }
        }
    }
    rmdir_rec(work)
}
