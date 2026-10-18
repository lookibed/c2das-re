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

// a substring the converted text must carry, reported by the needle when it is missing
def has_text(t : T?; text : string; needle : string) {
    t |> equal(text |> find(needle) >= 0, true, "missing `{needle}` in:\n{text}")
}

def write_file(path : string; text : string) {
    fopen(path, "wb") $(f) {
        if (f != null) {
            fwrite(f, text)
        }
    }
}

// a C source the converter must refuse, with the error naming the construct; `sidecar` is
// the `.c2das` text beside it, when the shape needs one
def rejects(t : T?; name : string; source : string; needle : string; sidecar : string = "") {
    let dir = path_join(work_root, "rejected")
    mkdir(dir)
    let c_path = path_join(dir, "{name}.c")
    write_file(c_path, source)
    if (!empty(sidecar)) {
        write_file(path_join(dir, "{name}.c2das"), sidecar)
    }
    let res <- convert(c_path, path_join(dir, name), "linux")
    t |> equal(res.ok, false, "{name} converted:\n{res.das_text}")
    t |> equal(res.error |> find(needle) >= 0, true, "{name}: `{needle}` not in `{res.error}`")
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
    p2_fixtures(t)
    rmdir_rec(work_root)
}

def p2_fixtures(t : T?) {
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
    p2_enum_fixtures(t)
    t |> run("strings: literals stay literals, the empty literal has its byte, char arrays are cstr_array, string.h and ctype through crt, sprintf through c_runtime") @(t : T?) {
        var text : string
        check_fixture(t, "p2_strings", text)
        has_text(t, text, "var private c2das_empty : uint8[1] = fixed_array(uint8(0))")
        has_text(t, text, "var private p2_strings__greeting : uint8? = unsafe(reinterpret<uint8?>(\"hello\"))")
        has_text(t, text, "var private p2_strings__buf : uint8[16] = cstr_array(\"abc\", 16)")
        has_text(t, text, "unsafe(addr(c2das_empty[0])), unsafe(reinterpret<uint8?>(\"three\"))")
        has_text(t, text, "var private p2_strings__empty : uint8[1] = cstr_array(\"\", 1)")
        has_text(t, text, "crt::strcpy(addr(local[0]), p2_strings__greeting)")
        has_text(t, text, "crt::strncpy(addr(local[0]) + crt::strlen(addr(local[0])), p2_strings__names[1], uint64(3))")
        has_text(t, text, "int64(crt::strchr(addr(local[0]), 44) - addr(local[0]))")
        has_text(t, text, "deref(reinterpret<uint8?>(crt::memchr(reinterpret<void?>(p2_strings__greeting), 101, uint64(5))))")
        has_text(t, text, "crt::atoi(addr(num[0])) + int(crt::atol(reinterpret<uint8?>(\"100\")))")
        has_text(t, text, "deref(reinterpret<uint8?>(\"abcdef\") + 2)")
        has_text(t, text, "typeinfo sizeof(type<uint8[4]>)")
        has_text(t, text, "sprintf(addr(local[0]), reinterpret<uint8?>(\"%d-%s\"), 7, addr(p2_strings__buf[0]))")
        has_text(t, text, "crt::isdigit(int(num[0])) != 0")
        has_text(t, text, "require crt\n")
    }
    p2_memory_fixtures(t)
    p3_fixtures(t)
    p4_fixtures(t)
}

