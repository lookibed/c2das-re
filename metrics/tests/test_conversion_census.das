options gen2
options stack = 1048576
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/json_boost
require daslib/strings_boost
require ../../converter/cir.das
require ../../converter/dumper_a.das
require ../conversion_census_count.das

let FIXTURE = "metrics/tests/fixtures/conversion_census.c"

var private g_census : ConversionCensus
var private g_read = false

// the fixture's census, counted once
def private fixture(t : T?) : ConversionCensus {
    if (!g_read) {
        var error : string
        census_c_file(FIXTURE, g_census, error)
        t |> equal(error, "")
        g_read = true
    }
    return <- clone_to_move(g_census)
}

// the C-IR text of the C file `c_path` dumped under the `linux` dialect; `error` the dumper's
def private dump_text(c_path : string; var error : string&) : string {
    var d = new Dumper
    dump_tu(*d, c_path, target_by_name("linux"), default_clang(), DumpInputs())
    error = d.error
    let text = empty(error) ? write_cir(d.tu) : ""
    delete_tu(d.tu)
    unsafe {
        delete d
    }
    return text
}

def private got(t : T?; key : string) : int => count_of(fixture(t), key)

[test(description = "every cast node of the fixture counted by castKind, implicit and explicit apart", timeout = 1200)]
def test_kinds(t : T?) {
    t |> run("the totals: one unit, its casts and the kinds' sum") @(t : T?) {
        t |> equal(got(t, "total\tunits"), 1)
        t |> equal(got(t, "total\tcasts"), 114)
        var sum = 0
        for (e in entries(fixture(t), "kind")) {
            sum += e.n
        }
        t |> equal(sum, 114)
    }
    t |> run("a C cast is explicit, clang's conversion implicit") @(t : T?) {
        t |> equal(got(t, "kind\tLValueToRValue\timplicit"), 57)
        t |> equal(got(t, "kind\tIntegralCast\timplicit"), 19)
        t |> equal(got(t, "kind\tIntegralCast\texplicit"), 1)
        t |> equal(got(t, "kind\tToVoid\texplicit"), 1)
        t |> equal(got(t, "kind\tNoOp\texplicit"), 1)
    }
}

[test(description = "the operand and result classes of each cast", timeout = 1200)]
def test_pairs(t : T?) {
    t |> run("integer ranks, enums, floating, pointers by pointee, records and functions") @(t : T?) {
        t |> equal(got(t, "pair\tIntegralCast\timplicit\tchar\tint"), 7)
        t |> equal(got(t, "pair\tIntegralCast\timplicit\tenum\tuint"), 1)
        t |> equal(got(t, "pair\tIntegralCast\timplicit\tint\tulong"), 2)
        t |> equal(got(t, "pair\tFloatingCast\timplicit\tfloat\tdouble"), 4)
        t |> equal(got(t, "pair\tBitCast\timplicit\tobjptr\tvoid*"), 3)
        t |> equal(got(t, "pair\tLValueToRValue\timplicit\tfnptr\tfnptr"), 1)
        t |> equal(got(t, "pair\tLValueToRValue\timplicit\trecord\trecord"), 3)
        t |> equal(got(t, "pair\tFunctionToPointerDecay\timplicit\tfunction\tfnptr"), 6)
        t |> equal(got(t, "pair\tIntegralToBoolean\timplicit\tint\tbool"), 1)
        t |> equal(got(t, "pair\tToVoid\texplicit\tobjptr\tvoid"), 1)
    }
    t |> run("a type of the table is classed through its typedefs, `long long` apart from `long`") @(t : T?) {
        let tu <- CirTu(types <- [CirType(k = "int", w = 64, is_signed = true, spell = "long long"),
            CirType(k = "typedef", name = "ll", to = 0),
            CirType(k = "int", w = 64, is_signed = false, spell = "unsigned long"),
            CirType(k = "float", w = 64, spell = "long double"),
            CirType(k = "int", w = 8, is_signed = true, spell = "signed char"),
            CirType(k = "int", w = 16, is_signed = false, spell = "unsigned short")])
        t |> equal(type_class(tu, 1), "llong")
        t |> equal(type_class(tu, 2), "ulong")
        t |> equal(type_class(tu, 3), "ldouble")
        t |> equal(type_class(tu, 4), "schar")
        t |> equal(type_class(tu, 5), "ushort")
        t |> equal(type_class(tu, 9), "?")
    }
}

