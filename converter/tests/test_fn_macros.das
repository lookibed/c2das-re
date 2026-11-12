options gen2
// the dump and the C-IR text parse below the test's own frames: a deep tree overflows the default stack
options stack = 1048576
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/json_boost
require daslib/strings_boost
require ../pipeline.das
require ../cir.das
require ../tiers.das
require ../macro_fold.das

//! The C-IR's function-like macro fields (`docs/c-ir-spec.md` section 6.3): the unit's `macros`,
//! `fn_macro` on each whole expansion and `macro_args` on each copy of an argument, over a fixture
//! with one macro per class, nested and side-by-side expansions, effectful and faulting
//! arguments; the das text is the one it was before the fields existed.

let FIXTURE = "converter/tests/fixtures/p9_fn_macros.c"

var res : ConvertResult
var tu : CirTu
var error : string

// one line per marked node of `js` in preorder: its kind, each expansion it is (macro, site,
// argument texts) and each argument it copies (`site.k`)
def marks_of(js : JsonValue?; macros : array<string>; var out : array<string>) {
    if (js is _array) {
        for (kid in js as _array) {
            marks_of(kid, macros, out)
        }
        return
    }
    if (!(js is _object)) {
        return
    }
    let fm = js?["fn_macro"]
    let ma = js?["macro_args"]
    let has_fm = fm != null && fm is _array
    let has_ma = ma != null && ma is _array
    if (has_fm || has_ma) {
        let kind = js?["e"] ?? (js?["s"] ?? "")
        out |> push(build_string() $(var w) {
            w |> write(kind)
            if (has_fm) {
                for (u in fm as _array) {
                    let site = u?["site"] ?? 0l
                    w |> write(" {macros[int(u?["m"] ?? 0l)]}#{site}(")
                    var first = true
                    for (a in u?["args"] as _array) {
                        w |> write(first ? "" : ", ")
                        w |> write(a ?? "")
                        first = false
                    }
                    w |> write(")")
                }
            }
            if (has_ma) {
                for (a in ma as _array) {
                    let site = a?["site"] ?? 0l
                    let k = a?["k"] ?? 0l
                    w |> write(" ={site}.{k}")
                }
            }
        })
    }
    for (key in keys(js as _object)) {
        if (key != "fn_macro" && key != "macro_args") {
            marks_of(js?[key], macros, out)
        }
    }
}

def uses_text(m : CirMacro) : string => join([for (u in m.uses); "{u}"], ",")

// the marks of the fixture, one line per marked node in preorder (`marks_of`)
def want_marks() : array<string> {
    return <- [
        // A, B twice, B never (no copy of `9`), B in one branch with a nested expansion
        "bin ADD1#0(i)", "ref =0.0", "member FIELD#1(p)", "ref =1.0", "bin SQ#2(i)", "ref =2.0", "ref =2.0",
        "ref FIRST#3(i, 9) =3.0",
        // C: the caller's local is no copy; the type argument has none
        "cond TONUM#4(p, n)", "bin IS_INT#5(c)", "member TAG_OF#6(c)", "ref =4.0 =5.0 =6.0", "ref =4.1",
        "ref =4.0", "bin PLUS_LOCAL#7(i)", "ref =7.0", "cast CAST#8(int, 2.5)", "float_lit =8.1",
        // D: a do-while(0) and a block
        "do SETV#9(p, 6)", "ref =9.0", "int_lit =9.1", "compound SWAP#10(j, k)", "ref =10.0", "ref =10.0",
        "ref =10.1", "ref =10.1",
        // a body that is one call shares its node; calls side by side; a call inside an argument used twice
        "bin TWICE#11(i) ADD1#12((x) * 2)", "bin =12.0", "ref =11.0", "bin BOTH#13(i)", "bin ADD1#14(x)",
        "ref =13.0 =14.0", "bin ADD1#15(x)", "ref =13.0 =15.0", "bin FOURTH#16(i) SQ#17(SQ(x))",
        "bin SQ#18(x) =17.0", "ref =16.0 =18.0", "ref =16.0 =18.0", "bin SQ#19(x) =17.0", "ref =16.0 =19.0",
        "ref =16.0 =19.0", "bin IS_INT#20(p)", "member TAG_OF#21(c)", "ref =20.0 =21.0",
        // effectful arguments, an expansion as an argument, faulting arguments never evaluated
        "bin SQ#22(next())", "call =22.0", "call =22.0", "bin ADD1#23(ADD1(i))", "bin ADD1#24(i) =23.0",
        "ref =24.0", "ref FIRST#25(i, arr[3]) =25.0", "ref FIRST#26(i, 8 / j) =26.0",
        "ref FIRST#27(i, (*p).v) =27.0",
        // a parameter called: the function is a copy, the rest of the body is followed
        "bin APPLY#28(twice, i)", "ref =28.0", "ref =28.1", "bin ADD1#29(x)", "ref =28.1 =29.0",
        // the node of `ADD1(x) + ADD1(0)` is neither call's: it holds ADD1's `1` twice; S3(i) * 3
        // has no node of its own; SUB(y, x) takes the node holding `j` first; ADDK(K),
        // MUL2(i + 1), ADD(i ? 1 : 2, 3), offsetof, va_start, va_end and MAX leave no mark
        "bin S4#30(i)", "bin ADD1#31(x)", "ref =30.0 =31.0", "bin ADD1#32(0)", "int_lit =32.0",
        "bin ANTI#33(i, j)", "bin SUB#34(x, y)", "ref =33.0 =34.0", "ref =33.1 =34.1", "bin SUB#35(y, x)",
        "ref =33.1 =35.0", "ref =33.0 =35.1", "bin BIGGER#36(i, j)", "ref =36.0", "ref =36.1", "ref =36.0",
        "ref =36.1",
        // parentheses around one call: the node of both, the outer first
        "bin OUTP#37(i) ADD1#38(x)", "ref =37.0 =38.0",
        // SQ called twice with arguments of BOTH2's own text, each taking the node holding its
        // own `1` or `2`; IS_F and IS_V alike but for the constant their CHK names
        "bin BOTH2#39(i)", "bin SQ#40(x + 1)", "bin =40.0", "ref =39.0", "bin =40.0", "ref =39.0",
        "bin SQ#41(x + 2)", "bin =41.0", "ref =39.0", "bin =41.0", "ref =39.0",
        "bin EITHER#42(p)", "bin IS_F#43(c) CHK#44(c, TAGF)", "member TAG_OF#45(c)", "ref =42.0 =43.0 =44.0 =45.0",
        "int_lit =44.1", "bin IS_V#46(c) CHK#47(c, TAGV)", "member TAG_OF#48(c)", "ref =42.0 =46.0 =47.0 =48.0",
        "int_lit =47.1",
        // APPLY3's calls of ADD1 pass only `f(...)`, so no node is told apart and neither is marked
        "bin APPLY3#49(twice, i)", "ref =49.0", "ref =49.1", "ref =49.0"
    ]
}

