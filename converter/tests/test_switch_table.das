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

//! `--switch-dispatch table` (ruling 38 addendum 30): a dense switch is flat, a jump to one das
//! label per case and no loop, flag or case test; a range with values no case holds jumps through
//! a module-level table. The fixture prints what its native build prints under every tier, and
//! the text carries each shape's form.

let FIXTURE = "converter/tests/fixtures/p9_switch_table.c"
let TABLE_TIERS = fixed_array("interp", "jit", "aot")

var work_root : string
var table_result : ConvertResult

// the fixture converted under `switch_dispatch` ("" for the default) into `<work_root>/<name>`
def converted(name, switch_dispatch : string) : ConvertResult {
    if (empty(work_root)) {
        var dir_error : string
        work_root = create_temp_directory("c2das_switch_table", dir_error)
    }
    return <- convert(FIXTURE, path_join(work_root, name), "linux", "", "", "", "", "", switch_dispatch)
}

// the das text of the fixture under table, converted once
def table_text : string {
    if (empty(table_result.das_path)) {
        delete table_result
        table_result <- converted("table", "table")
    }
    return table_result.das_text
}

// the program output of `das_path` under `tier`, its exit code in `rc`
def ran(das_path, tier, name : string; var rc : int&) : string {
    var out : string
    rc = run_tier(das_path, tier, path_join(work_root, "{name}_{tier}"), out, CONVERTED_MODULES, 900.0)
    // the JIT reports its compilation on `info` lines among the program's output
    return join([for (ln in split(out, "\n")); ln; where !(ln |> starts_with("[I] "))], "\n")
}

// the text of function `name` of the fixture in `text`, its remap tables included
def function_text(text, name : string) : string {
    let head = text |> find("def private p9_switch_table__{name}(")
    let tables = text |> find("let private _p9_switch_table__{name}_cases")
    let from = tables >= 0 ? tables : head
    return head < 0 ? "" : slice(text, from, text |> find("\n\}\n", head))
}

// the fixture with the body of `entered`, which only table lowers, a plain `return`: its path
def without_entered : string {
    let source = fread(FIXTURE)
    let head = source |> find("static int entered(int x, int k) \{\n")
    let path = path_join(work_root, "p9_switch_table_chain.c")
    fwrite(path, slice(source, 0, head) + "static int entered(int x, int k) \{\n    return x + k;\n\}\n" + slice(source, source |> find("\n\}\n", head) + 3))
    return path
}

def has_text(t : T?; text, needle : string) {
    t |> success(text |> contains(needle), "missing `{needle}` in:\n{text}")
}

[test]
def test_switch_table_runs(t : T?) {
    let text = table_text()
    let native = native_run(default_clang(), ["-w", "-funsigned-char"], FIXTURE, path_join(work_root, "native"), 60.0)
    let das_path = table_result.das_path
    let error = table_result.error
    let native_ok = native.built && native.rc == 0
    let want = native.output
    t |> run("the fixture converts under table and prints what its native build prints under the interpreter, the JIT and the AOT host") @(t : T?) {
        t |> equal(error, "")
        t |> success(native_ok, want)
        for (tier in TABLE_TIERS) {
            var rc = -1
            let out = ran(das_path, tier, "table", rc)
            t |> equal(rc, 0, "{tier}: {out}")
            t |> equal(out, want, tier)
        }
    }
    t |> run("a sparse switch, one under 8 values and one past int keep the chain's form") @(t : T?) {
        for (fn in ["sparse", "small", "past_int"]) {
            let kept = function_text(text, fn)
            t |> success(kept |> contains("    c_switch(x) \{\n") && !(kept |> contains("label ")), kept)
        }
    }
    t |> run("chain, the default, refuses the switch a goto both enters and re-dispatches, and spells no table and no jump over the rest of the fixture, naming Duff's device nowhere") @(t : T?) {
        let refused <- converted("chain_refused", "")
        t |> success(refused.error |> contains("a switch spelled open, for a goto into its body or a case label below its level, that a goto from another case re-dispatches is not lowered"), refused.error)
        let chain <- convert(without_entered(), path_join(work_root, "chain"), "linux")
        t |> equal(chain.error, "")
        for (gone in ["_cases", "goto _cond", "goto int(_cond", "Duff"]) {
            t |> success(!(chain.das_text |> contains(gone)), gone)
        }
        var rc = -1
        t |> equal(ran(chain.das_path, "interp", "chain", rc), native_run(default_clang(), ["-w", "-funsigned-char"], without_entered(), path_join(work_root, "native_chain"), 60.0).output)
    }
}

