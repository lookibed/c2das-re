options gen2
options stack = 262144
require dastest/testing_boost public
require strings
require daslib/strings_boost
require ../types/types_compare.das
require ../../converter/cir.das

//! `compare/types/types_compare.das`: the structural names, the first difference of two tables, of
//! two units' C-IR and of their conversion censuses, a run's counts, and the fixtures of
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

// a unit of the sample types and one function `main` of type 5 whose body returns `e`
def private unit_returning(var e : CirExpr?) : CirTu {
    var tu : CirTu
    tu.types <- sample_types()
    var body = new CirStmt(s = "compound")
    body.body |> push(new CirStmt(s = "return", e = e))
    tu.decls |> push(new CirDecl(k = "func", c_name = "main", t = 5, body = body))
    return <- tu
}

// `short` read from the reference `s`, then converted to `int`: an implicit cast pair
def private read_short() : CirExpr? => new CirExpr(e = "cast", t = 0, cast_kind = "IntegralCast", a = new CirExpr(e = "cast", t = 1, cast_kind = "LValueToRValue", a = new CirExpr(e = "ref", t = 1, name = "s")))

[test(description = "the C-IR comparison: equal units, then the first differing field of a declaration, a statement and an expression, a cast's kind and explicitness, a missing operand; a reference's name, but not the parentheses")]
def test_cir_difference(t : T?) {
    var a <- unit_returning(read_short())
    var b <- unit_returning(read_short())
    t |> equal(cir_difference(a, b), "")
    b.decls[0].body.body[0].e.a.a.name = "main__s"
    t |> equal(cir_difference(a, b), "decl 0 (main).body.0.e.a.a.name: builder s, Dumper A main__s")
    b.decls[0].body.body[0].e.a.a.name = "s"
    b.decls[0].body.body[0].e.paren = true
    t |> equal(cir_difference(a, b), "")
    b.decls[0].body.body[0].e.cast_kind = "NoOp"
    t |> equal(cir_difference(a, b), "decl 0 (main).body.0.e.cast: builder IntegralCast, Dumper A NoOp")
    b.decls[0].body.body[0].e.cast_kind = "IntegralCast"
    b.decls[0].body.body[0].e.explicit_cast = true
    t |> equal(cir_difference(a, b), "decl 0 (main).body.0.e.cast: builder IntegralCast, Dumper A IntegralCast!")
    b.decls[0].body.body[0].e.explicit_cast = false
    b.decls[0].body.body[0].e.a.t = 0
    t |> equal(cir_difference(a, b), "decl 0 (main).body.0.e.a.t: builder short/16s, Dumper A int/32s")
    b.decls[0].body.body[0].e.a.t = 1
    b.decls[0].body.body[0].s = "expr"
    t |> equal(cir_difference(a, b), "decl 0 (main).body.0.s: builder return, Dumper A expr")
    b.decls[0].body.body[0].s = "return"
    b.decls[0].t = 4
    t |> equal(cir_difference(a, b), "decl 0 (main).t: builder func(short/16s;), Dumper A func(int/32s;ptr(char/8u);...)")
    b.decls[0].t = 5
    b.decls |> push(new CirDecl(k = "global", c_name = "g", t = 0))
    t |> equal(cir_difference(a, b), "decls: builder 1, Dumper A 2")
    t |> equal(expr_difference(a.types, null, b.types, b.decls[0].body.body[0].e, "x"), "x: builder none, Dumper A cast")
    delete_tu(a)
    delete_tu(b)
}

[test(description = "the census comparison: equal censuses, then the first keys whose counts differ, both counts each")]
def test_census_difference(t : T?) {
    var a <- unit_returning(read_short())
    var b <- unit_returning(read_short())
    t |> equal(census_difference(a, b), "")
    b.decls[0].body.body[0].e.cast_kind = "NoOp"
    t |> success(starts_with(census_difference(a, b), "chain\tIntegralCast > LValueToRValue builder 1, Dumper A 0 | chain\tNoOp > LValueToRValue builder 0, Dumper A 1"), census_difference(a, b))
    delete_tu(a)
    delete_tu(b)
}

