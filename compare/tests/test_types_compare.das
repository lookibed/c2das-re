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

// the C-IR difference of two units returning `read_short()` after `change` has edited them
def private changed(change : block<(var a, b : CirTu) : void>) : string {
    var a <- unit_returning(read_short())
    var b <- unit_returning(read_short())
    invoke(change, a, b)
    let d = cir_difference(a, b)
    delete_tu(a)
    delete_tu(b)
    return d
}

[test(description = "the C-IR comparison reports each field it compares: an expression's value, bytes, operator, character mark, vol, trait value and type, argument and item counts, an item's position and value, an argument and each operand; a statement's type, value, mark, label, body count, expressions and statements; a declaration's kind, name, linkage, origin, parameters and initializer")]
def test_cir_fields(t : T?) {
    let e = "decl 0 (main).body.0.e"
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].e.v = "7"; }, "{e}.v: builder , Dumper A 7")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].e.bytes |> push(uint8(65)); }, "{e}.bytes: builder [], Dumper A [ 0x41]")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].e.op = "neg"; }, "{e}.op: builder , Dumper A neg")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].e.is_char = true; }, "{e}.char: builder false, Dumper A true")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].e.vol = true; }, "{e}.vol: builder false, Dumper A true")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].e.trait_v = 8ul; }, "{e}.trait_v: builder 0x0, Dumper A 0x8")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].e.of_t = 1; }, "{e}.of_t: builder int/32s, Dumper A short/16s")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].e.args |> push(read_short()); }, "{e}.args: builder 0, Dumper A 1")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].e.init_items |> push(CirInitItem(pos = 0, v = read_short())); }, "{e}.items: builder 0, Dumper A 1")
    t |> equal(changed() $(var a, b) {
        a.decls[0].body.body[0].e.init_items |> push(CirInitItem(pos = 0, v = read_short()))
        b.decls[0].body.body[0].e.init_items |> push(CirInitItem(pos = 1, v = read_short()))
    }, "{e}.item0.pos: builder 0, Dumper A 1")
    t |> equal(changed() $(var a, b) {
        a.decls[0].body.body[0].e.init_items |> push(CirInitItem(pos = 0, v = read_short()))
        b.decls[0].body.body[0].e.init_items |> push(CirInitItem(pos = 0, v = new CirExpr(e = "int_lit", t = 0, v = "1")))
    }, "{e}.item0.e: builder cast, Dumper A int_lit")
    t |> equal(changed() $(var a, b) {
        a.decls[0].body.body[0].e.args |> push(read_short())
        b.decls[0].body.body[0].e.args |> push(new CirExpr(e = "int_lit", t = 0, v = "1"))
    }, "{e}.arg0.e: builder cast, Dumper A int_lit")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].e.b = read_short(); }, "{e}.b: builder none, Dumper A cast")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].e.c = read_short(); }, "{e}.c: builder none, Dumper A cast")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].e.fn = read_short(); }, "{e}.fn: builder none, Dumper A cast")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].e.base = read_short(); }, "{e}.base: builder none, Dumper A cast")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].e.i = read_short(); }, "{e}.i: builder none, Dumper A cast")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].e.init = read_short(); }, "{e}.init: builder none, Dumper A cast")
    let s = "decl 0 (main).body.0"
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].t = 1; }, "{s}.t: builder int/32s, Dumper A short/16s")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].v = 5l; }, "{s}.v: builder 0, Dumper A 5")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].is_char = true; }, "{s}.char: builder false, Dumper A true")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].label_name = "l"; }, "{s}.label: builder , Dumper A l")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].body |> push(new CirStmt(s = "null")); }, "{s}.body: builder 0, Dumper A 1")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].init = read_short(); }, "{s}.init: builder none, Dumper A cast")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].cond = read_short(); }, "{s}.cond: builder none, Dumper A cast")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].inc = read_short(); }, "{s}.inc: builder none, Dumper A cast")
    t |> equal(changed() $(var a, b) {
        a.decls[0].body.body[0].body |> push(new CirStmt(s = "null"))
        b.decls[0].body.body[0].body |> push(new CirStmt(s = "break"))
    }, "{s}.0.s: builder null, Dumper A break")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].init_s = new CirStmt(s = "null"); }, "{s}.init_s: builder none, Dumper A null")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].then_s = new CirStmt(s = "null"); }, "{s}.then: builder none, Dumper A null")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].else_s = new CirStmt(s = "null"); }, "{s}.else: builder none, Dumper A null")
    t |> equal(changed() $(var _a, b) { b.decls[0].body.body[0].body_s = new CirStmt(s = "null"); }, "{s}.body_s: builder none, Dumper A null")
    t |> equal(changed() $(var _a, b) { b.decls[0].k = "global"; }, "decl 0 (main).k: builder func, Dumper A global")
    t |> equal(changed() $(var _a, b) { b.decls[0].c_name = "x"; }, "decl 0 (x).c_name: builder main, Dumper A x")
    t |> equal(changed() $(var _a, b) { b.decls[0].is_static = true; }, "decl 0 (main).static: builder false, Dumper A true")
    t |> equal(changed() $(var _a, b) { b.decls[0].is_extern = true; }, "decl 0 (main).extern: builder false, Dumper A true")
    t |> equal(changed() $(var _a, b) { b.decls[0].from_func = "f"; }, "decl 0 (main).from_func: builder , Dumper A f")
    t |> equal(changed() $(var _a, b) { b.decls[0].params |> push(CirParam(t = 0)); }, "decl 0 (main).params: builder , Dumper A :int/32s")
    t |> equal(changed() $(var _a, b) { b.decls[0].init = read_short(); }, "decl 0 (main).init: builder none, Dumper A cast")
}