[test]
def test_switch_table_jumps(t : T?) {
    let text = table_text()
    t |> run("a range every value of which is a case jumps by the value past a bounds guard to a label per value, a case falling into the next, `break` a goto to the end label, with no loop, flag, case test or table") @(t : T?) {
        let full = function_text(text, "full")
        has_text(t, full, "    let _cond = x\n    if (_cond < 3 || _cond > 10) \{\n        goto label 9\n    \}\n    goto _cond - 2\n    label 1:  // case 3\n    r += 1\n    label 2:  // case 4\n    r += 10\n    goto label 9\n    label 3:  // case 5\n    label 4:  // case 6\n")
        // a `break` under an `if`, a `return`, the last case falling off the end
        has_text(t, full, "    if (r > 500) \{\n        goto label 9\n    \}\n    r = -1\n    goto label 9\n    label 6:  // case 8\n    return -8\n")
        has_text(t, full, "    label 8:  // case 10\n    r += 10000\n    label 9:  // switch end\n    return r")
        for (gone in ["while (true)", "_flag", "_cond ==", "_cases", "c_switch"]) {
            t |> success(!(full |> contains(gone)), "{gone} in:\n{full}")
        }
        // `default` in the middle takes the guard's label, a case falling into it
        has_text(t, function_text(text, "full_default"), "        goto label 10\n    \}\n    goto _cond + 2\n    label 2:  // case 0\n    r = 1\n    goto label 1\n    label 3:  // case 1\n    r = 2\n    label 10:  // default\n    r += 500\n    goto label 1\n")
        // a negative low value, every case returning: no end label and no return after it
        has_text(t, function_text(text, "negative_full"), "    if (_cond < -3 || _cond > 4) \{\n        goto label 10\n    \}\n    goto _cond + 5\n    label 2:  // case -3\n    return 1\n")
        has_text(t, function_text(text, "negative_full"), "    label 10:  // default\n    return 9")
    }
    t |> run("a range with values no case holds jumps through a module-level table of label numbers before its function, one label per run of case labels, the values no case holds and those outside the range to `default`") @(t : T?) {
        let holes = function_text(text, "holes")
        has_text(t, holes, "let private _p9_switch_table__holes_cases = fixed_array<int>(2, 3, 3, 4, 5, 6, 7, 8, 9)\n\ndef private p9_switch_table__holes(op : int; x : int) : int \{\n")
        has_text(t, holes, "    let _cond = op\n    goto _p9_switch_table__holes_cases?[_cond - 2] ?? 5\n    label 2:  // case 2\n    r += 1\n    label 3:  // case 3, case 4\n    r += 10\n    goto label 10\n")
        // a goto into the neighbouring case is a goto to its C label, `default` stands in the middle
        has_text(t, holes, "    if (x != 0) \{\n        goto label 1\n    \}\n    goto label 10\n    label 5:  // default\n    r += 1000\n    goto label 10\n    label 6:  // case 7\n    r += 20\n    label 1:  // in7\n    r += 5\n")
        for (gone in ["while (true)", "_flag", "_goto", "_cond ==", "re-dispatch", "if (_cond <"]) {
            t |> success(!(holes |> contains(gone)), "{gone} in:\n{holes}")
        }
        // no `default`: the end label takes its place, and the last case's `break` is dropped
        let no_default = function_text(text, "no_default")
        has_text(t, no_default, "fixed_array<int>(1, 2, 9, 3, 4, 5, 9, 6, 7, 8)\n")
        has_text(t, no_default, "    goto _p9_switch_table__no_default_cases?[_cond - 10] ?? 9\n")
        has_text(t, no_default, "    label 8:  // case 19\n    r = 19\n    label 9:  // switch end\n    return r")
        // a negative low value is added
        has_text(t, function_text(text, "negative"), "    goto _p9_switch_table__negative_cases?[_cond + 4] ?? 9\n")
    }
    t |> run("the table is indexed in the condition's type when that is int, uint, int64 or uint64, and by `int(_cond)` for an enum; a label names its enumerator or character") @(t : T?) {
        has_text(t, function_text(text, "wide"), "    goto _p9_switch_table__wide_cases?[_cond - 20l] ?? 9\n")
        has_text(t, function_text(text, "low"), "    goto _p9_switch_table__low_cases?[_cond - 1u] ?? 9\n")
        has_text(t, function_text(text, "wide_low"), "    goto _p9_switch_table__wide_low_cases?[_cond] ?? 9\n")
        let ops = function_text(text, "ops")
        has_text(t, ops, "fixed_array<int>(1, 2, 3, 4, 4, 5, 6, 7, 9, 8)\n")
        has_text(t, ops, "    let _cond = op\n    goto _p9_switch_table__ops_cases?[int(_cond)] ?? 9\n    label 1:  // case A\n")
        has_text(t, ops, "    label 4:  // case D, case E\n")
        has_text(t, function_text(text, "op_names"), "    if (int(_cond) < 0 || int(_cond) > 9) \{\n        goto label 11\n    \}\n    goto int(_cond) + 1\n    label 1:  // case A\n")
        has_text(t, function_text(text, "letters"), "        goto _p9_switch_table__letters_cases?[_cond - 97] ?? 9\n        label 1:  // case 'a'\n")
    }
}

