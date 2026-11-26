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
    t |> run("the totals: one unit, its expression nodes and its casts") @(t : T?) {
        t |> equal(got(t, "total\tunits"), 1)
        t |> equal(got(t, "total\texprs"), 521)
        t |> equal(got(t, "total\tcasts"), 231)
    }
    t |> run("a C cast is explicit, clang's conversion implicit") @(t : T?) {
        t |> equal(got(t, "kind\tLValueToRValue\timplicit"), 111)
        t |> equal(got(t, "kind\tIntegralCast\timplicit"), 61)
        t |> equal(got(t, "kind\tIntegralCast\texplicit"), 3)
        t |> equal(got(t, "kind\tToVoid\texplicit"), 2)
        t |> equal(got(t, "kind\tNoOp\texplicit"), 2)
    }
}

[test(description = "the operand and result classes of each cast", timeout = 1200)]
def test_pairs(t : T?) {
    t |> run("integer ranks, enums, floating, pointers by pointee, records and functions") @(t : T?) {
        t |> equal(got(t, "pair\tIntegralCast\timplicit\tchar\tint"), 24)
        t |> equal(got(t, "pair\tIntegralCast\timplicit\tenum\tuint"), 1)
        t |> equal(got(t, "pair\tIntegralCast\timplicit\tint\tulong"), 3)
        t |> equal(got(t, "pair\tFloatingCast\timplicit\tfloat\tdouble"), 4)
        t |> equal(got(t, "pair\tBitCast\timplicit\tobjptr\tvoid*"), 4)
        t |> equal(got(t, "pair\tLValueToRValue\timplicit\tfnptr\tfnptr"), 1)
        t |> equal(got(t, "pair\tLValueToRValue\timplicit\trecord\trecord"), 3)
        t |> equal(got(t, "pair\tFunctionToPointerDecay\timplicit\tfunction\tfnptr"), 14)
        t |> equal(got(t, "pair\tIntegralCast\timplicit\tuint\tint"), 2)
        t |> equal(got(t, "pair\tIntegralToBoolean\timplicit\tint\tbool"), 1)
        t |> equal(got(t, "pair\tToVoid\texplicit\tobjptr\tvoid"), 1)
    }
    t |> run("a type of the table is classed through its typedefs, `long long` apart from `long`") @(t : T?) {
        let tu <- CirTu(types <- [CirType(k = "int", w = 64, is_signed = true, spell = "long long"),
            CirType(k = "typedef", name = "ll", to = 0),
            CirType(k = "int", w = 64, is_signed = false, spell = "unsigned long"),
            CirType(k = "float", w = 64, spell = "long double"),
            CirType(k = "int", w = 8, is_signed = true, spell = "signed char"),
            CirType(k = "int", w = 16, is_signed = false, spell = "unsigned short"),
            CirType(k = "int", w = 8, is_signed = false, spell = "unsigned char"),
            CirType(k = "int", w = 16, is_signed = true, spell = "short"),
            CirType(k = "int", w = 64, is_signed = true, spell = "long"),
            CirType(k = "int", w = 64, is_signed = false, spell = "unsigned long long"),
            CirType(k = "union", name = "u"),
            CirType(k = "array", elem = 6, count = 4),
            CirType(k = "void"),
            CirType(k = "typedef", name = "nothing", to = 12),
            CirType(k = "ptr", to = 13),
            CirType(k = "func", ret = 6),
            CirType(k = "typedef", name = "handler", to = 15),
            CirType(k = "ptr", to = 16)])
        t |> equal(type_class(tu, 1), "llong")
        t |> equal(type_class(tu, 2), "ulong")
        t |> equal(type_class(tu, 3), "ldouble")
        t |> equal(type_class(tu, 4), "schar")
        t |> equal(type_class(tu, 5), "ushort")
        t |> equal(type_class(tu, 6), "uchar")
        t |> equal(type_class(tu, 7), "short")
        t |> equal(type_class(tu, 8), "long")
        t |> equal(type_class(tu, 9), "ullong")
        t |> equal(type_class(tu, 10), "record")
        t |> equal(type_class(tu, 11), "array")
        t |> equal(type_class(tu, 14), "void*")
        t |> equal(type_class(tu, 17), "fnptr")
        t |> equal(type_class(tu, 99), "?")
        t |> equal(got(t, "pair\tArrayToPointerDecay\timplicit\tarray\tobjptr"), 5)
    }
}