[test(description = "the syntactic context of each cast, an implicit chain sharing its top's", timeout = 1200)]
def test_contexts(t : T?) {
    t |> run("call arguments: within the prototype, past a variadic one's parameters, past a function's with none") @(t : T?) {
        t |> equal(got(t, "context\tIntegralCast\timplicit\targument prototyped"), 4)
        t |> equal(got(t, "context\tIntegralCast\timplicit\targument variadic"), 1)
        t |> equal(got(t, "context\tFloatingCast\timplicit\targument variadic"), 1)
        t |> equal(got(t, "context\tIntegralCast\timplicit\targument unprototyped"), 1)
        t |> equal(got(t, "context\tFunctionToPointerDecay\timplicit\tcallee"), 5)
    }
    t |> run("operators, conditions, switch, subscripts, initializers and the operand of a C cast") @(t : T?) {
        t |> equal(got(t, "context\tIntegralCast\timplicit\tshift"), 1)
        t |> equal(got(t, "context\tIntegralCast\timplicit\tswitch"), 2)
        t |> equal(got(t, "context\tIntegralCast\timplicit\tcondition ?:"), 1)
        t |> equal(got(t, "context\tLValueToRValue\timplicit\tcondition while"), 1)
        t |> equal(got(t, "context\tLValueToRValue\timplicit\tsubscript index"), 2)
        t |> equal(got(t, "context\tIntegralToFloating\timplicit\tinit element"), 1)
        t |> equal(got(t, "context\tIntegralCast\timplicit\tinit scalar"), 1)
        t |> equal(got(t, "context\tLValueToRValue\timplicit\tcast operand"), 3)
        t |> equal(got(t, "context\tIntegralToFloating\timplicit\tcompound rhs"), 1)
        t |> equal(got(t, "context\tToVoid\texplicit\texpr stmt"), 1)
    }
    t |> run("the contexts no cast stands in are listed, the two the C-IR cannot hold among them") @(t : T?) {
        let never <- never_contexts(fixture(t))
        t |> success(has_value(never, "sizeof operand") && has_value(never, "case label") && has_value(never, "comma lhs"))
        t |> success(!has_value(never, "switch"))
    }
}

[test(description = "the rule of each cast: an explicit one's, the 6.3.2 conversions', a context's", timeout = 1200)]
def test_rules(t : T?) {
    t |> run("each rule counted, ranked most frequent first") @(t : T?) {
        t |> equal(got(t, "rule\t6.3.2.1p2 lvalue conversion"), 54)
        t |> equal(got(t, "rule\t6.3.2.1p2 lvalue conversion (record)"), 3)
        t |> equal(got(t, "rule\t6.3.2.1p3 array decay (string literal)"), 3)
        t |> equal(got(t, "rule\t6.3.2.1p4 function decay (value)"), 1)
        t |> equal(got(t, "rule\t6.3.1.1p2 integer promotion (binary operand): IntegralCast"), 2)
        t |> equal(got(t, "rule\t6.3.1.8 usual arithmetic conversions: IntegralCast"), 2)
        t |> equal(got(t, "rule\t6.5.2.2p6 default argument promotion (no prototype): FloatingCast"), 1)
        t |> equal(got(t, "rule\t6.5.4 cast operator: NoOp"), 1)
        t |> equal(entries(fixture(t), "rule")[0].key, "6.3.2.1p2 lvalue conversion")
    }
    t |> run("the rules covering a share of the casts, and the context rules never met") @(t : T?) {
        t |> equal(rules_covering(fixture(t), 50), 2)
        t |> equal(rules_covering(fixture(t), 100), 41)
        let never <- never_context_rules(fixture(t))
        t |> success(has_value(never, "6.5.13-6.5.14 logical operand"))
        t |> success(!has_value(never, "6.8.4.2p5 switch promotion"))
    }
    t |> run("an implicit conversion outside the named contexts is its context's own rule") @(t : T?) {
        t |> equal(cast_rule("IntegralCast", "char", "int", "comma lhs", false, false), "context comma lhs: IntegralCast")
        t |> equal(cast_rule("BitCast", "objptr", "objptr", "comparison", false, false), "6.5.6-6.5.9 pointer operand: BitCast")
    }
}