[test]
def test_switch_table_shapes(t : T?) {
    let text = table_text()
    t |> run("a switch in another's case takes its own table and labels, a goto from its `default` reaches the outer one's label; a sparse inner one keeps c_switch") @(t : T?) {
        let nested = function_text(text, "nested")
        has_text(t, nested, "let private _p9_switch_table__nested_cases = fixed_array<int>(2, 3, 4, 5, 6, 7, 8, 10, 9)\nlet private _p9_switch_table__nested_cases2 = fixed_array<int>(12, 13, 14, 14, 20, 15, 16, 17, 18, 19)\n\ndef private")
        has_text(t, nested, "    label 3:  // case 1\n    let _cond2 = y\n    goto _p9_switch_table__nested_cases2?[_cond2] ?? 20\n    label 12:  // case 0\n    r += 10\n    label 13:  // case 1\n")
        has_text(t, nested, "    label 20:  // default\n    goto label 1\n    label 21:  // switch end\n    r += 20000\n    label 4:  // case 2\n    label 1:  // two\n")
        has_text(t, nested, "    label 6:  // case 4\n    c_switch(y) \{\n")
        // a dense switch in a small one's case: its labels in the c_switch arm, `continue` the loop's
        has_text(t, function_text(text, "in_small"), "            case(1) \{\n                let _cond2 = i\n                goto _p9_switch_table__in_small_cases?[_cond2] ?? 9\n                label 1:  // case 0\n")
        has_text(t, function_text(text, "in_small"), "                label 3:  // case 2\n                r += 3\n                continue\n")
        has_text(t, function_text(text, "in_small"), "                label 10:  // switch end\n                r += 1000\n                break\n            \}\n")
    }
    t |> run("a dense switch that a goto enters from outside and a goto from another case re-dispatches, which chain refuses, is flat too; a range from INT_MIN is indexed by the distance from it") @(t : T?) {
        let entered = function_text(text, "entered")
        has_text(t, entered, "    if (k != 0) \{\n        goto label 1\n    \}\n    let _cond = x\n    goto _p9_switch_table__entered_cases?[_cond] ?? 10\n")
        has_text(t, entered, "    label 4:  // case 2\n    r += 3\n    label 1:  // mid\n    r += 30\n    goto label 10\n")
        has_text(t, entered, "    label 6:  // case 4\n    r += 5\n    goto label 1\n")
        has_text(t, function_text(text, "from_min"), "    goto _p9_switch_table__from_min_cases?[_cond - (-2147483647 - 1)] ?? 9\n    label 1:  // case -2147483648\n")
    }
    t |> run("in a loop `continue` and a nested loop's `break` stay das's, the switch's `break` is the goto to its end, a goto out of the loop reaches its label") @(t : T?) {
        let looped = function_text(text, "looped")
        has_text(t, looped, "        label 4:  // case 2, case 3\n        r += 100\n        continue\n        label 5:  // case 4\n        goto label 1\n")
        has_text(t, looped, "            if (k == 2) \{\n                break\n            \}\n            r += 1000\n        \}\n        goto label 10\n")
        has_text(t, looped, "        label 9:  // default\n        r += 50000\n        label 10:  // switch end\n        r *= 2\n    \}\n    label 1:  // out\n")
    }
    t |> run("a `for` whose body continues and holds the flat switch at its level steps by the increment-first flag, not in a `finally` block, where the interpreter would land each label one statement early") @(t : T?) {
        let stepped = function_text(text, "stepped")
        has_text(t, stepped, "        var _f = false\n        while (true) \{\n            if (_f) \{\n                d -= 4ul\n            \}\n            _f = true\n")
        has_text(t, stepped, "                continue\n            \}\n            let _cond = (d >> 4ul) & 15ul\n            goto _p9_switch_table__stepped_cases?[_cond] ?? 9\n            label 1:  // case 0, case 3\n")
        t |> success(!(stepped |> contains("finally")), stepped)
        // the switch in a block that keeps its braces, one and two blocks under the body's
        for (fn, jump in ["in_block", "in_blocks"], ["                let _cond = i\n                goto _p9_switch_table__in_block_cases?[_cond - 1] ?? 9\n", "                    let _cond = i\n                    goto _p9_switch_table__in_blocks_cases?[_cond - 1] ?? 9\n"]) {
            let braced = function_text(text, fn)
            has_text(t, braced, "        var _f = false\n        while (true) \{\n            if (_f) \{\n                i++\n                p9_switch_table__steps += 2\n            \}\n            _f = true\n")
            has_text(t, braced, jump)
            t |> success(!(braced |> contains("finally")), braced)
        }
    }
    t |> run("a declaration a later case reads is declared before the jump, and a case's own, now at the switch's level, is renamed past a later block's") @(t : T?) {
        let scoped = function_text(text, "scoped")
        has_text(t, scoped, "    let _cond = x\n    var carry : int\n    goto _p9_switch_table__scoped_cases?[_cond - 1] ?? 9\n    label 1:  // case 1\n    r += 1\n    carry = 5\n")
        has_text(t, scoped, "    let u1 : int = x + 1\n")
    }
    t |> run("Duff's device is named, and jumps by the value into its loop's body from two case values on, the loop a label and a goto back") @(t : T?) {
        has_text(t, function_text(text, "duff"), "    let _cond = count % 8\n    // Duff's device: the jump enters the loop's body at its case\n    if (_cond < 0 || _cond > 7) \{\n        goto label 9\n    \}\n    goto _cond + 1\n    label 1:  // case 0\n    label 10:  // do\n    sum += 1\n    label 8:  // case 7\n")
        has_text(t, function_text(text, "duff"), "    n--\n    if (n > 0) \{\n        goto label 10\n    \}\n    label 9:  // switch end\n")
        has_text(t, function_text(text, "duff4"), "    // Duff's device: the jump enters the loop's body at its case\n    if (_cond < 0 || _cond > 3) \{\n")
        // a range with values no case holds: through a table, from two case values on too
        has_text(t, function_text(text, "duff_holes"), "let private _p9_switch_table__duff_holes_cases = fixed_array<int>(1, 4, 5, 3, 5, 2)\n")
        has_text(t, function_text(text, "duff_holes"), "    // Duff's device: the jump enters the loop's body at its case\n    goto _p9_switch_table__duff_holes_cases?[_cond] ?? 5\n    label 1:  // case 0\n    label 6:  // do\n")
    }
    rmdir_rec(work_root)
    work_root = ""
    delete table_result
}

