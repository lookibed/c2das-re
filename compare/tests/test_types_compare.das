options gen2
options stack = 262144
require dastest/testing_boost public
require strings
require daslib/strings_boost
require daslib/fio
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

[test(description = "the C-IR comparison: equal units, then the first differing field of a declaration, a statement and an expression, a cast's kind and explicitness, a missing operand; a reference's name and the parentheses never differ")]
def test_cir_difference(t : T?) {
    var a <- unit_returning(read_short())
    var b <- unit_returning(read_short())
    t |> equal(cir_difference(a, b), "")
    b.decls[0].body.body[0].e.a.a.name = "main__s"
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

[test(description = "a run's counts: Dumper A failed, aggregates refused or typed, scalar-only refused, agreeing, differing in the table, the C-IR or the census")]
def test_count(t : T?) {
    var n : TypesTotals
    t |> equal(count_types(n, TypesResult(unit = "a.c", dialect = "linux", dumper_error = "boom")), "a.c [linux]: Dumper A failed: boom")
    t |> equal(count_types(n, TypesResult(unit = "b.c", dialect = "msvc", aggregate = true, builder_error = "builder: x")), "")
    t |> equal(count_types(n, TypesResult(unit = "c.c", dialect = "msvc", aggregate = true)), "c.c [msvc]: aggregates in Dumper A's table, but the builder typed the unit")
    t |> equal(count_types(n, TypesResult(unit = "d.c", dialect = "linux", builder_error = "parser: y")), "d.c [linux]: refused: parser: y")
    t |> equal(count_types(n, TypesResult(unit = "e.c", dialect = "linux", whole = true, cir = true, census = true)), "")
    t |> equal(count_types(n, TypesResult(unit = "f.c", dialect = "linux", whole = true, cir = true, difference = "census z")), "f.c [linux]: differs: census z")
    t |> equal(count_types(n, TypesResult(unit = "g.c", dialect = "linux", census = true, difference = "table entry 0: z")), "g.c [linux]: differs: table entry 0: z")
    t |> equal(describe_types_totals("all", n), "all: 7 units, 1 Dumper A failed, 2 with aggregates, 4 scalar-only: 2 whole table, 2 C-IR, 2 census agree; 2 differ, 1 refused")
}

// the fixture `name` compared under `dialect` as `whole/cir/census/aggregate`, the builder's error
// or the differences after it
def private compared(name, dialect : string) : string {
    let r = compare_types("{FIXTURES}/{name}", "compare/work/types", target_by_name(dialect))
    return "Dumper A: {r.dumper_error}" if (!empty(r.dumper_error))
    let shape = "{r.whole}/{r.cir}/{r.census}/{r.aggregate}"
    return !empty(r.builder_error) ? "{shape} {r.builder_error}" : empty(r.difference) ? shape : "{shape} {r.difference}"
}

[test(description = "the fixtures through Dumper A and the builder under both dialects: every conversion group agrees in the table, the C-IR and the census; an aggregate and a constant array size refused; declarations in branches, a loop body and an old-style parameter list, a type only an expression names and an own header's typedef agree", timeout = 600)]
def test_fixtures(t : T?) {
    for (dialect in ["linux", "msvc"]) {
        t |> run(dialect) @(t : T?) {
            t |> equal(compared("conversions.c", dialect), "true/true/true/false")
            t |> equal(compared("redeclared.c", dialect), "true/true/true/false")
            t |> equal(compared("walk_bodies.c", dialect), "true/true/true/false")
            t |> equal(compared("expr_only.c", dialect), "true/true/true/false")
            t |> equal(compared("header.c", dialect), "true/true/true/false")
            t |> equal(compared("aggregate.c", dialect), "false/false/false/true builder: {FIXTURES}/aggregate.c:2:1: a struct type is not typed yet")
            t |> equal(compared("refused.c", dialect), "false/false/false/false builder: {FIXTURES}/refused.c:2:11: an array size other than an integer literal is not typed yet")
        }
    }
}

[test(description = "has_aggregate takes a union and an enum")]
def test_aggregate_kinds(t : T?) {
    t |> success(has_aggregate([CirType(k = "union", name = "U")]))
    t |> success(has_aggregate([CirType(k = "enum", name = "E")]))
}

[test(description = "the builder's C-IR refuses a unit the parser refuses and one clang -E refuses, each naming the step", timeout = 600)]
def test_builder_refusals(t : T?) {
    let dir = path_join(test_temp_dir(), "edges")
    mkdir_rec(dir)
    let generic = path_join(dir, "generic.c")
    fwrite(generic, "int x = _Generic(1, int: 2, default: 3);\n")
    var error : string
    var tu : CirTu
    builder_tu(generic, dir, target_lp64_linux(), tu, error)
    t |> success(starts_with(error, "parser: "), error)
    delete_tu(tu)
    error = ""
    var missing : CirTu
    builder_tu(path_join(dir, "missing.c"), dir, target_lp64_linux(), missing, error)
    t |> success(starts_with(error, "clang -E: "), error)
    delete_tu(missing)
}

[test(description = "run_types: a unit that agrees passes, a refused one fails, no unit fails; the c-testsuite folder missing is an error; run.das as a child prints the totals", timeout = 600)]
def test_run_types(t : T?) {
    let work = path_join(test_temp_dir(), "work")
    t |> equal(run_types(TypesArgs(work = work, dialect <- ["linux"], units <- ["{FIXTURES}/conversions.c"])), 0)
    t |> equal(run_types(TypesArgs(work = work, dialect <- ["linux"], units <- ["{FIXTURES}/refused.c"])), 1)
    t |> equal(run_types(TypesArgs(work = work)), 1)
    var error : string
    let units <- c_testsuite_units(test_temp_dir(), error)
    t |> success(ends_with(error, "is missing (fetch it with suites/c_testsuite/fetch.sh)") && empty(units), error)
    let argv <- [get_das_root() + "/bin/daslang", "-load_module", "dasCRuntime", "-load_module", "c_runtime", "-load_module", "fetch/dasFlex", "compare/types/run.das", "--",
                 "--work", work, "--dialect", "linux", "{FIXTURES}/conversions.c"]
    var out : string
    t |> equal(run_and_capture(argv, out, 600.0), 0)
    t |> success(find(out, "total: 1 units, 0 Dumper A failed, 0 with aggregates, 1 scalar-only") >= 0, out)
}

