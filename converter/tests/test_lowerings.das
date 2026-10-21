options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require daslib/fio
require ../pipeline.das
require ../tiers.das
require ../dumper_a.das

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
    let run = native_run(default_clang(), ["-w", CLANG_DIALECT], "{FIXTURES}/{name}.c", path_join(work_root, "{name}_native"), 60.0)
    return run.built ? Expectation(rc = run.rc, out = run.output) : Expectation(rc = -1, out = "clang failed:\n{run.output}")
}

// `param_writes` is the converter's `--param-writes`, "" for its default
def converted(t : T?; name : string; var das_text : string&; param_writes : string = "") : Expectation {
    let work = path_join(work_root, empty(param_writes) ? name : "{name}_{param_writes}")
    let res <- convert("{FIXTURES}/{name}.c", work, "linux", "", "", param_writes)
    if (!res.ok) {
        t |> failure(res.error)
        return Expectation(rc = -2, out = "")
    }
    das_text = res.das_text
    var out : string
    let rc = run_tier(res.das_path, "interp", work, out, CONVERTED_MODULES)
    return Expectation(rc = rc, out = out)
}

// a substring the converted text must carry, reported by the needle when it is missing
def has_text(t : T?; text : string; needle : string) {
    t |> equal(text |> find(needle) >= 0, true, "missing `{needle}` in:\n{text}")
}


// `source` written as `<dir>/<name>.c` under the work root, and `sidecar`, when given, as the
// `.c2das` beside it: the C file's path
def written_source(dir, name, source, sidecar : string) : string {
    let at = path_join(work_root, dir)
    mkdir(at)
    let c_path = path_join(at, "{name}.c")
    fwrite(c_path, source)
    if (!empty(sidecar)) {
        fwrite(path_join(at, "{name}.c2das"), sidecar)
    }
    return c_path
}

// a C source the converter must refuse, with the error naming the construct; `sidecar` is
// the `.c2das` text beside it, when the shape needs one, and `param_writes` the converter's
// `--param-writes`
def rejects(t : T?; name : string; source : string; needle : string; sidecar : string = ""; param_writes : string = "") {
    let dir = path_join(work_root, "rejected")
    let c_path = written_source("rejected", name, source, sidecar)
    let res <- convert(c_path, path_join(dir, name), "linux", "", "", param_writes)
    t |> equal(res.ok, false, "{name} converted:\n{res.das_text}")
    t |> equal(res.error |> find(needle) >= 0, true, "{name}: `{needle}` not in `{res.error}`")
}


// a C source the converter must take: its das text, "" with a failure when it refuses;
// `sidecar` and `param_writes` as for `rejects`
def converts(t : T?; name : string; source : string; sidecar : string = ""; param_writes : string = "") : string {
    let dir = path_join(work_root, "converted")
    let c_path = written_source("converted", name, source, sidecar)
    let res <- convert(c_path, path_join(dir, name), "linux", "", "", param_writes)
    t |> equal(res.ok, true, "{name}: {res.error}")
    return res.das_text
}

def check_fixture(t : T?; name : string; var das_text : string&; param_writes : string = "") {
    let want = native(name)
    t |> equal(want.rc >= 0, true, want.out)
    let have = converted(t, name, das_text, param_writes)
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
    t |> run("functions: written parameters in place, statics, globals, exit") @(t : T?) {
        var text : string
        check_fixture(t, "p1_functions", text)
        has_text(t, text, "def twice(var v : int) : int \{\n    v = v * 2\n")
        t |> equal(text |> find("def private p1_functions__bump(") >= 0, true, text)
        t |> equal(text |> find("c_exit(42)") >= 0, true, text)
        t |> equal(text |> find("require c_runtime/c_exit") >= 0, true, text)
    }
    p2_fixtures(t)
    p4_csmith_fixtures(t)
    p4_csmith_more_fixtures(t)
    p4_scope_fidelity_fixtures(t)
    p4_matrix_fixtures(t)
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
        t |> equal(text |> find("var ptrs : int? [2] = fixed_array<int?>(unsafe(addr(full[1])), null)") >= 0, true, text)
        t |> equal(text |> find("var row : int[3]? = addr(m[1])") >= 0, true, text)
        t |> equal(text |> find("deref(row)[2]") >= 0, true, text)
        // an address that may be one past the end is the decayed array plus the checked index (F45)
        has_text(t, text, "addr(full[0]) + 3")
        has_text(t, text, "addr(local[1]), addr(local[0]) + end_index(n, 4)")
        has_text(t, text, "require c_runtime/c_bounds")
        // in a global initializer the decay and the sum each take their own unsafe (F48)
        has_text(t, text, "var gend : int? = unsafe(unsafe(addr(full[0])) + 3)")
        has_text(t, text, "var ends : int? [2] = fixed_array<int?>(unsafe(addr(full[0])), unsafe(unsafe(addr(full[0])) + 3))")
        has_text(t, text, "addr(m[1][0]) + 3")
        has_text(t, text, "int64(addr(m[0]) + 2 - addr(m[0]))")
        t |> equal(text |> find("m[0][i] *= 2") >= 0, true, text)
        t |> equal(text |> find("total(addr(full[0]), 3)") >= 0, true, text)
    }
    t |> run("pointers: the blit shape, function values and invoke, pointer differences, the CRT memory functions, [c_function] only where unsafe") @(t : T?) {
        var text : string
        check_fixture(t, "p2_pointers", text)
        t |> equal(text |> find("def private p2_pointers__blit(var src : uint8?; var dst : uint8?; var n : int)") >= 0, true, text)
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
    p4_bitfield_rejects(t)
    p4_union_fixtures(t)
    p4_layout_leftovers(t)
    p4_function_fixtures(t)
    p4_pointer_policy_fixtures(t)
    p4_varargs_fixtures(t)
    p4_param_writes_fixtures(t)
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
        // a packed record holding a pointer is a `var` record parameter of its writer (F3)
        has_text(t, text, "def write_pref_t(bytes : uint8?; ofs : int; var v : pref_t)")
        has_text(t, text, "def write_pref_t_p(bytes : uint8?; ofs : int; var v : int?)")
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
        has_text(t, text, "options indenting = 4\noptions stack = 8388608\n")
        has_text(t, text, "def private p3_alloca__variable(n : int) : int \{\n    var _c_astack : uint8[65536]\n    var _c_aoff = 0")
        has_text(t, text, "if (_c_aoff + int(uint64(n)) > 65536) \{\n        panic(\"alloca past the function's 65536 byte arena\")\n    \}\n    var _t0 = reinterpret<void?>(addr(_c_astack[_c_aoff]))\n    _c_aoff += (int(uint64(n)) + 15) & ~15")
        has_text(t, text, "crt::memset(reinterpret<void?>(buf), 3, uint64(n))")
        has_text(t, text, "var slot : int? = reinterpret<int?>(_t0)")
        t |> equal(text |> find("__builtin_alloca") < 0, true, "a builtin name survived:\n{text}")
        t |> equal(text |> find("def private p3_alloca__sum_bytes(var p : uint8?; n : int) : int \{\n    var s : int = 0") >= 0, true, text)
    }
}

