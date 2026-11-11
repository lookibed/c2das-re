options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../converter/tiers.das

//! A C function-like macro folded back into an `[inline] def` (the fn-macros research, docs/probe-findings.md
//! F104): one generic def, its parameters untyped, covers a macro expanded with arguments of different
//! types, in a module of its own as a header's macro would live, and runs alike under the interpreter,
//! the JIT, the JIT-linked executable and the AOT host of `converter/tiers.das`; the splice crosses the
//! module boundary, and binds a `let` copy for every argument that is a `var` variable.

// the header module: one def per macro shape of Lua's census (class A, B with an unused parameter,
// D with a statement body, a written argument), every parameter untyped but the written one
let private HEADER_SOURCE = "options gen2\noptions solid_context\nmodule fold_h public\n\nstruct TValue \{\n    value_ : int64\n    tt_ : uint8\n\}\n\nstruct GCNode \{\n    marked : uint8\n    tt_ : uint8\n\}\n\n// ttisinteger(o): one parameter, called with two record types and a const pointee\n[inline]\ndef ttisinteger(o) => int(o.tt_) == 3\n\n// cast_num(i): over int, int64 and uint8\n[inline]\ndef cast_num(i) => double(i)\n\n// luai_numadd(L, a, b): L is never evaluated; over double and int\n[inline]\ndef luai_numadd(L; a; b) => a + b\n\n// setivalue(obj, x): a statement body\n[inline]\ndef setivalue(var obj; x) \{\n    obj.value_ = int64(x)\n    obj.tt_ = uint8(3)\n\}\n\n// tonumberns(o, n): writes its second argument, a reference parameter\n[inline]\ndef tonumberns(o; var n : auto&) : bool \{\n    if (int(o.tt_) == 3) \{\n        n = double(o.value_)\n        return true\n    \}\n    return false\n\}\n\n// the same body as ttisinteger without [inline]\ndef ttis_plain(o) => int(o.tt_) == 3\n"

// the converted module's side: `var` and `let` arguments of each type; `{LOG}` is where the
// optimization log goes
let private MAIN_SOURCE = "options gen2\noptions solid_context\n\{LOG\}\nrequire fold_h\n\ndef run_all(var p : TValue?; q : TValue?; var nd : GCNode?; i : int; j : int64; k : uint8) : int \{\n    var s = 0\n    s += ttisinteger(p) ? 1 : 0\n    s += ttisinteger(q) ? 2 : 0\n    s += ttisinteger(nd) ? 4 : 0\n    s += ttis_plain(q) ? 0 : 8\n    let f = cast_num(i) + cast_num(j) + cast_num(k)\n    let d = luai_numadd(p, 1.5lf, f)\n    let e = luai_numadd(nd, i, 7)\n    setivalue(p, i)\n    setivalue(p, j + 1l)\n    var n = 0.0lf\n    if (tonumberns(q, n)) \{\n        s += int(n)\n    \}\n    return s + int(d) + e\n\}\n\n[export]\ndef main : int \{\n    var a = TValue(value_ = 10l, tt_ = uint8(3))\n    var b = TValue(value_ = 20l, tt_ = uint8(3))\n    var c = GCNode(marked = uint8(0), tt_ = uint8(3))\n    unsafe \{\n        print(\"\{run_all(addr(a), addr(b), addr(c), 2, 3l, uint8(4))\} \{a.value_\} \{int(a.tt_)\}\\n\")\n    \}\n    return 0\n\}\n"

let private FOLD_TIERS = fixed_array("interp", "jit", "exe", "aot")

// the program's two files in `work`; the entry path
def private write_program(work : string; log : bool) : string {
    fwrite(path_join(work, "fold_h.das"), HEADER_SOURCE)
    let entry = path_join(work, "fold_main.das")
    fwrite(entry, replace(MAIN_SOURCE, "\{LOG\}", log ? "options log_optimization = true" : ""))
    return entry
}

[test(description = "a generic [inline] def per macro shape gives the expanded C's results under every tier", timeout = 1200)]
def test_generic_inline_tiers(tt : T?) {
    let work = test_temp_dir()
    let entry = write_program(work, false)
    for (tier in FOLD_TIERS) {
        tt |> run("generic [inline] defs over differently typed arguments run under {tier} (F104)") @(t : T?) {
            var out : string
            t |> equal(run_tier(entry, tier, path_join(work, tier), out, CONVERTED_MODULES), 0, "{tier}: {out}")
            let lines <- [for (l in split(out, "\n")); strip(l); where !empty(strip(l))]
            // 1+2+4 tags, 20 read back, int(1.5 + 2 + 3 + 4) and 2 + 7; a.value_ set to j + 1
            t |> equal(!empty(lines) ? lines[length(lines) - 1] : "", "46 4 3", "{tier}: {out}")
        }
    }
}

[test(description = "the splice of a generic [inline] def crosses the module boundary and copies a var argument", timeout = 1200)]
def test_generic_inline_splice(tt : T?) {
    let work = test_temp_dir()
    let entry = write_program(work, true)
    var out : string
    let flags <- ["-no-module-cache"]
    let rc = run_tier(entry, "interp", path_join(work, "log"), out, CONVERTED_MODULES, 600.0, flags)
    var spliced = 0
    var declined = 0
    var plain = 0
    var var_copies = 0
    var let_in_place = 0
    for (l in split(out, "\n")) {
        spliced += l |> starts_with("INLINE ") && l |> contains(" into run_all") ? 1 : 0
        declined += l |> contains("DECLINED") ? 1 : 0
        plain += l |> contains("ttis_plain") && l |> contains(" into ") ? 1 : 0
        // `p` (a var parameter) is copied for ttisinteger, `q` (a let parameter) is read in place
        var_copies += l |> contains("_arg_o:") && l |> ends_with("TValue? const = p;") ? 1 : 0
        let_in_place += l |> contains("int(q.tt_) == 3") ? 1 : 0
    }
    tt |> run("every call of an [inline] def in the other module is spliced, none declined (F104)") @(t : T?) {
        t |> equal(rc, 0, out)
        t |> equal(spliced, 11, out)
        t |> equal(declined, 0, out)
    }
    tt |> run("a def without [inline] in the other module stays a call: the automatic inliner is same-module only (F104)") @(t : T?) {
        t |> equal(plain, 0, out)
    }
    tt |> run("a var argument binds a let copy at the splice, a let argument substitutes as written (F104)") @(t : T?) {
        t |> success(var_copies >= 1, out)
        t |> success(let_in_place >= 1, out)
    }
}
