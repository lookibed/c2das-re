options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require _daslang_child

//! The ways a run can turn off the cached JIT's per-module partitioning (`--jit-split-modules`,
//! dasLLVM's `llvm_jit_cli.das`) without the converted program seeing it (docs/probe-findings.md
//! F92): daslang takes no such flag before the script; the JIT reads it only after `--`, where it
//! lands in the program's C `argv`; no environment variable sets it; and the script pin `options
//! jit_split_modules` is undeclared unless the program requires `llvm/llvm_jit`, under the
//! interpreter and the JIT alike. The working mechanism, `c_runtime/c_jit_build`, is its piece's
//! fixture test (`c_runtime/tests/test_c_jit_build.das`).

let PART_SOURCE = "options gen2\nmodule split_pin_part public\n\ndef part_step(x : int) : int => (x * 3 + 1) & 1023\n"

// a converted program's shape: `main` builds C's argv, prints argc and calls across modules
let ARGS_SOURCE = "options gen2\nrequire c_runtime/c_args\nrequire split_pin_part\n\n[export]\ndef main : int \{\n    c_runtime_init(\"args\")\n    print(\"argc \{c_argc()\} \{part_step(4)\}\\n\")\n    return 0\n\}\n"

let PIN_SOURCE = "options gen2\noptions jit_split_modules = 0\n\n[export]\ndef main \{\n    print(\"ok\\n\")\n\}\n"

// `<env> daslang <flags> <work>/<file> <after>` run from the folder `work/<cache>`, its own JIT
// cache, the info lines kept
def private run_in(work, cache, env, file, flags, after : string) : tuple<rc : int; out : string> {
    let root = getcwd()
    let cwd = path_join(work, cache)
    mkdir_rec(cwd)
    let cmd = "cd '{cwd}' && {env} DAS_LOG_LEVEL=info '{get_das_root()}/bin/daslang' -load_module '{root}/dasCRuntime' -load_module '{root}/c_runtime' {flags} '{work}/{file}' {after}"
    var out : string
    let rc = run_and_capture(["sh", "-c", cmd], out, 300.0)
    return (rc, out)
}

[test]
def test_jit_split_pin(tt : T?) {
    let work = test_temp_dir()
    fwrite(path_join(work, "split_pin_part.das"), PART_SOURCE)
    fwrite(path_join(work, "split_pin_args.das"), ARGS_SOURCE)
    fwrite(path_join(work, "split_pin_bare.das"), PIN_SOURCE)
    tt |> run("daslang refuses -jit-split-modules before the script and runs nothing") @(t : T?) {
        let r = run_in(work, "flag", "", "split_pin_args.das", "-jit -jit-split-modules=0", "")
        t |> success(r.rc != 0, r.out)
        t |> success(r.out |> contains("unknown command line option jit-split-modules=0"), r.out)
        t |> success(!(r.out |> contains("argc ")), r.out)
    }
    tt |> run("after `--` the JIT builds one unit and the program's argv holds the flag") @(t : T?) {
        let r = run_in(work, "argv", "", "split_pin_args.das", "-jit", "-- --jit-split-modules=0")
        t |> equal(r.rc, 0, r.out)
        t |> success(r.out |> contains("argc 2 13\n"), r.out)
        t |> success(!(r.out |> contains("split codegen")), r.out)
        let split = run_in(work, "argv", "", "split_pin_args.das", "-jit", "")
        t |> success(split.out |> contains("argc 1 13\n"), split.out)
        t |> success(split.out |> contains("split codegen"), split.out)
    }
    tt |> run("DAS_JIT_SPLIT_MODULES=0 in the environment leaves the build split") @(t : T?) {
        let r = run_in(work, "env", "DAS_JIT_SPLIT_MODULES=0", "split_pin_args.das", "-jit", "")
        t |> equal(r.rc, 0, r.out)
        t |> success(r.out |> contains("argc 1 13\n"), r.out)
        t |> success(r.out |> contains("split codegen"), r.out)
    }
    for (flags in ["", "-jit"]) {
        tt |> run("the bare pin is an invalid option under {empty(flags) ? "the interpreter" : "-jit"}") @(t : T?) {
            let r = run_in(work, "bare", "", "split_pin_bare.das", flags, "")
            t |> success(r.out |> contains("invalid option 'jit_split_modules'"), r.out)
            t |> success(!(r.out |> contains("ok\n")), r.out)
        }
    }
}
