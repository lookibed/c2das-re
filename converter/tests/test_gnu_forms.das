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

//! The GNU forms P7.6 lowers: a case range is a pair of tests in the condition's type under every
//! switch dispatch, `__alignof__` is clang's value, a `typeof` inside a declarator is the type
//! libclang resolves, `__extension__` is its operand, `__builtin_classify_type`,
//! `__builtin_types_compatible_p` and `__builtin_choose_expr` are what clang folded or chose, the
//! checked arithmetic builtins are calls of `c_runtime/c_builtins`; and the C11 and GNU forms beside
//! them: a generic selection is the association clang selected, an enum the unit never defines is
//! an `int` behind its pointers, a bitfield of enum type is one of the enum's integer, an anonymous
//! member takes an initializer, a statement expression is statements where its value is assigned
//! or discarded. Each fixture prints what its native build
//! prints; the text carries each form, and what the lowering refuses names the construct.

let FIXTURES = "converter/tests/fixtures"

var work_root : string

def work_dir(name : string) : string {
    if (empty(work_root)) {
        var dir_error : string
        work_root = create_temp_directory("c2das_gnu_forms", dir_error)
    }
    return path_join(work_root, name)
}

def has_text(t : T?; text, needle : string) {
    t |> success(text |> contains(needle), "missing `{needle}` in:\n{text}")
}

// fixture `name` converted under `switch_dispatch` prints what its native build prints: its das text
def same_as_native(t : T?; name, switch_dispatch : string) : string {
    let c_path = "{FIXTURES}/{name}.c"
    let native = native_run(default_clang(), ["-w", "-funsigned-char"], c_path, work_dir("{name}_native"), 60.0)
    t |> success(native.built && native.rc == 0, native.output)
    let work = work_dir("{name}_{switch_dispatch}")
    let res <- convert(c_path, work, "linux", "", "", "", "", "", switch_dispatch)
    t |> equal(res.ok, true, res.error)
    var out : string
    let rc = run_tier(res.das_path, "interp", work, out, CONVERTED_MODULES, 600.0)
    t |> equal(rc, native.rc, out)
    t |> equal(out, native.output)
    return res.das_text
}

// `source` as `<name>.c` under the work root, converted
def converted_source(name, source : string) : ConvertResult {
    let dir = work_dir(name)
    mkdir(dir)
    let c_path = path_join(dir, "{name}.c")
    fwrite(c_path, source)
    return <- convert(c_path, dir, "linux")
}

// `source` converts and exits 0 under the interpreter: its das text
def runs_clean(t : T?; name, source : string) : string {
    let res <- converted_source(name, source)
    t |> equal(res.ok, true, "{name}: {res.error}")
    var out : string
    let rc = run_tier(res.das_path, "interp", work_dir(name), out, CONVERTED_MODULES, 600.0)
    t |> equal(rc, 0, out)
    return res.das_text
}

def rejects(t : T?; name, source, needle : string) {
    let res <- converted_source(name, source)
    t |> equal(res.ok, false, "{name} converted:\n{res.das_text}")
    t |> success(res.error |> contains(needle), "{name}: `{needle}` not in `{res.error}`")
}

// the text of function `name` in das module `text`
def function_text(text, name : string) : string {
    let head = text |> find("def {name}(")
    return head < 0 ? "" : slice(text, head, text |> find("\n\}\n", head))
}

