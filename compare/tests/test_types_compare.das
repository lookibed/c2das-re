options gen2
options stack = 262144
require dastest/testing_boost public
require strings
require daslib/strings_boost
require ../types/types_compare.das
require ../../converter/cir.das

//! `compare/types/types_compare.das`: the structural names, the first difference, Dumper A's
//! declaration order rebuilt with its hoisted declarations, a run's counts, and the fixtures of
//! `compare/types/fixtures/` through Dumper A and the builder under both dialects.

let FIXTURES = "compare/types/fixtures"

// a C-IR type table: int, short, char, a pointer to char, `int (char *, ...)`, `short ()`, the
// typedef `T` of short, and an int of a second spelling
def private sample_types() : array<CirType> {
    var f = CirType(k = "func", ret = 0, variadic = true)
    f.params |> push(3)
    return <- [CirType(k = "int", w = 32, is_signed = true, spell = "int"), CirType(k = "int", w = 16, is_signed = true, spell = "short"),
               CirType(k = "int", w = 8, is_signed = false, spell = "char"), CirType(k = "ptr", to = 2), f, CirType(k = "func", ret = 1),
               CirType(k = "typedef", name = "T", to = 1), CirType(k = "array", elem = 2, count = -1)]
}

[test(description = "a type's structural name spells each part through its parts' names, the same type alike in any table")]
def test_type_name(t : T?) {
    let types <- sample_types()
    t |> equal(join(table_names(types), " "), "int/32s short/16s char/8u ptr(char/8u) func(int/32s;ptr(char/8u);...) func(short/16s;) typedef(T=short/16s) array(char/8u,-1)")
    t |> equal(type_name(types, 9), "?")
    let rec <- [CirType(k = "struct", name = "S")]
    t |> equal(type_name(rec, 0), "struct S")
    t |> equal(type_name([CirType(k = "void")], 0), "void")
    t |> success(has_aggregate(rec))
    t |> success(!has_aggregate(types))
}

[test(description = "the first difference of two name lists: a differing entry, either side longer, none")]
def test_first_difference(t : T?) {
    t |> equal(first_difference(["a", "b"], ["a", "c"]), "entry 1: builder b, Dumper A c")
    t |> equal(first_difference(["a", "b"], ["a"]), "entry 1: builder b, Dumper A has 1 entries")
    t |> equal(first_difference(["a"], ["a", "c"]), "entry 1: Dumper A c, builder has 1 entries")
    t |> equal(first_difference(["a"], ["a"]), "")
}

// a statement of kind `s` at line `line` of `t.c`, of type `ty` for a `decl`
def private stmt(s : string; line : int; ty : int = -1) : CirStmt? => new CirStmt(s = s, t = ty, loc = CirLoc(file = "t.c", line = line, col = 1))

[test(description = "Dumper A's declaration order rebuilt: a typedef's target before it, a function's type and parameters before its body, and the static it hoisted and the block function it declared placed by their lines among the body's statements, nested statements included")]
def test_declaration_order(t : T?) {
    var tu : CirTu
    tu.types <- sample_types()
    var inner = stmt("compound", 5)
    inner.body <- [stmt("null", 5), stmt("decl", 6, 2)]
    var body = stmt("compound", 3)
    body.body <- [stmt("decl", 4, 3), inner]
    var main = new CirDecl(k = "func", t = 4, loc = CirLoc(file = "t.c", line = 3, col = 1), body = body)
    main.params |> push(CirParam(name = "s", t = 3))
    // a typedef; a static hoisted from main's body, line 5, and a block declaration of a function
    // there, line 7, both ahead of main
    tu.decls <- [new CirDecl(k = "typedefdecl", t = 6, loc = CirLoc(file = "t.c", line = 1, col = 1)),
                 new CirDecl(k = "global", t = 7, from_func = "main", loc = CirLoc(file = "t.c", line = 5, col = 5)),
                 new CirDecl(k = "func", t = 5, loc = CirLoc(file = "t.c", line = 7, col = 5)), main]
    t |> equal(join(declaration_order(tu), " "), "short/16s typedef(T=short/16s) int/32s char/8u ptr(char/8u) func(int/32s;ptr(char/8u);...) array(char/8u,-1) func(short/16s;)")
    delete_tu(tu)
}

