options gen2
// the pipeline parses clang's JSON dump below the test's own frames
options stack = 1048576
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../pipeline.das
require ../tiers.das
require ../dumper_a.das

//! The JIT's and the exe's typed aliasing over converted programs (P8.5, `ARCHITECTURE_TIERS.md`
//! section 9, docs/probe-findings.md F95). `p8_alias_unsafe.c` holds the shapes the model misses (two
//! views through `void *`, two views loaded from a record), `p8_alias_safe.c` the shapes it keeps
//! right (unions, a typed cast, a byte view, `memcpy`, two integer widths); each writes a float, the
//! same bytes under another type, and reads the float back, through pointers the compiler cannot
//! prove equal. By default the entry module turns the model off and both print what the native
//! build prints; the sidecar's `strict_aliasing: true` keeps it, which the safe shapes survive and
//! the unsafe ones do not.

let FIXTURES = "converter/tests/fixtures"
let OFF_LINE = "\noptions strict_aliasing = false\n"

var work_root : string

// the fixture `name` converted into `<work_root>/<dir>`, with `sidecar` as its `.c2das` when given
def private converted(t : T?; name, dir, sidecar : string) : ConvertResult {
    let at = path_join(work_root, dir)
    mkdir_rec(at)
    let side = empty(sidecar) ? "" : path_join(at, "{name}.c2das")
    if (!empty(side)) {
        fwrite(side, sidecar)
    }
    var res <- convert("{FIXTURES}/{name}.c", path_join(at, "out"), "linux", "", side)
    t |> equal(res.error, "")
    return <- res
}

// the output of the fixture's native build at `level` (`-O0`, the oracle; `-O2`, strict aliasing on)
def private native_output(t : T?; name, level : string) : string {
    let run = native_run(default_clang(), ["-w", "-funsigned-char", level], "{FIXTURES}/{name}.c", path_join(work_root, "{name}_native{level}"), 60.0)
    t |> equal(run.built, true, run.output)
    t |> equal(run.rc, 0, run.output)
    return run.output
}

// the converted program's output under `tier`, the JIT's `info` lines dropped
def private tier_output(t : T?; res : ConvertResult; tier, dir : string) : string {
    var out : string
    let rc = run_tier(res.das_path, tier, path_join(work_root, "{dir}_{tier}"), out, CONVERTED_MODULES)
    t |> equal(rc, 0, "{tier}: {out}")
    return join([for (ln in split(out, "\n")); ln; where !(ln |> starts_with("[I] "))], "\n")
}

[test]
def test_strict_aliasing(t : T?) {
    var dir_error : string
    work_root = create_temp_directory("c2das_strict_aliasing", dir_error)
    t |> equal(dir_error, "")
    let native_unsafe = native_output(t, "p8_alias_unsafe", "-O0")
    t |> run("the unsafe shapes print 1 and 3 natively, 2 and 2 under clang -O2's strict aliasing") @(t : T?) {
        t |> equal(native_unsafe, "1\n3\n")
        t |> equal(native_output(t, "p8_alias_unsafe", "-O2"), "2\n2\n")
    }
    t |> run("by default the entry module turns the typed aliasing off, and the unsafe shapes print what the native build prints under interp, jit and exe") @(t : T?) {
        let res <- converted(t, "p8_alias_unsafe", "unsafe_default", "")
        t |> equal(length(split(res.das_text, OFF_LINE)) - 1, 1, res.das_text)
        for (tier in ["interp", "jit", "exe"]) {
            t |> equal(tier_output(t, res, tier, "unsafe_default"), native_unsafe, tier)
        }
    }
    t |> run("negative control: under the sidecar's `strict_aliasing: true` no line turns the model off, and the unsafe shapes print clang -O2's 2 and 2 under jit and exe") @(t : T?) {
        let res <- converted(t, "p8_alias_unsafe", "unsafe_kept", "\{\"strict_aliasing\": true\}\n")
        t |> equal(res.das_text |> contains("strict_aliasing"), false, res.das_text)
        t |> equal(tier_output(t, res, "interp", "unsafe_kept"), native_unsafe)
        for (tier in ["jit", "exe"]) {
            t |> equal(tier_output(t, res, tier, "unsafe_kept"), "2\n2\n", tier)
        }
    }
    t |> run("the safe shapes print what the native build prints with the model kept, under interp, jit and exe, and by default") @(t : T?) {
        let native_safe = native_output(t, "p8_alias_safe", "-O0")
        t |> equal(native_safe, "1\n1\n1\n1\n1\n12341111\n")
        let kept <- converted(t, "p8_alias_safe", "safe_kept", "\{\"strict_aliasing\": true\}\n")
        t |> equal(kept.das_text |> contains("strict_aliasing"), false, kept.das_text)
        for (tier in ["interp", "jit", "exe"]) {
            t |> equal(tier_output(t, kept, tier, "safe_kept"), native_safe, tier)
        }
        let plain <- converted(t, "p8_alias_safe", "safe_default", "")
        t |> equal(tier_output(t, plain, "jit", "safe_default"), native_safe)
    }
    rmdir_rec(work_root)
}