[test(description = "the syntactic context of each cast, an implicit chain sharing its top's", timeout = 1200)]
def test_contexts(t : T?) {
    t |> run("call arguments: within the prototype, past a variadic one's parameters, past a function's with none") @(t : T?) {
        t |> equal(got(t, "context\tIntegralCast\timplicit\targument prototyped"), 6)
        t |> equal(got(t, "context\tIntegralCast\timplicit\targument variadic"), 1)
        t |> equal(got(t, "context\tFloatingCast\timplicit\targument variadic"), 1)
        t |> equal(got(t, "context\tIntegralCast\timplicit\targument unprototyped"), 2)
        t |> equal(got(t, "context\tFunctionToPointerDecay\timplicit\tcallee"), 13)
    }
    t |> run("an argument of a call to a K&R definition the unit holds is its own context, not an unprototyped one") @(t : T?) {
        t |> equal(got(t, "context\tNullToPointer\timplicit\targument K&R definition"), 2)
        t |> equal(got(t, "context\tIntegralCast\timplicit\targument K&R definition"), 1)
        t |> equal(got(t, "context\tLValueToRValue\timplicit\targument unprototyped"), 3)
        t |> equal(got(t, "rule\tK&R definition argument converted to the parameter type (clang, not 6.5.2.2p6): IntegralCast"), 1)
        t |> equal(got(t, "anomaly\tan argument past the parameters of a function that is not variadic (no prototype)"), 3)
    }
    t |> run("each slot of the walk: comma operands, a member's base, va_arg's list, loops, else, a hoisted static") @(t : T?) {
        t |> equal(got(t, "context\tLValueToRValue\timplicit\tcomma lhs"), 1)
        t |> equal(got(t, "context\tLValueToRValue\timplicit\tcomma rhs"), 1)
        t |> equal(got(t, "context\tLValueToRValue\timplicit\tmember base"), 2)
        t |> equal(got(t, "context\tArrayToPointerDecay\timplicit\tva_arg list"), 1)
        t |> equal(got(t, "context\tToVoid\texplicit\tfor inc"), 1)
        t |> equal(got(t, "context\tLValueToRValue\timplicit\tcondition do"), 1)
        t |> equal(got(t, "context\tIntegralCast\timplicit\tinit element"), 2)
        t |> equal(got(t, "context\tIntegralCast\timplicit\tinit scalar"), 8)
        t |> equal(got(t, "context\tIntegralCast\timplicit\tassign rhs"), 2)
        t |> equal(got(t, "context\tIntegralCast\timplicit\tcomparison"), 13)
    }
    t |> run("an assignment's right side, an if's condition apart from a ?:'s and a for's, unary operators by group") @(t : T?) {
        t |> equal(got(t, "context\tLValueToRValue\timplicit\tassign rhs"), 8)
        t |> equal(got(t, "context\tLValueToRValue\timplicit\tcondition if"), 2)
        t |> equal(got(t, "context\tLValueToRValue\timplicit\tcondition ?:"), 3)
        t |> equal(got(t, "context\tLValueToRValue\timplicit\tunary not"), 1)
        t |> equal(got(t, "context\tLValueToRValue\timplicit\tcondition for"), 1)
        t |> equal(got(t, "context\tIntegralCast\timplicit\tunary arithmetic"), 2)
        t |> equal(got(t, "context\tLValueToRValue\timplicit\tunary deref"), 1)
        t |> equal(got(t, "context\tIntegralCast\timplicit\tbitwise"), 6)
        t |> equal(got(t, "context\tIntegralCast\timplicit\treturn"), 5)
        t |> equal(got(t, "context\tIntegralCast\timplicit\tlogical"), 1)
    }
    t |> run("operators, conditions, switch, subscripts, initializers and the operand of a C cast") @(t : T?) {
        t |> equal(got(t, "context\tIntegralCast\timplicit\tshift"), 1)
        t |> equal(got(t, "context\tIntegralCast\timplicit\tswitch"), 2)
        t |> equal(got(t, "context\tIntegralCast\timplicit\tcondition ?:"), 1)
        t |> equal(got(t, "context\tLValueToRValue\timplicit\tcondition while"), 1)
        t |> equal(got(t, "context\tLValueToRValue\timplicit\tsubscript index"), 2)
        t |> equal(got(t, "context\tIntegralToFloating\timplicit\tinit element"), 1)
        t |> equal(got(t, "context\tLValueToRValue\timplicit\tcast operand"), 5)
        t |> equal(got(t, "context\tIntegralToFloating\timplicit\tcompound rhs"), 1)
        t |> equal(got(t, "context\tToVoid\texplicit\texpr stmt"), 1)
    }
    t |> run("the contexts no cast stands in are listed, the two the C-IR cannot hold among them") @(t : T?) {
        t |> equal(never_contexts(fixture(t)), ["unary address", "increment", "assign lhs", "compound lhs", "sizeof operand", "case label"])
    }
}