[test]
def test_case_ranges(t : T?) {
    t |> run("chain: a range is two tests in the condition's type, in the if-chain, the flag loop and the open switch") @(t : T?) {
        let text = same_as_native(t, "p7_case_ranges", "chain")
        // alone it is bare, beside another label of its group it takes parentheses
        has_text(t, text, "    if (_cond >= 1 && _cond <= 5) \{\n        return 10\n    \} elif (_cond == 7 || (_cond >= 9 && _cond <= 11)) \{\n")
        // both ends characters keep their spelling; one a number, both are numbers
        has_text(t, text, "    \} elif (_cond >= 'a' && _cond <= 'f') \{\n")
        has_text(t, text, "    \} elif (_cond >= 48 && _cond <= 57) \{\n")
        // the flag loop: a flag line, default's match-none test, a plain group
        has_text(t, text, "        _flag ||= _cond >= -3 && _cond <= -1\n")
        has_text(t, text, "        _flag ||= !((_cond >= -3 && _cond <= -1) || _cond == 0 || (_cond >= 4 && _cond <= 4) || (_cond >= 20 && _cond <= 29) || _cond == 40)\n")
        has_text(t, text, "        if ((_cond >= 20 && _cond <= 29) || _cond == 40) \{\n")
        // a `uint64` end past `int64` is its decimal digits, a plain case's too
        has_text(t, text, "    \} elif (_cond >= 1000000000000000000ul && _cond <= 9999999999999999999ul) \{\n")
        has_text(t, text, "    \} elif (_cond == 18446744073709551615ul) \{\n")
        has_text(t, text, "    if (_cond >= 2147483648u && _cond <= 4294967295u) \{\n")
        // the ends are held in the controlling type; an empty range is no label
        has_text(t, text, "    if (_cond >= -2147483647 - 1 && _cond <= -2) \{\n")
        has_text(t, text, "    \} elif (_cond >= 4294967293u && _cond <= 4294967294u) \{\n")
        has_text(t, function_text(text, "falls"), "        case(1) \{\n            r += 1\n            r += 10\n            break\n")
        // an enum compares by value
        has_text(t, text, "    if (int(_cond) >= 1 && int(_cond) <= 3) \{\n")
        // the open switch: a goto on the range, the label naming it
        has_text(t, text, "    \} elif (_cond >= 5 && _cond <= 9) \{\n        goto label 3\n")
        has_text(t, text, "    label 3:  // case 5 ... 9\n")
        // a re-dispatch tests its goto variable: no value of the condition is a sentinel
        has_text(t, text, "    let _cond = x\n    var _goto = 0\n")
        has_text(t, text, "        if (_goto == 0 && _cond >= 1 && _cond <= 3) \{\n")
        // no `c_switch` arm spells a range; the switch inside one is its own, and the outer one's
        // ranges are back after it
        t |> success(!(function_text(text, "chain") |> contains("c_switch")) && !(function_text(text, "wide") |> contains("c_switch")), text)
        has_text(t, text, "            c_switch(y) \{\n")
        has_text(t, function_text(text, "nested"), "        _flag ||= _cond >= 3 && _cond <= 4\n")
        // and after an inner switch with ranges of its own
        has_text(t, function_text(text, "nested"), "            if (_cond3 >= 0 && _cond3 <= 1) \{\n")
        has_text(t, function_text(text, "nested"), "        if (_cond >= 5 && _cond <= 6) \{\n")
    }
    t |> run("goto and table: a switch with a range takes no jump table, however dense its other cases") @(t : T?) {
        for (mode in ["goto", "table"]) {
            let text = same_as_native(t, "p7_case_ranges", mode)
            let dense = function_text(text, "dense")
            has_text(t, dense, "    \} elif (_cond >= 8 && _cond <= 9) \{\n        return 108\n")
            t |> success(!(dense |> contains("goto")), dense)
        }
    }
    rmdir_rec(work_root)
    work_root = ""
}