def p2_enum_fixtures(t : T?) {
    t |> run("enums: das enums with default base, symbolic enumerators, int() at relational and index sites, enum_from_int at int-to-enum sites, the count as a dimension") @(t : T?) {
        var text : string
        check_fixture(t, "p2_enums", text)
        t |> equal(text |> find("enum mobjtype_t \{\n    MT_PLAYER\n    MT_SHOTGUN = 5\n    NUMMOBJTYPES\n\}") >= 0, true, text)
        t |> equal(text |> find("enum color \{\n    RED = -1\n    GREEN = 8\n    BLUE\n    CYAN = 8\n\}") >= 0, true, text)
        t |> equal(text |> find("var private p2_enums__mobjinfo : mobjinfo_t[int(mobjtype_t.NUMMOBJTYPES)]") >= 0, true, text)
        t |> equal(text |> find("hits : int[int(color.BLUE)]") >= 0, true, text)
        t |> equal(text |> find("if (t == mobjtype_t.MT_SHOTGUN)") >= 0, true, text)
        t |> equal(text |> find("if (c == color.RED)") >= 0, true, text)
        t |> equal(text |> find("uint(int(t)) < uint(int(mobjtype_t.MT_SHOTGUN))") >= 0, true, text)
        t |> equal(text |> find("p2_enums__mobjinfo[int(t)].speed = 3") >= 0, true, text)
        t |> equal(text |> find("p._c_type = mobjtype_t.MT_PLAYER") >= 0, true, text)
        t |> equal(text |> find("t = enum_from_int(type<mobjtype_t>, int(t) + 1)") >= 0, true, text)
        t |> equal(text |> find("return i > 0 ? color.GREEN : color.RED") >= 0, true, text)
        t |> equal(text |> find("mobj(_c_type = mobjtype_t.MT_SHOTGUN, c = color.BLUE, hp = 7)") >= 0, true, text)
        t |> equal(text |> find("var inner : anon_") >= 0 && text |> find(".INNER_Y\n") >= 0, true, text)
        t |> equal(text |> find("require c_runtime/enum_from_int") >= 0, true, text)
        has_text(t, text, "var local : anon_")
        has_text(t, text, "return int(uint(int(local)) + uint(int(anon_")
        has_text(t, text, "int(uint8(int(w))) == int(wide.W_LOW)")
        has_text(t, text, "enum_from_int(type<wide>, int(uint8(int(w))))")
        has_text(t, text, "F_TOP = -2147483647 - 1")
        has_text(t, text, "var x : uint64 = uint64(uint(int(f)))")
        has_text(t, text, "var d : double = double(uint(int(f)))")
        has_text(t, text, "g = enum_from_int(type<flags>, int(uint(int(g)) >> 4u))")
        has_text(t, text, "w >>= 28u")
        has_text(t, text, "int64(int(c)) == int64(uint(int(color.RED)))")
        has_text(t, text, "u = wide.W_LOW\n        _t0 = uint(int(u))")
        has_text(t, text, "enum_from_int(type<wide>, int(uint8(c != 0 ? int(wide.W_LOW) : int(wide.W_HIGH))))")
        has_text(t, text, "var b : int[int(color.BLUE)]")
        has_text(t, text, "var grid : int[int(wide.W_LOW)][int(color.BLUE)]")
        has_text(t, text, "var private lines_filled : int[int(color.BLUE)] = fixed_array(5, 0, 0, 0, 0, 0, 0, 0, 0)")
        has_text(t, text, "int(anon_18.L_A)\n}")
        has_text(t, text, "var same : color = c")
        has_text(t, text, "var fromd : color = enum_from_int(type<color>, int(d))")
        has_text(t, text, "deref(p + int(t))")
        has_text(t, text, "fixed_array(neg.N_HIGH, enum_from_int(type<neg>, 0))")
    }
    t |> run("enums the dumper refuses, each with a located message naming the construct") @(t : T?) {
        rejects(t, "same_tag", "static int f(void) \{ enum e \{ A = 1 \}; return A; \}\nstatic int g(void) \{ enum e \{ B = 2 \}; return B; \}\nint main(void) \{ return f() + g(); \}\n", "defined more than once")
        rejects(t, "packed", "enum __attribute__((packed)) P \{ P1 = 1 \};\nint main(void) \{ enum P p = P1; return p; \}\n", "bits wide")
        rejects(t, "in_sizeof", "int main(void) \{ return (int) sizeof(enum Q \{ Q1 = 5 \}); \}\n", "defined inside an expression")
        rejects(t, "macro_constant", "enum E \{ A = 1, B = 2 \};\n#define BOTH (A + B)\nint main(void) \{ return BOTH; \}\n", "libclang reports no reference")
    }
}