[test(description = "the census comparison: equal censuses, then the first keys whose counts differ, both counts each")]
def test_census_difference(t : T?) {
    var a <- unit_returning(read_short())
    var b <- unit_returning(read_short())
    t |> equal(census_difference(a, b), "")
    b.decls[0].body.body[0].e.cast_kind = "NoOp"
    t |> success(starts_with(census_difference(a, b), "chain\tIntegralCast > LValueToRValue builder 1, Dumper A 0 | chain\tNoOp > LValueToRValue builder 0, Dumper A 1"), census_difference(a, b))
    // four casts of other kinds: more keys differ than the three shown
    var chain = new CirExpr(e = "ref", t = 1, name = "s")
    for (kind in fixed_array("LValueToRValue", "BitCast", "FloatingCast", "PointerToBoolean", "NoOp")) {
        chain = new CirExpr(e = "cast", t = 0, cast_kind = kind, a = chain)
    }
    delete_expr(b.decls[0].body.body[0].e)
    b.decls[0].body.body[0].e = chain
    t |> equal(length(split(census_difference(a, b), " | ")), 3, census_difference(a, b))
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
    t |> equal(count_types(n, TypesResult(unit = "h.c", dialect = "linux", whole = true, census = true, difference = "C-IR x")), "h.c [linux]: differs: C-IR x")
    t |> equal(describe_types_totals("all", n), "all: 8 units, 1 Dumper A failed, 2 refused, 4 whole table, 3 C-IR, 4 census, 3 bytes agree, 3 differ; byte-identical: aggregates 1/2, scalar-only 2/5, core (no array) 1/2")
}

// the fixture `name` compared under `dialect` as `whole/cir/census/bytes/aggregate`, the builder's error
// or the differences after it
def private compared(name, dialect : string) : string {
    let r = compare_types("{FIXTURES}/{name}", target_by_name(dialect))
    return "Dumper A: {r.dumper_error}" if (!empty(r.dumper_error))
    let shape = "{r.whole}/{r.cir}/{r.census}/{r.bytes}/{r.aggregate}"
    return !empty(r.builder_error) ? "{shape} {r.builder_error}" : empty(r.difference) ? shape : "{shape} {r.difference}"
}