// a program of two files, each with a static `pick` whose range has a hole, and a global and a
// local named like the first table of `plain`
def table_program(dir : string) : array<string> {
    mkdir(dir)
    let cases = join([for (v in [0, 1, 2, 3, 5, 6, 7, 8]); "case {v}: return {v + 1};"], " ")
    let first = path_join(dir, "tp_main.c")
    fwrite(first, "int other(int x);\nint _plain_cases = 40;\nstatic int pick(int x) \{ switch (x) \{ {cases} \} return 0; \}\nint plain(int x) \{ int _plain_cases2 = 2; switch (x) \{ {cases} \} return _plain_cases2; \}\nint main(void) \{ return pick(3) + other(5) + plain(4) + plain(9) + _plain_cases == 4 + 60 + 2 + 2 + 40 ? 0 : 1; \}\n")
    let second = path_join(dir, "tp_other.c")
    fwrite(second, "static int pick(int x) \{ switch (x) \{ {cases} default: return 0; \} \}\nint other(int x) \{ return pick(x) * 10 + pick(4); \}\n")
    return <- [first, second]
}

[test]
def test_switch_table_names(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_switch_table_names", dir_error)
    if (!empty(dir_error)) {
        t |> failure(dir_error)
        return
    }
    for (layout in ["source", "source-cut", "single"]) {
        t |> run("under the {layout} layout each function's table is private to its module under a name of its own there, past a global and a local of that name, and the program runs") @(t : T?) {
            let sources <- table_program(path_join(dir, layout))
            let res <- convert_program(sources, path_join(dir, "{layout}_out"), "linux", "", "", "", "", "main", layout, false, "", "table")
            t |> equal(res.error, "")
            var tables : array<string>
            for (name in ["tp_main.das", "tp_other.das"]) {
                let path = path_join(path_join(dir, "{layout}_out"), name)
                let text = stat(path).is_reg ? fread(path) : ""
                var inscope own <- [for (ln in split(text, "\n")); slice(ln, 0, ln |> find(" = ")); where ln |> starts_with("let private _")]
                sort(own)
                t |> success(length(own) < 2 || own[0] != own[1], text)
                tables |> push_from(own)
            }
            sort(tables)
            t |> equal(join(tables, ", "), layout == "single" ? "let private _plain_cases3, let private _tp_main_pick_cases, let private _tp_other_pick_cases" : "let private _pick_cases, let private _pick_cases, let private _plain_cases3")
            var out : string
            t |> equal(run_tier(res.das_path, "interp", path_join(dir, "{layout}_run"), out, CONVERTED_MODULES), 0, out)
        }
    }
    rmdir_rec(dir)
}