[test(description = "the rule of each cast: an explicit one's, the 6.3.2 conversions', a context's", timeout = 1200)]
def test_rules(t : T?) {
    t |> run("each rule counted, ranked most frequent first") @(t : T?) {
        t |> equal(got(t, "rule\t6.3.2.1p2 lvalue conversion"), 108)
        t |> equal(got(t, "rule\t6.3.2.1p2 lvalue conversion (record)"), 3)
        t |> equal(got(t, "rule\t6.3.2.1p3 array decay (string literal)"), 3)
        t |> equal(got(t, "rule\t6.3.2.1p4 function decay (value)"), 1)
        t |> equal(got(t, "rule\t6.3.1.1p2 integer promotion (binary operand): IntegralCast"), 22)
        t |> equal(got(t, "rule\t6.5.13-6.5.14 logical operand: IntegralCast"), 1)
        t |> equal(got(t, "rule\t6.3.1.8 usual arithmetic conversions: IntegralCast"), 4)
        t |> equal(got(t, "rule\t6.5.2.2p6 default argument promotion (no prototype): FloatingCast"), 1)
        t |> equal(got(t, "rule\t6.5.4 cast operator: NoOp"), 2)
        t |> equal(entries(fixture(t), "rule")[0].key, "6.3.2.1p2 lvalue conversion")
    }
    t |> run("the rules covering a share of the casts, and the context rules never met") @(t : T?) {
        t |> equal(rules_covering(fixture(t), 50), 2)
        t |> equal(rules_covering(fixture(t), 100), 46)
        let never <- never_context_rules(fixture(t))
        t |> success(has_value(never, "6.5.3.3p5 logical negation operand"))
        t |> success(!has_value(never, "6.8.4.2p5 switch promotion") && !has_value(never, "6.5.13-6.5.14 logical operand"))
    }
    t |> run("each C rule the fixture hits, by its exact name") @(t : T?) {
        t |> equal(got(t, "crule\t6.5.7p3 shift operand promotion"), 1)
        t |> equal(got(t, "crule\t6.5.3.3 unary operand promotion"), 2)
        t |> equal(got(t, "crule\t6.5.16.2 compound assignment"), 2)
        t |> equal(got(t, "crule\t6.5.2.2p7 prototyped argument"), 10)
        t |> equal(got(t, "crule\t6.5.2.2p6-7 default argument promotion (variadic)"), 2)
        t |> equal(got(t, "crule\t6.8.6.4p3 return"), 6)
        t |> equal(got(t, "crule\t6.7.9p11 scalar initializer"), 9)
        t |> equal(got(t, "crule\t6.7.9 aggregate element initializer"), 4)
        t |> equal(got(t, "crule\t6.5.15p3-6 conditional operator arms"), 1)
        t |> equal(got(t, "crule\t6.5.15p2 conditional operator condition"), 1)
        t |> equal(got(t, "crule\t6.3.2.1p3 array decay"), 5)
        t |> equal(got(t, "crule\t6.3.2.1p4 function decay (callee)"), 13)
        t |> equal(got(t, "crule\t6.3.2.3p3 null pointer constant"), 6)
        t |> equal(got(t, "crule\t6.3.1.1p2 integer promotion (binary operand)"), 22)
        t |> equal(got(t, "crule\t6.3.1.8 usual arithmetic conversions"), 7)
        t |> equal(got(t, "crule\t6.5.6-6.5.9 pointer operand"), 1)
    }
    t |> run("the C rules: a rule's keys of every castKind counted as one") @(t : T?) {
        t |> equal(got(t, "crule\t6.5.4 cast operator"), 9)
        t |> equal(got(t, "crule\t6.5.16.1 simple assignment"), 8)
        t |> equal(got(t, "crule\tK&R definition argument converted to the parameter type (clang, not 6.5.2.2p6)"), 1)
        t |> equal(length(entries(fixture(t), "crule")), 26)
        t |> equal(rules_covering(fixture(t), 100, "crule"), 26)
        t |> equal(rules_covering(fixture(t), 99, "crule"), 24)
    }
    t |> run("a promotion and a conversion to the common type are told apart; a narrow bit-field promotes") @(t : T?) {
        t |> equal(cast_rule("IntegralCast", "char", "uint", "comparison", false, false), "6.3.1.8 usual arithmetic conversions: IntegralCast")
        t |> equal(cast_rule("IntegralCast", "char", "int", "comparison", false, false), "6.3.1.1p2 integer promotion (binary operand): IntegralCast")
        t |> equal(cast_rule("IntegralCast", "uint", "int", "binary arithmetic", false, false, true), "6.3.1.1p2 integer promotion (binary operand): IntegralCast")
        t |> equal(cast_rule("IntegralCast", "uint", "int", "binary arithmetic", false, false), "6.3.1.8 usual arithmetic conversions: IntegralCast")
        t |> equal(cast_rule("IntegralCast", "char", "int", "unary not", false, false), "6.5.3.3p5 logical negation operand: IntegralCast")
        t |> equal(got(t, "anomaly\tIntegralCast implicit of a bit-field narrower than int"), 2)
    }
    t |> run("an implicit conversion outside the named contexts is its context's own rule") @(t : T?) {
        t |> equal(cast_rule("IntegralCast", "char", "int", "comma lhs", false, false), "context comma lhs: IntegralCast")
        t |> equal(cast_rule("BitCast", "objptr", "objptr", "comparison", false, false), "6.5.6-6.5.9 pointer operand: BitCast")
    }
}

