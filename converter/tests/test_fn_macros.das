options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/json_boost
require daslib/strings_boost
require ../pipeline.das
require ../cir.das
require ../tiers.das

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
        t |> equal(printed |> find("57 5 7 2 6") >= 0, true, printed)
    }
    unsafe {
        delete tu
    }
    tu <- read_cir(res.cir_text, error)
    t |> run("the unit's macros: each function-like #define a whole expansion uses, with its file, line, text and the times its expansion holds each argument") @(t : T?) {
        t |> equal(error, "")
        let names <- [for (m in tu.macros); m.name]
        t |> equal(join(names, " "), "ADD1 FIELD SQ FIRST TONUM IS_INT TAG_OF PLUS_LOCAL CAST SETV SWAP TWICE BOTH FOURTH APPLY")
        let uses <- [for (m in tu.macros); "{m.name}={uses_text(m)}"]
        // through nested calls: IS_INT's `c` once through TAG_OF, TONUM's `c` twice, FOURTH's `x` four
        // times; APPLY calls `f`, and `x` passes through it: neither count is known
        t |> equal(join(uses, " "), "ADD1=1 FIELD=1 SQ=2 FIRST=1,0 TONUM=2,1 IS_INT=1 TAG_OF=1 PLUS_LOCAL=1 CAST=1,1 SETV=1,1 SWAP=2,2 TWICE=1 BOTH=2 FOURTH=4 APPLY=-1,-1")
        t |> equal(tu.macros[2].text, "#define SQ(x) ((x) * (x))")
        t |> equal(tu.macros[2].line, 9)
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
        let want <- [
            // A, B twice, B never (no copy of `9`), B in one branch with a nested expansion
            "bin ADD1#0(i)", "ref =0.0", "member FIELD#1(p)", "ref =1.0", "bin SQ#2(i)", "ref =2.0", "ref =2.0",
            "ref FIRST#3(i, 9) =3.0", "cond TONUM#4(p, n)", "bin IS_INT#5(c)", "member TAG_OF#6(c)", "ref =4.0 =5.0 =6.0",
            "ref =4.1", "ref =4.0",
            // C: the caller's local is no copy; the type argument has none
            "bin PLUS_LOCAL#7(i)", "ref =7.0", "cast CAST#8(int, 2.5)", "float_lit =8.1",
            // D: a do-while(0) and a block
            "do SETV#9(p, 6)", "ref =9.0", "int_lit =9.1", "compound SWAP#10(j, k)", "ref =10.0", "ref =10.0", "ref =10.1", "ref =10.1",
            // a body that is one call shares its node; calls side by side; a call inside an argument used twice
            "bin TWICE#11(i) ADD1#12((x) * 2)", "bin =12.0", "ref =11.0",
            "bin BOTH#13(i)", "bin ADD1#14(x)", "ref =13.0 =14.0", "bin ADD1#15(x)", "ref =13.0 =15.0",
            "bin FOURTH#16(i) SQ#17(SQ(x))", "bin SQ#18(x) =17.0", "ref =16.0 =18.0", "ref =16.0 =18.0", "bin SQ#19(x) =17.0", "ref =16.0 =19.0", "ref =16.0 =19.0",
            "bin IS_INT#20(p)", "member TAG_OF#21(c)", "ref =20.0 =21.0",
            // effectful arguments, an expansion as an argument, faulting arguments never evaluated
            "bin SQ#22(next())", "call =22.0", "call =22.0", "bin ADD1#23(ADD1(i))", "bin ADD1#24(i) =23.0", "ref =24.0",
            "ref FIRST#25(i, arr[3]) =25.0", "ref FIRST#26(i, 8 / j) =26.0", "ref FIRST#27(i, (*p).v) =27.0",
            // a parameter called: the function is a copy, the rest of the body is followed
            "bin APPLY#28(twice, i)", "ref =28.0", "ref =28.1", "bin ADD1#29(x)", "ref =28.1 =29.0"
        ]
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
