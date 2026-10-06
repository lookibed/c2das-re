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
        t |> equal(text |> find("\} finally \{") >= 0, true, text)
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
    t |> run("structs: records with grouped fields, initializer lists, by-value copies, writes through a pointer, sizeof and offsetof as typeinfo, the layout assertion") @(t : T?) {
        var text : string
        check_fixture(t, "p2_structs", text)
        t |> equal(text |> find("struct mobj_t \{\n    thinker : thinker_t\n    x, y : int\n\}") >= 0, true, text)
        t |> equal(text |> find("mobj_t(thinker = thinker_t(fn = 7), x = 1)") >= 0, true, text)
        t |> equal(text |> find("scale(p_in : P; k : int) : P \{\n    var p = p_in") >= 0, true, text)
        t |> equal(text |> find("bump(var m : mobj_t?)") >= 0, true, text)
        t |> equal(text |> find("typeinfo offsetof < x > (type<mobj_t>)") >= 0, true, text)
        t |> equal(text |> find("[init]\ndef private c2das_layout_check") >= 0, true, text)
        t |> equal(text |> find("typeinfo sizeof(type<P>) == 16 && typeinfo alignof(type<P>) == 8") >= 0, true, text)
    }
    t |> run("arrays: padded fixed_array literals, sparse stores at init, cstr_array, multi-dim and row pointers, decay, direct subscripts") @(t : T?) {
        var text : string
        check_fixture(t, "p2_arrays", text)
        t |> equal(text |> find("var part : int[6] = fixed_array(1, 2, 0, 0, 0, 0)") >= 0, true, text)
        t |> equal(text |> find("var sparse : int[40]\n") >= 0, true, text)
        t |> equal(text |> find("def private c2das_init_globals \{\n    sparse[5] = 9") >= 0, true, text)
        t |> equal(text |> find("var name : uint8[8] = cstr_array(\"abc\", 8)") >= 0, true, text)
        t |> equal(text |> find("var m : int[2][3] = fixed_array(fixed_array(1, 2, 3), fixed_array(4, 5, 6))") >= 0, true, text)
        t |> equal(text |> find("var ptrs : int? [2] = fixed_array(unsafe(addr(full[1])), null)") >= 0, true, text)
        t |> equal(text |> find("var row : int[3]? = addr(m[1])") >= 0, true, text)
        t |> equal(text |> find("deref(row)[2]") >= 0, true, text)
        t |> equal(text |> find("m[0][i] *= 2") >= 0, true, text)
        t |> equal(text |> find("total(addr(full[0]), 3)") >= 0, true, text)
    }
    t |> run("pointers: the blit shape, function values and invoke, pointer differences, the CRT memory functions, [c_function] only where unsafe") @(t : T?) {
        var text : string
        check_fixture(t, "p2_pointers", text)
        t |> equal(text |> find("def private p2_pointers__blit(src_in : uint8?; var dst_in : uint8?; n_in : int)") >= 0, true, text)
        t |> equal(text |> find("deref(_t1) = deref(_t2)") >= 0, true, text)
        t |> equal(text |> find("f : function<(a0 : int) : int>") >= 0, true, text)
        t |> equal(text |> find("invoke(f, x) + invoke(f, 1)") >= 0, true, text)
        t |> equal(text |> find("fixed_array(@@p2_pointers__twice, @@p2_pointers__thrice)") >= 0, true, text)
        t |> equal(text |> find("invoke(p2_pointers__table[1], 4)") >= 0, true, text)
        t |> equal(text |> find("return int64(hi - lo)") >= 0, true, text)
        t |> equal(text |> find("var raw : void? = crt::malloc(uint64(16))") >= 0 && text |> find("reinterpret<int?>(raw)") >= 0, true, text)
        t |> equal(text |> find("intptr(p) > intptr(q)") >= 0, true, text)
        t |> equal(text |> find("[c_function]\ndef private p2_pointers__twice") < 0, true, text)
    }
    rmdir_rec(work_root)
}