[test(description = "the C11 6.3 clause of each conversion, by kind, classes and context", timeout = 1200)]
def test_clauses(t : T?) {
    t |> run("every clause the fixture's casts apply, counted exactly") @(t : T?) {
        let want <- [("6.3.1.1p2 integer promotion", 32), ("6.3.1.2 to _Bool", 2), ("6.3.1.3p1 integer, value kept", 22), ("6.3.1.3p2 integer to unsigned, wraps", 7), ("6.3.1.3p3 integer to signed, implementation-defined", 3), ("6.3.1.4p1 real floating to integer", 2), ("6.3.1.4p2 integer to real floating", 6), ("6.3.1.5 real floating widened", 4), ("6.3.2.1p2 lvalue conversion", 111), ("6.3.2.1p3 array to pointer", 8), ("6.3.2.1p4 function to pointer", 14), ("6.3.2.2 to void", 2), ("6.3.2.3p1 void pointer to and from object pointer", 5), ("6.3.2.3p2 pointer to a more qualified type", 3), ("6.3.2.3p3 null pointer constant", 7), ("6.3.2.3p4 null pointer to another pointer type", 1), ("6.5.4 cast to the same type", 2)]
        for (w in want) {
            t |> equal(got(t, "clause\t{w._0}"), w._1, w._0)
        }
        t |> equal(length(entries(fixture(t), "clause")), length(want))
    }
    t |> run("each promoting context promotes a small operand to int") @(t : T?) {
        for (ctx in ["unary arithmetic", "argument variadic", "unary not", "bitwise", "comparison", "binary arithmetic", "shift", "switch", "argument unprototyped"]) {
            t |> equal(conversion_clause("IntegralCast", "short", "int", ctx, false, false), "6.3.1.1p2 integer promotion", ctx)
        }
    }
    t |> run("integer conversions: a promotion only in a promoting context, else 6.3.1.3 by width and sign") @(t : T?) {
        t |> equal(conversion_clause("IntegralCast", "short", "int", "shift", false, false), "6.3.1.1p2 integer promotion")
        t |> equal(conversion_clause("IntegralCast", "short", "int", "assign rhs", false, false), "6.3.1.3p1 integer, value kept")
        t |> equal(conversion_clause("IntegralCast", "uint", "long", "assign rhs", false, false), "6.3.1.3p1 integer, value kept")
        t |> equal(conversion_clause("IntegralCast", "int", "uint", "assign rhs", false, false), "6.3.1.3p2 integer to unsigned, wraps")
        t |> equal(conversion_clause("IntegralCast", "long", "int", "assign rhs", false, false), "6.3.1.3p3 integer to signed, implementation-defined")
        t |> equal(conversion_clause("IntegralCast", "int", "bool", "assign rhs", false, false), "6.3.1.2 to _Bool")
    }
    t |> run("a promotion: to int below its rank, a narrow bit-field, an unsigned enum to unsigned int; never a small type to unsigned int") @(t : T?) {
        t |> equal(conversion_clause("IntegralCast", "schar", "uint", "comparison", false, false), "6.3.1.3p2 integer to unsigned, wraps")
        t |> equal(conversion_clause("IntegralCast", "uint", "int", "binary arithmetic", false, false, true), "6.3.1.1p2 integer promotion")
        t |> equal(conversion_clause("IntegralCast", "uint", "int", "binary arithmetic", false, false), "6.3.1.3p3 integer to signed, implementation-defined")
        t |> equal(conversion_clause("IntegralCast", "enum", "uint", "switch", false, false), "6.3.1.1p2 integer promotion")
        t |> equal(conversion_clause("IntegralCast", "char", "int", "logical", false, false), "6.3.1.1p2 integer promotion")
        t |> equal(conversion_clause("IntegralCast", "short", "int", "?: arm", false, false), "6.3.1.1p2 integer promotion")
        t |> equal(conversion_clause("IntegralCast", "bool", "int", "condition ?:", false, false), "6.3.1.1p2 integer promotion")
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
        t |> equal(got(t, "chain\tIntegralCast > LValueToRValue"), 47)
        t |> equal(got(t, "chain\tToVoid! > ArrayToPointerDecay"), 1)
        t |> equal(got(t, "chain\tNoOp > ArrayToPointerDecay"), 2)
        t |> equal(got(t, "chain\tLValueToRValue"), 47)
    }
    t |> run("the casts clang inserts that the standard does not name, and the facts the C-IR loses") @(t : T?) {
        t |> equal(got(t, "anomaly\tNoOp implicit, operand and result one C-IR type"), 3)
        t |> equal(got(t, "anomaly\tNoOp over a decayed string literal (to a const pointer)"), 2)
        t |> equal(got(t, "anomaly\tFunctionToPointerDecay of a __builtin_ callee"), 4)
        t |> equal(got(t, "anomaly\ta cast in an argument of a __builtin_ call"), 9)
        t |> equal(got(t, "anomaly\ta compound assignment whose operands' classes differ (its computation type is not in the C-IR)"), 2)
        t |> equal(got(t, "anomaly\tan implicit cast under an explicit cast"), 6)
        t |> equal(got(t, "anomaly\tPointerToBoolean in assign rhs"), 1)
        t |> equal(got(t, "chain\tIntegralCast > NoOp! > LValueToRValue"), 1)
        t |> equal(got(t, "anomaly\ta chain of three or more casts"), 1)
        t |> equal(got(t, "anomaly\tBitCast implicit objptr -> void*"), 4)
        t |> equal(got(t, "anomaly\tBitCast implicit void* -> objptr"), 2)
        t |> equal(got(t, "anomaly\tFunctionToPointerDecay of a callee"), 9)
        t |> equal(got(t, "anomaly\tFunctionToPointerDecay of a function value"), 1)
        t |> equal(got(t, "anomaly\tArrayToPointerDecay of a string literal"), 3)
        t |> equal(got(t, "anomaly\tToVoid explicit"), 2)
        t |> equal(got(t, "anomaly\tToVoid implicit"), 0)
        t |> equal(got(t, "anomaly\tIntegralCast implicit of a literal or enum constant (int_lit)"), 8)
        t |> equal(got(t, "anomaly\tIntegralCast implicit of a literal or enum constant (enum_ref)"), 1)
        t |> equal(got(t, "anomaly\tIntegralCast implicit directly over a call's result"), 1)
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
        t |> equal(count_of(twice, "total\tcasts"), 462)
        t |> equal(count_of(twice, "chain\tLValueToRValue"), 94)
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
        t |> success(find(text, "1 units, 521 expression nodes, 231 casts (222 implicit, 9 explicit); 26 C rules, 24 of them cover 99% of the casts; 46 C rule and castKind keys, 44 of them cover 99%") >= 0, text)
        t |> success(find(text, "| LValueToRValue | 111 | 0 | 111 | 48.05% |") >= 0)
        t |> success(find(text, "| 6.3.2.3p5 integer to pointer | never | 0.00% |") >= 0)
        t |> success(find(text, "| IntegralCast > LValueToRValue | 47 |") >= 0)
        t |> equal(length([for (line in split(text, "\n")); line; where line |> starts_with("| LValueToRValue | implicit |")]), 4)
    }
    t |> run("the JSON parses and holds each count under its dimension") @(t : T?) {
        var rows : array<CensusRow>
        rows |> emplace(CensusRow(name = "fixture"))
        rows[0].c |> add_census(fixture(t))
        var error : string
        var js = read_json(render_json(rows), error)
        t |> equal(error, "")
        t |> equal(js?["fixture"]?["chain"]?["IntegralCast > LValueToRValue"] ?? 0, 47)
        t |> equal(js?["fixture"]?["kind"]?["NoOp | explicit"] ?? 0, 2)
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
        t |> equal(count_of(c, "total\tunits"), 0)
    }
    t |> run("a file the dumper refuses gives its error and no count, not the part dumped before it") @(t : T?) {
        // a global with a cast, then a variable-length array: the dumper refuses the file past the global
        let path = path_join(folder, "vla.c")
        fwrite(path, "long g = 1;\nint f(int n) \{ int a[n]; a[0] = (long)n; return a[0]; \}\n")
        var error : string
        var c : ConversionCensus
        census_c_file(path, c, error)
        t |> success(find(error, "a variable-length array is not lowered") >= 0, error)
        t |> equal(count_of(c, "total\tcasts"), 0)
        t |> equal(count_of(c, "total\tunits"), 0)
    }
    rmdir_rec(folder)
}