[test]
def test_fn_macros(t : T?) {
    var dir_error : string
    let out = create_temp_directory("c2das_fn_macros", dir_error)
    if (!empty(dir_error)) {
        t |> failure(dir_error)
        return
    }
    delete res
    res <- convert(FIXTURE, out, "linux")
    t |> run("the fixture converts, and the program prints what the native build prints") @(t : T?) {
        t |> equal(res.ok, true, res.error)
        var printed : string
        t |> equal(run_tier(res.das_path, "interp", path_join(out, "interp"), printed, CONVERTED_MODULES), 0, printed)
        t |> equal(printed |> find("87 5 7 2 6") >= 0, true, printed)
    }
    unsafe {
        delete tu
    }
    tu <- read_cir(res.cir_text, error)
    t |> run("the unit's macros: each function-like #define a whole expansion uses, with its file, line, text and the times its expansion holds each argument") @(t : T?) {
        t |> equal(error, "")
        let names <- [for (m in tu.macros); m.name]
        t |> equal(join(names, " "), "ADD1 FIELD SQ FIRST TONUM IS_INT TAG_OF PLUS_LOCAL CAST SETV SWAP TWICE BOTH FOURTH APPLY S4 ANTI SUB BIGGER OUTP BOTH2 EITHER IS_F CHK IS_V APPLY3")
        let uses <- [for (m in tu.macros); "{m.name}={uses_text(m)}"]
        // through nested calls: IS_INT's `c` once through TAG_OF, TONUM's `c` twice, FOURTH's `x` four
        // times; APPLY calls `f`, and `x` passes through it: neither count is known; BIGGER calls a
        // system header's MAX, which the pass does not follow
        t |> equal(join(uses, " "), "ADD1=1 FIELD=1 SQ=2 FIRST=1,0 TONUM=2,1 IS_INT=1 TAG_OF=1 PLUS_LOCAL=1 CAST=1,1 SETV=1,1 SWAP=2,2 TWICE=1 BOTH=2 FOURTH=4 APPLY=-1,-1 S4=1 ANTI=2,2 SUB=1,1 BIGGER=-1,-1 OUTP=1 BOTH2=4 EITHER=2 IS_F=1 CHK=1,1 IS_V=1 APPLY3=-1,-1")
        t |> equal(tu.macros[2].text, "#define SQ(x) ((x) * (x))")
        t |> equal(tu.macros[2].line, 12)
        t |> equal(tu.macros[5].file |> ends_with("p9_fn_macros.h"), true, tu.macros[5].file)
        t |> equal(tu.macros[5].text, "#define IS_INT(c) (TAG_OF(c) == 3)")
        t |> equal(join(tu.macros[9].params, ","), "p,x")
    }
    t |> run("each whole expansion and each argument copy carries its marks; a split argument, a paste and a type argument leave none") @(t : T?) {
        let macros <- [for (m in tu.macros); m.name]
        var json_error : string
        var js = read_json(res.cir_text, json_error)
        var lines : array<string>
        marks_of(js?["decls"], macros, lines)
        delete_json(js)
        let want <- want_marks()
        t |> equal(join(lines, "\n"), join(want, "\n"))
    }
    t |> run("the marks leave the das text alone: every expansion is printed expanded") @(t : T?) {
        t |> equal(res.das_text |> find("    var sum : int = i + 1 + p.v + i * i + i + _t0\n") >= 0, true, res.das_text)
        t |> equal(res.das_text |> find("    sum += i * 2 + 1 + (i + 1 + (i + 1)) + i * i * (i * i) + i + 1 * 2 + int_of(p.tag == 3)\n") >= 0, true)
    }
    t |> run("the writer and the reader keep every field: the rewritten text is the text read") @(t : T?) {
        t |> equal(write_cir(tu), res.cir_text)
    }
}

