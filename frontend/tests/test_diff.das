options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require ../diff.das

//! `frontend/diff.das`: two C-IR texts byte-compared after the normalization the spec allows -
//! the macro fields and the producer set aside, any other difference reported at its line.

// a unit of `int` with one function `main` returning the literal `v`; `macro` on the literal and a
// `macros` entry when `marked`, produced by `producer`
def private unit_text(v : string; marked : bool; producer : string) : string {
    var tu = CirTu(cir = CIR_VERSION, producer = producer, target = target_lp64_linux(), tu = "t.c")
    tu.types |> emplace(CirType(k = "int", w = 32, is_signed = true, spell = "int"))
    var params : array<int>
    var f = CirType(k = "func", ret = 0)
    f.params <- params
    tu.types |> emplace(f)
    var lit = new CirExpr(e = "int_lit", t = 0, v = v, macro = marked ? "ZERO" : "")
    if (marked) {
        lit.fn_macro |> emplace(CirMacroUse(m = 0, site = 1))
        tu.macros |> emplace(CirMacro(name = "ZERO", file = "t.c", line = 1, text = "#define ZERO() 0"))
    }
    var body = new CirStmt(s = "compound", loc = CirLoc(file = "t.c", line = 2, col = 1))
    body.body |> push(new CirStmt(s = "return", e = lit, loc = CirLoc(file = "t.c", line = 2, col = 3)))
    tu.decls |> push(new CirDecl(k = "func", name = "main", c_name = "main", t = 1, body = body, loc = CirLoc(file = "t.c", line = 2, col = 5)))
    let text = write_cir(tu)
    delete_tu(tu)
    return text
}

[test(description = "equal texts, texts differing in the macro fields and in the producer: no difference")]
def test_normalized_equal(t : T?) {
    t |> equal(cir_diff(unit_text("0", false, "c2das-dumper-c 0.1"), unit_text("0", false, "c2das-dumper-c 0.1")), "")
    t |> equal(cir_diff(unit_text("0", false, "c2das-dumper-c 0.1"), unit_text("0", true, "c2das-dumper-a 0.1 / clang 22.1.5")), "")
}

[test(description = "any other difference reported at its line with both texts' lines; a text the reader refuses named")]
def test_difference(t : T?) {
    let found = cir_diff(unit_text("0", false, "x"), unit_text("1", false, "x"))
    t |> equal(found, "line 43: ours \"v\": \"0\" | theirs \"v\": \"1\"")
    t |> success(starts_with(cir_diff("not json", unit_text("0", false, "x")), "ours: "))
    t |> success(starts_with(cir_diff(unit_text("0", false, "x"), "\{\}"), "theirs: "))
}