[test(description = "a call whose callee type is no function, and a counts file's units, each counted once")]
def test_units(t : T?) {
    t |> run("an argument of a callee whose type is no function pointer is unprototyped") @(t : T?) {
        // the C-IR a dumper never writes: a call through an `int`; the walk must still give it a context
        var tu <- CirTu(types <- [CirType(k = "int", w = 32, is_signed = true, spell = "int"), CirType(k = "int", w = 64, is_signed = true, spell = "long")])
        var arg = new CirExpr(e = "cast", t = 1, cast_kind = "IntegralCast", a = new CirExpr(e = "int_lit", t = 0, v = "1"))
        var call = new CirExpr(e = "call", t = 0, fn = new CirExpr(e = "ref", t = 0, name = "g"))
        call.args |> push(arg)
        var body = new CirStmt(s = "compound")
        body.body |> push(new CirStmt(s = "expr", e = call))
        tu.decls |> push(new CirDecl(k = "func", name = "f", body = body))
        var c : ConversionCensus
        census_tu(tu, c)
        delete_tu(tu)
        t |> equal(count_of(c, "context\tIntegralCast\timplicit\targument unprototyped"), 1)
    }
    t |> run("a unit two counts files hold is added once, every other unit of either is added") @(t : T?) {
        var one, two : ConversionCensus
        one.n["total\tcasts"] = 3
        two.n["total\tcasts"] = 5
        var first <- unit_lines("lvm.c", one)
        first |> push_from(unit_lines("lua.c", two))
        var second <- unit_lines("lvm.c", one)
        second |> push_from(unit_lines("luac.c", one))
        var c : ConversionCensus
        var seen : table<string>
        c |> add_counts_file(seen, join(first, "\n"))
        c |> add_counts_file(seen, join(second, "\n"))
        t |> equal(count_of(c, "total\tcasts"), 11)
        t |> equal(length(seen), 3)
    }
}