[test(description = "the C11 6.3 clause of each conversion, by kind, classes and context")]
def test_clauses(t : T?) {
    t |> run("integer conversions: a promotion only in a promoting context, else 6.3.1.3 by width and sign") @(t : T?) {
        t |> equal(conversion_clause("IntegralCast", "short", "int", "shift", false, false), "6.3.1.1p2 integer promotion")
        t |> equal(conversion_clause("IntegralCast", "short", "int", "assign rhs", false, false), "6.3.1.3p1 integer, value kept")
        t |> equal(conversion_clause("IntegralCast", "uint", "long", "assign rhs", false, false), "6.3.1.3p1 integer, value kept")
        t |> equal(conversion_clause("IntegralCast", "int", "uint", "assign rhs", false, false), "6.3.1.3p2 integer to unsigned, wraps")
        t |> equal(conversion_clause("IntegralCast", "long", "int", "assign rhs", false, false), "6.3.1.3p3 integer to signed, implementation-defined")
        t |> equal(conversion_clause("IntegralCast", "int", "bool", "assign rhs", false, false), "6.3.1.2 to _Bool")
    }
    t |> run("floating, boolean and the 6.3.2 conversions") @(t : T?) {
        t |> equal(conversion_clause("FloatingCast", "float", "double", "", false, false), "6.3.1.5 real floating widened")
        t |> equal(conversion_clause("FloatingCast", "double", "float", "", false, false), "6.3.1.5 real floating narrowed")
        t |> equal(conversion_clause("FloatingToBoolean", "double", "bool", "", false, false), "6.3.1.2 to _Bool")
        t |> equal(conversion_clause("IntegralToPointer", "long", "objptr", "", true, false), "6.3.2.3p5 integer to pointer")
        t |> equal(conversion_clause("PointerToIntegral", "objptr", "long", "", true, false), "6.3.2.3p6 pointer to integer")
        t |> equal(conversion_clause("ToVoid", "int", "void", "", true, false), "6.3.2.2 to void")
    }
    t |> run("pointer bit casts by pointee, a qualifying NoOp, a same-type cast and what no clause names") @(t : T?) {
        t |> equal(conversion_clause("BitCast", "void*", "objptr", "", false, false), "6.3.2.3p1 void pointer to and from object pointer")
        t |> equal(conversion_clause("BitCast", "objptr", "objptr", "", true, false), "6.3.2.3p7 object pointer to object pointer")
        t |> equal(conversion_clause("BitCast", "fnptr", "fnptr", "", true, false), "6.3.2.3p8 function pointer to function pointer")
        t |> equal(conversion_clause("BitCast", "objptr", "objptr", "", true, true), "6.3.2.3p4 null pointer to another pointer type")
        t |> equal(conversion_clause("NoOp", "objptr", "objptr", "", false, false), "6.3.2.3p2 pointer to a more qualified type")
        t |> equal(conversion_clause("NoOp", "int", "int", "", true, false), "6.5.4 cast to the same type")
        t |> equal(conversion_clause("BitCast", "fnptr", "void*", "", true, false), "no clause: BitCast fnptr -> void*")
    }
}

[test(description = "chains of casts by shape, and the anomalies counted beside them", timeout = 1200)]
def test_chains_and_anomalies(t : T?) {
    t |> run("a chain is counted once, at its top, outermost kind first, an explicit one marked") @(t : T?) {
        t |> equal(got(t, "chain\tIntegralCast > LValueToRValue"), 15)
        t |> equal(got(t, "chain\tToVoid! > ArrayToPointerDecay"), 1)
        t |> equal(got(t, "chain\tNoOp > ArrayToPointerDecay"), 2)
        t |> equal(got(t, "chain\tLValueToRValue"), 27)
    }
    t |> run("the casts clang inserts that the standard does not name, and the facts the C-IR loses") @(t : T?) {
        t |> equal(got(t, "anomaly\tNoOp implicit, operand and result one C-IR type"), 3)
        t |> equal(got(t, "anomaly\tNoOp over a decayed string literal (to a const pointer)"), 2)
        t |> equal(got(t, "anomaly\tFunctionToPointerDecay of a __builtin_ callee"), 1)
        t |> equal(got(t, "anomaly\ta cast in an argument of a __builtin_ call"), 2)
        t |> equal(got(t, "anomaly\tan argument past the parameters of a function that is not variadic (no prototype)"), 2)
        t |> equal(got(t, "anomaly\ta compound assignment whose operands' classes differ (its computation type is not in the C-IR)"), 1)
        t |> equal(got(t, "anomaly\tan implicit cast under an explicit cast"), 4)
        t |> equal(got(t, "anomaly\tPointerToBoolean in assign rhs"), 1)
    }
    t |> run("the castKinds of the pinned list never met") @(t : T?) {
        t |> equal(never_kinds(fixture(t)), ["BooleanToSignedIntegral", "FloatingToBoolean", "IntegralToPointer", "PointerToIntegral"])
    }
}

