options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../../probes/_daslang_child.das
require ../../converter/tiers.das

//! `c_jit_build`: an entry module requiring the piece writes `options jit_split_modules = 0`, which
//! compiles and runs under the four tiers of `converter/tiers.das`, and under the cached JIT builds
//! the program's DLL in one unit, the DLL `--jit-split-modules=0` after `--` builds
//! (`docs/probe-findings.md` F92).

// the required module, a function the entry calls across the module boundary
let PART_SOURCE = "options gen2\nmodule jit_pin_part public\n\ndef part_step(x : int) : int => (x * 3 + 1) & 1023\n"

// the entry module, `pin` its option line ("" none); it prints 12 on every tier
def private main_source(pin : string) : string => "options gen2\n{pin}require c_runtime/c_jit_build\nrequire jit_pin_part\n\n[export]\ndef main : int \{\n    var s = 0\n    for (i in range(1000)) \{\n        s = part_step(s + i)\n    \}\n    print(\"\{s\}\\n\")\n    return 0\n\}\n"

let PIN = "options jit_split_modules = 0\n"

// the cached JIT's run of `entry` from the folder `cache_dir`, `after` following `--`, its info lines kept
def private cached_jit(entry, cache_dir : string; after : string) : tuple<rc : int; out : string> {
    let root = getcwd()
    let cmd = "cd '{cache_dir}' && DAS_LOG_LEVEL=info '{get_das_root()}/bin/daslang' -load_module '{root}/dasCRuntime' -load_module '{root}/c_runtime' -jit '{entry}' {after}"
    var out : string
    let rc = run_and_capture(["sh", "-c", cmd], out, 300.0)
    return (rc, out)
}

// the file name of the DLL a JIT run linked, its cache key
def private linked_dll(out : string) : string {
    for (l in split(out, "\n")) {
        let at = l |> find(".dll linked")
        if (at >= 0) {
            let head = slice(l, 0, at)
            return slice(head, head |> rfind("/") + 1)
        }
    }
    return ""
}

[test]
def test_c_jit_build(tt : T?) {
    let work = test_temp_dir()
    fwrite(path_join(work, "jit_pin_part.das"), PART_SOURCE)
    let pinned = path_join(work, "jit_pin_main.das")
    fwrite(pinned, main_source(PIN))
    let unpinned = path_join(work, "jit_pin_free.das")
    fwrite(unpinned, main_source(""))
    for (tier in ["interp", "jit", "exe", "aot"]) {
        tt |> run("the pinned entry builds and runs under {tier}") @(t : T?) {
            var out : string
            t |> equal(run_tier(pinned, tier, path_join(work, tier), out, CONVERTED_MODULES), 0, "{tier}: {out}")
            t |> success(out |> contains("12\n"), "{tier}: {out}")
        }
    }
    tt |> run("without the piece the interpreter refuses the option") @(t : T?) {
        let r = runtime_child("jit_pin_bare", "options gen2\n{PIN}\n[export]\ndef main \{\n    print(\"ok\\n\")\n\}\n", false)
        child_rejects(t, "the bare pin", r, "invalid option 'jit_split_modules'")
    }
    tt |> run("under the cached JIT the pin builds one unit, the DLL --jit-split-modules=0 builds; without it the build splits") @(t : T?) {
        let cache_dir = path_join(work, "cached")
        mkdir_rec(cache_dir)
        let pin = cached_jit(pinned, cache_dir, "")
        t |> equal(pin.rc, 0, pin.out)
        t |> success(pin.out |> contains("12\n"), pin.out)
        t |> success(!(pin.out |> contains("split codegen")), pin.out)
        let split = cached_jit(unpinned, cache_dir, "")
        t |> equal(split.rc, 0, split.out)
        t |> success(split.out |> contains("split codegen"), split.out)
        let flag = cached_jit(unpinned, cache_dir, "-- --jit-split-modules=0")
        t |> equal(flag.rc, 0, flag.out)
        t |> success(!(flag.out |> contains("split codegen")), flag.out)
        t |> success(!empty(linked_dll(pin.out)), pin.out)
        t |> equal(linked_dll(pin.out), linked_dll(flag.out), "{pin.out}\n{flag.out}")
        t |> success(linked_dll(pin.out) != linked_dll(split.out), "{pin.out}\n{split.out}")
    }
}
