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

// an int literal `v`, its macro fields set when `marked`
def private lit(v : string; marked : bool) : CirExpr? {
    var x = new CirExpr(e = "int_lit", t = 0, v = v, macro = marked ? "M" : "")
    if (marked) {
        x.fn_macro |> emplace(CirMacroUse(m = 0, site = 1))
        x.macro_args |> emplace(CirMacroArg(site = 1, k = 0))
    }
    return x
}

// a statement `s` holding expression `e`
def private stmt_of(s : string; var e : CirExpr?; marked : bool) : CirStmt? {
    var st = new CirStmt(s = s, e = e, loc = CirLoc(file = "t.c", line = 3, col = 3))
    if (marked) {
        st.fn_macro |> emplace(CirMacroUse(m = 0, site = 2))
    }
    return st
}

// a unit whose every expression and statement position the C-IR writes holds a literal, each with
// its macro fields when `marked`: operands, a call's callee and arguments, a subscript, a member's
// base, list items, `va_arg`'s list, a compound literal's initializer, a branch's condition and
// statements, a loop's, a `for`'s initializer and step, a declaration's initializer, a global's
def private deep_text(marked : bool) : string {
    var tu = CirTu(cir = CIR_VERSION, producer = "x", target = target_lp64_linux(), tu = "t.c")
    tu.types |> emplace(CirType(k = "int", w = 32, is_signed = true, spell = "int"))
    var params : array<int>
    var f = CirType(k = "func", ret = 0)
    f.params <- params
    tu.types |> emplace(f)
    if (marked) {
        tu.macros |> emplace(CirMacro(name = "M", file = "t.c", line = 1, text = "#define M() 0"))
    }
    let m = marked
    var call = new CirExpr(e = "call", t = 0, fn = lit("1", m))
    call.args |> push(lit("2", m))
    var items = new CirExpr(e = "init_list", t = 0)
    items.init_items |> push(CirInitItem(pos = 0, v = lit("1", m)))
    var branch = stmt_of("if", null, m)
    branch.cond = lit("1", m)
    branch.then_s = stmt_of("expr", lit("2", m), m)
    branch.else_s = stmt_of("expr", lit("3", m), m)
    var loop = stmt_of("for", null, m)
    loop.init_s = stmt_of("expr", lit("1", m), m)
    loop.cond = lit("2", m)
    loop.inc = lit("3", m)
    loop.body_s = stmt_of("expr", lit("4", m), m)
    var decl = stmt_of("decl", null, m)
    decl.init = lit("5", m)
    var body = new CirStmt(s = "compound", loc = CirLoc(file = "t.c", line = 2, col = 1))
    body.body <- [stmt_of("expr", new CirExpr(e = "bin", t = 0, op = "add", a = lit("1", m), b = lit("2", m)), m),
                  stmt_of("expr", new CirExpr(e = "cond", t = 0, c = lit("1", m), a = lit("2", m), b = lit("3", m)), m),
                  stmt_of("expr", call, m),
                  stmt_of("expr", new CirExpr(e = "index", t = 0, base = lit("1", m), i = lit("2", m)), m),
                  stmt_of("expr", new CirExpr(e = "member", t = 0, base = lit("1", m)), m),
                  stmt_of("expr", items, m),
                  stmt_of("expr", new CirExpr(e = "va_arg", t = 0, list = lit("1", m)), m),
                  stmt_of("expr", new CirExpr(e = "compound_lit", t = 0, init = lit("1", m)), m),
                  branch, loop, decl]
    tu.decls <- [new CirDecl(k = "global", name = "g", c_name = "g", t = 0, init = lit("7", m), loc = CirLoc(file = "t.c", line = 1, col = 5)),
                 new CirDecl(k = "func", name = "main", c_name = "main", t = 1, body = body, loc = CirLoc(file = "t.c", line = 2, col = 5))]
    let text = write_cir(tu)
    delete_tu(tu)
    return text
}

[test(description = "the macro fields are set aside at every depth the C-IR writes: under operands, calls, subscripts, members, lists, `va_arg`, a compound literal, branches, loops, a declaration's and a global's initializer, and a statement's own")]
def test_normalized_deep(t : T?) {
    let plain = deep_text(false)
    let marked = deep_text(true)
    t |> success(plain != marked)
    t |> equal(cir_diff(marked, plain), "")
}
