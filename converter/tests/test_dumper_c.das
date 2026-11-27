options gen2
options stack = 1048576
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../pipeline.das
require ../tiers.das
require ../dumper_c.das
require ../cir.das
require ../dumper_a.das
require ../../frontend/diff.das

//! `converter/dumper_c.das` and `--dumper` (`converter/ARCHITECTURE_DUMPER_C.md`): a scalar unit
//! converted with Dumper C gives the C-IR Dumper A gives, byte for byte past the macro fields and
//! the producer, and converts on to a module; the command line takes a or c only; a sidecar's
//! inputs refused.

let FIXTURE = "compare/types/fixtures/conversions.c"

[test(description = "a scalar unit through convert with Dumper C: the C-IR of Dumper A, then the das module", timeout = 600)]
def test_convert_with_dumper_c(t : T?) {
    let dir = path_join(test_temp_dir(), "dumper_c")
    let a <- convert(FIXTURE, path_join(dir, "a"), "linux")
    let c <- convert(FIXTURE, path_join(dir, "c"), "linux", "", "", "", "", "", "", false, "", "", false, "", "", "c")
    t |> success(a.ok, a.error)
    t |> success(c.ok, c.error)
    t |> equal(cir_diff(c.cir_text, a.cir_text), "")
    t |> success(find(c.cir_text, "\"producer\": \"c2das-dumper-c 0.1\"") >= 0)
}

[test(description = "the command line's --dumper: a or c, any other refused with exit 2", timeout = 300)]
def test_dumper_flag(t : T?) {
    var argv <- daslang_cmd(CONVERTED_MODULES)
    argv |> push_from(["converter/main.das", "--", FIXTURE, "--out", path_join(test_temp_dir(), "flag"), "--dumper", "b"])
    var out : string
    t |> equal(run_and_capture(argv, out, 300.0), 2)
    t |> success(find(out, "--dumper is a or c, not `b`") >= 0, out)
}

[test(description = "a sidecar's defines, include folders or files are refused: Dumper C takes none yet")]
def test_inputs_refused(t : T?) {
    var tu : CirTu
    var error : string
    dumper_c_tu(FIXTURE, target_lp64_linux(), default_clang(), DumpInputs(defines <- ["X=1"]), tu, error)
    t |> equal(error, "Dumper C takes no sidecar defines, include folders or include files yet")
}

[test(description = "Dumper C's child needs dasFlex: a repository without fetch/dasFlex refused by name, this one's taken")]
def test_dasflex_missing(t : T?) {
    let bare = path_join(test_temp_dir(), "bare")
    mkdir_rec(bare)
    t |> equal(dasflex_missing(bare), "--dumper c needs dasFlex at {bare}/fetch/dasFlex: scripts/fetch_dasflex.sh fetches it")
    t |> equal(dasflex_missing(getcwd()), "")
}