[test(description = "the counts file, the sum of censuses, the tables and the JSON", timeout = 1200)]
def test_text(t : T?) {
    t |> run("a census's lines read back as its counts; a line of another shape is none") @(t : T?) {
        var back : ConversionCensus
        for (line in census_lines(fixture(t))) {
            var key : string
            var ok : bool
            let n = read_census_line(line, key, ok)
            t |> success(ok, line)
            back.n[key] += n
        }
        t |> equal(census_lines(back), census_lines(fixture(t)))
        var key : string
        var ok = true
        read_census_line("unit\tlvm.c", key, ok)
        t |> success(!ok)
    }
    t |> run("censuses add key by key") @(t : T?) {
        var twice : ConversionCensus
        twice |> add_census(fixture(t))
        twice |> add_census(fixture(t))
        t |> equal(count_of(twice, "total\tcasts"), 228)
        t |> equal(count_of(twice, "chain\tLValueToRValue"), 54)
    }
    t |> run("a share has two decimals; an empty whole has none") @(t : T?) {
        t |> equal(percent(1, 3), "33.33%")
        t |> equal(percent(1, 20), "5.00%")
        t |> equal(percent(1, 0), "-")
    }
    t |> run("a set's report holds every table and the clauses never met") @(t : T?) {
        var row = CensusRow(name = "fixture")
        row.c |> add_census(fixture(t))
        let text = render_set(row, 2)
        t |> success(find(text, "1 units, 261 expression nodes, 114 casts (110 implicit, 4 explicit)") >= 0, text)
        t |> success(find(text, "| LValueToRValue | 57 | 0 | 57 | 50.00% |") >= 0)
        t |> success(find(text, "| 6.3.2.3p5 integer to pointer | never | 0.00% |") >= 0)
        t |> success(find(text, "| IntegralCast > LValueToRValue | 15 |") >= 0)
        t |> equal(length([for (line in split(text, "\n")); line; where line |> starts_with("| LValueToRValue | implicit |")]), 4)
    }
    t |> run("the JSON parses and holds each count under its dimension") @(t : T?) {
        var rows : array<CensusRow>
        rows |> emplace(CensusRow(name = "fixture"))
        rows[0].c |> add_census(fixture(t))
        var error : string
        var js = read_json(render_json(rows), error)
        t |> equal(error, "")
        t |> equal(js?["fixture"]?["chain"]?["IntegralCast > LValueToRValue"] ?? 0, 15)
        t |> equal(js?["fixture"]?["kind"]?["NoOp | explicit"] ?? 0, 1)
    }
}

[test(description = "a C-IR file is counted as its dump is, and a file that does not dump or read counts nothing", timeout = 1200)]
def test_files(t : T?) {
    var temp_error : string
    let folder = create_temp_directory("conversion_census_", temp_error)
    t |> run("the C-IR the converter writes counts as the dump") @(t : T?) {
        var error : string
        let path = path_join(folder, "fixture.cir.json")
        fwrite(path, dump_text(FIXTURE, error))
        t |> equal(error, "")
        var c : ConversionCensus
        census_cir_file(path, c, error)
        t |> equal(error, "")
        t |> equal(census_lines(c), census_lines(fixture(t)))
    }
    t |> run("a file that is no C-IR gives its error") @(t : T?) {
        let path = path_join(folder, "broken.cir.json")
        fwrite(path, "\{")
        var error : string
        var c : ConversionCensus
        census_cir_file(path, c, error)
        t |> success(!empty(error))
    }
    t |> run("a file the dumper refuses gives its error and no count") @(t : T?) {
        // a variable-length array: the dumper refuses the file
        let path = path_join(folder, "vla.c")
        fwrite(path, "int f(int n) \{ int a[n]; a[0] = (long)n; return a[0]; \}\n")
        var error : string
        var c : ConversionCensus
        census_c_file(path, c, error)
        t |> success(find(error, "a variable-length array is not lowered") >= 0, error)
        t |> equal(count_of(c, "total\tcasts"), 0)
    }
    rmdir_rec(folder)
}