[test]
def test_gnu_keywords(t : T?) {
    t |> run("`__alignof__` is das's alignment where it is clang's value, else the value; `typeof` and `__extension__` leave no trace") @(t : T?) {
        let text = same_as_native(t, "p7_gnu_keywords", "")
        has_text(t, text, "int(uint64(typeinfo alignof(type<uint8>))), int(uint64(typeinfo alignof(type<double>)))")
        // an expression's is its type's
        has_text(t, text, "int(uint64(typeinfo alignof(type<S>))), int(uint64(typeinfo alignof(type<int[3]>)))")
        // a function's own alignment and an `aligned` typedef's are clang's values
        has_text(t, text, "int(uint64(256)), int(uint64(16)), int(uint64(typeinfo alignof(type<int[4]>)))")
        // two in one macro, each spelled by its own token
        has_text(t, text, "uint64(typeinfo alignof(type<int>)) + uint64(typeinfo alignof(type<double>))")
        // a whole `typeof` as the operand of `va_arg`, `sizeof` and `_Alignof`
        has_text(t, text, "double(uint64(typeinfo sizeof(type<double>))) + double(uint64(typeinfo alignof(type<int>)))")
        // `typeof` in a function type, a pointer and a macro's local
        has_text(t, text, "def private p7_gnu_keywords__twice(n : int) : int64 \{\n    let r : int64 = int64(n)\n")
        has_text(t, text, "    var p : int? = addr(arr[1])\n")
        has_text(t, text, "        var _t : S = s\n")
        has_text(t, text, "    let w : int64 = int64(arr[0]) * p7_gnu_keywords__big\n")
        has_text(t, text, "    return 0\n")
    }
    t |> run("`typeof` under a declarator: one spelling naming one type in two functions, an unnamed record, a cast; a name holding the word is no `typeof`") @(t : T?) {
        runs_clean(t, "typeof_same", "int f(void) \{ int x = 1; typeof(x) *p = &x; return *p; \}\nint g(void) \{ int x = 2; typeof(x) *p = &x; return *p; \}\nint main(void) \{ return f() + g() - 3; \}\n")
        runs_clean(t, "typeof_unnamed", "int main(void) \{ struct \{ int a; \} s = \{ 3 \}; typeof(s) *p = &s; return p->a - 3; \}\n")
        let cast_text = runs_clean(t, "typeof_cast", "struct S \{ int a; long b; \};\nint main(void) \{ struct S s = \{ 1, 2 \}; void *v = &s.b; const typeof(((struct S *)0)->b) *m = (typeof(s.b) *)v; return (int)*m - 2; \}\n")
        has_text(t, cast_text, "var m : int64? = reinterpret<int64?>(v)")
        // under a pointer to an array, and under a parameter of a function pointer's type
        runs_clean(t, "typeof_rows", "int main(void) \{ int x = 1; int rows[2] = \{ x, 2 \}; typeof(x) (*pa)[2] = &rows; return (*pa)[0] + (*pa)[1] - 3; \}\n")
        runs_clean(t, "typeof_param", "static long g = 2;\nstatic int take(long *p) \{ return (int) *p; \}\nint main(void) \{ int (*fp)(typeof(g) *) = take; return fp(&g) - 2; \}\n")
        runs_clean(t, "typeof_names", "typedef int _typeof; typedef int my_typeof_t; static int one(void) \{ return 1; \}\nint main(void) \{ _typeof (*fp)(void) = one; my_typeof_t v = 1; my_typeof_t *q = &v; return fp() - *q; \}\n")
    }
    t |> run("what the lowering refuses, each naming the construct") @(t : T?) {
        rejects(t, "alignof_split", "#define D(x) (x(char) + x(double))\nint main(void) \{ return (int)D(__alignof__) - 9; \}\n", "two `__alignof__` of one macro expansion that clang values apart are not lowered")
        rejects(t, "typeof_split", "int f(void) \{ int x = 1; typeof(x) *p = &x; return *p; \}\nint g(void) \{ char x = 2; typeof(x) *p = &x; return *p; \}\nint main(void) \{ return f() + g() - 3; \}\n", "`typeof (x)`: a `typeof` libclang resolves to no one type")
        // a type operand is no place the libclang pass reads a type of: the spelling of a `typeof`
        // there is never resolved by another scope's declaration (`f`'s `x` is an `int`)
        let other_scope = "int f(void) \{ int x = 1; typeof(x) *p = &x; return *p; \}\n"
        let operand = "a `typeof` under a declarator in the operand of `sizeof`, `_Alignof` or `va_arg` is not lowered yet"
        rejects(t, "typeof_sizeof", other_scope + "int g(void) \{ double x = 0; return (int) sizeof(typeof(x)[3]); \}\nint main(void) \{ return f() + g() - 25; \}\n", "`typeof (x)[3]`: {operand}")
        rejects(t, "typeof_alignof", other_scope + "int g(void) \{ double x = 0; return (int) _Alignof(typeof(x)[3]); \}\nint main(void) \{ return f() + g() - 9; \}\n", "`typeof (x)[3]`: {operand}")
        rejects(t, "typeof_va_arg", "#include <stdarg.h>\n" + other_scope + "static double g(int n, ...) \{ double x = 0; va_list ap; va_start(ap, n); x = *va_arg(ap, typeof(x) *); va_end(ap); return x; \}\nint main(void) \{ double d = 2.0; return f() + (int) g(1, &d) - 3; \}\n", "`typeof (x) *`: {operand}")
        // a header outside the program spells the same `typeof` for another type
        mkdir(work_dir("typeof_inc"))
        fwrite(path_join(work_dir("typeof_inc"), "ext.h"), "extern long gx;\nstruct E \{ typeof(gx) *p; \};\n")
        rejects(t, "typeof_header", "#include \"../typeof_inc/ext.h\"\nlong gx = 5;\nstatic void set(struct E *e) \{ e->p = &gx; \}\nint main(void) \{ struct E e; set(&e); double gx = 1.0; typeof(gx) *q = &gx; return (int) *e.p - 5 + (int) *q - 1; \}\n", "`typeof (gx)`: a `typeof` libclang resolves to no one type")
        // an empty range labels nothing, so its statement stands before the switch's first label
        rejects(t, "empty_range_first", "int main(void) \{ int x = 3; switch (x) \{ case 3 ... 2: return 9; case 3: return 0; default: return 1; \} \}\n", "a statement before the first case label is unreachable; not lowered")
        rejects(t, "typeof_array", "int main(void) \{ int arr[3] = \{ 1, 2, 3 \}; typeof(arr) *p = &arr; return (*p)[0] - 1; \}\n", "`typeof (arr) *`: a `typeof` of a function, an array or a pointer to one (`int[3]`) under a declarator is not lowered yet")
        rejects(t, "typeof_fn_pointer", "static int one(void) \{ return 1; \}\nint main(void) \{ int (*fp)(void) = one; typeof(fp) *pp = &fp; return (*pp)() - 1; \}\n", "`typeof (fp) *`: a `typeof` of a function, an array or a pointer to one (`int (*)(void)`) under a declarator is not lowered yet")
    }
    rmdir_rec(work_root)
    work_root = ""
}