def p4_fixtures(t : T?) {
    t |> run("bitfields: [c_bitfields] with clang's units, openers and padding, folded initializers, steps and compound stores spelled `x = x + 1`, F5's alignment") @(t : T?) {
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
        has_text(t, text, "p.a = p.a + 1u\n    p.b = p.b + 1\n")
        has_text(t, text, "let _t0 = s.a\n    s.a = s.a + 1u\n")
        has_text(t, text, "m.flag = 1 != 0\n")
        has_text(t, text, "[c_bitfields(_bits0 = \"uint16\", a = 8, b = 8)]\nstruct R \{")
        has_text(t, text, "\"W: clang lays it out as size 8, align 4, its das alignment is 2\")")
        has_text(t, text, "\n\nstruct T \{\n    x, y : int\n\}")
        has_text(t, text, "Full(_bits0 = 18364758544493064720ul, _bits1 = (uint64(100) & 0x7ful) | (((1 != 0 ? 1ul : 0ul) & 0x1ul) << 7ul))")
        has_text(t, text, "f.all = f.all + 1ul\n    f.top = f.top - 1ul\n")
        has_text(t, text, "ll.q = ll.q - 1l\n")
        has_text(t, text, "h.bf.b = h.bf.b + 3\n")
        has_text(t, text, "p.hi = p.hi << 1u\n")
        has_text(t, text, "[c_bitfields(_bits0 = \"uint8\", a = 3)]\nstruct Narrow")
        has_text(t, text, "[c_bitfields(_bits0 = \"uint8\", q = 4)]\nstruct LL")
        has_text(t, text, "[c_bitfields(f = 3)]\nstruct Names \{\n    _1, _bits9 : int\n    f : uint\n\}")
        t |> equal(text |> find("_pad") < 0 && text |> find("\"uint8[") < 0, true, "naturally aligned units place every record here, with no padding field and no byte unit:\n{text}")
        has_text(t, text, "struct W \{\n    x : uint8[3]\n    r : R\n\}")
        let msvc <- convert("{FIXTURES}/p4_bitfields.c", path_join(work_root, "p4_bitfields_msvc"), "msvc")
        t |> equal(msvc.ok, true, msvc.error)
        has_text(t, msvc.das_text, "[c_bitfields(a = 3, b = 5)]\nstruct BF \{")
        has_text(t, msvc.das_text, "[c_bitfields(lo = 3, _0 = 2, mid = 4, _bits1 = \"uint\", hi = 6)]\nstruct Pad \{")
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
        fwrite(c_path, nest)
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

def p4_bitfield_rejects(t : T?) {
    t |> run("bitfields: what the lowering refuses, each with its reason") @(t : T?) {
        rejects(t, "bitfield_enum", "enum E \{ A, B \};\nstruct S \{ enum E k : 2; int n; \};\nint main(void) \{ struct S s = \{ B, 2 \}; return s.k + s.n; \}\n", "bitfield `S.k` of enum type is not lowered yet")
        rejects(t, "bitfield_opener_name", "struct S \{ unsigned _bits0 : 3; int n; \};\nint main(void) \{ struct S s = \{ 1, 2 \}; return s._bits0 + s.n; \}\n", "field `S._bits0` is spelled like a storage or padding name")
        rejects(t, "bitfield_padding_name", "struct S \{ unsigned _1 : 3; int n; \};\nint main(void) \{ struct S s = \{ 1, 2 \}; return s._1 + s.n; \}\n", "field `S._1` is spelled like a storage or padding name")
        rejects(t, "bitfield_unit_name", "struct S \{ unsigned a : 3; int _bits0; \};\nint main(void) \{ struct S s = \{ 1, 2 \}; return s.a + s._bits0; \}\n", "field `S._bits0` is spelled like a storage or padding name")
        rejects(t, "bitfield_marshal", "struct S \{ unsigned a : 3; int n; \};\nint main(void) \{ struct S s = \{ 1, 2 \}; return s.a + s.n; \}\n", "bitfields of the marshal-only record `S`", "\{\"marshal\": [\"S\"]\}\n")
        rejects(t, "bitfield_aligned", "struct A16 \{ int a : 3; char pad[15]; \} __attribute__((aligned(16)));\nint main(void) \{ struct A16 s = \{ 1 \}; return s.a; \}\n", "record `A16` has an alignment attribute das cannot spell: clang aligns it to 16, its members to 4; not lowered yet")
        rejects(t, "unnamed_aligned4", "struct __attribute__((aligned(4))) A \{ char a; int : 20; \};\nint main(void) \{ struct A s = \{ 1 \}; return s.a - 1; \}\n", "record `A` has an alignment attribute das cannot spell: clang aligns it to 4, its members to 1; not lowered yet")
        rejects(t, "unnamed_aligned8", "struct __attribute__((aligned(8))) A \{ char a; int : 20; \};\nint main(void) \{ struct A s = \{ 1 \}; return s.a - 1; \}\n", "record `A` has an alignment attribute das cannot spell: clang aligns it to 8, its members to 1; not lowered yet")
        rejects(t, "f5_holder_aligned", "struct N \{ char a; unsigned b : 20; \};\nstruct __attribute__((aligned(8))) H \{ char c; struct N n; \};\nint main(void) \{ struct H h = \{ 1, \{ 2, 3 \} \}; return h.n.b - 3; \}\n", "record `H` has an alignment attribute das cannot spell: clang aligns it to 8, its members to 4; not lowered yet")
        rejects(t, "unnamed_marshal", "struct __attribute__((aligned(16))) S \{ char a; long long : 20; \};\nint main(void) \{ struct S v; v.a = 7; return v.a - 7; \}\n", "bitfields of the marshal-only record `S` are not lowered yet", "\{\"marshal\": [\"S\"]\}\n")
        rejects(t, "packed_int_first", "struct __attribute__((packed)) P \{ int n; unsigned a : 3; \};\nint main(void) \{ struct P s = \{ 1, 2 \}; return s.a + s.n; \}\n", "record `P` has bitfields and das cannot lay it out as clang does; not lowered yet")
        rejects(t, "pack1_int_at_2", "#pragma pack(1)\nstruct P \{ unsigned a : 3; char c; int x; \};\n#pragma pack()\nint main(void) \{ struct P s = \{ 1, 2, 3 \}; return s.a + s.x; \}\n", "record `P` has bitfields and das cannot lay it out as clang does; not lowered yet")
        rejects(t, "packed_nine_bytes", "struct __attribute__((packed)) P \{ char c; unsigned x : 7; unsigned long long a : 60; \};\nint main(void) \{ struct P s = \{ 1, 2, 3 \}; return (int) s.a + s.c; \}\n", "record `P` has bitfields and das cannot lay it out as clang does; not lowered yet")
        let msvc <- convert(path_join(work_root, "rejected/packed_int_first.c"), path_join(work_root, "rejected/packed_int_first_msvc"), "msvc")
        t |> equal(msvc.ok, false, msvc.das_text)
        t |> equal(msvc.error |> find("record `P` has bitfields and das cannot lay it out as clang does") >= 0, true, msvc.error)
        rejects(t, "bitfield_packed_attribute", "struct __attribute__((packed)) P \{ char c; int n; unsigned a : 3; \};\nint main(void) \{ struct P s = \{ 1, 2, 3 \}; return s.a + s.c; \}\n", "record `P` has bitfields and das cannot lay it out as clang does; not lowered yet")
        rejects(t, "aligned_container", "struct P8 \{ int x; int y; \} __attribute__((aligned(8)));\nstruct C3 \{ char c; struct P8 p; \};\nint main(void) \{ struct C3 s = \{ 1, \{ 2, 3 \} \}; return s.p.y; \}\n", "record `P8` is not laid out naturally")
        rejects(t, "flexible_array", "struct V \{ int n; int data[]; \};\nint main(void) \{ return (int) sizeof(struct V); \}\n", "flexible array member `V.data` is not lowered yet")
    }
}

def p4_layout_leftovers(t : T?) {
    t |> run("a union's bitfield member is a property pair; byte units and padding fields reproduce clang where no naturally aligned unit does") @(t : T?) {
        var text : string
        check_fixture(t, "p4_layout_leftovers", text)
        has_text(t, text, "[c_union(f0 = 8)]\nstruct Pun \{\n    f0 : int\n    f1 : uint\n\}")
        has_text(t, text, "[c_union(f = 5)]\nstruct Wide \{")
        has_text(t, text, "[c_union(size = 2, align = 1)]\nstruct Gap \{\n    c : uint8\n\}")
        has_text(t, text, "[c_union]\nstruct Zero \{\n    a : int16\n    b, c : int\n\}")
        has_text(t, text, "[c_bitfields(f0 = 16, f1 = 14, _bits1 = \"uint8[2]\", f3 = 12, _bits2 = \"uint\", f5 = 19, _bits3 = \"uint\", f6 = 30, _bits4 = \"uint\", f7 = 27)]\nstruct Cramped \{")
        has_text(t, text, "[c_bitfields(_bits0 = \"uint8[3]\", f0 = 24, _bits1 = \"uint\", f2 = 20)]\nstruct Lead3 \{")
        has_text(t, text, "[c_bitfields(_bits0 = \"uint8[5]\", x = 40)]\nstruct Five \{\n    c : uint8\n    x : uint64\n    _pad0 : uint8[2]\n\}")
        has_text(t, text, "struct Tail3 \{\n    f0 : uint\n    f1 : int16\n    f2, f3, f4 : uint\n")
        has_text(t, text, "struct HoldBF \{\n    bf : BF\n    y : int16\n    _pad0 : uint8[2]\n\}")
        has_text(t, text, "struct CharBF \{\n    c : uint8\n    _pad0 : uint8[3]\n    bf : BF\n\}")
        has_text(t, text, "struct OnlyPad \{\n    a : uint8\n    _pad0 : uint8[3]\n\}")
        has_text(t, text, "_bits1 = c_unit_bytes(uint(4000) & 0xfffu, default<uint8[2]>)")
        has_text(t, text, "typeinfo alignof(type<HoldBF>) == 2, \"HoldBF: clang lays it out as size 8, align 4, its das alignment is 2\")")
        has_text(t, text, "typeinfo alignof(type<Narrow>) == 1, \"Narrow: clang lays it out as size 4, align 4, its bitfield units align 1\")")
        has_text(t, text, "static_assert(typeinfo offsetof < _bits1 > (type<Cramped>) == 5")
        has_text(t, text, "    p4_layout_leftovers__gpun.f0 = -3\n")
        has_text(t, text, "a.f0 = a.f0 + 1\n    a.f0 = a.f0 + 3\n    a.f0 = a.f0 - 1\n")
        has_text(t, text, "pin.u.f0 = pin.u.f0 - 1\n")
        has_text(t, text, "deref(p + 2).bf.a = deref(p + 2).bf.a + 1u\n")
        has_text(t, text, "deref(p + 2).u.s = deref(p + 2).u.s + 1u\n")
        has_text(t, text, "deref(p + 2).bf.b = deref(p + 2).bf.b + 3\n")
        has_text(t, text, "deref(p + 1).u.s = deref(p + 1).u.s | 2\n")
        has_text(t, text, "[c_bitfields(_bits0 = \"uint8[6]\", a = 3, b = 40)]\nstruct WideJoin \{")
        has_text(t, text, "[c_bitfields(_bits0 = \"uint8[3]\", a = 12, b = 12, _bits1 = \"uint\", d = 7, e = 20)]\nstruct SplitJoin \{")
        has_text(t, text, "[c_bitfields(_bits0 = \"uint8[2]\", a = 9)]\nstruct ZeroSkip \{\n    c : uint8\n    a : uint\n    _pad0 : uint8[1]\n    d : uint8\n    _pad1 : uint8[3]\n\}")
        has_text(t, text, "struct ZeroTail \{\n    p0 : int16\n    _pad0 : uint8[2]\n\}")
        has_text(t, text, "[c_bitfields(a = 3)]\nstruct FloorUnit \{\n    c : uint8\n    _pad0 : uint8[7]\n    a : uint\n\}")
        has_text(t, text, "[c_bitfields(_bits0 = \"uint8[8]\", a = 64)]\nstruct Wide64 \{")
        has_text(t, text, "[c_bitfields(_bits0 = \"uint8\", a = 3, _bits1 = \"uint8[3]\", b = 20)]\nstruct PackedBits \{")
        has_text(t, text, "[c_union(f = 5, size = 1, align = 1)]\nstruct PackedUnion \{")
        has_text(t, text, "[c_union(b = 1)]\nstruct Flag \{")
        has_text(t, text, "struct PadName \{\n    _pad0, x : int\n\}")
        let msvc <- convert("{FIXTURES}/p4_layout_leftovers.c", path_join(work_root, "p4_layout_leftovers_msvc"), "msvc")
        t |> equal(msvc.ok, true, msvc.error)
        has_text(t, msvc.das_text, "[c_union(f0 = 2, size = 4, align = 1)]\nstruct Only \{")
        has_text(t, msvc.das_text, "struct OnlyPad \{\n    a : uint8\n    _pad0 : uint8[7]\n\}")
        has_text(t, msvc.das_text, "[c_union(f = 5, size = 8, align = 1)]\nstruct Wide \{")
        has_text(t, msvc.das_text, "[c_union(f0 = 8)]\nstruct Pun \{")
        has_text(t, msvc.das_text, "[c_bitfields(a = 9)]\nstruct ZeroAfterBits \{\n    c : uint8\n    a : uint\n    d : uint8\n    _pad0 : uint8[7]\n\}")
        has_text(t, msvc.das_text, "typeinfo alignof(type<ZeroAfterBits>) == 4, \"ZeroAfterBits: clang lays it out as size 16, align 8, its bitfield units align 4\")")
        has_text(t, msvc.das_text, "[c_bitfields(x = 3)]\nstruct ZeroAfterPlain \{\n    x, y, d : uint8\n\}")
        rejects(t, "pad_name", "struct S \{ char _pad0; struct \{ unsigned a : 3; int b : 5; short e; \} bf; short y; \};\nint main(void) \{ struct S s = \{ 1 \}; return s._pad0 - 1; \}\n", "field `S._pad0` is spelled like a padding field")
    }
}

def p4_union_rejects(t : T?) {
    t |> run("unions: what the union lowering refuses, each with its reason") @(t : T?) {
        rejects(t, "union_bitfield_enum", "enum E \{ A, B \};\nunion U \{ enum E k : 2; int n; \};\nint main(void) \{ union U u; u.n = 1; return u.k; \}\n", "bitfield `U.k` of enum type is not lowered yet")
        rejects(t, "union_bitfield_align", "union U \{ unsigned align : 3; int n; \};\nint main(void) \{ union U u; u.n = 1; return u.align; \}\n", "bitfield `U.align` is spelled like an argument of `[c_union]`")
        rejects(t, "union_unnamed_only", "union U \{ int : 4; \};\nint main(void) \{ union U u; return (int) sizeof u - 1; \}\n", "union `U` has no member; not lowered yet")
        rejects(t, "union_bitfield_size", "union U \{ unsigned size : 3; int n; \};\nint main(void) \{ union U u; u.n = 1; return u.size; \}\n", "bitfield `U.size` is spelled like an argument of `[c_union]`")
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
        // every data pointer position of a function type is `var`, c_sort's comparator's too
        has_text(t, text, "def private p4_fnptr__cmp_int(var a : void?; var b : void?) : int")
        has_text(t, text, "def private p4_fnptr__cmp_desc(var a : void?; var b : void?) : int")
        has_text(t, text, "c_qsort(reinterpret<void?>(addr(arr[0])), uint64(n), uint64(typeinfo sizeof(type<int>)), @@p4_fnptr__cmp_int)")
        has_text(t, text, "reinterpret<int?>(c_bsearch(reinterpret<void?>(addr(key)), reinterpret<void?>(addr(arr[0])), uint64(n), uint64(typeinfo sizeof(type<int>)), @@p4_fnptr__cmp_int))")
        has_text(t, text, "def private p4_fnptr__apply_to(f : function<(var a0 : Counter?) : void>; var c : Counter?) \{")
        has_text(t, text, "def private p4_fnptr__twice(v : int) : int")
        has_text(t, text, "invoke(pc.step, pc)")
        // a reading chain passes `var` pointers on; a record parameter is copied on entry
        has_text(t, text, "def private p4_fnptr__leaf(var p : int?) : int")
        has_text(t, text, "def private p4_fnptr__mid(var p : int?; var q : int?; c : int) : int \{\n    return p4_fnptr__leaf(c != 0 ? p : q)\n")
        has_text(t, text, "def private p4_fnptr__field(var s_in : Holder) : int \{\n    var s = s_in\n")
        // a stepped pointer parameter is written in place, whatever names the body spells
        has_text(t, text, "def private p4_fnptr__put(var p : int?; p_in : int) \{\n    var _t0 = p\n")
        has_text(t, text, "def private p4_fnptr__put_local(var q : int?) : int \{\n    var q_in : int = 4\n")
        has_text(t, text, "var erased : function<() : void> = reinterpret<function<() : void>>(@@p4_fnptr__add3)")
        has_text(t, text, "[c_union]\nstruct handler_t \{\n    h1 : function<(var a0 : void?) : void>\n    h0 : function<() : void>\n    h2 : function<(var a0 : void?; var a1 : void?) : void>\n\}")
        has_text(t, text, "[c_union]\nstruct Slots \{\n    fns : function<(var a0 : Counter?) : void>[2]\n")
        has_text(t, text, "static_assert(typeinfo offsetof < run > (type<task>) == 8")
        has_text(t, text, "p4_fnptr__steps[0].action.h1 = unsafe(reinterpret<function<(var a0 : void?) : void>>(@@p4_fnptr__gun_fire))")
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
        // a function pointer parameter has no pointee: copied it stays `let`, reassigned it is
        // `var` in place
        has_text(t, text, "def private p4_fnptr__call_copy(g : function<(a0 : int) : int>; v : int) : int")
        has_text(t, text, "def private p4_fnptr__call_default(var f : function<(a0 : int) : int>; v : int) : int \{\n    if (!(f != null)) \{\n")
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
    }
    t |> run("the dumper's libclang pass: a clang reporting no resource directory, and an error libclang meets") @(t : T?) {
        var fake_out : string
        let no_resources <- convert("{FIXTURES}/ret42.c", path_join(work_root, "no_resources"), "linux", "/bin/false")
        t |> equal(no_resources.ok, false, no_resources.das_text)
        t |> equal(no_resources.error |> find("-print-resource-dir` gave no resource directory") >= 0, true, no_resources.error)
        // a clang that prints a path but fails is no resource directory either
        let fake = path_join(work_root, "fake_clang.sh")
        fwrite(fake, "#!/bin/sh\necho /usr\nexit 3\n")
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

def p4_pointer_policy_fixtures(t : T?) {
    t |> run("pointer constness: every data pointer and pointer-holding record parameter is `var`, every record parameter copied on entry") @(t : T?) {
        var text : string
        check_fixture(t, "p4_pointer_policy", text)
        // a pointer the function only reads is `var` and passes on to one that writes through it
        has_text(t, text, "def private p4_pointer_policy__chain(var p : int?) \{\n    p4_pointer_policy__deep(p)\n")
        has_text(t, text, "def private p4_pointer_policy__ident(var p : int?) : int? \{\n    return p\n")
        has_text(t, text, "def private p4_pointer_policy__through(var pp : int ??)")
        has_text(t, text, "def private p4_pointer_policy__arrow(var hp : H?)")
        has_text(t, text, "var private p4_pointer_policy__sink : function<(var a0 : int?) : void> = @@p4_pointer_policy__deep")
        // a record holding a pointer is `var`, one holding none `let`, and both are copied
        has_text(t, text, "def private p4_pointer_policy__fld(var s_in : S) : int? \{\n    var s = s_in\n    return s.p\n")
        has_text(t, text, "def private p4_pointer_policy__alias_plain(s_in : P; var q : P?) : int \{\n    var s = s_in\n")
        has_text(t, text, "var private p4_pointer_policy__rec_sink : function<(var a0 : S) : void> = @@p4_pointer_policy__bump_rec")
        // a record holding a pointer in an array field or a nested record is `var`, and the
        // copy's parameter takes a name the body leaves free
        has_text(t, text, "def private p4_pointer_policy__arr_field(var a_in : A) : int")
        has_text(t, text, "def private p4_pointer_policy__nested(var n_in : N) : int")
        has_text(t, text, "def private p4_pointer_policy__renamed(var s_in1 : S; s_in : int) : int \{\n    var s = s_in1\n")
        // a cast between function pointer types that spell one das type is the value itself
        has_text(t, text, "var same : function<(var a0 : int?) : int> = @@p4_pointer_policy__read_const\n")
        has_text(t, text, "var other : function<(var a0 : uint8?) : int> = reinterpret<function<(var a0 : uint8?) : int>>(@@p4_pointer_policy__read_const)")
        // a hoisted temporary holding a pointer is `var`
        has_text(t, text, "var _t0 = p4_pointer_policy__next_pick(addr(a[0]))")
        has_text(t, text, "var _t2 = reinterpret<void?>(addr(_c_astack[_c_aoff]))")
    }
}

def p4_param_writes_fixtures(t : T?) {
    t |> run("parameter writes: in place by default, a local copy under --param-writes copy, the same output both ways") @(t : T?) {
        var text, copied : string
        check_fixture(t, "p4_param_writes", text)
        check_fixture(t, "p4_param_writes", copied, "in-place")
        t |> equal(copied, text)
        check_fixture(t, "p4_param_writes", copied, "copy")
        // in place: the written scalar or pointer parameter is `var`, no copy opens the body
        has_text(t, text, "def private p4_param_writes__count_down(var n : int) : int \{\n    var steps : int = 0\n")
        has_text(t, text, "def private p4_param_writes__reassigned(var q : int?; k : int) : int \{\n    q = q + k\n")
        has_text(t, text, "def private p4_param_writes__through_address(var x : int) : int \{\n    p4_param_writes__set_to(addr(x), x * 3)\n")
        has_text(t, text, "def private p4_param_writes__shadowed(v_in : int; var v : int) : int \{\n    var pv : int? = addr(v)\n")
        t |> equal(count(text, "_in1"), 0)
        // copy: the parameter keeps its own mode under a free name, a scalar `let`, a pointer
        // `var` (F3), and the body opens with its `var` copy
        has_text(t, copied, "def private p4_param_writes__count_down(n_in : int) : int \{\n    var n = n_in\n    var steps : int = 0\n")
        has_text(t, copied, "def private p4_param_writes__sum_walk(var p_in : int?; n : int) : int \{\n    var p = p_in\n")
        has_text(t, copied, "def private p4_param_writes__reassigned(var q_in : int?; k : int) : int \{\n    var q = q_in\n    q = q + k\n")
        has_text(t, copied, "def private p4_param_writes__through_address(x_in : int) : int \{\n    var x = x_in\n    p4_param_writes__set_to(addr(x), x * 3)\n")
        has_text(t, copied, "def private p4_param_writes__apply(fn : function<(a0 : int) : int>; v_in : int) : int \{\n    var v = v_in\n")
        has_text(t, copied, "def private p4_param_writes__shadowed(v_in : int; v_in1 : int) : int \{\n    var v = v_in1\n")
        // a parameter only read and the record copy are the same in both modes
        has_text(t, copied, "def private p4_param_writes__read_at(var q : int?) : int \{\n    return deref(q)\n")
        has_text(t, text, "def private p4_param_writes__record_param(var h_in : holder) : int \{\n    var h = h_in\n")
        has_text(t, copied, "def private p4_param_writes__record_param(var h_in : holder) : int \{\n    var h = h_in\n")
        has_text(t, copied, "def private p4_param_writes__aliased(var a_in : holder; var b : holder?) : int \{\n    var a = a_in\n")
        // a `va_list` parameter is the caller's cursor, in place in both modes
        var va_text : string
        check_fixture(t, "p4_varargs", va_text, "copy")
        has_text(t, va_text, "def private p4_varargs__take_two(var ap : CVaCursor) : int")
    }
    t |> run("parameter writes: the sidecar's `param_writes`, refused when it is not a mode, and the converter's option over it") @(t : T?) {
        let source = "static int dec(int n) \{ n--; return n; \}\nint main(void) \{ return dec(1); \}\n"
        rejects(t, "param_writes_bad", source, "`param_writes` is \"in-place\" or \"copy\", not \"local\"", "\{\"param_writes\": \"local\"\}\n")
        rejects(t, "param_writes_number", source, "`param_writes` is \"in-place\" or \"copy\", not 1", "\{\"param_writes\": 1\}\n")
        rejects(t, "param_writes_option", source, "--param-writes is in-place or copy, not `local`", "", "local")
        // a sidecar holding no `marshal` key is taken
        let by_sidecar = converts(t, "param_writes_copy", source, "\{\"param_writes\": \"copy\"\}\n")
        has_text(t, by_sidecar, "def private param_writes_copy__dec(n_in : int) : int \{\n    var n = n_in\n")
        let in_place = converts(t, "param_writes_in_place", source, "\{\"param_writes\": \"in-place\"\}\n")
        has_text(t, in_place, "def private param_writes_in_place__dec(var n : int) : int \{\n")
        // the option wins over the sidecar, both ways
        let over_copy = converts(t, "param_writes_over_copy", source, "\{\"param_writes\": \"copy\"\}\n", "in-place")
        has_text(t, over_copy, "def private param_writes_over_copy__dec(var n : int) : int \{\n")
        let over_in_place = converts(t, "param_writes_over_in_place", source, "\{\"param_writes\": \"in-place\"\}\n", "copy")
        has_text(t, over_in_place, "def private param_writes_over_in_place__dec(n_in : int) : int \{\n    var n = n_in\n")
    }
}

def p4_varargs_fixtures(t : T?) {
    t |> run("varargs: [variadic] definitions, the va_list cursor, va_copy, forwarding to the printf family, sscanf") @(t : T?) {
        var text : string
        check_fixture(t, "p4_varargs", text)
        has_text(t, text, "require c_runtime/variadic\n")
        has_text(t, text, "require c_runtime/scanf\n")
        has_text(t, text, "[variadic]\ndef sum(var n : int; va : va_args) : double \{")
        has_text(t, text, "[c_function, variadic]\ndef private p4_varargs__mix(var kinds : uint8?; va : va_args) : double \{\n    var ap : CVaCursor\n")
        has_text(t, text, "    ap = va_begin(va)\n")
        has_text(t, text, "acc += double(int(va_i(ap)))")
        has_text(t, text, "acc += va_d(ap)")
        has_text(t, text, "acc += double(uint(va_i(ap)))")
        has_text(t, text, "var s : uint8? = reinterpret<uint8?>(va_p(ap))")
        has_text(t, text, "var c : color = enum_from_int(type<color>, int(va_i(ap)))")
        // va_copy is the cursor's assignment, va_end no statement
        has_text(t, text, "    b = a\n")
        has_text(t, text, "def private p4_varargs__take_two(var ap : CVaCursor) : int")
        has_text(t, text, "c_vprintf(fmt, va_rest(ap))")
        has_text(t, text, "n = c_vsnprintf(buf, size, fmt, va_rest(ap))")
        has_text(t, text, "n = c_vsprintf(buf, fmt, va_rest(ap))")
        // every data pointer parameter is `var` (F3)
        has_text(t, text, "def private p4_varargs__bounded(var buf : uint8?; size : uint64; var fmt : uint8?; va : va_args) : int")
        has_text(t, text, "let _t0 = int(va_i(ap))")
        has_text(t, text, "ok = int(va_i(ap)) == 7 || int(va_i(ap)) == 8 ? 1 : 0")
        // `sizeof(va_list)` is clang's size: the cursor is never laid out
        has_text(t, text, "int(uint64(24))")
        has_text(t, text, "sscanf(reinterpret<uint8?>(\"  12,-7 2.5e1 hello\")")
        // `va_end` is no statement: the text starts a cursor exactly where C calls `va_start`
        let c_source = fread("{FIXTURES}/p4_varargs.c")
        t |> equal(count(text, "= va_begin("), count(c_source, "va_start("), text)
        // a `va_list` parameter reassigned and passed on stays the caller's `var` cursor
        has_text(t, text, "def private p4_varargs__relay(var ap : CVaCursor) : int \{\n    var mine : CVaCursor\n    mine = ap\n    ap = mine\n")
        // a pop is an effect: an initializer holding a union evaluates its items first
        has_text(t, text, "    let _t0 = int(va_i(ap))\n    let _t1 = int(va_i(ap))\n    var t : tagged = tagged(tag = _t0)\n    t.u.i = _t1\n")
        has_text(t, text, "def private p4_varargs__put_number(var buf : uint8?; v : int)")
        has_text(t, text, "n = c_vsscanf(src, fmt, va_rest(ap))")
        // a call of the module's own variadic is the macro's expansion, the library's keeps C's
        has_text(t, text, "return p4_varargs__late`va(2, (first, n))")
        has_text(t, text, "return p4_varargs__shared_third`va(1, (n,))")
        has_text(t, text, "sum`va(0, VaNone())")
        // the spelled call resolves at inference: above its definition and inside it
        has_text(t, text, "return n > 0 ? n + p4_varargs__countdown`va(n - 1, VaNone()) : 0")
        has_text(t, text, "p4_varargs__ping`va(n - 1, VaNone())")
        has_text(t, text, "printf(reinterpret<uint8?>(\"pairs %d\\n\"), p4_varargs__pairs`va(1, (4, 2, 9)))")
        // a `va_list` position is `var` in a function type as in the function
        has_text(t, text, "var t : function<(var a0 : CVaCursor) : int> = @@p4_varargs__take_two")
        has_text(t, text, "first = invoke(t, ap)")
        has_text(t, text, "[init]\ndef private c2das_dialect \{\n    c_long_bits = 64\n")
        // the module's first `[init]`
        t |> equal(text |> find("def private c2das_dialect") < text |> find("[init]\ndef private c2das_layout_check"), true, text)
        let msvc <- convert("{FIXTURES}/p4_varargs.c", path_join(work_root, "p4_varargs_msvc"), "msvc")
        t |> equal(msvc.ok, true, msvc.error)
        has_text(t, msvc.das_text, "def private p4_varargs__take_two(var ap : CVaCursor) : int")
        has_text(t, msvc.das_text, "    b = a\n")
        has_text(t, msvc.das_text, "    c_long_bits = 32\n")
        has_text(t, msvc.das_text, "int(uint64(8))")
    }
    t |> run("varargs: the converted module runs from a cold module cache under the interpreter and the JIT") @(t : T?) {
        let res <- convert("{FIXTURES}/p4_varargs.c", path_join(work_root, "p4_varargs_cold"), "linux")
        t |> equal(res.ok, true, res.error)
        for (tier_flags in [["-module-cache"], ["-jit", "-module-cache"]]) {
            let cache = path_join(work_root, "p4_varargs_cold.dascache")
            remove(cache)
            var inscope args <- [get_das_root() + "/bin/daslang", "-load_module", "dasCRuntime", "-load_module", "c_runtime"]
            args |> push_from(tier_flags, [cache, res.das_path])
            var out : string
            let rc = run_and_capture(args, out, 600.0)
            t |> equal(rc, 0, out)
            t |> equal(out |> find("outer 42") >= 0, true, out)
            remove(cache)
        }
    }
    p4_varargs_shapes(t)
}

def p4_varargs_shapes(t : T?) {
    t |> run("varargs: the undefined reads of a promoted type pop the promoted class and narrow") @(t : T?) {
        let text = converts(t, "va_narrow", "#include <stdarg.h>\nstatic int f(int n, ...) \{ va_list ap; va_start(ap, n); char c = va_arg(ap, char); short s = va_arg(ap, short); float x = va_arg(ap, float); _Bool b = va_arg(ap, _Bool); va_end(ap); return c + s + (int) x + b; \}\nint main(void) \{ return f(0, 1, 2, 3.0, 1) - 7; \}\n")
        has_text(t, text, "var c : uint8 = uint8(va_i(ap))")
        has_text(t, text, "var s : int16 = int16(va_i(ap))")
        has_text(t, text, "var x : float = float(va_d(ap))")
        has_text(t, text, "var b : bool = va_i(ap) != 0l")
        // a function pointer pops as a pointer; a body that takes `va` binds the list as `va1`
        let named = converts(t, "va_fn_and_name", "#include <stdarg.h>\nstatic int twice(int v) \{ return 2 * v; \}\nstatic int f(int n, ...) \{ va_list va; va_start(va, n); int (*g)(int) = va_arg(va, int (*)(int)); va_end(va); return g(n); \}\nint main(void) \{ return f(3, twice) - 6; \}\n")
        has_text(t, named, "def private va_fn_and_name__f(n : int; va1 : va_args) : int")
        has_text(t, named, "va = va_begin(va1)")
        has_text(t, named, "var g : function<(a0 : int) : int> = reinterpret<function<(a0 : int) : int>>(va_p(va))")
    }
    t |> run("varargs: a name that is no `va_list` converts as before, under both dialects") @(t : T?) {
        let shapes <- [
            ("user_va_list_typedef", "typedef int va_list;\nint main(void) \{ va_list v = 3; return v - 3; \}\n", "var v : int = 3"),
            ("user_va_list_tag", "#include <stdarg.h>\nstruct va_list \{ int a, b; \};\nint main(void) \{ struct va_list s = \{ 1, 2 \}; return s.a + s.b - 3; \}\n", "struct va_list \{"),
            ("local_typedef_char", "#include <stdarg.h>\nstatic int f(int n, ...) \{ typedef va_list L; L ap; va_start(ap, n); int v = va_arg(ap, int); va_end(ap); return v; \}\nstatic int g(void) \{ typedef char *L; L x = 0; return x == 0; \}\nint main(void) \{ return f(1, 4) + g() - 5; \}\n", "var x : uint8? = null"),
            ("local_typedef_shadow", "#include <stdarg.h>\nstatic int f(int n, ...) \{ typedef va_list L; L ap; va_start(ap, n); int v = va_arg(ap, int); va_end(ap); return v; \}\nstatic int g(void) \{ typedef int L; L x = 3; return x; \}\nint main(void) \{ return f(1, 4) + g() - 7; \}\n", "var x : int = 3")
        ]
        let dir = path_join(work_root, "converted")
        mkdir(dir)
        for (shape in shapes) {
            let c_path = path_join(dir, "{shape._0}.c")
            fwrite(c_path, shape._1)
            for (target in ["linux", "msvc"]) {
                let res <- convert(c_path, path_join(dir, "{shape._0}_{target}"), target)
                t |> equal(res.ok, true, "{shape._0} {target}: {res.error}")
                has_text(t, res.das_text, shape._2)
            }
        }
    }
    t |> run("varargs under msvc: a `va_list` is known by its name, a typedef of it included, where the type is a `char *`") @(t : T?) {
        let dir = path_join(work_root, "converted")
        mkdir(dir)
        let c_path = path_join(dir, "va_msvc_typedef.c")
        fwrite(c_path, "#include <stdarg.h>\ntypedef va_list my_list;\nstatic int f(int n, ...) \{ my_list ap; va_start(ap, n); int v = va_arg(ap, int); va_end(ap); return v + n; \}\nint main(void) \{ return f(1, 2) - 3; \}\n")
        let res <- convert(c_path, path_join(dir, "va_msvc_typedef"), "msvc")
        t |> equal(res.ok, true, res.error)
        has_text(t, res.das_text, "var ap : CVaCursor")
        let field_path = path_join(dir, "va_msvc_field.c")
        fwrite(field_path, "#include <stdarg.h>\nstruct S \{ va_list ap; int n; \};\nint main(void) \{ struct S s; s.n = 0; return s.n; \}\n")
        let field <- convert(field_path, path_join(dir, "va_msvc_field"), "msvc")
        t |> equal(field.error |> find("a `va_list` field (`S.ap`) is not lowered yet") >= 0, true, field.error)
        // msvc's `va_list` is a `char *`, so C reads one through `...`
        let nested_path = path_join(dir, "va_msvc_nested.c")
        fwrite(nested_path, "#include <stdarg.h>\nstatic int f(int n, ...) \{ va_list ap; va_start(ap, n); va_list inner = va_arg(ap, va_list); (void) inner; va_end(ap); return n; \}\nint main(void) \{ return f(0); \}\n")
        let nested <- convert(nested_path, path_join(dir, "va_msvc_nested"), "msvc")
        t |> equal(nested.error |> find("va_arg of a `va_list` is not lowered yet") >= 0, true, nested.error)
    }
    p4_varargs_rejects(t)
}

def p4_varargs_rejects(t : T?) {
    t |> run("varargs: what the lowering refuses, each with its reason") @(t : T?) {
        rejects(t, "va_arg_record", "#include <stdarg.h>\nstruct P \{ int x; \};\nstatic int f(int n, ...) \{ va_list ap; va_start(ap, n); struct P p = va_arg(ap, struct P); va_end(ap); return p.x; \}\nint main(void) \{ struct P p = \{ 0 \}; return f(1, p); \}\n", "va_arg of a record type is not lowered yet")
        rejects(t, "va_record_argument", "int printf(const char *, ...);\nstruct P \{ int x; \};\nint main(void) \{ struct P p = \{ 0 \}; return printf(\"%d\", p); \}\n", "a record passed through `...` (argument 1 of `printf`) is not lowered yet")
        rejects(t, "va_list_field", "#include <stdarg.h>\nstruct S \{ va_list ap; int n; \};\nint main(void) \{ struct S s; s.n = 0; return s.n; \}\n", "a `va_list` field (`S.ap`) is not lowered yet")
        rejects(t, "va_list_global", "#include <stdarg.h>\nva_list g;\nint main(void) \{ return 0; \}\n", "a `va_list` global (`g`) is not lowered yet")
        rejects(t, "va_list_array", "#include <stdarg.h>\nint main(void) \{ va_list two[2]; (void) two; return 0; \}\n", "a pointer to a `va_list` or an array of them is not lowered yet")
        rejects(t, "va_list_pointer", "#include <stdarg.h>\nstatic int f(int n, ...) \{ va_list ap; va_list *p = &ap; va_start(*p, n); int v = va_arg(*p, int); va_end(ap); return v; \}\nint main(void) \{ return f(1, 0); \}\n", "a pointer to a `va_list` or an array of them is not lowered yet")
        rejects(t, "va_arg_array", "#include <stdarg.h>\nstatic int f(int n, ...) \{ va_list ap; va_start(ap, n); int x = va_arg(ap, int[2])[0]; va_end(ap); return x; \}\nint main(void) \{ return f(0); \}\n", "va_arg of type kind `array` is not lowered yet")
        rejects(t, "va_list_through_dots", "#include <stdarg.h>\nstatic int g(int n, ...) \{ return n; \}\nstatic int f(int n, ...) \{ va_list ap; va_start(ap, n); int r = g(1, ap); va_end(ap); return r; \}\nint main(void) \{ return f(1, 2) - 1; \}\n", "a `va_list` passed through `...` (argument 1 of `g`) is not lowered yet")
        rejects(t, "va_end_value", "#include <stdarg.h>\nstatic int f(int n, ...) \{ va_list ap; va_start(ap, n); n ? va_end(ap) : (void) 0; return n; \}\nint main(void) \{ return f(0); \}\n", "`va_end` used as a value is not lowered yet")
        rejects(t, "va_tuple_param", "#include <stdarg.h>\nstatic int f(int _va_tuple, ...) \{ return _va_tuple; \}\nint main(void) \{ return f(0); \}\n", "a C name `_va_tuple` in variadic function `f`")
        rejects(t, "va_tuple_local", "#include <stdarg.h>\nstatic int f(int n, ...) \{ int _va_tuple = n; return _va_tuple; \}\nint main(void) \{ return f(0); \}\n", "a C name `_va_tuple` in variadic function `f`")
        rejects(t, "scanf_stdin", "int scanf(const char *, ...);\nint main(void) \{ int x = 0; scanf(\"%d\", &x); return x; \}\n", "external function `scanf` has no c_runtime mapping")
        rejects(t, "fprintf_stream", "typedef struct F F;\nextern F *stderr;\nint fprintf(F *, const char *, ...);\nint main(void) \{ fprintf(stderr, \"x\"); return 0; \}\n", "external function `fprintf` has no c_runtime mapping")
    }
}

// the shapes the csmith differential found (docs/implementation_order.md P4.5)
def p4_csmith_fixtures(t : T?) {
    t |> run("csmith shapes: a shift's count takes the type of its left side") @(t : T?) {
        var text : string
        check_fixture(t, "p4_csmith_shifts", text)
        // das shifts a value only by a count of its own type (F40)
        has_text(t, text, "int(left) > 127 >> int(right) ? int(left) : int(left) << int(right)")
        has_text(t, text, "return v << int64(n) >> int64(n / 2)")
        has_text(t, text, "return v >> uint64(int(n))")
        has_text(t, text, "    a <<= int(b)\n    u >>= uint(int(uint8(1)))\n    b <<= int64(u)\n    b >>= 1l\n")
        has_text(t, text, "b << 2l")
    }
    t |> run("csmith shapes: pointers returned, copied out, compared across constness, null arrays") @(t : T?) {
        var text : string
        check_fixture(t, "p4_csmith_pointers", text)
        // a returned or copied-out pointer parameter is `var` (F3), through `*pp` and `?:` arms
        has_text(t, text, "def private p4_csmith_pointers__pass_back(var p : int?) : int?")
        has_text(t, text, "def private p4_csmith_pointers__pick(k : int; var p : int?; var q : int?) : int?")
        has_text(t, text, "def private p4_csmith_pointers__keep(var pp : int ??; var out : int ??)")
        has_text(t, text, "def private p4_csmith_pointers__write_either(var b : uint8?; var e : uint8?; k : int) : int")
        has_text(t, text, "def private p4_csmith_pointers__via_alias(var p : int?) : int")
        has_text(t, text, "def private p4_csmith_pointers__chained(var p : int?) : int")
        // pointers compare as addresses, a null constant as `null` on either side (F44)
        has_text(t, text, "return intptr(p) == intptr(reinterpret<int?>(q)) ? 1 : 0")
        has_text(t, text, "return reinterpret<int?>(p) == null ? 1 : 0")
        has_text(t, text, "local[0] == null ? 1 : 0")
        // an array of pointers names its element type (F41)
        has_text(t, text, "var private p4_csmith_pointers__table : int? [3] = fixed_array<int?>(null, null, null)")
        has_text(t, text, "= fixed_array(fixed_array<int?>(null, null), fixed_array<int?>(unsafe(addr(p4_csmith_pointers__g)), null))")
        // a row the initializer leaves out is a typed zero literal
        has_text(t, text, "var private p4_csmith_pointers__partial : int? [2][2] = fixed_array(fixed_array<int?>(unsafe(addr(p4_csmith_pointers__g)), null), fixed_array<int?>(null, null))")
        has_text(t, text, "var local : int? [2] = fixed_array<int?>(null, null)")
    }
    t |> run("csmith shapes: a local hiding another takes a free name, discards are fresh, small subscripts widen") @(t : T?) {
        var text : string
        check_fixture(t, "p4_csmith_scopes", text)
        // das refuses a local that shadows another (F42), `_` included
        has_text(t, text, "var i1 : int = 5")
        has_text(t, text, "var i2 : int = 7")
        has_text(t, text, "let _t0 = p4_csmith_scopes__g[0]")
        has_text(t, text, "var p1 : int = 3")
        has_text(t, text, "var v1 : int = 100")
        has_text(t, text, "var i3 : int = 1\n        while (i3 < 3) \{")
        // das indexes by `int`, `int64`, `uint` or `uint64` alone (F43)
        has_text(t, text, "p4_csmith_scopes__g[int(k)] + p4_csmith_scopes__g[int(m)] + p4_csmith_scopes__g[int(n)]")
        has_text(t, text, "def private p4_csmith_scopes__at(var p : int?; c : uint8) : int \{\n    return deref(p + int(c))")
    }
}

// the csmith shapes of the fix round: bindings, pointer walks and the refusals
def p4_csmith_more_fixtures(t : T?) {
    t |> run("csmith shapes: a reference binds to the declaration clang resolved, never to its spelling") @(t : T?) {
        var text : string
        check_fixture(t, "p4_csmith_bindings", text)
        // a local hiding a static keeps its own binding (F47)
        has_text(t, text, "var g1 : int = 5\n            n += g1\n        \}\n    \}\n    return n + p4_csmith_bindings__g")
        // two static locals of one name hoist under two names; a later block's local is its own
        has_text(t, text, "var private static_then_local_s : int = 5\nvar private static_then_local_s1 : int = 9")
        has_text(t, text, "var s : int = 1")
        // a block-scope extern declares nothing and binds to the global
        has_text(t, text, "    \{\n        return x\n    \}")
        // a temporary skips a name the function spells
        has_text(t, text, "var _t0 : int = 7")
        has_text(t, text, "let _t1 = a[0]")
    }
    t |> run("csmith shapes: every pointer parameter is `var`, a stepped scalar or pointer written in place") @(t : T?) {
        var text : string
        check_fixture(t, "p4_csmith_walks", text)
        has_text(t, text, "def private p4_csmith_walks__say(var s : uint8?) : int")
        has_text(t, text, "def private p4_csmith_walks__say2(var s : uint8?) : int")
        has_text(t, text, "def private p4_csmith_walks__show(var p : int?; var n : int)")
        has_text(t, text, "def private p4_csmith_walks__comma(var k : int; var p : int?) : int?")
        // a `_Bool` shift computes in `int`
        has_text(t, text, "b = (int(b ? 1 : 0) << n) != 0")
    }
    t |> run("csmith shapes: what the lowering refuses, and the addresses it keeps checked") @(t : T?) {
        rejects(t, "extern_unknown_length", "extern int arr[];\nstatic int *at(int k) \{ return &arr[k]; \}\nint arr[3] = \{1, 2, 3\};\nint main(void) \{ return (int) (at(3) - at(0)); \}\n", "an array of unknown length (`extern int a[];`) is not lowered yet")
        rejects(t, "hidden_block_extern", "int x = 40;\nint main(void) \{ int x = 1; \{ extern int x; return x; \} \}\n", "a block-scope `extern` declaration of `x`, which a local of the function also names, is not lowered yet")
        rejects(t, "late_block_extern", "int main(void) \{ \{ extern int y; return y; \} \}\nint y = 3;\n", "a block-scope `extern` declaration of `y` with no file-scope declaration before it is not lowered yet")
        // a literal past `int64` is no constant below the length: it takes the checked form
        let huge = converts(t, "past_int64_index", "static int a[3];\nstatic int *far(void) \{ return &a[18446744073709551615ULL]; \}\nint main(void) \{ return far() == 0; \}\n")
        has_text(t, huge, "addr(past_int64_index__a[0]) + end_index(18446744073709551615ul, 3)")
        // a 19-digit literal within `int64` is a constant past the length: das's range check stands
        let far = converts(t, "int64_index", "static int a[3];\nstatic int *far(void) \{ return &a[1000000000000000000]; \}\nint main(void) \{ return far() == 0; \}\n")
        has_text(t, far, "return addr(int64_index__a[1000000000000000000l])")
        // a string literal's address is through its pointer, never the decayed array
        let literal = converts(t, "literal_address", "static const char *at(int k) \{ return &\"abcdef\"[k]; \}\nint main(void) \{ return at(6) - at(0) - 6; \}\n")
        has_text(t, literal, "return addr(deref(reinterpret<uint8?>(\"abcdef\") + k))")
    }
}

// a local the lowering moves out of its C block, and an lvalue with an effect evaluated once
def p4_scope_fidelity_fixtures(t : T?) {
    t |> run("scope fidelity: a moved local takes a free name, a case's local is the switch's, a target with an effect is pinned") @(t : T?) {
        var text : string
        check_fixture(t, "p4_scope_fidelity", text)
        // a block a goto enters loses its braces: its local leaves the global and a later
        // block's local their names
        has_text(t, text, "    var g1 : int = 3\n    n += g1\n    label 1:  // in\n    n += 1\n    return n * 100 + g\n")
        has_text(t, text, "    var t1 : int = 2\n    n += t1\n")
        // a local a later case reaches is declared before the lowered switch
        has_text(t, text, "    let _cond = k\n    var v : int\n    while (true) \{")
        has_text(t, text, "        if (_flag) \{\n            v = 1\n            r += v\n        \}")
        has_text(t, text, "    let _cond = k\n    var w : int\n    if (_cond == 0) \{\n        w = 5\n")
        // a later case's block or `for` declaring the name binds its own references: the
        // switch's union stays in its branch, the `int` a later label names is carried
        has_text(t, text, "    var v1 : int\n    if (_cond == 0) \{\n        var u : un\n        u.i = 5\n        v1 = 1\n")
        has_text(t, text, "            var u1 : un\n            u1.i = 9\n")
        has_text(t, text, "            var v2 : int = 0\n            while (v2 < 3) \{")
        has_text(t, text, "        v1 = 7\n        r = v1\n")
        // a step's value reads the index the step used
        has_text(t, text, "    let _t0 = k\n    k++\n    let _t1 = arr[_t0].a\n    arr[_t0].a++\n    var v : int = _t1\n")
        has_text(t, text, "    arr[_t2].a++\n    var w : int = arr[_t2].a\n")
        // a target through a call holds the call's pointer
        has_text(t, text, "    var _t0 = p4_scope_fidelity__next()\n    deref(_t0)++\n    var _t1 = p4_scope_fidelity__next()\n    deref(_t1) += 5\n")
        has_text(t, text, "    var _t5 = p4_scope_fidelity__cell_at()\n    _t5.a += 3\n")
        // an assignment read as a value reads the target the store used
        has_text(t, text, "        deref(_t0) = deref(_t1)\n        if (!(deref(_t0) != 0)) \{\n            break\n")
        has_text(t, text, "    deref(_t2) = deref(_t3)\n    if (deref(_t2) != 0) \{\n")
        has_text(t, text, "    a[_t6] = 9\n    var got : int = a[_t6]\n")
        // a bitfield's getter and setter, spelled apart (F52), share the pinned index
        has_text(t, text, "    let _t0 = p4_scope_fidelity__pick(1)\n    deref(p + _t0).bf = uint(int(deref(p + _t0).bf) + 5)\n")
        has_text(t, text, "    bytes[_t3] = int8(int(bytes[_t3]) + 7)\n")
        // a target spelled by a variable's own name is pinned too: a call later in the
        // statement changes the variable
        has_text(t, text, "    p4_scope_fidelity__gi++\n    let _t0 = p4_scope_fidelity__gi\n    uc[_t0] += p4_scope_fidelity__gi_to_one()\n")
        has_text(t, text, "    var _t1 = p4_scope_fidelity__gp\n    deref(_t1) += p4_scope_fidelity__gp_away()\n")
        has_text(t, text, "    let _t2 = p4_scope_fidelity__gi\n    uc[_t2] += p4_scope_fidelity__gi_to_zero()\n    var v : int = uc[_t2]\n")
        rejects(t, "carried_union_local", "union U \{ int i; float f; \};\nint main(void) \{\n    int r = 0;\n    switch (r) \{\n    case 0:;\n        union U u = \{5\};\n        r = u.i;\n    case 1:\n        u.i = 2;\n        r += u.i;\n    \}\n    return r - 7;\n\}\n", "a declaration under a case label filled by stores (a union or a sparse array) and used under a later label is not lowered yet")
    }
    t |> run("scope fidelity edges: array members and pointer bases with effects, an else-if step, a C name spelled like a temporary, carried declarations of every shape, the names a later label resolves") @(t : T?) {
        var text : string
        check_fixture(t, "p4_scope_edges", text)
        // a C variable named like a temporary is pinned like any other
        has_text(t, text, "    _t1 = 2\n    let _t0 = _t1\n    p4_scope_edges__uc[_t0] += p4_scope_edges__t1_to_zero()\n")
        // a plain `=` statement pins nothing
        has_text(t, text, "    deref(p4_scope_edges__sink()) = 21\n")
        // a carried declaration without an initializer, and one under a nested `if`
        has_text(t, text, "p4_scope_edges__carried_bare(k : int) : int \{\n    var r : int = 0\n    let _cond = k\n    var v : int\n")
        has_text(t, text, "p4_scope_edges__nested_use(k : int) : int \{\n    var r : int = 0\n    let _cond = k\n    var v : int\n")
        // a `for` declaring the name among others binds its own: the union stays in its branch
        has_text(t, text, "p4_scope_edges__for_declares_two(k : int) : int \{\n    var r : int = 0\n    let _cond = k\n    if (_cond == 0) \{\n        var u : un\n")
        has_text(t, text, "            var a : int = 1\n            var u1 : int = 0\n")
    }
}

// the c-feature-matrix rows the P4 phase-end audit found without a green fixture
def p4_matrix_fixtures(t : T?) {
    t |> run("matrix shapes: an opaque struct pointer, _Alignof, char rows from string literals, _Alignas, ~ and ^, restrict, K&R parameters, inline, long double, volatile, the comma's value, exit from deep") @(t : T?) {
        var text : string
        check_fixture(t, "p4_matrix_shapes", text)
        // a struct the unit never defines is an empty struct, reached through pointers alone
        has_text(t, text, "struct opaque \{\}\n")
        has_text(t, text, "var slots : opaque? [3]\n")
        has_text(t, text, "def private p4_matrix_shapes__wrap(var r : real?) : opaque? \{\n    return reinterpret<opaque?>(r)\n")
        // `_Alignof` is das's alignment where it is clang's, clang's value where das aligns lower (F5)
        has_text(t, text, "int(uint64(typeinfo alignof(type<S>))), int(uint64(typeinfo alignof(type<double>))), int(uint64(typeinfo alignof(type<int[4]>))), int(uint64(4)))")
        // a row of a char array from a string literal is `cstr_array`, a missing row zeros
        has_text(t, text, "var private p4_matrix_shapes__s4_2 : uint8[2][4] = fixed_array(cstr_array(\"1234\", 4), cstr_array(\"5678\", 4))")
        has_text(t, text, "var part : uint8[3][4] = fixed_array(cstr_array(\"ab\", 4), fixed_array(uint8(0), uint8(0), uint8(0), uint8(0)), fixed_array(uint8(0), uint8(0), uint8(0), uint8(0)))")
        has_text(t, text, "var cube : uint8[2][2][3] = fixed_array(fixed_array(cstr_array(\"a\", 3), cstr_array(\"bc\", 3)), fixed_array(cstr_array(\"de\", 3), fixed_array(uint8(0), uint8(0), uint8(0))))")
        has_text(t, text, "var private p4_matrix_shapes__nm : named = named(name = cstr_array(\"abc\", 6), id = 3)")
        // a union's member is stored after the declaration; one evaluated ahead is read back
        has_text(t, text, "    var tx : text4\n    tx.s = cstr_array(\"abc\", 4)\n    let _t0 = cstr_array(\"xy\", 4)\n")
        has_text(t, text, "    h.t.s = _t0\n")
        // `_Alignas` on a field at its own alignment changes nothing das spells
        has_text(t, text, "struct aligned_nat \{\n    x : int\n    c : uint8\n\}")
        has_text(t, text, "~u, ~i, u ^ 240u, i ^ ~i")
        has_text(t, text, "def private p4_matrix_shapes__copy_r(var dst : int?; var src : int?; n : int)")
        // a K&R parameter arrives promoted and converts on entry, `var` where the body writes it
        has_text(t, text, "def private p4_matrix_shapes__knr(a : int; b_in : int; s_in : int; f_in : double; e_in : uint; ok_in : int) : int \{\n    let b = uint8(b_in)\n    var s = int16(s_in)\n    let f = float(f_in)\n    let e = enum_from_int(type<level>, int(e_in))\n    let ok = ok_in != 0\n")
        has_text(t, text, "def private p4_matrix_shapes__sq(v : int) : int \{\n    return v * v\n")
        has_text(t, text, "def private p4_matrix_shapes__half(x : double) : double \{\n    return x / 2.0lf\n")
        has_text(t, text, "struct vol \{\n    ticks, other : int\n\}")
        has_text(t, text, "    p4_matrix_shapes__clock_v.ticks += 2\n")
        has_text(t, text, "    a++\n    var x : int = b + a\n")
        has_text(t, text, "        c_exit(3)\n")
    }
    t |> run("matrix shapes: _Alignof of a record das never lays out is clang's value") @(t : T?) {
        let va = converts(t, "alignof_va_list", "#include <stdarg.h>\nint main(void) \{ return (int) _Alignof(va_list) - 8; \}\n")
        has_text(t, va, "return int(uint64(8)) - 8")
        let marshal = converts(t, "alignof_marshal", "struct __attribute__((packed)) P \{ char c; int x; \};\nint main(void) \{ struct P p; p.x = 1; return (int) _Alignof(struct P) - p.x; \}\n", "\{\"marshal\": [\"P\"]\}\n")
        has_text(t, marshal, "return int(uint64(1)) - p.x")
    }
    t |> run("matrix shapes: a literal longer than its row keeps the row's bytes, as clang initializes the array") @(t : T?) {
        let long_row = converts(t, "literal_past_row", "static const char a[2][3] = \{ \"1234\", \"xyz\" \};\nint main(void) \{ return a[0][2] - '3'; \}\n")
        has_text(t, long_row, "fixed_array(cstr_array(\"123\", 3), cstr_array(\"xyz\", 3))")
    }
    t |> run("matrix shapes: what the lowering refuses, each naming the construct") @(t : T?) {
        rejects(t, "alignas_over", "struct over \{ char c; _Alignas(8) char d; \};\nint main(void) \{ struct over o = \{ 1, 2 \}; return o.d - 2; \}\n", "record `over` is not laid out naturally: a packed record is marshal-only")
        rejects(t, "gnu_alignof", "int main(void) \{ return (int) __alignof__(double) - 8; \}\n", "`__alignof` is not dumped yet")
        rejects(t, "vla", "int main(void) \{ int n = 3; int a[n]; a[0] = 0; return a[0]; \}\n", "`int a[n]`: a variable-length array is not lowered (out of scope in v1)")
        rejects(t, "vla_rows", "int main(void) \{ int n = 3; int a[n][2]; a[0][0] = 0; return a[0][0]; \}\n", "`int a[n][2]`: a variable-length array is not lowered (out of scope in v1)")
        rejects(t, "vla_row_pointer", "int main(void) \{ int n = 2; int (*rp)[n] = 0; return rp != 0; \}\n", "`int[n]`: a variable-length array is not lowered (out of scope in v1)")
        rejects(t, "vla_function_pointers", "int main(void) \{ int n = 2; void (*fps[n])(void); fps[0] = 0; return fps[0] != 0; \}\n", "`void (*[n])(void)`: a variable-length array is not lowered (out of scope in v1)")
        rejects(t, "vla_unnamed_records", "int main(void) \{ int n = 2; struct \{ int x; \} rs[n]; rs[0].x = 0; return rs[0].x; \}\n", ")[n]`: a variable-length array is not lowered (out of scope in v1)")
        rejects(t, "zero_length_local", "int main(void) \{ int a[0]; return 0; \}\n", "a zero-length array (a GNU extension) is not lowered yet")
    }
}
