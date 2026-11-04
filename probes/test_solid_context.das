options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../converter/tiers.das

//! `options solid_context` in a converted program's modules: daslang's option list says it
//! "prohibits AOT and patches"; a program of two solid modules, each holding module globals, the
//! entry one requiring `c_runtime` modules as converted output does, compiles and runs with the same
//! output under the interpreter, the JIT and the AOT host of `converter/tiers.das`
//! (docs/probe-findings.md F80, P7.0m); the AOT context is the generated C++, its initializers
//! solid (F49).

// the required module: a global table and a counter written through a function
let PART_SOURCE = "options gen2\noptions solid_context\nmodule solid_part public\n\nvar part_table : int[8]\nvar part_count : int = 0\n\ndef part_bump(n : int) \{\n    part_count += n\n    part_table[n & 7] += 1\n\}\n"

// the entry module: its own globals read under a branch in a loop (F80's shape), the other
// module's written through calls, the printed sums the same at every tier
let MAIN_SOURCE = "options gen2\noptions solid_context\nrequire solid_part\nrequire c_runtime/c_function\nrequire c_runtime/printf\n\nvar private scale : int = 3\nvar private lut : int[4] = fixed_array(1, 2, 3, 4)\n\n[c_function]\ndef private c_main : int \{\n    var s = 0\n    for (i in range(1000)) \{\n        if ((i & 3) != 0) \{\n            s += scale * lut[i & 3]\n        \}\n        part_bump(i)\n    \}\n    print(\"\{s\} \{part_count\} \{part_table[5]\}\\n\")\n    return 0\n\}\n\n[export]\ndef main : int => c_main()\n"

let SOLID_TIERS = fixed_array("interp", "jit", "aot")

[test]
def test_solid_context(tt : T?) {
    let work = test_temp_dir()
    fwrite(path_join(work, "solid_part.das"), PART_SOURCE)
    let entry = path_join(work, "solid_main.das")
    fwrite(entry, MAIN_SOURCE)
    for (tier in SOLID_TIERS) {
        tt |> run("a two-module solid_context program builds and runs under {tier}") @(t : T?) {
            var out : string
            let rc = run_tier(entry, tier, path_join(work, tier), out, CONVERTED_MODULES)
            t |> equal(rc, 0, "{tier}: {out}")
            let lines <- [for (l in split(out, "\n")); strip(l); where !empty(strip(l))]
            t |> equal(empty(lines) ? "" : lines[length(lines) - 1], "6750 499500 125", "{tier}: {out}")
            if (tier == "aot") {
                // the host runs the generated C++, solid initializers in it (F49), not an interpreter
                let cpp = fread(path_join(work, "aot/ctx/solid_main.das.cpp"))
                t |> success(cpp |> contains("das_global_solid<int32_t,"), "the context's solid initializers")
                t |> success(cpp |> contains("inline int32_t c_main_"), "c_main compiled to C++")
            }
        }
    }
}
