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

[test(description = "Dumper C reads C source through the frontend's preprocessor, the own headers searched, the predefined macros defined and the dialect's feature table loaded, so a node an expansion made stands at its macro name; every place in the file as read, `#line` aside, an #if evaluated", timeout = 600)]
def test_dumper_c_source(t : T?) {
    t |> equal(dumped_c("raw.c", "#include <stddef.h>\n#define RET(v) return (v)\n#line 50\nint f(void) \{\n  RET(\n__LP64__);\n\}\n"), "f@4:5 body@5:3")
    t |> equal(dumped_c("pp4.c", "#if __LINE__ > 0\n#line 90\n#define RET(v) return (v)\n#endif\nint f(void) \{\n  RET(\n1);\n\}\n"), "f@5:5 body@6:3")
    t |> equal(dumped_c("feature.c", "#if !__has_builtin(__builtin_expect)\n#error no feature table\n#endif\nint f(void) \{\n  return 1;\n\}\n"), "f@4:5 body@5:3")
}

[test(description = "main.das --dumper c on one file runs Dumper C: its C-IR file beside the module and its producer; a unit with no macro converts to the module --dumper a gives", timeout = 600)]
def test_main_dumper_c(t : T?) {
    let dir = path_join(test_temp_dir(), "main_c")
    mkdir_rec(dir)
    let unit = path_join(dir, "plain.c")
    fwrite(unit, "static int g(int x) \{ return x * 2 + 1; \}\nint main(void) \{ return g(1) - 3; \}\n")
    var modules : array<string>
    modules |> reserve(2)
    for (dumper in ["a", "c"]) {
        let out = path_join(dir, dumper)
        var inscope argv <- daslang_cmd(CONVERTED_MODULES)
        argv |> push_from(["converter/main.das", "--", unit, "--out", out, "--target", "linux", "--dumper", dumper])
        var text : string
        let rc = run_and_capture(argv, text, 300.0)
        t |> equal(rc, 0, text)
        modules |> push(fread(path_join(out, "plain.das")))
        let cir = fread(path_join(out, "plain.cir.json"))
        t |> success(find(cir, "\"producer\": \"c2das-dumper-{dumper} 0.1") >= 0, dumper)
        t |> equal(stat(path_join(out, "plain.dumper_c.cir.json")).is_reg, dumper == "c")
    }
    t |> success(!empty(modules[0]))
    t |> equal(modules[1], modules[0])
}

// the byte diff of Dumper C's and Dumper A's C-IR of `c_path` under `inputs`, or the error of either
def private both_dumpers(c_path : string; inputs : DumpInputs) : string {
    var tu : CirTu
    var error : string
    dumper_c_tu(c_path, target_lp64_linux(), default_clang(), inputs, tu, error)
    var d = new Dumper
    dump_tu(*d, c_path, target_lp64_linux(), default_clang(), inputs)
    let listed = !empty(error) ? "C: {error}" : !empty(d.error) ? "A: {d.error}" : cir_diff(write_cir(tu), write_cir(d.tu))
    delete_tu(tu)
    delete_tu(d.tu)
    unsafe {
        delete d
    }
    return listed
}

[test(description = "Dumper C leaves out the declarations of a header outside the program root as Dumper A does, takes them under a wider sidecar root, and refuses a C file outside the root and a main file outside it; a `#line` naming a file is no file outside the root", timeout = 600)]
def test_dumper_c_program_root(t : T?) {
    mkdir_rec(path_join(test_temp_dir(), "root/d"))
    let top = get_full_file_name(path_join(test_temp_dir(), "root"))
    fwrite(path_join(top, "hdr.h"), "int shared_count;\nint twice(int v);\n")
    fwrite(path_join(top, "d/q.c"), "#include \"../hdr.h\"\nint main(void) \{ return shared_count + twice(1); \}\n")
    let q = path_join(top, "d/q.c")
    t |> equal(both_dumpers(q, DumpInputs()), "")
    t |> equal(both_dumpers(q, DumpInputs(program_root = top)), "")
    var tu : CirTu
    var error : string
    dumper_c_tu(q, target_lp64_linux(), default_clang(), DumpInputs(), tu, error)
    t |> equal(length([for (d in tu.decls); d; where d.name == "shared_count"]), 0)
    delete_tu(tu)
    dumper_c_tu(q, target_lp64_linux(), default_clang(), DumpInputs(program_root = top), tu, error)
    t |> equal(length([for (d in tu.decls); d; where d.name == "shared_count"]), 1)
    delete_tu(tu)
    fwrite(path_join(top, "d/renamed.c"), "int foo(void) \{\n#line 1 \"renamed.c\"\n  return 26;\n\}\nint main(void) \{ return foo(); \}\n")
    t |> equal(both_dumpers(path_join(top, "d/renamed.c"), DumpInputs()), "")
    fwrite(path_join(top, "other.c"), "int other(void) \{ return 1; \}\n")
    fwrite(path_join(top, "d/r.c"), "#include \"../other.c\"\nint main(void) \{ return other(); \}\n")
    error = ""
    dumper_c_tu(path_join(top, "d/r.c"), target_lp64_linux(), default_clang(), DumpInputs(), tu, error)
    t |> success(find(error, "other.c is a C file outside the program root {top}/d/: its definitions would stay external") >= 0, error)
    delete_tu(tu)
    mkdir_rec(path_join(top, "elsewhere"))
    error = ""
    dumper_c_tu(q, target_lp64_linux(), default_clang(), DumpInputs(program_root = path_join(top, "elsewhere")), tu, error)
    t |> success(starts_with(error, "the main file {q} is no file of the program"), error)
    delete_tu(tu)
}