[test(description = "the ratchet's keys: a unit's dialect and file stem; a list's lines, its comments aside")]
def test_ratchet(t : T?) {
    t |> equal(ratchet_key("msvc", "suites/x/00012.c"), "msvc 00012")
    t |> equal(ratchet_key("linux", "pr34.c.c"), "linux pr34")
    let keys <- ratchet_keys("# a comment\nlinux 00001\n\nmsvc 00002\n")
    var listed <- [for (k in keys(keys)); k]
    sort(listed)
    t |> equal(join(listed, ","), "linux 00001,msvc 00002")
}

[test(description = "a ratchet's text: the listed keys and the run's byte-identical ones, sorted, a listed key the run did not compare kept")]
def test_ratchet_text(t : T?) {
    let listed <- ratchet_keys("linux 00009\nmsvc 00001\n")
    let text = ratchet_text(listed, ["msvc 00001", "linux 00002"])
    t |> equal(text, "# units whose Dumper C C-IR is Dumper A's byte for byte (compare/types/run.das); the ratchet, kept sorted\nlinux 00002\nlinux 00009\nmsvc 00001\n")
}

[test(description = "a run's counts: Dumper A failed, a unit with aggregates refused or byte-identical, a scalar-only one refused, agreeing, differing in the table, the C-IR or the census")]
def test_count(t : T?) {
    var n : TypesTotals
    t |> equal(count_types(n, TypesResult(unit = "a.c", dialect = "linux", dumper_error = "boom")), "a.c [linux]: Dumper A failed: boom")
    t |> equal(count_types(n, TypesResult(unit = "b.c", dialect = "msvc", aggregate = true, builder_error = "builder: x")), "b.c [msvc, aggregate]: refused: builder: x")
    t |> equal(count_types(n, TypesResult(unit = "c.c", dialect = "msvc", aggregate = true, whole = true, cir = true, census = true, bytes = true)), "")
    t |> equal(count_types(n, TypesResult(unit = "d.c", dialect = "linux", builder_error = "parser: y")), "d.c [linux]: refused: parser: y")
    t |> equal(count_types(n, TypesResult(unit = "e.c", dialect = "linux", whole = true, cir = true, census = true, bytes = true, core = true)), "")
    t |> equal(count_types(n, TypesResult(unit = "f.c", dialect = "linux", whole = true, cir = true, bytes = true, difference = "census z")), "f.c [linux]: differs: census z")
    t |> equal(count_types(n, TypesResult(unit = "g.c", dialect = "linux", census = true, core = true, difference = "table entry 0: z")), "g.c [linux, core]: differs: table entry 0: z")
    t |> equal(describe_types_totals("all", n), "all: 7 units, 1 Dumper A failed, 2 refused, 3 whole table, 3 C-IR, 3 census, 3 bytes agree, 2 differ; byte-identical: aggregates 1/2, scalar-only 2/4, core (no array) 1/2")
}

// the fixture `name` compared under `dialect` as `whole/cir/census/bytes/aggregate`, the builder's error
// or the differences after it
def private compared(name, dialect : string) : string {
    let r = compare_types("{FIXTURES}/{name}", target_by_name(dialect))
    return "Dumper A: {r.dumper_error}" if (!empty(r.dumper_error))
    let shape = "{r.whole}/{r.cir}/{r.census}/{r.bytes}/{r.aggregate}"
    return !empty(r.builder_error) ? "{shape} {r.builder_error}" : empty(r.difference) ? shape : "{shape} {r.difference}"
}

[test(description = "the fixtures through Dumper A and the builder under both dialects: every conversion group agrees in the table, the C-IR, the census and byte for byte; an aggregate's initializer and a constant array size refused", timeout = 600)]
def test_fixtures(t : T?) {
    for (dialect in ["linux", "msvc"]) {
        t |> run(dialect) @(t : T?) {
            t |> equal(compared("conversions.c", dialect), "true/true/true/true/false")
            t |> equal(compared("aggregate.c", dialect), "false/false/false/false/true builder: {FIXTURES}/aggregate.c:8:22: a braced scalar initializer of other than one value is not typed yet")
            t |> equal(compared("refused.c", dialect), "false/false/false/false/false builder: {FIXTURES}/refused.c:4:12: a prefixed string literal is not typed yet")
        }
    }
}
