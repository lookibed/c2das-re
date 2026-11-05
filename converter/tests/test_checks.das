options gen2
// the pipeline parses clang's JSON dump below the test's own frames
options stack = 1048576
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/sha_256
require daslib/strings_boost
require ../pipeline.das
require ../emit.das
require ../tiers.das
require ../dumper_a.das

//! `--checks safe|off` (P7.0o, docs/probe-findings.md F84): under `off` every converted function
//! carries `unsafe_deref` and `hint(unsafe_range_check)` and the module says so under its banner;
//! a well-defined program prints what its native build prints in both modes, and an index one past
//! a fixed array panics in the checked module and reads the next field in the unchecked one.

let FIXTURE = "converter/tests/fixtures/p7_unchecked.c"
let SAFE_SHA = "70b0f715ca4bde5a0cb12b034f87c0459ee8663db2f3eed3adb8e033c5825abf"
let OFF_SHA = "ba24523389ba57e2fa7ac670e4e5867b0dc2d34983f6eae6c5ea77f8748a44a1"

var work_root : string
var safe : ConvertResult
var off : ConvertResult

// the fixture converted with `checks` ("" for the default) into `<work_root>/<name>`
def converted(name, checks : string; sidecar : string = "") : ConvertResult => <- convert(FIXTURE, path_join(work_root, name), "linux", "", sidecar, "", "", "", "", false, checks)

// the converted fixture's program output under `tier` with `program_args`, its exit code in `rc`
def ran(das_path, tier, name : string; program_args : array<string>; var rc : int&) : string {
    var out : string
    let no_flags : array<string>
    rc = run_tier(das_path, tier, path_join(work_root, "{name}_{tier}"), out, CONVERTED_MODULES, 600.0, no_flags, program_args)
    // the JIT reports its compilation on `info` lines among the program's output
    return join([for (ln in split(out, "\n")); ln; where !(ln |> starts_with("[I] "))], "\n")
}

[test]
def test_checks(t : T?) {
    var dir_error : string
    work_root = create_temp_directory("c2das_checks", dir_error)
    if (!empty(dir_error)) {
        t |> failure(dir_error)
        return
    }
    delete safe
    safe <- converted("safe", "")
    delete off
    off <- converted("off", "off")
    t |> run("by default no function drops a check; under `off` each carries both annotations after `c_function`, and the module says so under its banner") @(t : T?) {
        t |> equal(safe.error, "")
        t |> equal(off.error, "")
        t |> success(!(safe.das_text |> contains("unsafe_deref")) && !(safe.das_text |> contains("--checks off")), safe.das_text)
        t |> success(safe.das_text |> starts_with("{GENERATED_BANNER}\noptions gen2\n"), safe.das_text)
        t |> success(off.das_text |> starts_with("{GENERATED_BANNER}\n// converted with --checks off: no null or range checks (the AOT host keeps its range checks), a wrong C program reads garbage or dies by SIGSEGV instead of panicking\noptions gen2\n"), off.das_text)
        t |> success(off.das_text |> contains("\n[unsafe_deref, hint(unsafe_range_check)]\ndef private p7_unchecked__at(var s : S?; i : int) : int \{\n"), off.das_text)
        t |> success(off.das_text |> contains("\n[unsafe_deref, hint(unsafe_range_check)]\ndef private p7_unchecked__sum(n : int) : int \{\n"), off.das_text)
        t |> success(off.das_text |> contains("\n[c_function, unsafe_deref, hint(unsafe_range_check)]\ndef c_main("), off.das_text)
        // the generated `main`, the `[init]` functions and the layout check stay as they are
        t |> success(off.das_text |> contains("\n[export]\ndef main : int \{\n"), off.das_text)
        t |> success(off.das_text |> contains("\n[init]\ndef private c2das_layout_check \{\n"), off.das_text)
    }
    t |> run("golden hashes of the module in both modes") @(t : T?) {
        t |> equal(sha256_hex(safe.das_text), SAFE_SHA, safe.das_text)
        t |> equal(sha256_hex(off.das_text), OFF_SHA, off.das_text)
    }
    let native = native_run(default_clang(), ["-w", "-funsigned-char"], FIXTURE, path_join(work_root, "native"), 60.0)
    for (tier in ["interp", "jit"]) {
        t |> run("under {tier} both modes print what the native build prints; one past the array panics checked and reads the next field unchecked") @(t : T?) {
            t |> success(native.built, native.output)
            var rc : int
            for (name in ["safe", "off"]) {
                let das_path = name == "off" ? off.das_path : safe.das_path
                t |> equal(ran(das_path, tier, name, array<string>(), rc), native.output, name)
                t |> equal(rc, native.rc, name)
            }
            let checked = ran(safe.das_path, tier, "safe_past", array<string>("4"), rc)
            t |> success(rc != 0 && checked |> contains("index out of range"), "rc {rc}: {checked}")
            let unchecked = ran(off.das_path, tier, "off_past", array<string>("4"), rc)
            t |> equal(rc, 0, unchecked)
            t |> success(unchecked |> starts_with("at 4 = 77\nsum 84\n"), unchecked)
        }
    }
    t |> run("the sidecar's `checks: \"off\"` converts as the option does, the option wins over it, and a value but safe or off is refused") @(t : T?) {
        let sidecar = path_join(work_root, "off.c2das")
        fwrite(sidecar, "\{\"checks\": \"off\"\}\n")
        let sided <- converted("sided", "", sidecar)
        t |> equal(sided.das_text, off.das_text)
        let overridden <- converted("overridden", "safe", sidecar)
        t |> equal(overridden.das_text, safe.das_text)
        let refused <- converted("refused", "fast")
        t |> equal(refused.ok, false)
        t |> equal(refused.error, "--checks is safe or off, not `fast`")
    }
    t |> run("a program of several files converted with `off` carries both annotations and the banner line in its module") @(t : T?) {
        let cut = "converter/tests/fixtures/p5_layout_cut"
        let paths <- ["{cut}/main.c", "{cut}/a.c", "{cut}/b.c"]
        let program <- convert_program(paths, path_join(work_root, "program"), "linux", "", "", "", "", "main", "single", false, "", "", false, "off")
        t |> equal(program.error, "")
        t |> success(program.das_text |> contains("{GENERATED_BANNER}\n{UNCHECKED_BANNER}\noptions gen2\n"), program.das_text)
        t |> success(program.das_text |> contains("\n[unsafe_deref, hint(unsafe_range_check)]\ndef a_run(n : int) : int \{\n"), program.das_text)
        t |> success(program.das_text |> contains("\n[c_function, unsafe_deref, hint(unsafe_range_check)]\ndef c_main("), program.das_text)
    }
    t |> run("under `off` the marshal accessors stay plain `[c_function]`, the converted functions take both annotations") @(t : T?) {
        let marshal <- convert("converter/tests/fixtures/p2_marshal.c", path_join(work_root, "marshal"), "linux", "", "", "", "", "", "", false, "off")
        t |> equal(marshal.error, "")
        for (accessor in ["read_disk_t(", "write_disk_t_width(", "read_pref_t_p("]) {
            t |> success(marshal.das_text |> contains("\n[c_function]\ndef {accessor}"), "{accessor}\n{marshal.das_text}")
        }
        t |> success(marshal.das_text |> contains("\n[c_function, unsafe_deref, hint(unsafe_range_check)]\ndef private p2_marshal__sum_widths("), marshal.das_text)
    }
    rmdir_rec(work_root)
}
