options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../converter/tiers.das
require _daslang_child

//! `options solid_context` in a converted program's modules: daslang's option list says it
//! "prohibits AOT and patches"; a program of two solid modules, each holding module globals and
//! function values taken across them with `@@`, the entry one requiring `c_runtime` modules as
//! converted output does, compiles and runs with the same output under the interpreter, the JIT,
//! the JIT-linked executable and the AOT host of `converter/tiers.das`
//! (docs/probe-findings.md F80, P7.0m); the AOT context is the generated C++, its initializers
//! solid (F49).

// the required module: a global table and a counter written through a function, and a callback
// stored in a module global and invoked through it, as Doom's `doom_exit` is
let PART_SOURCE = "options gen2\noptions solid_context\nmodule solid_part public\n\nvar part_table : int[8]\nvar part_count : int = 0\nvar part_callback : function<(a0 : int) : void> = default<function<(a0 : int) : void>>\n\ndef part_bump(n : int) \{\n    part_count += n\n    part_table[n & 7] += 1\n\}\n\ndef part_set_callback(fn : function<(a0 : int) : void>) \{\n    part_callback = fn\n\}\n\ndef part_fire(n : int) \{\n    if (part_callback != null) \{\n        invoke(part_callback, n)\n    \}\n\}\n"

// the entry module: its own globals read under a branch in a loop (F80's shape), the other
// module's function taken as `@@` into a global and invoked through it, its own `@@` handed to the
// other module as the callback (the converter takes every function address as `@@`); the printed
// sums the same at every tier, then whether the function value runs AOT or JIT code
let MAIN_SOURCE = "options gen2\noptions solid_context\nrequire solid_part\nrequire c_runtime/c_function\nrequire c_runtime/printf\n\nvar private scale : int = 3\nvar private lut : int[4] = fixed_array(1, 2, 3, 4)\nvar private fired : int = 0\nvar private bump : function<(n : int) : void> = default<function<(n : int) : void>>\n\n[c_function]\ndef private on_fire(code : int) \{\n    fired += code\n\}\n\n[c_function]\ndef private c_main : int \{\n    bump = @@part_bump\n    part_set_callback(@@on_fire)\n    var s = 0\n    for (i in range(1000)) \{\n        if ((i & 3) != 0) \{\n            s += scale * lut[i & 3]\n        \}\n        invoke(bump, i)\n        part_fire(i & 1)\n    \}\n    print(\"\{s\} \{part_count\} \{part_table[5]\} \{fired\}\\n\")\n    print(\"aot \{is_aot_function(bump)\} jit \{is_jit_function(bump)\}\\n\")\n    return 0\n\}\n\n[export]\ndef main : int => c_main()\n"

let SOLID_TIERS = fixed_array("interp", "jit", "exe", "aot")

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
            let n = length(lines)
            t |> equal(n >= 2 ? lines[n - 2] : "", "6750 499500 125 500", "{tier}: {out}")
            // the code that ran: an AOT-compiled function only under the AOT host
            t |> equal(n >= 1 ? lines[n - 1] : "", "aot {tier == "aot"} jit {tier == "jit" || tier == "exe"}", "{tier}: {out}")
            if (tier == "aot") {
                // the host runs the generated C++, solid initializers in it (F49), not an interpreter
                let cpp = fread(path_join(work, "aot/ctx/solid_main.das.cpp"))
                t |> success(cpp |> contains("das_global_solid<int32_t,"), "the context's solid initializers")
                t |> success(cpp |> contains("inline int32_t c_main_"), "c_main compiled to C++")
            }
        }
    }
}

// a global pointer assigned its own address, then written through and compared with it: 0 when the
// assignment holds (gcc-torture pr17252's shape); `{SOLID}` is where the option goes
let private SELF_ADDRESS = "options gen2\n\{SOLID\}\nvar a : uint8?\n\n[export]\ndef main : int \{\n    unsafe \{\n        a = reinterpret<uint8?>(addr(a))\n        deref(a) = uint8(uint(deref(a)) + 1u)\n        return intptr(a) == intptr(reinterpret<uint8?>(addr(a))) ? 3 : 0\n    \}\n\}\n"

[test]
def test_solid_self_address(t : T?) {
    t |> run("under solid_context the JIT drops the store of a global pointer assigned its own address: the next deref reads null, under -exe alike (F99, lookibed/daScript#47); the interpreter and a plain JIT keep it") @(t : T?) {
        let solid = SELF_ADDRESS |> replace("\{SOLID\}", "options solid_context\n")
        let interp = daslang_child_flags("self_address_interp", solid, array<string>())
        t |> equal(interp.rc, 0, interp.out)
        let jit = daslang_child_flags("self_address_jit", solid, jit_flags())
        t |> success(jit_ran(jit.out), jit.out)
        t |> success(jit.out |> contains("dereferencing null pointer, a is null"), jit.out)
        let exe = "{temp_directory_result() as value}/c2das_probe_self_address_exe"
        let build = daslang_run("self_address_exe", solid, ["-exe"], array<string>(), "c2das_probe", ["-output", exe])
        t |> equal(build.rc, 0, build.out)
        var ran : string
        t |> equal(run_and_capture([exe], ran, 60.0), 1, ran)
        t |> success(ran |> contains("dereferencing null pointer, a is null"), ran)
        remove(exe)
        let plain = daslang_child_flags("self_address_plain_jit", SELF_ADDRESS |> replace("\{SOLID\}", ""), jit_flags())
        t |> success(jit_ran(plain.out), plain.out)
        t |> equal(plain.rc, 0, plain.out)
    }
}