[test]
def test_gnu_builtins(t : T?) {
    t |> run("the folded builtins are clang's values, the chosen operand is the expression itself, and no operand left out is evaluated") @(t : T?) {
        let text = same_as_native(t, "p7_folded_builtins", "")
        has_text(t, text, "printf(cstr(\"compatible %d %d %d %d\\n\"), 1, 1, 1, 1)")
        has_text(t, text, "printf(cstr(\"incompatible %d %d %d %d\\n\"), 0, 0, 0, 0)")
        // two calls of one expansion spelled from one token, valued alike
        has_text(t, text, "printf(cstr(\"classify %d %d %d %d %d %d\\n\"), 1, 8, 5, 12, 1, 1 * 100 + 1)")
        has_text(t, text, "printf(cstr(\"choose %d %d %s %s\\n\"), 7, 8, cstr(\"double\"), cstr(\"other\"))")
        has_text(t, text, "    i = 9\n    p7_folded_builtins__step()\n")
        has_text(t, text, "    let classified : bool = 8 != 0\n")
        has_text(t, text, "var private p7_folded_builtins__sized : uint8[2]\n")
        has_text(t, text, "var private p7_folded_builtins__chosen_global : int = 64\n")
    }
    t |> run("the checked arithmetic builtins: operands and result of any integer types, the typed spellings, an operand as the result") @(t : T?) {
        let text = same_as_native(t, "p7_overflow_builtins", "")
        has_text(t, text, "let o : int = int_of(c_mul_overflow(sc, sc, addr(r)))")
        has_text(t, text, "o = int_of(c_sub_overflow(1ul, 2ul, addr(ur)))")
        has_text(t, text, "    n++\n    if (c_add_overflow(a, n, addr(a))) \{\n")
        has_text(t, text, "require c_runtime/c_builtins\n")
    }
    t |> run("what the lowering refuses, each naming the construct") @(t : T?) {
        let nested = "#define C(x) __builtin_classify_type(x)\n#define T(a, b) __builtin_types_compatible_p(a, b)\n"
        rejects(t, "classify_split", nested + "#define BOTH(a, b) (C(a) + C(b))\nint main(void) \{ int i = 0; double d = 0; return BOTH(i, d) - 9; \}\n", "two `__builtin_classify_type` of one macro expansion that clang values apart are not lowered")
        rejects(t, "compatible_split", nested + "#define BOTH(a, b, c) (T(a, b) + T(a, c))\nint main(void) \{ return BOTH(int, int, char) - 1; \}\n", "two `__builtin_types_compatible_p` of one macro expansion that clang values apart are not lowered")
        // clang's 4 is not GCC's 1: a plain, a qualified and a typedef'd `_Bool`; a pointer to one is clang's value
        let of_bool = "`__builtin_classify_type` of a `_Bool` is not lowered (clang's value is not GCC's)"
        rejects(t, "classify_bool", "int main(void) \{ _Bool b = 1; return __builtin_classify_type(b) - 1; \}\n", of_bool)
        rejects(t, "classify_const_bool", "int main(void) \{ const _Bool b = 1; return __builtin_classify_type(b) - 1; \}\n", of_bool)
        rejects(t, "classify_bool_typedef", "typedef _Bool flag;\nint main(void) \{ flag b = 1; return __builtin_classify_type(b) - 1; \}\n", of_bool)
        runs_clean(t, "classify_bool_pointer", "int main(void) \{ _Bool b = 1; _Bool *p = &b; return __builtin_classify_type(p) - 5; \}\n")
        // a pasted spelling is no token of the file's text: the pass gives the trait no value
        rejects(t, "compatible_pasted", "#define TC(a, b) __builtin_types_##compatible_p(a, b)\nint main(void) \{ return TC(int, int) - 1; \}\n", "`__builtin_types_compatible_p`: libclang gives no value at this location")
        let refused = "over an enum or a `_Bool` is not lowered yet"
        rejects(t, "overflow_enum", "enum E \{ A, B \};\nint main(void) \{ enum E e = B; int r; return __builtin_add_overflow(e, 1, &r); \}\n", "`__builtin_add_overflow` {refused}")
        rejects(t, "overflow_bool", "int main(void) \{ _Bool b = 1; int r; return __builtin_sub_overflow(1, b, &r); \}\n", "`__builtin_sub_overflow` {refused}")
        rejects(t, "overflow_bool_result", "int main(void) \{ _Bool r; return __builtin_mul_overflow(1, 1, &r); \}\n", "`__builtin_mul_overflow` {refused}")
        // a function of the program whose name ends alike is the program's own
        runs_clean(t, "own_overflow", "enum E \{ A, B \};\nstatic int my_overflow(enum E e, _Bool b) \{ return e == B && b; \}\nint main(void) \{ return my_overflow(B, 1) - 1; \}\n")
    }
    rmdir_rec(work_root)
    work_root = ""
}