[test(description = "the fixtures through Dumper A and the builder under both dialects: every conversion group agrees in the table, the C-IR, the census and byte for byte; an aggregate's initializer and a constant array size refused; declarations in branches, a loop body and an old-style parameter list, a type only an expression names and an own header's typedef agree; a unit clang types otherwise differs in all four", timeout = 600)]
def test_fixtures(t : T?) {
    for (dialect in ["linux", "msvc"]) {
        t |> run(dialect) @(t : T?) {
            t |> equal(compared("conversions.c", dialect), "true/true/true/true/false")
            t |> equal(compared("redeclared.c", dialect), "true/true/true/true/false")
            t |> equal(compared("walk_bodies.c", dialect), "true/true/true/true/false")
            t |> equal(compared("expr_only.c", dialect), "true/true/true/true/false")
            t |> equal(compared("header.c", dialect), "true/true/true/true/false")
            t |> equal(compared("decl_order.c", dialect), "true/true/true/true/false")
            t |> equal(compared("expr_first.c", dialect), "true/true/true/true/false")
            t |> equal(compared("aggregate.c", dialect), "false/false/false/false/true builder: {FIXTURES}/aggregate.c:8:22: an initializer list of a struct or union is not typed yet")
            let size = dialect == "linux" ? "unsigned long" : "unsigned long long"
            t |> equal(compared("differs.c", dialect), "false/false/false/false/false table entry 0: builder int/32s, Dumper A {size}/64u; C-IR decl 1 (main).body.t: builder int/32s, Dumper A {size}/64u; census anomaly\tIntegralCast implicit directly over a call's result builder 0, Dumper A 1 | chain\tIntegralCast builder 0, Dumper A 1 | clause\t6.3.1.3p3 integer to signed, implementation-defined builder 0, Dumper A 1; bytes line 16: ours \"w\": 32, | theirs \"w\": 64,")
            t |> equal(compared("refused.c", dialect), "false/false/false/false/false builder: {FIXTURES}/refused.c:4:12: a prefixed string literal is not typed yet")
        }
    }
}

[test(description = "has_aggregate takes a union and an enum")]
def test_aggregate_kinds(t : T?) {
    t |> success(has_aggregate([CirType(k = "union", name = "U")]))
    t |> success(has_aggregate([CirType(k = "enum", name = "E")]))
}

[test(description = "the builder's C-IR refuses a unit the parser refuses and one it cannot read, naming the step", timeout = 600)]
def test_builder_refusals(t : T?) {
    let dir = path_join(test_temp_dir(), "edges")
    mkdir_rec(dir)
    let generic = path_join(dir, "generic.c")
    fwrite(generic, "int x = _Generic(1, int: 2, default: 3);\n")
    var error : string
    var tu : CirTu
    builder_tu(generic, target_lp64_linux(), tu, error)
    t |> success(starts_with(error, "parser: "), error)
    delete_tu(tu)
    error = ""
    var missing : CirTu
    builder_tu(path_join(dir, "missing.c"), target_lp64_linux(), missing, error)
    t |> success(starts_with(error, "parser: cannot read "), error)
    delete_tu(missing)
}

[test(description = "run_types: a unit that agrees passes, a refused one fails, no unit fails; the c-testsuite folder missing is an error; run.das as a child prints the totals", timeout = 600)]
def test_run_types(t : T?) {
    t |> equal(run_types(TypesArgs(dialect <- ["linux"], units <- ["{FIXTURES}/conversions.c"])), 0)
    t |> equal(run_types(TypesArgs(dialect <- ["linux"], units <- ["{FIXTURES}/refused.c"])), 1)
    t |> equal(run_types(TypesArgs()), 1)
    var error : string
    let units <- c_testsuite_units(test_temp_dir(), error)
    t |> success(ends_with(error, "is missing (fetch it with suites/c_testsuite/fetch.sh)") && empty(units), error)
    let argv <- [get_das_root() + "/bin/daslang", "-load_module", "dasCRuntime", "-load_module", "c_runtime", "-load_module", "fetch/dasFlex", "compare/types/run.das", "--",
                 "--dialect", "linux", "{FIXTURES}/conversions.c"]
    var out : string
    t |> equal(run_and_capture(argv, out, 600.0), 0)
    t |> success(find(out, "total: 1 units, 0 Dumper A failed, 0 refused, 1 whole table, 1 C-IR, 1 census, 1 bytes agree, 0 differ; byte-identical: aggregates 0/0, scalar-only 1/1, core (no array) 0/0") >= 0, out)
}

