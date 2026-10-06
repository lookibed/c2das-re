options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require ../pipeline.das
require ../tiers.das

//! Every P1 lowering fixture is a C program whose output and exit code the converted module
//! must reproduce; the expectation is the native build of the same file by the pinned clang
//! under the same dialect, so the fixture is a differential test, not a golden text.

let FIXTURES = "converter/tests/fixtures"
let CLANG_DIALECT = "-funsigned-char"

struct Expectation {
    rc : int
    out : string
}

var work_root : string

def native(name : string) : Expectation {
    let bin = path_join(work_root, "{name}_native")
    let clang = has_env_variable("PATH_TO_LIBCLANG") ? get_env_variable("PATH_TO_LIBCLANG") + "/bin/clang" : "clang"
    var out : string
    let crc = run_and_capture([clang, "-w", CLANG_DIALECT, "-o", bin, "{FIXTURES}/{name}.c"], out, 120.0)
    if (crc != 0) {
        return Expectation(rc = -1, out = "clang failed:\n{out}")
    }
    var program_out : string
    let rc = run_and_capture([bin], program_out, 60.0)
    return Expectation(rc = rc, out = program_out)
}

def converted(t : T?; name : string; var das_text : string&) : Expectation {
    let res <- convert("{FIXTURES}/{name}.c", path_join(work_root, name), "linux")
    if (!res.ok) {
        t |> failure(res.error)
        return Expectation(rc = -2, out = "")
    }
    das_text = res.das_text
    var out : string
    let rc = run_tier(res.das_path, "interp", path_join(work_root, name), out, ["c_runtime", "dasCRuntime"])
    return Expectation(rc = rc, out = out)
}

def check_fixture(t : T?; name : string; var das_text : string&) {
    let want = native(name)
    t |> equal(want.rc >= 0, true, want.out)
    let have = converted(t, name, das_text)
    t |> equal(have.out, want.out)
    t |> equal(have.rc, want.rc)
}

[test]
def test_lowerings(t : T?) {
    var dir_error : string
    work_root = create_temp_directory("c2das_lowerings", dir_error)
    if (!empty(dir_error)) {
        t |> failure(dir_error)
        return
    }
    t |> run("scalars: promotions, usual conversions, operators and the cast table") @(t : T?) {
        var text : string
        check_fixture(t, "p1_scalars", text)
        t |> equal(text |> find("b = uint8(int(b) + 1)") >= 0, true, text)
        t |> equal(text |> find("ub = uint8(int(ub) + 1)") >= 0, true, text)
        t |> equal(text |> find("uint(i) < u") >= 0, true, text)
    }
    t |> run("statement-ification: assignment as expression, steps, comma, side-effecting arms") @(t : T?) {
        var text : string
        check_fixture(t, "p1_statements", text)
        t |> equal(text |> find("let _t0 = x") >= 0, true, text)
        t |> equal(text |> find("c = next()\n    if (c != 5)") >= 0, true, text)
        t |> equal(text |> find("var _t") >= 0 && text |> find("\} else \{") >= 0, true, text)
    }
    t |> run("loops: while, do-while with the first-pass flag, for with the increment-first flag, if chains") @(t : T?) {
        var text : string
        check_fixture(t, "p1_loops", text)
        t |> equal(text |> find("var _first = true") >= 0, true, text)
        t |> equal(text |> find("while (_first || ") >= 0, true, text)
        t |> equal(text |> find("var _f = false") >= 0, true, text)
        t |> equal(text |> find("} elif (") >= 0, true, text)
    }
    t |> run("functions: callee copies of written parameters, statics, globals, exit") @(t : T?) {
        var text : string
        check_fixture(t, "p1_functions", text)
        t |> equal(text |> find("def twice(v_in : int) : int") >= 0, true, text)
        t |> equal(text |> find("var v = v_in") >= 0, true, text)
        t |> equal(text |> find("def private p1_functions__bump(") >= 0, true, text)
        t |> equal(text |> find("c_exit(42)") >= 0, true, text)
        t |> equal(text |> find("require c_runtime/c_exit") >= 0, true, text)
    }
    rmdir_rec(work_root)
}