def p2_memory_fixtures(t : T?) {
    t |> run("globals: zero-init pass-through, value inits, address inits inline where legal else [init], function values, statics") @(t : T?) {
        var text : string
        check_fixture(t, "p2_globals", text)
        has_text(t, text, "var leveltime : int\n")
        has_text(t, text, "var private p2_globals__p : int?\n")
        has_text(t, text, "var private p2_globals__q : int? = unsafe(addr(p2_globals__ready))")
        has_text(t, text, "var later : int = 5\nvar private p2_globals__r : int? = unsafe(addr(later))")
        has_text(t, text, "def private c2das_init_globals \{\n    p2_globals__p = unsafe(addr(p2_globals__data[1]))\n    p2_globals__s = S(fn = @@p2_globals__zero, at = unsafe(addr(p2_globals__data[2])))")
        has_text(t, text, "var private p2_globals__fptr : function<() : int> = default<function<() : int>>")
        has_text(t, text, "fixed_array(@@p2_globals__zero, @@p2_globals__one)")
        has_text(t, text, "var x : int = 3\n")
        has_text(t, text, "var private tick_count : int = 4567")
        has_text(t, text, "def private p2_globals__sum(var a : int?; n : int) : int")
        has_text(t, text, "p2_globals__fptr = default<function<() : int>>")
        has_text(t, text, "p2_globals__fptr != null ? 1 : 0")
        has_text(t, text, "return p2_globals__fptr == null ? 3 : 4")
    }
    t |> run("marshal: a sidecar-flagged packed record is bytes in C memory, a natural struct as a value, with generated readers and writers at clang's offsets") @(t : T?) {
        var text : string
        check_fixture(t, "p2_marshal", text)
        has_text(t, text, "struct disk_t \{\n    width : int16\n    ofs : int\n    tag : uint8\n\}")
        has_text(t, text, "def read_disk_t(bytes : uint8?; ofs : int) : disk_t \{\n    var r : disk_t\n    crt::memcpy(reinterpret<void?>(addr(r.width)), reinterpret<void?>(bytes + (ofs + 0)), uint64(2))")
        has_text(t, text, "def write_disk_t_ofs(bytes : uint8?; ofs : int; v : int)")
        has_text(t, text, "typeinfo sizeof(type<natural_t>) == 8")
        t |> equal(text |> find("type<disk_t>") < 0, true, "disk_t carries a layout assertion:\n{text}")
        has_text(t, text, "var first : uint8? = reinterpret<uint8?>(addr(p2_marshal__lump[0]) + 2)")
        has_text(t, text, "write_disk_t(first, 0, local)")
        has_text(t, text, "write_disk_t_width(w, 0, int16(300 + i))")
        has_text(t, text, "write_disk_t_width(first + 1 * 7, 0, int16(9))")
        has_text(t, text, "write_disk_t_ofs(first + 2 * 7, 0, read_disk_t_ofs(first + 2 * 7, 0) + 5)")
        has_text(t, text, "var copy : disk_t = read_disk_t(first, 0)")
        has_text(t, text, "int(uint64(7)), int(uint64(7)), int(uint64(typeinfo sizeof(type<natural_t>)))")
        has_text(t, text, "var end : uint8? = entries + n * 7")
        has_text(t, text, "entries = entries + 7")
        has_text(t, text, "read_disk_t_width(entries, 0)")
    }
    t |> run("marshal: the shapes the emitter refuses, each naming the record") @(t : T?) {
        let packed = "#pragma pack(1)\ntypedef struct \{ short w; int o; \} disk_t;\nint main(void) \{ disk_t d; d.w = 1; return d.w; \}\n"
        rejects(t, "packed_unlisted", packed, "listed under `marshal`")
        rejects(t, "marshal_addr", "#pragma pack(1)\ntypedef struct \{ short w; int o; \} disk_t;\nint main(void) \{ disk_t d; disk_t *p = &d; return p->w; \}\n", "address of a value of the marshal-only record", "\{ \"marshal\": [\"disk_t\"] \}\n")
        rejects(t, "marshal_array", "#pragma pack(1)\ntypedef struct \{ short w; int o; \} disk_t;\nstatic disk_t table[3];\nint main(void) \{ return table[1].w; \}\n", "array of the marshal-only record", "\{ \"marshal\": [\"disk_t\"] \}\n")
    }
}

