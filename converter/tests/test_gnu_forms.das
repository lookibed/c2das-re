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
//! libclang resolves, `__extension__` is its operand. Each fixture prints what its native build
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
        t |> success(!(text |> contains("c_switch(x)")) && !(text |> contains("c_switch(v)")), text)
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
        // a type name the libclang pass reads no type of
        rejects(t, "typeof_sizeof", "int main(void) \{ long x = 1; return (int) sizeof(typeof(x) *) - 8; \}\n", "`typeof (x)`: a `typeof` libclang resolves to no one type")
        rejects(t, "typeof_array", "int main(void) \{ int arr[3] = \{ 1, 2, 3 \}; typeof(arr) *p = &arr; return (*p)[0] - 1; \}\n", "`typeof (arr) *`: a `typeof` of a function, an array or a pointer to one (`int[3]`) under a declarator is not lowered yet")
        rejects(t, "typeof_fn_pointer", "static int one(void) \{ return 1; \}\nint main(void) \{ int (*fp)(void) = one; typeof(fp) *pp = &fp; return (*pp)() - 1; \}\n", "`typeof (fp) *`: a `typeof` of a function, an array or a pointer to one (`int (*)(void)`) under a declarator is not lowered yet")
    }
    rmdir_rec(work_root)
    work_root = ""
}
