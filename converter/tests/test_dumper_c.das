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

// Dumper C's C-IR of unit `text` written as `<name>` under the test folder: its first function's
// first statement's place and the C-IR text past the producer, or `error: ` and the error
def private dumped_c(name, text : string) : string {
    let path = path_join(test_temp_dir(), name)
    fwrite(path, text)
    var tu : CirTu
    var error : string
    dumper_c_tu(path, target_lp64_linux(), default_clang(), DumpInputs(), tu, error)
    var listed = "error: {error}"
    if (empty(error)) {
        let last = tu.decls[length(tu.decls) - 1]
        listed = "{last.name}@{last.loc.line}:{last.loc.col} body@{last.body.body[0].loc.line}:{last.body.body[0].loc.col}"
    }
    delete_tu(tu)
    return listed
}

[test(description = "Dumper C reads C source through the frontend's preprocessor, the own headers searched and the predefined macros defined, so a node an expansion made stands at its macro name; every place in the file as read, `#line` aside; where an #if needs PP.4, clang -E stands in", timeout = 600)]
def test_dumper_c_source(t : T?) {
    t |> equal(dumped_c("raw.c", "#include <stddef.h>\n#define RET(v) return (v)\n#line 50\nint f(void) \{\n  RET(\n__LP64__);\n\}\n"), "f@4:5 body@5:3")
    t |> equal(dumped_c("pp4.c", "#if __LINE__ > 0\n#define RET(v) return (v)\n#endif\nint f(void) \{\n  RET(\n1);\n\}\n"), "f@4:5 body@5:3")
    t |> success(dumper_c_needs_evaluator("main.c:1:2: #if expression needs the PP.4 evaluator: 1 + 1"))
    t |> success(!dumper_c_needs_evaluator("main.c:1:2: #error x"))
}
