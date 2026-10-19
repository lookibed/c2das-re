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

// a C source the converter must take: its das text, "" with a failure when it refuses
def converts(t : T?; name : string; source : string) : string {
    let dir = path_join(work_root, "converted")
    mkdir(dir)
    let c_path = path_join(dir, "{name}.c")
    write_file(c_path, source)
    let res <- convert(c_path, path_join(dir, name), "linux")
    t |> equal(res.ok, true, "{name}: {res.error}")
    return res.das_text
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
    p4_union_fixtures(t)
    p4_function_fixtures(t)
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

def p4_union_fixtures(t : T?) {
    t |> run("unions: [c_union] over one storage, members through ref operators, initializers as stores, anonymous members as `_anon<N>`") @(t : T?) {
        var text : string
        check_fixture(t, "p4_unions", text)
        has_text(t, text, "require c_runtime/c_union")
        has_text(t, text, "[c_union]\nstruct Value \{\n    gc : GCObject?\n    p : void?\n    n : double\n    i : int64\n\}")
        has_text(t, text, "[c_union]\nstruct Mix \{\n    pt : Point\n    bytes : uint8[12]\n    i : int\n\}")
        has_text(t, text, "[c_union(size = 4, align = 4)]\nstruct Wrap \{")
        has_text(t, text, "[c_union(size = 12, align = 4)]\nstruct Slots \{\n    slot : int[int(anon_26.SLOTS)]")
        has_text(t, text, "[c_union(size = 12, align = 4)]\nstruct Nested \{")
        has_text(t, text, "[c_union]\nstruct Ragged \{")
        has_text(t, text, "static_assert(typeinfo offsetof < _storage > (type<Mix>) == 0, \"Mix: every member sits at 0\")")
        has_text(t, text, "var m : Mix\n    m.pt = Point(x = 1, y = 2)\n")
        has_text(t, text, "m.i++\n")
        has_text(t, text, "p4_unions__bump(addr(m.i))")
        has_text(t, text, "var h : Half\n    p4_unions__fill(")
        has_text(t, text, "var gtags : Tagged[2] = fixed_array(Tagged(tag = 1), Tagged(tag = 2))")
        has_text(t, text, "    p4_unions__gmix.i = 16909060\n    gtags[0].m.i = 7\n    gtags[1].m.pt = Point(x = 3, y = 4)\n")
        has_text(t, text, "    pbits = unsafe(addr(p4_unions__gbits.u))\n")
        has_text(t, text, "    pbig = unsafe(addr(big[5]))\n")
        has_text(t, text, "    later = Later(p = unsafe(addr(later_target)))\n    later.u.u = uint(3)\n")
        has_text(t, text, "var t : Tagged = Tagged(tag = 5)\n    t.m.i = 9\n")
        has_text(t, text, "var arr : Mix[2] = fixed_array(Mix(), Mix())\n    arr[0].i = 1\n    arr[1].pt = Point(x = 5, y = 6)\n")
        has_text(t, text, "var o1 : Order = Order(a = _t")
        has_text(t, text, "var out : Out\n    out._c_in.s = int16(5)\n")
        has_text(t, text, "var sparse : Bits[40]\n    sparse[3].u = uint(4)\n")
        has_text(t, text, "def private p4_unions__decay_read(h_in : Half) : int \{\n    var h = h_in\n")
        has_text(t, text, "def private p4_unions__store_struct(q_in : Q) : int \{\n    var q = q_in\n")
        has_text(t, text, "def private p4_unions__step_union(h_in : Half) : int \{\n    var h = h_in\n")
        has_text(t, text, "var zero : Mix\n")
        has_text(t, text, "int(uint64(0))")
        has_text(t, text, "struct Shape \{\n    kind : int\n    _anon1 : anon_29\n    _anon2 : anon_30\n\}")
        has_text(t, text, "var sh : Shape = Shape(kind = 1, _anon2 = anon_30(w = int16(3), h = int16(4)))\n    sh._anon1.radius = 2.5lf\n")
        let msvc <- convert("{FIXTURES}/p4_unions.c", path_join(work_root, "p4_unions_msvc"), "msvc")
        t |> equal(msvc.ok, true, msvc.error)
        has_text(t, msvc.das_text, "[c_union]\nstruct Value \{")
        has_text(t, msvc.das_text, "[c_union]\nstruct Wrap \{")
        has_text(t, msvc.das_text, "static_assert(typeinfo sizeof(type<Wrap>) == 8 && typeinfo alignof(type<Wrap>) == 4")
    }
    p4_union_rejects(t)
}

def p4_union_rejects(t : T?) {
    t |> run("unions: what the union lowering refuses, each with its reason") @(t : T?) {
        rejects(t, "union_bitfield", "union B \{ unsigned a : 3; int n; \};\nint main(void) \{ union B b; b.n = 1; return b.a; \}\n", "bitfield `B.a` of the union `B` is not lowered yet")
        rejects(t, "union_aligned", "union A \{ int i; char c; \} __attribute__((aligned(16)));\nint main(void) \{ union A a; a.i = 1; return a.c; \}\n", "union `A` of size 16 and alignment 16 is not laid out naturally")
        rejects(t, "union_packed", "union __attribute__((packed)) P \{ char c; int i; \};\nint main(void) \{ union P p; p.i = 1; return p.c - 1; \}\n", "union `P` aligns to 1, below member `i`'s alignment 4; not lowered yet")
        rejects(t, "union_empty", "union E \{\};\nint main(void) \{ union E e; return (int) sizeof e; \}\n", "union `E` has no member; not lowered yet")
        rejects(t, "union_marshal", "#pragma pack(1)\ntypedef struct \{ short w; int o; \} disk_t;\n#pragma pack()\nunion DU \{ disk_t d; char c; \};\nint main(void) \{ union DU u; u.c = 0; return u.c; \}\n", "union `DU` holds the marshal-only record `disk_t`; not lowered yet", "\{ \"marshal\": [\"disk_t\"] \}\n")
        rejects(t, "union_storage_name", "union S \{ int _storage; char c; \};\nint main(void) \{ union S s; s.c = 1; return s.c; \}\n", "member `S._storage` is spelled like the storage field of `[c_union]`")
        rejects(t, "anon_name", "struct S \{ int _anon1; union \{ int i; \}; \};\nint main(void) \{ struct S s; s.i = 1; return s.i - 1; \}\n", "field `S._anon1` is spelled like the name of an anonymous member")
        rejects(t, "anon_no_name", "struct S \{ int t; struct \{ int : 4; \}; \};\nint main(void) \{ struct S s; s.t = 0; return s.t; \}\n", "anonymous member of `struct S` exposes no field name; not dumped yet")
        rejects(t, "anon_init", "union U \{ struct \{ int a; \}; int b; \};\nint main(void) \{ union U u = \{ \{ 1 \} \}; return u.a - 1; \}\n", "an initializer of an anonymous member of a union is not dumped yet")
        rejects(t, "anon_macro_two", "#define REC(n) union \{ int n; \}\n#define TWO REC(a); REC(b)\nstruct S \{ TWO; \};\nint main(void) \{ struct S s; s.a = 1; return s.a - 1; \}\n", "anonymous records from one macro expansion are not dumped yet")
        rejects(t, "anon_macro_twou", "#define TWOU union \{ int a; \} u1; union \{ int b; \} u2\nstruct S \{ TWOU; \};\nint main(void) \{ struct S s; s.u1.a = 1; s.u2.b = 2; return s.u1.a - 1; \}\n", "anonymous records from one macro expansion are not dumped yet")
        rejects(t, "zero_length", "struct Z \{ int n; char z[0]; \};\nint main(void) \{ struct Z s; s.n = 0; return s.n; \}\n", "a zero-length array (a GNU extension) is not lowered yet")
    }
}

def p4_function_fixtures(t : T?) {
    t |> run("function pointers: qsort and bsearch through c_sort, a type's `var` positions, casts as reinterpret, a union of function pointers as one storage") @(t : T?) {
        var text : string
        check_fixture(t, "p4_fnptr", text)
        has_text(t, text, "require c_runtime/c_sort\n")
        // a function type takes the `var` positions of the value-taken functions of its
        // signature, each of which declares them; a library call takes the plain type
        has_text(t, text, "def private p4_fnptr__cmp_int(var a : void?; var b : void?) : int")
        has_text(t, text, "def private p4_fnptr__cmp_desc(var a : void?; var b : void?) : int")
        has_text(t, text, "c_qsort(reinterpret<void?>(addr(arr[0])), uint64(n), uint64(typeinfo sizeof(type<int>)), reinterpret<function<(a0 : void?; a1 : void?) : int>>(@@p4_fnptr__cmp_int))")
        has_text(t, text, "reinterpret<int?>(c_bsearch(reinterpret<void?>(addr(key)), reinterpret<void?>(addr(arr[0])), uint64(n), uint64(typeinfo sizeof(type<int>)), reinterpret<function<(a0 : void?; a1 : void?) : int>>(@@p4_fnptr__cmp_int)))")
        has_text(t, text, "def private p4_fnptr__apply_to(f : function<(var a0 : Counter?) : void>; var c : Counter?) \{")
        has_text(t, text, "def private p4_fnptr__twice(v : int) : int")
        has_text(t, text, "invoke(pc.step, pc)")
        // a reading chain keeps every parameter `let`
        has_text(t, text, "def private p4_fnptr__leaf(p : int?) : int")
        has_text(t, text, "def private p4_fnptr__mid(p : int?; q : int?; c : int) : int \{\n    return p4_fnptr__leaf(c != 0 ? p : q)\n")
        has_text(t, text, "def private p4_fnptr__field(s : Holder) : int")
        // the callee copy takes a name the body leaves free
        has_text(t, text, "def private p4_fnptr__put(var p_in1 : int?; p_in : int) \{\n    var p = p_in1\n")
        has_text(t, text, "def private p4_fnptr__put_local(var q_in1 : int?) : int \{\n    var q = q_in1\n    var q_in : int = 4\n")
        has_text(t, text, "var erased : function<() : void> = reinterpret<function<() : void>>(@@p4_fnptr__add3)")
        has_text(t, text, "[c_union]\nstruct handler_t \{\n    h1 : function<(a0 : void?) : void>\n    h0 : function<() : void>\n    h2 : function<(a0 : void?; a1 : void?) : void>\n\}")
        has_text(t, text, "[c_union]\nstruct Slots \{\n    fns : function<(var a0 : Counter?) : void>[2]\n")
        has_text(t, text, "static_assert(typeinfo offsetof < run > (type<task>) == 8")
        has_text(t, text, "p4_fnptr__steps[0].action.h1 = unsafe(reinterpret<function<(a0 : void?) : void>>(@@p4_fnptr__gun_fire))")
        has_text(t, text, "invoke(p4_fnptr__steps[s].action.h2, reinterpret<void?>(addr(gn)), reinterpret<void?>(addr(fr)))")
        has_text(t, text, "un.task.run.h0 = reinterpret<function<() : void>>(uint64(-1))")
        // a zero function pointer is `default<...>`, in an array's fill and a fall-off return
        has_text(t, text, "var zeros : function<(a0 : int) : int>[3] = fixed_array(default<function<(a0 : int) : int>>, default<function<(a0 : int) : int>>, default<function<(a0 : int) : int>>)")
        has_text(t, text, "var sparse : function<(a0 : int) : int>[3] = fixed_array(default<function<(a0 : int) : int>>, default<function<(a0 : int) : int>>, @@p4_fnptr__inc)")
        has_text(t, text, "var pair2 : function<(a0 : int) : int>[2] = fixed_array(@@p4_fnptr__inc, default<function<(a0 : int) : int>>)")
        has_text(t, text, "    return default<function<(a0 : int) : int>>\n")
        // an invoke of an invoke goes through a temporary (the JIT crash)
        has_text(t, text, "let _t0 = invoke(getter, 1)")
        has_text(t, text, "invoke(_t0, 5)")
        has_text(t, text, "if (un.task.run.h0 != null)")
        // a function pointer parameter has no pointee: copied or reassigned, it stays `let`
        has_text(t, text, "def private p4_fnptr__call_copy(g : function<(a0 : int) : int>; v : int) : int")
        has_text(t, text, "def private p4_fnptr__call_default(f_in : function<(a0 : int) : int>; v : int) : int \{\n    var f = f_in\n")
    }
    t |> run("the library renames: `_longjmp` is `c_longjmp`") @(t : T?) {
        let text = converts(t, "underscore_longjmp", "#include <setjmp.h>\nstatic jmp_buf env;\nint main(void) \{ if (setjmp(env) == 0) \{ _longjmp(env, 1); \} return 0; \}\n")
        has_text(t, text, "c_longjmp(addr(")
    }
    t |> run("function pointers: what the lowering refuses, each with its reason") @(t : T?) {
        rejects(t, "external_function_value", "#include <string.h>\nint main(void) \{ int (*c)(const char *, const char *) = strcmp; return c(\"a\", \"a\"); \}\n", "the value of external function `strcmp` (a pointer to a function this file does not define) is not lowered yet")
        rejects(t, "external_function_address", "#include <string.h>\nint main(void) \{ int (*c)(const char *, const char *) = &strcmp; return c(\"a\", \"a\"); \}\n", "the value of external function `strcmp`")
        rejects(t, "variadic_function_pointer", "int main(void) \{ int (*f)(int, ...) = 0; return f == 0 ? 0 : 1; \}\n", "a pointer to a variadic function is not lowered yet")
        rejects(t, "unprototyped_call", "static int one(int v) \{ return v; \}\nint main(void) \{ int (*f)() = (int (*)()) one; return f(0); \}\n", "a call with 1 arguments through a function pointer whose type takes 0")
        let gap = "a pointer the callee writes through arrives through const parameter"
        rejects(t, "chain_direct", "static void deep(int *p) \{ *p = 1; \}\nstatic void leaf(int *p) \{ deep(p); \}\nint main(void) \{ int x = 0; leaf(&x); return x - 1; \}\n", "{gap} `p` of `leaf`")
        rejects(t, "chain_ternary", "static void deep(int *p) \{ *p = 1; \}\nstatic void mid(int *p, int *q, int c) \{ deep(c ? p : q); \}\nint main(void) \{ int x = 0; mid(&x, &x, 1); return x - 1; \}\n", "{gap} `p` of `mid`")
        rejects(t, "chain_field", "struct S \{ int *p; \};\nstatic void deep(int *p) \{ *p = 1; \}\nstatic void field(struct S s) \{ deep(s.p); \}\nint main(void) \{ int x = 0; struct S s = \{ &x \}; field(s); return x - 1; \}\n", "{gap} `s` of `field`")
        rejects(t, "chain_arithmetic", "static void w(int *p) \{ *p = 1; \}\nstatic void f(int *p) \{ w(p + 1); \}\nint main(void) \{ int a[2] = \{ 0, 0 \}; f(a); return a[1] - 1; \}\n", "{gap} `p` of `f`")
        rejects(t, "chain_deref", "static void w(int *p) \{ *p = 1; \}\nstatic void f(int **pp) \{ w(*pp); \}\nint main(void) \{ int x = 0; int *p = &x; f(&p); return x - 1; \}\n", "{gap} `pp` of `f`")
        rejects(t, "chain_index", "static void w(int *p) \{ *p = 1; \}\nstatic void f(int **pp) \{ w(pp[0]); \}\nint main(void) \{ int x = 0; int *p = &x; f(&p); return x - 1; \}\n", "{gap} `pp` of `f`")
        rejects(t, "chain_arrow", "struct S \{ int *q; \};\nstatic void w(int *p) \{ *p = 1; \}\nstatic void f(struct S *sp) \{ w(sp->q); \}\nint main(void) \{ int x = 0; struct S s = \{ &x \}; f(&s); return x - 1; \}\n", "{gap} `sp` of `f`")
        rejects(t, "chain_invoke", "static void deep(int *p) \{ *p = 1; \}\nstatic void (*sink)(int *) = deep;\nstatic void leaf(int *p) \{ sink(p); \}\nint main(void) \{ int x = 0; leaf(&x); return x - 1; \}\n", "{gap} `p` of `leaf`")
    }
    t |> run("the dumper's libclang pass: a clang reporting no resource directory, and an error libclang meets") @(t : T?) {
        var fake_out : string
        let no_resources <- convert("{FIXTURES}/ret42.c", path_join(work_root, "no_resources"), "linux", "/bin/false")
        t |> equal(no_resources.ok, false, no_resources.das_text)
        t |> equal(no_resources.error |> find("-print-resource-dir` gave no resource directory") >= 0, true, no_resources.error)
        // a clang that prints a path but fails is no resource directory either
        let fake = path_join(work_root, "fake_clang.sh")
        write_file(fake, "#!/bin/sh\necho /usr\nexit 3\n")
        let mode = run_and_capture(["chmod", "+x", fake], fake_out, 10.0)
        t |> equal(mode, 0, fake_out)
        let failing <- convert("{FIXTURES}/ret42.c", path_join(work_root, "fake_resources"), "linux", fake)
        t |> equal(failing.error |> find("-print-resource-dir` gave no resource directory") >= 0, true, failing.error)
        rejects(t, "libclang_error", "#include \"c2das_no_such_header.h\"\nint main(void) \{ return 0; \}\n", "libclang: ")
    }
    t |> run("a wide string literal fails closed") @(t : T?) {
        rejects(t, "wide_literal", "int main(void) \{ const int *w = (const int *) L\"ab\"; return w[1] == 98 ? 0 : 1; \}\n", "a wide string literal")
    }
}