// the verdict of every outermost expansion below expression `x` and statement `st` of a function
// whose scope is `scope`, `NAME:reason` (`NAME:fold` when it folds) in preorder
def verdicts_expr(tu : CirTu; x : CirExpr const?; scope : FoldScope; var out : array<string>) {
    if (x == null) {
        return
    }
    if (!empty(x.fn_macro)) {
        assume use = x.fn_macro[0]
        let site <- fold_expr_site(tu.macros[use.m], use, x, scope)
        out |> push("{tu.macros[use.m].name}:{empty(site.reason) ? "fold" : site.reason}")
    }
    for (part in fixed_array<CirExpr const?>(x.fn, x.base, x.i, x.a, x.b, x.c)) {
        verdicts_expr(tu, part, scope, out)
    }
    for (arg in x.args) {
        verdicts_expr(tu, arg, scope, out)
    }
}

def verdicts_stmt(tu : CirTu; st : CirStmt const?; scope : FoldScope; var out : array<string>) {
    if (st == null) {
        return
    }
    if (!empty(st.fn_macro)) {
        assume use = st.fn_macro[0]
        let site <- fold_stmt_site(tu.macros[use.m], use, st, scope)
        out |> push("{tu.macros[use.m].name}:{empty(site.reason) ? "fold" : site.reason}")
    }
    for (x in fixed_array<CirExpr const?>(st.init, st.e, st.cond, st.inc)) {
        verdicts_expr(tu, x, scope, out)
    }
    for (child in fixed_array<CirStmt const?>(st.init_s, st.then_s, st.else_s, st.body_s)) {
        verdicts_stmt(tu, child, scope, out)
    }
    for (child in st.body) {
        verdicts_stmt(tu, child, scope, out)
    }
}

// the names a statement tree declares, and the names it takes the address of
def scope_names(st : CirStmt const?; var scope : FoldScope) {
    if (st == null) {
        return
    }
    if (st.s == "decl") {
        scope.locals |> insert(st.name)
    }
    for (child in fixed_array<CirStmt const?>(st.init_s, st.then_s, st.else_s, st.body_s)) {
        scope_names(child, scope)
    }
    for (child in st.body) {
        scope_names(child, scope)
    }
}

var fold_unit : CirTu

[test]
def test_fold_verdicts(tt : T?) {
    var dir_error : string
    let out = create_temp_directory("c2das_fold_verdicts", dir_error)
    if (!empty(dir_error)) {
        tt |> failure(dir_error)
        return
    }
    let conv <- convert("converter/tests/fixtures/p9_fn_fold.c", out, "linux")
    var read_error : string
    unsafe {
        delete fold_unit
    }
    fold_unit <- read_cir(conv.cir_text, read_error)
    tt |> run("each outermost expansion of the fold fixture gets the verdict its node allows: A, B and D fold, every guard names its reason") @(t : T?) {
        t |> equal(read_error, "")
        var lines : array<string>
        for (d in fold_unit.decls) {
            if (d.k == "func" && d.body != null) {
                var scope = FoldScope(locals <- {for (p in d.params); p.name})
                scope_names(d.body, scope)
                // the fixture takes the address of `n1`, `n2`, `arr`, `t1`, `t2` only
                scope.addressed <- {"n1", "n2", "arr", "t1", "t2"}
                verdicts_stmt(fold_unit, d.body, scope, lines)
            }
        }
        t |> equal(join(lines, " "), "RET_IF:flow ADD1:fold SUB:fold SUB:fold GETA:fold OUTER:fold ADD1:fold SQ:fold SQ:fold SQ:fold KEEP:fold KEEP:fold PICK:fold SQ:faulting SQ:faulting SQ:faulting PICK:faulting KEEP:faulting ADD1:fold SQ:effects ADD2:order TWICE:fold TWICE:fold TWICE:fold SETV:fold BUMP:fold SETLEN:fold FLD:fold FLD:fold FLD:fold NEXT:fold NEXT:fold NEXT:fold ORD:order PLUS_LOCAL:capture SWAP:fold length:fold TAG:fold TAG:fold TONUM:fold TONUM:fold INC:fold BAD:order SWAP:order")
    }
}