def p3_fixtures(t : T?) {
    t |> run("switch: the if-chain where no case falls through and breaks are tail-only, the matched-flag loop otherwise, enum compares, the cont epilogue, nested switches") @(t : T?) {
        var text : string
        check_fixture(t, "p3_switch", text)
        has_text(t, text, "let _cond = x\n    if (_cond == 1) \{\n        r = 10\n    \} elif (_cond == 2 || _cond == 3) \{\n        r = 20\n    \} elif (_cond == -4) \{")
        has_text(t, text, "if (_cond == 1u) \{\n        return 1\n    \} elif (_cond == 7u) \{\n        return 7\n    \} else \{\n        return 99")
        has_text(t, text, "let _cond = t\n    if (_cond == mobjtype_t.MT_PLAYER) \{")
        has_text(t, text, "_flag ||= _cond == 5\n        if (_flag) \{\n            let _t1 = n\n            n++\n            deref(trace + _t1) = 5\n        \}\n        _flag ||= _cond == 9")
        has_text(t, text, "_flag ||= !(_cond == 1 || _cond == 5 || _cond == 9)")
        has_text(t, text, "var _cont = false\n                while (true) \{")
        has_text(t, text, "_cont = true\n                        break")
        has_text(t, text, "if (_cont) \{\n                    continue\n                \}")
        has_text(t, text, "let _cond2 = b\n        if (_cond2 == 1) \{")
        has_text(t, text, "if (_cond == 8589934592l) \{")
        has_text(t, text, "if (b == 2) \{\n                break\n            \}")
    }
    t |> run("goto: labels numbered per function with the C name as a comment, forward and backward jumps, a jump out of nested loops, a block flattened for a goto into it") @(t : T?) {
        var text : string
        check_fixture(t, "p3_goto", text)
        has_text(t, text, "label 1:  // retry\n    if (!(p3_goto__try_lock() != 0)) \{\n        n++\n        goto label 1\n    \}")
        has_text(t, text, "return n\n    label 2:  // fail\n    n = -n")
        has_text(t, text, "found = i * 10 + j\n                        goto label 1\n")
        has_text(t, text, "    label 1:  // done\n    return found")
        has_text(t, text, "r += 1\n    r += 10\n    label 1:  // inside\n    r += 100")
        has_text(t, text, "r = 2\n    \{\n        var unused : int = 7\n        r += unused\n    \}\n    label 1:  // skip")
        has_text(t, text, "label 1:  // again\n    n += 2\n    if (n < 7) \{\n        goto label 1")
        rejects(t, "goto_into_loop", "int main(void) \{ int i = 0, n = 0; goto in; while (i < 3) \{ in: n++; i++; \} return n; \}\n", "Duff's device")
        rejects(t, "goto_into_if", "int main(void) \{ int n = 0; goto in; if (n == 0) \{ in: n = 5; \} return n; \}\n", "Duff's device")
    }
    t |> run("setjmp: the contained site as try/recover with the target check, the single-branch site as the rerun loop, longjmp as c_longjmp") @(t : T?) {
        var text : string
        check_fixture(t, "p3_setjmp", text)
        has_text(t, text, "require c_runtime/setjmp")
        has_text(t, text, "var private p3_setjmp__outer : CJmpBuf")
        has_text(t, text, "def private p3_setjmp__deep(n : int; var target : CJmpBuf?; v : int) \{\n    p3_setjmp__depth_reached = n\n    if (n == 0) \{\n        c_longjmp(target, v)")
        has_text(t, text, "    try \{\n        if (fail_at != 0) \{\n            p3_setjmp__deep(fail_at, addr(buf), value)\n        \}\n        status = 100\n    \} recover \{\n        if (c_jmp_target != addr(buf)) \{\n            panic(\"longjmp\")\n        \}\n        c_jmp_target = null\n        status = -1\n    \}")
        has_text(t, text, "var _sj_run = true\n    var _sj_val = 0\n    while (_sj_run) \{\n        _sj_run = false\n        try \{\n            if (_sj_val != 0) \{\n                return 1\n            \}\n            c_longjmp(addr(buf), 0)")
        has_text(t, text, "_sj_val = buf.val\n            _sj_run = true")
        rejects(t, "setjmp_value", "#include <setjmp.h>\nint main(void) \{ jmp_buf b; int r = setjmp(b); return r; \}\n", "trampoline form")
        rejects(t, "setjmp_tail_break", "#include <setjmp.h>\nint main(void) \{ jmp_buf b; int i = 0; while (i < 3) \{ if (setjmp(b)) \{ i = 9; \} i++; if (i > 1) break; \} return i; \}\n", "tail leaves an enclosing loop")
    }
    t |> run("alloca: the per-function arena with its guard, allocations accumulating to the function's exit, __builtin_ names through the shim list, options stack") @(t : T?) {
        var text : string
        check_fixture(t, "p3_alloca", text)
        has_text(t, text, "options indenting = 4\noptions stack = 1048576\n")
        has_text(t, text, "def private p3_alloca__variable(n : int) : int \{\n    var _c_astack : uint8[65536]\n    var _c_aoff = 0")
        has_text(t, text, "if (_c_aoff + int(uint64(n)) > 65536) \{\n        panic(\"alloca past the function's 65536 byte arena\")\n    \}\n    let _t0 = reinterpret<void?>(addr(_c_astack[_c_aoff]))\n    _c_aoff += (int(uint64(n)) + 15) & ~15")
        has_text(t, text, "crt::memset(reinterpret<void?>(buf), 3, uint64(n))")
        has_text(t, text, "var slot : int? = reinterpret<int?>(_t0)")
        t |> equal(text |> find("__builtin_alloca") < 0, true, "a builtin name survived:\n{text}")
        t |> equal(text |> find("def private p3_alloca__sum_bytes(p : uint8?; n : int) : int \{\n    var s : int = 0") >= 0, true, text)
    }
}