[test(description = "a run's counts: Dumper A failed, aggregates refused or typed, scalar-only refused, agreeing whole or by declarations, differing")]
def test_count(t : T?) {
    var n : TypesTotals
    t |> equal(count_types(n, TypesResult(unit = "a.c", dialect = "linux", dumper_error = "boom")), "a.c [linux]: Dumper A failed: boom")
    t |> equal(count_types(n, TypesResult(unit = "b.c", dialect = "msvc", aggregate = true, builder_error = "builder: x")), "")
    t |> equal(count_types(n, TypesResult(unit = "c.c", dialect = "msvc", aggregate = true)), "c.c [msvc]: aggregates in Dumper A's table, but the builder typed the unit")
    t |> equal(count_types(n, TypesResult(unit = "d.c", dialect = "linux", builder_error = "parser: y")), "d.c [linux]: refused: parser: y")
    t |> equal(count_types(n, TypesResult(unit = "e.c", dialect = "linux", declarations = true, whole = true)), "")
    t |> equal(count_types(n, TypesResult(unit = "f.c", dialect = "linux", declarations = true)), "")
    t |> equal(count_types(n, TypesResult(unit = "g.c", dialect = "linux", difference = "entry 0: z")), "g.c [linux]: differs: entry 0: z")
    t |> equal(describe_types_totals("all", n), "all: 7 units, 1 Dumper A failed, 2 with aggregates, 4 scalar-only: 2 declaration order agrees (1 whole table), 1 differ, 1 refused")
}

// the fixture `name` compared under `dialect` as `whole/declarations/aggregate`, the builder's
// error after it when it has one
def private compared(name, dialect : string) : string {
    let r = compare_types("{FIXTURES}/{name}", "compare/work/types", target_by_name(dialect))
    return "Dumper A: {r.dumper_error}" if (!empty(r.dumper_error))
    let shape = "{r.whole}/{r.declarations}/{r.aggregate}"
    return empty(r.builder_error) ? shape : "{shape} {r.builder_error}"
}

[test(description = "the fixtures through Dumper A and the builder under both dialects: declarations alone agree whole, an expression type first agrees by declarations, an aggregate and a constant array size refused", timeout = 600)]
def test_fixtures(t : T?) {
    for (dialect in ["linux", "msvc"]) {
        t |> run(dialect) @(t : T?) {
            t |> equal(compared("decl_order.c", dialect), "true/true/false")
            t |> equal(compared("expr_first.c", dialect), "false/true/false")
            t |> equal(compared("aggregate.c", dialect), "false/false/true builder: {FIXTURES}/aggregate.c:2:1: a struct type is not typed yet")
            t |> equal(compared("refused.c", dialect), "false/false/false builder: {FIXTURES}/refused.c:2:11: an array size other than an integer literal is not typed yet")
            t |> equal(compared("redeclared.c", dialect), "true/true/false")
        }
    }
}

[test(description = "the declaration comparison holds the builder to every entry a declaration interned: those no rebuilt declaration names, in Dumper A's order; never to an entry only expressions reach; never past an entry Dumper A lacks")]
def test_declaration_difference(t : T?) {
    let order <- ["short/16s", "typedef(T=short/16s)", "void", "func(void;)"]
    let theirs <- ["short/16s", "typedef(T=short/16s)", "void", "func(void;)", "long/64s", "ptr(char/8u)"]
    var expression_only : table<string; bool>
    expression_only["ptr(char/8u)"] = true
    let agree <- ["short/16s", "typedef(T=short/16s)", "void", "func(void;)", "long/64s"]
    t |> equal(declaration_difference(agree, order, theirs, expression_only), "")
    let dropped <- ["short/16s", "typedef(T=short/16s)", "void", "func(void;)"]
    t |> equal(declaration_difference(dropped, order, theirs, expression_only), "Dumper A long/64s (interned by a declaration no rebuilt declaration names), which the builder lacks")
    let extra <- ["short/16s", "typedef(T=short/16s)", "void", "func(void;)", "long/64s", "int/32s"]
    t |> equal(declaration_difference(extra, order, theirs, expression_only), "builder int/32s, which Dumper A's declarations do not intern")
    let missing <- ["short/16s", "typedef(T=short/16s)", "func(void;)", "long/64s"]
    t |> equal(declaration_difference(missing, order, theirs, expression_only), "Dumper A void, which the builder lacks")
    let swapped <- ["typedef(T=short/16s)", "short/16s", "void", "func(void;)", "long/64s"]
    t |> equal(declaration_difference(swapped, order, theirs, expression_only), "in the rebuilt order, entry 0: builder typedef(T=short/16s), Dumper A short/16s")
    let theirs2 <- ["short/16s", "typedef(T=short/16s)", "void", "func(void;)", "long/64s", "int/32s"]
    let extras_swapped <- ["short/16s", "typedef(T=short/16s)", "void", "func(void;)", "int/32s", "long/64s"]
    let none : table<string; bool>
    t |> equal(declaration_difference(extras_swapped, order, theirs2, none), "among the entries no rebuilt declaration names, entry 0: builder int/32s, Dumper A long/64s")
}