[test]
def test_c11_forms(t : T?) {
    t |> run("a generic selection, an incomplete enum, a bitfield of enum type, an anonymous member's initializer and a statement expression") @(t : T?) {
        let text = same_as_native(t, "p7_c11_forms", "")
        // the selected association alone: the callee, a value, an lvalue; the controlling `i++` is gone
        has_text(t, text, "    let picked : int = p7_c11_forms__twice(7)\n    printf(cstr(\"%d %d %d %d %d\\n\"), 1, 2, 3, 4, 9)\n")
        has_text(t, text, "    printf(cstr(\"%d %d %s\\n\"), picked, i, cstr(\"long\"))\n")
        has_text(t, text, "    i = 4\n    return i\n")
        has_text(t, text, "var nowhere : int?\nvar nowhere_const : int?\n")
        // the field is the enum's integer, signed as clang chose; the units are an integer's
        has_text(t, text, "[c_bitfields(code = 8, flag = 1, sign = 3)]\nstruct node \{\n    next : node?\n    code, flag : uint\n    sign : int\n\}\n")
        has_text(t, text, "[c_union(c = 4)]\nstruct packed_code \{\n    c : uint\n")
        has_text(t, text, "_bits0 = (uint(code.TOP) & 0xffu) | ((1u & 0x1u) << 8u) | ((uint(int(sign.NEG)) & 0x7u) << 9u))")
        has_text(t, text, "    u.c = uint(code.LOW)\n")
        // a read converts to the enum, a store from it; a store's value is the member read back
        has_text(t, text, "    c_switch(enum_from_int(type<code>, int(n.code))) \{\n")
        has_text(t, text, "    n.code = uint(code.TOP)\n    n.sign = int(sign.NEG)\n    got = enum_from_int(type<code>, int(n.code))\n")
        has_text(t, text, "    n.code = uint(code.LOW)\n    got = enum_from_int(type<code>, int(n.code))\n    n.code = uint(int(n.code) | 4)\n")
        has_text(t, text, "    local._anon0 = anon_30(a = 1u8, b = 2u8)\n")
        has_text(t, text, "    braced._anon0 = anon_30(a = 6u8, b = 5u8)\n    designated._anon0 = anon_30(a = 7u8, b = 8u8)\n")
        // an assigned block ends in the store, through parentheses; a `void` conditional is an `if`
        has_text(t, text, "    \{\n        var k : int = n\n        while (k > 10) \{\n            k -= 10\n        \}\n        r = k\n    \}\n")
        has_text(t, text, "    if (r > 5) \{\n        printf(cstr(\"high %d\\n\"), r)\n    \} else \{\n        var k : int = r\n")
        has_text(t, text, "    \{\n        let twice_r : int = 2 * r\n        r = twice_r + 1\n    \}\n")
    }
    t |> run("what the lowering refuses, each naming the construct") @(t : T?) {
        let node = "enum E \{ A, B, C \};\nstruct S \{ enum E e : 4; \};\n"
        rejects(t, "enum_bitfield_step", node + "int main(void) \{ struct S s = \{ A \}; s.e++; return s.e - B; \}\n", "a step of a bitfield of enum type is not lowered yet")
        rejects(t, "block_into_bitfield", node + "int main(void) \{ struct S s = \{ A \}; s.e = (\{ enum E v = B; v; \}); return s.e - B; \}\n", "a statement expression that does not end in a value of its target's type is not lowered yet")
        rejects(t, "block_shadows_target", "int main(void) \{ int x = 1; x = (\{ int x = 2; x + 1; \}); return x - 3; \}\n", "a statement expression assigned to an object named like a variable its block declares is not lowered yet")
        // a value used anywhere else is still no statement
        rejects(t, "block_operand", "int main(void) \{ int x = 1; return (\{ int y = x; y; \}) - 1; \}\n", "unsupported expression `StmtExpr`")
        rejects(t, "block_conditional_value", "int main(void) \{ int x = 1; x = x ? (\{ int y = x; y; \}) : 2; return x - 1; \}\n", "unsupported expression `StmtExpr`")
        // a named member of a union still takes one value
        runs_clean(t, "union_named", "union U \{ struct \{ char a, b; \}; int whole; \};\nint main(void) \{ union U u = \{ .whole = 3 \}; return u.whole - 3; \}\n")
    }
    rmdir_rec(work_root)
    work_root = ""
}