def p4_fixtures(t : T?) {
    t |> run("bitfields: [c_bitfields] with clang's units, openers and padding, folded initializers, steps through += 1, F5's alignment") @(t : T?) {
        var text : string
        check_fixture(t, "p4_bitfields", text)
        has_text(t, text, "require c_runtime/c_bitfields")
        has_text(t, text, "[c_bitfields(_bits0 = \"uint8\", a = 3, b = 5)]\nstruct BF \{\n    a : uint\n    b : int\n    e : int16\n\}")
        has_text(t, text, "[c_bitfields(lo = 3, _0 = 2, mid = 4, _bits1 = \"uint\", hi = 6)]\nstruct Pad \{\n    lo, mid, hi : uint\n\}")
        has_text(t, text, "[c_bitfields(_bits0 = \"uint64\", a = 3, b = 5, wide = 40, flag = 1, neg = 1)]")
        has_text(t, text, "typeinfo alignof(type<BF>) == 2, \"BF: clang lays it out as size 4, align 4, its bitfield units align 2\")")
        has_text(t, text, "static_assert(typeinfo offsetof < _bits1 > (type<Pad>) == 4")
        has_text(t, text, "var private p4_bitfields__g : BF = BF(_bits0 = uint8((uint(9) & 0x7u) | ((uint(-3) & 0x1fu) << 3u)), e = int16(7))")
        has_text(t, text, "BF(_bits0 = uint8((uint(-1) & 0x1fu) << 3u))")
        has_text(t, text, "var r : BF = BF(_bits0 = uint8((uint(v) & 0x7u) | ((uint(v - 20) & 0x1fu) << 3u)), e = int16(v))")
        has_text(t, text, "Mixed(_bits0 = (uint64(uint8(6)) & 0x7ul) | ((uint64(3) & 0x1ful) << 3ul) | ((uint64(int64(-5)) & 0xfffffffffful) << 8ul))")
        has_text(t, text, "p.a += 1u\n    p.b += 1\n")
        has_text(t, text, "let _t0 = s.a\n    s.a += 1u\n")
        has_text(t, text, "m.flag = 1 != 0\n")
        has_text(t, text, "[c_bitfields(_bits0 = \"uint16\", a = 8, b = 8)]\nstruct R \{")
        has_text(t, text, "\"W: clang lays it out as size 8, align 4, its das alignment is 2\")")
        has_text(t, text, "\n\nstruct T \{\n    x, y : int\n\}")
        has_text(t, text, "Full(_bits0 = 18364758544493064720ul, _bits1 = (uint64(100) & 0x7ful) | (((1 != 0 ? 1ul : 0ul) & 0x1ul) << 7ul))")
        has_text(t, text, "f.all += 1ul\n    f.top -= 1ul\n")
        has_text(t, text, "ll.q -= 1l\n")
        has_text(t, text, "[c_bitfields(_bits0 = \"uint8\", a = 3)]\nstruct Narrow")
        has_text(t, text, "[c_bitfields(_bits0 = \"uint8\", q = 4)]\nstruct LL")
        has_text(t, text, "[c_bitfields(f = 3)]\nstruct Names \{\n    _1, _bits9 : int\n    f : uint\n\}")
        let msvc <- convert("{FIXTURES}/p4_bitfields.c", path_join(work_root, "p4_bitfields_msvc"), "msvc")
        t |> equal(msvc.ok, true, msvc.error)
        has_text(t, msvc.das_text, "[c_bitfields(a = 3, b = 5)]\nstruct BF \{")
        has_text(t, msvc.das_text, "[c_bitfields(lo = 3, _0 = 2, mid = 4, _bits1 = \"uint\", hi = 6)]\nstruct Pad \{")
        rejects(t, "bitfield_packed", "struct S \{ unsigned a : 3; char c; \};\nint main(void) \{ struct S s = \{ 1, 2 \}; return s.a + s.c; \}\n", "record `S` has bitfields and das cannot lay it out as clang does; not lowered yet")
        rejects(t, "bitfield_enum", "enum E \{ A, B \};\nstruct S \{ enum E k : 2; int n; \};\nint main(void) \{ struct S s = \{ B, 2 \}; return s.k + s.n; \}\n", "bitfield `S.k` of enum type is not lowered yet")
        rejects(t, "bitfield_opener_name", "struct S \{ unsigned _bits0 : 3; int n; \};\nint main(void) \{ struct S s = \{ 1, 2 \}; return s._bits0 + s.n; \}\n", "field `S._bits0` is spelled like a storage or padding name")
        rejects(t, "bitfield_padding_name", "struct S \{ unsigned _1 : 3; int n; \};\nint main(void) \{ struct S s = \{ 1, 2 \}; return s._1 + s.n; \}\n", "field `S._1` is spelled like a storage or padding name")
        rejects(t, "bitfield_unit_name", "struct S \{ unsigned a : 3; int _bits0; \};\nint main(void) \{ struct S s = \{ 1, 2 \}; return s.a + s._bits0; \}\n", "field `S._bits0` is spelled like a storage or padding name")
        rejects(t, "bitfield_marshal", "struct S \{ unsigned a : 3; int n; \};\nint main(void) \{ struct S s = \{ 1, 2 \}; return s.a + s.n; \}\n", "bitfields of the marshal-only record `S`", "\{\"marshal\": [\"S\"]\}\n")
        rejects(t, "bitfield_padding_only", "struct U1 \{ char a; int : 20; \};\nint main(void) \{ struct U1 u = \{ 1 \}; return u.a; \}\n", "record `U1` is not laid out naturally")
        rejects(t, "bitfield_aligned", "struct A16 \{ int a : 3; char pad[15]; \} __attribute__((aligned(16)));\nint main(void) \{ struct A16 s = \{ 1 \}; return s.a; \}\n", "record `A16` has bitfields and das cannot lay it out as clang does")
        rejects(t, "aligned_container", "struct P8 \{ int x; int y; \} __attribute__((aligned(8)));\nstruct C3 \{ char c; struct P8 p; \};\nint main(void) \{ struct C3 s = \{ 1, \{ 2, 3 \} \}; return s.p.y; \}\n", "record `P8` is not laid out naturally")
        rejects(t, "flexible_array", "struct V \{ int n; int data[]; \};\nint main(void) \{ return (int) sizeof(struct V); \}\n", "flexible array member `V.data` is not lowered yet")
    }
    t |> run("bitfields: the layout law measures each record once, so a 20-deep nest and a 12-deep F5 chain convert within 30 s (HEAD before the memo: 20 s for the plain nest alone)") @(t : T?) {
        let nest = build_string() $(var w) {
            w |> write("struct D0 \{ int k; \};\n")
            for (i in range(1, 20)) {
                w |> write("struct D{i} \{ struct D{i - 1} a; struct D{i - 1} b; int k; \};\n")
            }
            w |> write("struct L0 \{ unsigned a : 3; int b : 5; short e; \};\n")
            for (i in range(1, 12)) {
                w |> write("struct L{i} \{ struct L{i - 1} a; struct L{i - 1} b; \};\n")
            }
            w |> write("int main(void) \{ return (int) (sizeof(struct D19) > sizeof(struct L11)); \}\n")
        }
        let dir = path_join(work_root, "nest")
        mkdir(dir)
        let c_path = path_join(dir, "nest.c")
        write_file(c_path, nest)
        let started = ref_time_ticks()
        let res <- convert(c_path, path_join(dir, "out"), "linux")
        let seconds = get_time_usec(started) / 1000000
        t |> equal(res.ok, true, res.error)
        t |> equal(seconds < 30, true, "{seconds} s")
        has_text(t, res.das_text, "typeinfo alignof(type<L11>) == 2, \"L11: clang lays it out as size 8192, align 4, its das alignment is 2\")")
    }
    t |> run("_Bool: a das bool everywhere, `? 1 : 0` where C reads a number, the truth of the result on a compound store") @(t : T?) {
        var text : string
        check_fixture(t, "p4_bool", text)
        has_text(t, text, "    if (b) \{\n        x += 100\n")
        has_text(t, text, "b = (int(b ? 1 : 0) + 1) != 0\n")
        has_text(t, text, "c = (int(c ? 1 : 0) | 0) != 0\n")
        has_text(t, text, "p4_bool__take(b), p4_bool__take(x > 9), p4_bool__take(x != 0)")
        has_text(t, text, "arr[b ? 1 : 0]")
        has_text(t, text, "return int(b ? 1 : 0)\n")
        has_text(t, text, "var p : bool? = addr(b)")
        has_text(t, text, "if (!f.on) \{")
        rejects(t, "bool_step", "int main(void) \{ _Bool b = 0; b++; return b; \}\n", "a `_Bool` step (`b++`, `s.f++`) is not lowered yet")
        rejects(t, "bool_bitfield_step", "struct F \{ _Bool on : 1; \};\nint main(void) \{ struct F f = \{ 0 \}; f.on++; return f.on; \}\n", "a `_Bool` step (`b++`, `s.f++`) is not lowered yet")
    }
}