let LABELS_FIXTURE = "converter/tests/fixtures/p9_for_labels.c"

[test]
def test_for_labels(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_for_labels", dir_error)
    if (!empty(dir_error)) {
        t |> failure(dir_error)
        return
    }
    let native = native_run(default_clang(), ["-w", "-funsigned-char"], LABELS_FIXTURE, path_join(dir, "native"), 60.0)
    let want = native.output
    for (mode in ["", "goto", "table"]) {
        t |> run("under `{empty(mode) ? "chain" : mode}` a `for` that continues with a das label in its body's block or a plain block under it, an open switch or an unused C label, steps by the flag, has no `finally` block and prints its native build's output under the interpreter and the JIT") @(t : T?) {
            let res <- convert(LABELS_FIXTURE, path_join(dir, "out_{mode}"), "linux", "", "", "", "", "", mode)
            t |> equal(res.error, "")
            t |> success(!(res.das_text |> contains("finally")), res.das_text)
            t |> equal(length(split(res.das_text, "        var _f = false\n        while (true) \{\n            if (_f) \{\n                i++\n                p9_for_labels__steps++\n")) - 1, 3, res.das_text)
            has_text(t, res.das_text, "                let q : int = k + 1\n                r += q\n                label 1:  // never\n")
            for (tier in ["interp", "jit"]) {
                var out : string
                let rc = run_tier(res.das_path, tier, path_join(dir, "{mode}_{tier}"), out, CONVERTED_MODULES, 600.0)
                t |> equal(rc, 0, "{tier}: {out}")
                t |> equal(join([for (ln in split(out, "\n")); ln; where !(ln |> starts_with("[I] "))], "\n"), want, tier)
            }
        }
    }
    rmdir_rec(dir)
}
