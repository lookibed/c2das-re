options gen2

module conversion_census_count public

require daslib/cmp
require strings
require daslib/strings_boost
require daslib/fio
require ../converter/cir.das
require ../converter/dumper_a.das
require ../converter/pipeline.das
require ../converter/sidecar.das

//! The conversions census's counting (`metrics/ARCHITECTURE_CONVERSIONS.md`): every cast node of a
//! C-IR translation unit read with its operand and result classes, its syntactic context, the
//! conversion rule it applies and the chain it stands in, counted under one key per dimension.

//! The dimensions a census counts under, each key `<dimension>\t<fields...>`: `kind` (castKind,
//! `implicit` or `explicit`), `pair` (castKind, implicit or explicit, operand class, result
//! class), `context` (castKind, implicit or explicit, context), `rule` (the rule's name and the
//! castKind, a context and kind key), `crule` (the C rule alone, the rule's name before the kind), `clause`
//! (the C11 6.3 clause of the conversion), `chain` (the castKinds of a chain, outermost first),
//! `anomaly` (the anomaly's name) and `total` (`units`, `exprs`, `casts`).
let DIMENSIONS <- ["kind", "pair", "context", "rule", "crule", "clause", "chain", "anomaly", "total"]

//! The counts of a census: one count per key of a dimension.
struct ConversionCensus {
    n : table<string; int>
}

//! The C11 6.3 clauses a cast node can apply, in the standard's order; one the inputs never hit is
//! listed as such.
let CLAUSES <- ["6.3.1.1p2 integer promotion", "6.3.1.2 to _Bool", "6.3.1.3p1 integer, value kept", "6.3.1.3p2 integer to unsigned, wraps", "6.3.1.3p3 integer to signed, implementation-defined", "6.3.1.4p1 real floating to integer", "6.3.1.4p2 integer to real floating", "6.3.1.5 real floating widened", "6.3.1.5 real floating narrowed", "6.3.1.6 complex to complex", "6.3.1.7 real and complex", "6.3.2.1p2 lvalue conversion", "6.3.2.1p3 array to pointer", "6.3.2.1p4 function to pointer", "6.3.2.2 to void", "6.3.2.3p1 void pointer to and from object pointer", "6.3.2.3p2 pointer to a more qualified type", "6.3.2.3p3 null pointer constant", "6.3.2.3p4 null pointer to another pointer type", "6.3.2.3p5 integer to pointer", "6.3.2.3p6 pointer to integer", "6.3.2.3p7 object pointer to object pointer", "6.3.2.3p8 function pointer to function pointer", "6.5.4 cast to the same type"]

//! The context rules of an implicit conversion that is not an lvalue, array, function or null
//! pointer conversion, each with its C11 clause; one the inputs never hit is listed as such.
let CONTEXT_RULES <- ["6.3.1.1p2 integer promotion (binary operand)", "6.3.1.8 usual arithmetic conversions", "6.5.6-6.5.9 pointer operand", "6.5.7p3 shift operand promotion", "6.5.3.3 unary operand promotion", "6.5.13-6.5.14 logical operand", "6.5.3.3p5 logical negation operand", "6.5.16.1 simple assignment", "6.5.16.2 compound assignment", "6.5.2.2p7 prototyped argument", "6.5.2.2p6-7 default argument promotion (variadic)", "6.5.2.2p6 default argument promotion (no prototype)", "K&R definition argument converted to the parameter type (clang, not 6.5.2.2p6)", "6.8.6.4p3 return", "6.7.9p11 scalar initializer", "6.7.9 aggregate element initializer", "6.5.15p3-6 conditional operator arms", "6.8.4-6.8.5 controlling expression", "6.5.15p2 conditional operator condition", "6.8.4.2p5 switch promotion", "6.5.2.1 subscript"]

//! The contexts a cast can stand in, as `context_of` names them; `sizeof operand` and `case label`
//! never appear, since the C-IR keeps neither a `sizeof` operand nor a case label's expression.
let CONTEXTS <- ["binary arithmetic", "comparison", "bitwise", "shift", "logical", "unary arithmetic", "unary not", "unary address", "unary deref", "increment", "assign rhs", "assign lhs", "compound rhs", "compound lhs", "argument prototyped", "argument variadic", "argument unprototyped", "argument K&R definition", "callee", "return", "init scalar", "init element", "condition if", "condition while", "condition do", "condition for", "condition ?:", "?: arm", "switch", "subscript base", "subscript index", "member base", "cast operand", "comma lhs", "comma rhs", "expr stmt", "for inc", "va_arg list", "sizeof operand", "case label"]

def private bump(var c : ConversionCensus; key : string; by : int = 1) {
    c.n[key] += by
}

//! The count of `key` in `c`, 0 when it was never counted.
def count_of(c : ConversionCensus; key : string) : int => c.n?[key] ?? 0

def private resolved(tu : CirTu; t : int) : int {
    var at = t
    while (at >= 0 && at < length(tu.types) && tu.types[at].k == "typedef") {
        at = tu.types[at].to
    }
    return at
}

// the class of an integer type of width `w`, signedness `signed` and spelling `spell`
def private integer_class(w : int; signed : bool; spell : string) : string {
    if (spell == "_Bool") {
        return "bool"
    }
    if (w == 8) {
        return spell == "char" ? "char" : (signed ? "schar" : "uchar")
    }
    if (w == 16) {
        return signed ? "short" : "ushort"
    }
    if (w == 32) {
        return signed ? "int" : "uint"
    }
    if (w == 64) {
        let llong = find(spell, "long long") >= 0
        return signed ? (llong ? "llong" : "long") : (llong ? "ullong" : "ulong")
    }
    return signed ? "int{w}" : "uint{w}"
}

//! The coarse class of type `t` of `tu`: `bool`, an integer class (`char`, `schar`, `uchar`,
//! `short`, `ushort`, `int`, `uint`, `long`, `ulong`, `llong`, `ullong`), `float`, `double`,
//! `ldouble`, `enum`, `objptr`, `fnptr`, `void*`, `array`, `function`, `record`, `void`; `?` for a
//! reference outside the table.
def type_class(tu : CirTu; t : int) : string {
    let at = resolved(tu, t)
    if (at < 0 || at >= length(tu.types)) {
        return "?"
    }
    let k = tu.types[at].k
    let spell = tu.types[at].spell
    if (k == "int") {
        return integer_class(tu.types[at].w, tu.types[at].is_signed, spell)
    }
    if (k == "float") {
        return spell == "float" ? "float" : (spell == "long double" ? "ldouble" : "double")
    }
    if (k == "ptr") {
        let to = resolved(tu, tu.types[at].to)
        let pointee = to >= 0 && to < length(tu.types) ? tu.types[to].k : ""
        return pointee == "void" ? "void*" : (pointee == "func" ? "fnptr" : "objptr")
    }
    if (k == "struct" || k == "union") {
        return "record"
    }
    if (k == "func") {
        return "function"
    }
    return k
}

// the width and signedness of an integer class; 0 for a class that is no integer
def private integer_width(cls : string; var signed : bool&) : int {
    signed = cls == "schar" || cls == "short" || cls == "int" || cls == "long" || cls == "llong" || cls == "enum"
    if (cls == "bool") {
        return 1
    }
    if (cls == "char" || cls == "schar" || cls == "uchar") {
        return 8
    }
    if (cls == "short" || cls == "ushort") {
        return 16
    }
    if (cls == "int" || cls == "uint" || cls == "enum") {
        return 32
    }
    if (cls == "long" || cls == "ulong" || cls == "llong" || cls == "ullong") {
        return 64
    }
    return 0
}

def private is_pointer_class(cls : string) : bool => cls == "objptr" || cls == "fnptr" || cls == "void*"

// whether `cls` is promoted to `int` or `unsigned int` by C11 6.3.1.1p2: below `int`'s rank, or an
// enum, whose compatible type has `int`'s rank
def private is_small(cls : string) : bool {
    var signed : bool
    let w = integer_width(cls, signed)
    return (w > 0 && w < 32) || cls == "enum"
}

// the contexts that promote a small integer operand (C11 6.3.1.1p2): by itself, or as the first
// step of the usual arithmetic conversions, which clang folds into the one cast to the common type
def private promotes(ctx : string) : bool =>
    ctx == "binary arithmetic" || ctx == "comparison" || ctx == "bitwise" || ctx == "shift" || ctx == "logical" || ctx == "unary arithmetic" || ctx == "unary not" || ctx == "switch" || ctx == "condition ?:" || ctx == "?: arm" || ctx == "argument variadic" || ctx == "argument unprototyped"

//! Whether an `IntegralCast` from class `src` to class `dst` in context `ctx` is an integer
//! promotion (C11 6.3.1.1p2), `bit_field` when the operand is a bit-field narrower than `int`: a
//! type below `int`'s rank, or such a bit-field, to `int` (with a 32-bit `int` every one of them
//! fits), or an enum whose compatible type is `unsigned int` to it, in a context that promotes.
//! A small type converted to `unsigned int` is the usual arithmetic conversions, not a promotion.
def is_promotion(src, dst, ctx : string; bit_field : bool) : bool =>
    promotes(ctx) && ((dst == "int" && (bit_field || is_small(src))) || (dst == "uint" && src == "enum"))

// the 6.3.1.3 paragraph of an integer conversion from `src` to `dst`
def private integer_clause(src, dst : string) : string {
    var src_signed, dst_signed : bool
    let sw = integer_width(src, src_signed)
    let dw = integer_width(dst, dst_signed)
    if ((src_signed == dst_signed && dw >= sw) || (dst_signed && !src_signed && dw > sw)) {
        return "6.3.1.3p1 integer, value kept"
    }
    return dst_signed ? "6.3.1.3p3 integer to signed, implementation-defined" : "6.3.1.3p2 integer to unsigned, wraps"
}

//! The C11 6.3 clause a cast of `kind` from class `src` to class `dst` applies in context `ctx`;
//! `null_operand` when the operand is a null pointer constant already converted. A conversion no
//! clause names is `no clause: <kind> <src> -> <dst>`; `bit_field` as `is_promotion` takes it.
def conversion_clause(kind, src, dst, ctx : string; is_explicit, null_operand : bool; bit_field : bool = false) : string {
    if (kind == "LValueToRValue") {
        return "6.3.2.1p2 lvalue conversion"
    } elif (kind == "ArrayToPointerDecay") {
        return "6.3.2.1p3 array to pointer"
    } elif (kind == "FunctionToPointerDecay") {
        return "6.3.2.1p4 function to pointer"
    } elif (kind == "ToVoid") {
        return "6.3.2.2 to void"
    } elif (kind == "IntegralToBoolean" || kind == "FloatingToBoolean" || kind == "PointerToBoolean") {
        return "6.3.1.2 to _Bool"
    } elif (kind == "IntegralCast") {
        if (dst == "bool") {
            return "6.3.1.2 to _Bool"
        }
        return is_promotion(src, dst, ctx, bit_field) ? "6.3.1.1p2 integer promotion" : integer_clause(src, dst)
    } elif (kind == "IntegralToFloating") {
        return "6.3.1.4p2 integer to real floating"
    } elif (kind == "FloatingToIntegral") {
        return "6.3.1.4p1 real floating to integer"
    } elif (kind == "FloatingCast") {
        let widened = (src == "float" && dst != "float") || (src == "double" && dst == "ldouble")
        return widened ? "6.3.1.5 real floating widened" : "6.3.1.5 real floating narrowed"
    } elif (kind == "NullToPointer") {
        return "6.3.2.3p3 null pointer constant"
    } elif (kind == "IntegralToPointer") {
        return "6.3.2.3p5 integer to pointer"
    } elif (kind == "PointerToIntegral") {
        return "6.3.2.3p6 pointer to integer"
    }
    return pointer_clause(kind, src, dst, is_explicit, null_operand)
}

// the clause of a `BitCast` or `NoOp` from `src` to `dst`, and of any conversion no clause names
def private pointer_clause(kind, src, dst : string; is_explicit, null_operand : bool) : string {
    if (kind == "BitCast" && null_operand && is_pointer_class(dst)) {
        return "6.3.2.3p4 null pointer to another pointer type"
    } elif (kind == "BitCast" && ((src == "void*" && dst == "objptr") || (src == "objptr" && dst == "void*"))) {
        return "6.3.2.3p1 void pointer to and from object pointer"
    } elif (kind == "BitCast" && (src == "objptr" || src == "void*") && (dst == "objptr" || dst == "void*")) {
        return "6.3.2.3p7 object pointer to object pointer"
    } elif (kind == "BitCast" && src == "fnptr" && dst == "fnptr") {
        return "6.3.2.3p8 function pointer to function pointer"
    } elif (kind == "NoOp" && is_pointer_class(src) && src == dst && !is_explicit) {
        return "6.3.2.3p2 pointer to a more qualified type"
    } elif (kind == "NoOp" && is_explicit && src == dst) {
        return "6.5.4 cast to the same type"
    }
    return "no clause: {kind} {src} -> {dst}"
}

let private CONTEXT_RULE_OF <- {
    "shift" => "6.5.7p3 shift operand promotion",
    "unary arithmetic" => "6.5.3.3 unary operand promotion",
    "logical" => "6.5.13-6.5.14 logical operand",
    "unary not" => "6.5.3.3p5 logical negation operand",
    "assign rhs" => "6.5.16.1 simple assignment",
    "compound rhs" => "6.5.16.2 compound assignment",
    "argument prototyped" => "6.5.2.2p7 prototyped argument",
    "argument variadic" => "6.5.2.2p6-7 default argument promotion (variadic)",
    "argument unprototyped" => "6.5.2.2p6 default argument promotion (no prototype)",
    "argument K&R definition" => "K&R definition argument converted to the parameter type (clang, not 6.5.2.2p6)",
    "return" => "6.8.6.4p3 return",
    "init scalar" => "6.7.9p11 scalar initializer",
    "init element" => "6.7.9 aggregate element initializer",
    "?: arm" => "6.5.15p3-6 conditional operator arms",
    "condition if" => "6.8.4-6.8.5 controlling expression",
    "condition while" => "6.8.4-6.8.5 controlling expression",
    "condition do" => "6.8.4-6.8.5 controlling expression",
    "condition for" => "6.8.4-6.8.5 controlling expression",
    "condition ?:" => "6.5.15p2 conditional operator condition",
    "switch" => "6.8.4.2p5 switch promotion",
    "subscript index" => "6.5.2.1 subscript",
    "subscript base" => "6.5.2.1 subscript"
}

// the context rule of an implicit conversion of `kind` from `src` to `dst` in context `ctx`
def private context_rule(kind, src, dst, ctx : string; bit_field : bool) : string {
    if (ctx == "binary arithmetic" || ctx == "comparison" || ctx == "bitwise") {
        if (is_pointer_class(dst) || is_pointer_class(src)) {
            return "6.5.6-6.5.9 pointer operand"
        }
        return (kind == "IntegralCast" && is_promotion(src, dst, ctx, bit_field)) ? "6.3.1.1p2 integer promotion (binary operand)" : "6.3.1.8 usual arithmetic conversions"
    }
    return CONTEXT_RULE_OF?[ctx] ?? "context {ctx}"
}

//! The rule a cast of `kind` from `src` to `dst` in context `ctx` applies: an explicit cast is
//! `6.5.4 cast operator: <kind>`; an lvalue, array, function or null pointer conversion is its
//! 6.3.2 rule, whatever the context (a decayed string literal, `string_operand`, and a callee's
//! decay named apart); any other implicit conversion is its context's rule and its kind,
//! `bit_field` as `is_promotion` takes it.
def cast_rule(kind, src, dst, ctx : string; is_explicit, string_operand : bool; bit_field : bool = false) : string {
    if (is_explicit) {
        return "6.5.4 cast operator: {kind}"
    } elif (kind == "LValueToRValue") {
        return dst == "record" ? "6.3.2.1p2 lvalue conversion (record)" : "6.3.2.1p2 lvalue conversion"
    } elif (kind == "ArrayToPointerDecay") {
        return string_operand ? "6.3.2.1p3 array decay (string literal)" : "6.3.2.1p3 array decay"
    } elif (kind == "FunctionToPointerDecay") {
        return ctx == "callee" ? "6.3.2.1p4 function decay (callee)" : "6.3.2.1p4 function decay (value)"
    } elif (kind == "NullToPointer") {
        return "6.3.2.3p3 null pointer constant"
    }
    return "{context_rule(kind, src, dst, ctx, bit_field)}: {kind}"
}

let private BINARY_CONTEXTS <- {
    "add" => "binary arithmetic", "sub" => "binary arithmetic", "mul" => "binary arithmetic", "div" => "binary arithmetic", "rem" => "binary arithmetic",
    "lt" => "comparison", "gt" => "comparison", "le" => "comparison", "ge" => "comparison", "eq" => "comparison", "ne" => "comparison",
    "band" => "bitwise", "bor" => "bitwise", "bxor" => "bitwise",
    "shl" => "shift", "shr" => "shift",
    "land" => "logical", "lor" => "logical"
}

let private UNARY_CONTEXTS <- {
    "neg" => "unary arithmetic", "plus" => "unary arithmetic", "bnot" => "unary arithmetic", "not" => "unary not",
    "addr" => "unary address", "deref" => "unary deref",
    "preinc" => "increment", "predec" => "increment", "postinc" => "increment", "postdec" => "increment"
}

// what a walk knows beyond the context: whether the expression walked stands in an argument of a
// `__builtin_*` call
struct private Walk {
    builtin_args : bool
}

// whether `x` below its casts is a null pointer constant converted by `NullToPointer`
def private null_operand(x : CirExpr const?) : bool {
    var at = x
    while (at != null && at.e == "cast") {
        if (at.cast_kind == "NullToPointer") {
            return true
        }
        at = at.a
    }
    return false
}

// whether `x` below its casts is a bit-field narrower than `int`, which the C-IR types as its
// declared type
def private narrow_bit_field(tu : CirTu; x : CirExpr const?) : bool {
    let m = below_casts(x)
    if (m == null || m.e != "member" || m.base == null) {
        return false
    }
    var rec = resolved(tu, m.base.t)
    if (m.arrow && rec >= 0 && rec < length(tu.types) && tu.types[rec].k == "ptr") {
        rec = resolved(tu, tu.types[rec].to)
    }
    if (rec < 0 || rec >= length(tu.types) || m.field < 0 || m.field >= length(tu.types[rec].fields)) {
        return false
    }
    return tu.types[rec].fields[m.field].is_bitfield && tu.types[rec].fields[m.field].bit_w < 32
}

// the rule's name before its castKind: the C rule a context and kind key belongs to
def private c_rule(rule : string) : string {
    let colon = find(rule, ": ")
    return colon < 0 ? rule : slice(rule, 0, colon)
}

// the castKinds of the chain from cast `x` down, outermost first, an explicit one marked `!`
def private chain_shape(x : CirExpr const?) : string {
    var kinds : array<string>
    var at = x
    while (at != null && at.e == "cast") {
        kinds |> push(at.explicit_cast ? "{at.cast_kind}!" : at.cast_kind)
        at = at.a
    }
    return join(kinds, " > ")
}

// cast `x` in context `ctx` counted under every dimension; `top` when no cast stands over it
def private count_cast(tu : CirTu; x : CirExpr const?; ctx : string; top : bool; w : Walk; var c : ConversionCensus) {
    let how = x.explicit_cast ? "explicit" : "implicit"
    let src = x.a != null ? type_class(tu, x.a.t) : "?"
    let dst = type_class(tu, x.t)
    let operand = x.a != null ? x.a.e : ""
    c |> bump("total\tcasts")
    c |> bump("kind\t{x.cast_kind}\t{how}")
    c |> bump("pair\t{x.cast_kind}\t{how}\t{src}\t{dst}")
    c |> bump("context\t{x.cast_kind}\t{how}\t{ctx}")
    let bit_field = x.cast_kind == "IntegralCast" && narrow_bit_field(tu, x.a)
    let rule = cast_rule(x.cast_kind, src, dst, ctx, x.explicit_cast, operand == "str_lit", bit_field)
    c |> bump("rule\t{rule}")
    c |> bump("crule\t{c_rule(rule)}")
    c |> bump("clause\t{conversion_clause(x.cast_kind, src, dst, ctx, x.explicit_cast, null_operand(x.a), bit_field)}")
    if (bit_field) {
        c |> bump("anomaly\tIntegralCast {how} of a bit-field narrower than int")
    }
    if (top) {
        let shape = chain_shape(x)
        c |> bump("chain\t{shape}")
        if (length(split(shape, " > ")) >= 3) {
            c |> bump("anomaly\ta chain of three or more casts")
        }
    }
    if (x.cast_kind == "NoOp" && x.a != null && x.a.t == x.t) {
        c |> bump("anomaly\tNoOp {how}, operand and result one C-IR type")
    }
    if (x.cast_kind == "NoOp" && x.a != null && x.a.e == "cast" && x.a.cast_kind == "ArrayToPointerDecay" && x.a.a != null && x.a.a.e == "str_lit") {
        c |> bump("anomaly\tNoOp over a decayed string literal (to a const pointer)")
    }
    if (x.cast_kind == "BitCast" && !x.explicit_cast && (src == "void*" || dst == "void*")) {
        c |> bump("anomaly\tBitCast implicit {src} -> {dst}")
    }
    if (x.cast_kind == "FunctionToPointerDecay") {
        let builtin = x.a != null && x.a.e == "ref" && x.a.name |> starts_with("__builtin_")
        c |> bump(ctx == "callee" ? (builtin ? "anomaly\tFunctionToPointerDecay of a __builtin_ callee" : "anomaly\tFunctionToPointerDecay of a callee") : "anomaly\tFunctionToPointerDecay of a function value")
    }
    if (x.cast_kind == "ArrayToPointerDecay" && operand == "str_lit") {
        c |> bump("anomaly\tArrayToPointerDecay of a string literal")
    }
    if (x.cast_kind == "ToVoid") {
        c |> bump("anomaly\tToVoid {how}")
    }
    if (x.cast_kind == "IntegralToBoolean" || x.cast_kind == "FloatingToBoolean" || x.cast_kind == "PointerToBoolean") {
        c |> bump("anomaly\t{x.cast_kind} in {ctx}")
    }
    if (w.builtin_args) {
        c |> bump("anomaly\ta cast in an argument of a __builtin_ call")
    }
    if (operand == "int_lit" || operand == "float_lit" || operand == "enum_ref") {
        c |> bump("anomaly\t{x.cast_kind} {how} of a literal or enum constant ({operand})")
    }
    if (operand == "call" && x.cast_kind == "IntegralCast" && !x.explicit_cast) {
        c |> bump("anomaly\tIntegralCast implicit directly over a call's result")
    }
    if (!x.explicit_cast && ctx == "cast operand") {
        c |> bump("anomaly\tan implicit cast under an explicit cast")
    }
}

// the function type a callee of type `t` calls through, -1 for none
def private callee_function(tu : CirTu; t : int) : int {
    var at = resolved(tu, t)
    if (at >= 0 && at < length(tu.types) && tu.types[at].k == "ptr") {
        at = resolved(tu, tu.types[at].to)
    }
    return at >= 0 && at < length(tu.types) && tu.types[at].k == "func" ? at : -1
}

// whether the unit defines the function `name` with a K&R definition of more than `idx` parameters,
// whose type has none: clang converts a call's argument to the definition's parameter type
def private knr_parameter(tu : CirTu; name : string; idx : int) : bool {
    for (d in tu.decls) {
        if (d.k == "func" && d.name == name && d.body != null && length(d.params) > idx) {
            return true
        }
    }
    return false
}

// the context of argument `idx` of call `x`: prototyped within the parameters, variadic past them
// of a variadic function, a K&R definition's past the parameters of a function type with none that
// the unit defines with that many, unprototyped past them of any other (the C-IR spells `T ()` as
// `T (void)`)
def private argument_context(tu : CirTu; x : CirExpr const?; idx : int) : string {
    let fn = x.fn != null ? callee_function(tu, x.fn.t) : -1
    if (fn < 0) {
        return "argument unprototyped"
    }
    if (idx < length(tu.types[fn].params)) {
        return "argument prototyped"
    }
    if (tu.types[fn].variadic) {
        return "argument variadic"
    }
    return empty(tu.types[fn].params) && knr_parameter(tu, called_name(*x), idx) ? "argument K&R definition" : "argument unprototyped"
}

// call `x`: its callee and each argument in its context
def private walk_call(tu : CirTu; x : CirExpr const?; w : Walk; var c : ConversionCensus) {
    walk_expr(tu, x.fn, "callee", false, w, c)
    let inner = Walk(builtin_args = w.builtin_args || called_name(*x) |> starts_with("__builtin_"))
    for (idx, arg in range(length(x.args)), x.args) {
        let at = argument_context(tu, x, idx)
        if (at == "argument unprototyped") {
            c |> bump("anomaly\tan argument past the parameters of a function that is not variadic (no prototype)")
        }
        walk_expr(tu, arg, at, false, inner, c)
    }
}

def private walk_expr(tu : CirTu; x : CirExpr const?; ctx : string; under_cast : bool; w : Walk; var c : ConversionCensus) {
    if (x == null) {
        return
    }
    c |> bump("total\texprs")
    if (x.e == "cast") {
        count_cast(tu, x, ctx, !under_cast, w, c)
        walk_expr(tu, x.a, x.explicit_cast ? "cast operand" : ctx, true, w, c)
        return
    }
    if (x.e == "bin") {
        let at = BINARY_CONTEXTS?[x.op] ?? "binary {x.op}"
        walk_expr(tu, x.a, at, false, w, c)
        walk_expr(tu, x.b, at, false, w, c)
    } elif (x.e == "assign") {
        let compound = !empty(x.op)
        if (compound && x.a != null && x.b != null && type_class(tu, x.a.t) != type_class(tu, x.b.t)) {
            c |> bump("anomaly\ta compound assignment whose operands' classes differ (its computation type is not in the C-IR)")
        }
        walk_expr(tu, x.a, compound ? "compound lhs" : "assign lhs", false, w, c)
        walk_expr(tu, x.b, compound ? "compound rhs" : "assign rhs", false, w, c)
    } elif (x.e == "un") {
        walk_expr(tu, x.a, UNARY_CONTEXTS?[x.op] ?? "unary {x.op}", false, w, c)
    } elif (x.e == "cond") {
        walk_expr(tu, x.c, "condition ?:", false, w, c)
        walk_expr(tu, x.a, "?: arm", false, w, c)
        walk_expr(tu, x.b, "?: arm", false, w, c)
    } elif (x.e == "comma") {
        walk_expr(tu, x.a, "comma lhs", false, w, c)
        walk_expr(tu, x.b, "comma rhs", false, w, c)
    } elif (x.e == "call") {
        walk_call(tu, x, w, c)
    } elif (x.e == "member") {
        walk_expr(tu, x.base, "member base", false, w, c)
    } elif (x.e == "index") {
        walk_expr(tu, x.base, "subscript base", false, w, c)
        walk_expr(tu, x.i, "subscript index", false, w, c)
    } elif (x.e == "init_list") {
        for (item in x.init_items) {
            walk_expr(tu, item.v, "init element", false, w, c)
        }
    } elif (x.e == "compound_lit") {
        walk_expr(tu, x.init, "init element", false, w, c)
    } elif (x.e == "va_arg") {
        walk_expr(tu, x.list, "va_arg list", false, w, c)
    }
}

// the context of an initializer `x`: a list's items are aggregate elements, anything else a scalar
def private walk_init(tu : CirTu; x : CirExpr const?; w : Walk; var c : ConversionCensus) {
    walk_expr(tu, x, x != null && x.e == "init_list" ? "init list" : "init scalar", false, w, c)
}

let private CONDITION_CONTEXTS <- {"if" => "condition if", "while" => "condition while", "do" => "condition do", "for" => "condition for", "switch" => "switch"}

def private walk_stmt(tu : CirTu; st : CirStmt const?; w : Walk; var c : ConversionCensus) {
    if (st == null) {
        return
    }
    if (st.s == "decl") {
        walk_init(tu, st.init, w, c)
    } elif (st.s == "expr") {
        walk_expr(tu, st.e, "expr stmt", false, w, c)
    } elif (st.s == "return") {
        walk_expr(tu, st.e, "return", false, w, c)
    } elif (key_exists(CONDITION_CONTEXTS, st.s)) {
        walk_expr(tu, st.cond, CONDITION_CONTEXTS?[st.s] ?? "", false, w, c)
    }
    if (st.s == "for") {
        walk_expr(tu, st.inc, "for inc", false, w, c)
    }
    for (child in st.body) {
        walk_stmt(tu, child, w, c)
    }
    for (child in fixed_array<CirStmt const?>(st.init_s, st.then_s, st.else_s, st.body_s)) {
        walk_stmt(tu, child, w, c)
    }
}

//! Every cast node of `tu` counted into `c`: the initializers of its globals and the bodies of its
//! functions, with the unit itself under `total\tunits`.
def census_tu(tu : CirTu; var c : ConversionCensus) {
    let w = Walk()
    c |> bump("total\tunits")
    for (d in tu.decls) {
        if (d.k == "global") {
            walk_init(tu, d.init, w, c)
        } elif (d.k == "func") {
            walk_stmt(tu, d.body, w, c)
        }
    }
}

//! Every count of `from` added into `c`.
def add_census(var c : ConversionCensus; from : ConversionCensus) {
    for (key, n in keys(from.n), values(from.n)) {
        c |> bump(key, n)
    }
}

//! The lines of `c` in a counts file, `<count>\t<key>` each, sorted by key.
def census_lines(c : ConversionCensus) : array<string> {
    var keys_sorted <- [for (k in keys(c.n)); k]
    sort(keys_sorted)
    return <- [for (k in keys_sorted); "{c.n?[k] ?? 0}\t{k}"]
}

//! A unit's counts as lines of a counts file: its `unit` line, then `census_lines`.
def unit_lines(unit : string; c : ConversionCensus) : array<string> {
    var lines <- ["unit\t{unit}"]
    lines |> push_from(census_lines(c))
    return <- lines
}

//! The counts of the counts file `text` (`unit_lines` of each unit) added into `c`, a unit whose
//! name `seen` already holds skipped, so a unit two programs link is counted once; each unit read is
//! added to `seen`.
def add_counts_file(var c : ConversionCensus; var seen : table<string>; text : string) {
    var counting = true
    for (line in split(text, "\n")) {
        if (line |> starts_with("unit\t")) {
            let unit = slice(line, length("unit\t"))
            counting = !key_exists(seen, unit)
            seen |> insert(unit)
            continue
        }
        var name : string
        var ok : bool
        let n = read_census_line(line, name, ok)
        if (ok && counting) {
            c.n[name] += n
        }
    }
}

//! The count and key of a line of `census_lines`; `ok` is false for a line of another shape.
def read_census_line(line : string; var key : string&; var ok : bool&) : int {
    let tab = find(line, "\t")
    ok = tab > 0 && is_count(slice(line, 0, tab))
    key = ok ? slice(line, tab + 1) : ""
    return ok ? to_int(slice(line, 0, tab)) : 0
}

def private is_count(text : string) : bool {
    for (ch in text) {
        if (!is_number(ch)) {
            return false
        }
    }
    return !empty(text)
}

//! The cast nodes of the C file `c_path` dumped under the `linux` dialect, with the sidecar the
//! converter finds beside it, counted into `c`; `error` is the dumper's when it refuses the file.
def census_c_file(c_path : string; var c : ConversionCensus; var error : string&) {
    let side <- read_sidecar(find_sidecar(c_path, ""), error)
    if (!empty(error)) {
        return
    }
    // on the heap: a `Dumper` in this frame would take a fifth of das's default stack
    var d = new Dumper
    dump_tu(*d, c_path, target_by_name("linux"), default_clang(), dump_inputs(side))
    error = d.error
    if (empty(error)) {
        census_tu(d.tu, c)
    }
    delete_tu(d.tu)
    unsafe {
        delete d
    }
}

//! The cast nodes of the C-IR file `path` counted into `c`; `error` when it does not read.
def census_cir_file(path : string; var c : ConversionCensus; var error : string&) {
    var tu <- read_cir(fread(path), error)
    if (empty(error)) {
        census_tu(tu, c)
    }
    delete_tu(tu)
}

//! A row of the report: an input set's name and its census.
struct CensusRow {
    name : string
    c : ConversionCensus
}

//! The entries of dimension `dim` of `c`, the key's fields after the dimension, most frequent
//! first, ties by key.
def entries(c : ConversionCensus; dim : string) : array<tuple<key : string; n : int>> {
    let prefix = "{dim}\t"
    var out <- [for (key, n in keys(c.n), values(c.n)); (key = slice(key, length(prefix)), n = n); where key |> starts_with(prefix)]
    sort(out) <| cmp_by(-_.n, _.key)
    return <- out
}

//! `part` of `whole` in percent with two decimals, `-` for an empty whole.
def percent(part, whole : int) : string {
    if (whole == 0) {
        return "-"
    }
    let hundredths = (int64(part) * 10000l + int64(whole) / 2l) / int64(whole)
    let frac = int(hundredths % 100l)
    return "{hundredths / 100l}.{frac < 10 ? "0" : ""}{frac}%"
}

def private md_row(cells : array<string>) : string => "| " + join(cells, " | ") + " |\n"

def private md_head(cells : array<string>) : string => md_row(cells) + md_row([for (_ in cells); "---"])

def private casts_of(c : ConversionCensus) : int => count_of(c, "total\tcasts")

//! The castKind table: per kind its implicit and explicit nodes, their total and its share of all
//! casts, most frequent first.
def render_kinds(c : ConversionCensus) : string {
    var totals : table<string; int>
    for (e in entries(c, "kind")) {
        totals[split(e.key, "\t")[0]] += e.n
    }
    var kinds <- [for (k in keys(totals)); k]
    sort(kinds) <| cmp_by(-(totals?[_] ?? 0), _)
    let all = casts_of(c)
    return md_head(["castKind", "implicit", "explicit", "total", "share"]) + join([for (k in kinds); kind_row(c, k, totals?[k] ?? 0, all)], "")
}

// the castKind table's row of kind `k`, `total` its nodes of `all` casts
def private kind_row(c : ConversionCensus; k : string; total, all : int) : string {
    let implicit_n = count_of(c, "kind\t{k}\timplicit")
    let explicit_n = count_of(c, "kind\t{k}\texplicit")
    return md_row([k, "{implicit_n}", "{explicit_n}", "{total}", percent(total, all)])
}

// the rows of a dimension whose keys start with castKind and `implicit` or `explicit`, grouped by
// the kind's total, at most `limit` rows per kind and form (0: all)
def private render_by_kind(c : ConversionCensus; dim : string; head : array<string>; limit : int) : string {
    var totals : table<string; int>
    for (e in entries(c, "kind")) {
        totals[split(e.key, "\t")[0]] += e.n
    }
    var shown : table<string; int>
    var rows <- entries(c, dim)
    sort(rows) <| cmp_by(-(totals?[split(_.key, "\t")[0]] ?? 0), split(_.key, "\t")[0], -_.n, _.key)
    return md_head(head) + build_string() $(var w) {
        for (e in rows) {
            var inscope fields <- split(e.key, "\t")
            let group = "{fields[0]}\t{fields[1]}"
            if (limit > 0 && (shown?[group] ?? 0) >= limit) {
                continue
            }
            shown[group]++
            fields |> push("{e.n}")
            w |> write(md_row(fields))
        }
    }
}

//! The pair table: per castKind and form the operand class and result class pairs with their
//! counts, at most `limit` pairs per kind and form (0: all).
def render_pairs(c : ConversionCensus; limit : int) : string => render_by_kind(c, "pair", ["castKind", "form", "from", "to", "count"], limit)

//! The context table: per castKind and form the contexts with their counts.
def render_contexts(c : ConversionCensus; limit : int) : string => render_by_kind(c, "context", ["castKind", "form", "context", "count"], limit)

//! The number of keys of dimension `dim` (`rule`, the context and kind keys, or `crule`, the C
//! rules), most frequent first, whose casts reach `share` percent of all casts.
def rules_covering(c : ConversionCensus; share : int; dim : string = "rule") : int {
    let all = casts_of(c)
    var sum = 0
    let ranked <- entries(c, dim)
    for (idx, e in count(), ranked) {
        sum += e.n
        if (int64(sum) * 100l >= int64(all) * int64(share)) {
            return idx + 1
        }
    }
    return length(ranked)
}

//! The ranked table of dimension `dim` (`rule` or `crule`): every key the casts hit, most frequent
//! first, its count, share and the cumulative share down to it.
def render_rules(c : ConversionCensus; dim : string = "rule") : string {
    let all = casts_of(c)
    var sum = 0
    return md_head(["#", dim == "crule" ? "C rule" : "rule (C rule: castKind)", "count", "share", "cumulative"]) + build_string() $(var w) {
        for (idx, e in count(), entries(c, dim)) {
            sum += e.n
            w |> write(md_row(["{idx + 1}", e.key, "{e.n}", percent(e.n, all), percent(sum, all)]))
        }
    }
}

//! The clause table: every clause of `CLAUSES` in order, `never` for one no cast applies, then any
//! conversion no clause names.
def render_clauses(c : ConversionCensus) : string {
    let all = casts_of(c)
    return md_head(["clause", "count", "share"]) + build_string() $(var w) {
        for (name in CLAUSES) {
            let n = count_of(c, "clause\t{name}")
            w |> write(md_row([name, n == 0 ? "never" : "{n}", percent(n, all)]))
        }
        for (e in entries(c, "clause")) {
            if (!has_value(CLAUSES, e.key)) {
                w |> write(md_row([e.key, "{e.n}", percent(e.n, all)]))
            }
        }
    }
}

//! The chain table: the `limit` most frequent chain shapes, outermost cast first, `!` marking an
//! explicit one, each with its count and share of all chains.
def render_chains(c : ConversionCensus; limit : int) : string {
    let chains <- entries(c, "chain")
    var all = 0
    for (e in chains) {
        all += e.n
    }
    return md_head(["chain", "count", "share of chains"]) + join([for (idx, e in count(), chains); md_row([e.key, "{e.n}", percent(e.n, all)]); where idx < limit], "")
}

//! The anomaly table: each anomaly with its count, most frequent first.
def render_anomalies(c : ConversionCensus) : string =>
    md_head(["anomaly", "count"]) + join([for (e in entries(c, "anomaly")); md_row([e.key, "{e.n}"])], "")

//! The castKinds of the pinned list no cast of `c` has, sorted.
def never_kinds(c : ConversionCensus) : array<string> {
    var seen : table<string>
    for (e in entries(c, "kind")) {
        seen |> insert(split(e.key, "\t")[0])
    }
    var out <- [for (k in keys(CAST_KINDS)); k; where !key_exists(seen, k)]
    sort(out)
    return <- out
}

//! The contexts of `CONTEXTS` no cast of `c` stands in, in their order.
def never_contexts(c : ConversionCensus) : array<string> {
    var seen : table<string>
    for (e in entries(c, "context")) {
        seen |> insert(split(e.key, "\t")[2])
    }
    return <- [for (ctx in CONTEXTS); ctx; where !key_exists(seen, ctx)]
}

//! The context rules of `CONTEXT_RULES` no implicit cast of `c` applies, in their order.
def never_context_rules(c : ConversionCensus) : array<string> {
    var seen : table<string>
    for (e in entries(c, "crule")) {
        seen |> insert(e.key)
    }
    return <- [for (r in CONTEXT_RULES); r; where !key_exists(seen, r)]
}

def private listed(names : array<string>) : string => empty(names) ? "none" : join([for (n in names); "`{n}`"], ", ")

//! The report of one input set: its totals line, then the castKind, rule, clause, context, pair,
//! chain and anomaly tables and the never-met lists; `limit` bounds the pairs and contexts shown
//! per castKind and form (0: all).
def render_set(row : CensusRow; limit : int) : string {
    let c & = unsafe(row.c)
    var implicit_n = 0
    for (e in entries(c, "kind")) {
        implicit_n += e.key |> ends_with("\timplicit") ? e.n : 0
    }
    let all = casts_of(c)
    let units = count_of(c, "total\tunits")
    let exprs = count_of(c, "total\texprs")
    let keys_n = length(entries(c, "rule"))
    let crules_n = length(entries(c, "crule"))
    let keys_99 = rules_covering(c, 99)
    let crules_99 = rules_covering(c, 99, "crule")
    var out = "### {row.name}\n\n{units} units, {exprs} expression nodes, {all} casts ({implicit_n} implicit, {all - implicit_n} explicit); {crules_n} C rules, {crules_99} of them cover 99% of the casts; {keys_n} C rule and castKind keys, {keys_99} of them cover 99%.\n\n"
    out += "castKinds:\n\n{render_kinds(c)}\nC rules, most frequent first:\n\n{render_rules(c, "crule")}\nC rule and castKind keys, most frequent first:\n\n{render_rules(c)}\nC11 6.3 clauses:\n\n{render_clauses(c)}\n"
    out += "Contexts:\n\n{render_contexts(c, limit)}\nOperand and result classes:\n\n{render_pairs(c, limit)}\nChains, top 30:\n\n{render_chains(c, 30)}\nAnomalies:\n\n{render_anomalies(c)}\n"
    out += "castKinds never met: {listed(never_kinds(c))}.\n\nContexts never met: {listed(never_contexts(c))}.\n\nContext rules never met: {listed(never_context_rules(c))}.\n\n"
    return out
}

// `text` as a JSON string
def private json_string(text : string) : string =>
    "\"" + replace(replace(replace(text, "\\", "\\\\"), "\"", "\\\""), "\t", " | ") + "\""

//! The raw counts of `rows` as JSON: an object of row name to dimension to key (its fields joined
//! by ` | `) to count, keys sorted.
def render_json(rows : array<CensusRow>) : string {
    var sets : array<string>
    sets |> reserve(length(rows))
    for (row in rows) {
        var inscope dims : array<string>
        dims |> reserve(length(DIMENSIONS))
        for (dim in DIMENSIONS) {
            var inscope es <- entries(row.c, dim)
            sort(es) <| cmp_by(_.key)
            dims |> push("    {json_string(dim)}: \{" + join([for (e in es); "\n      {json_string(e.key)}: {e.n}"], ",") + (empty(es) ? "}" : "\n    }"))
        }
        sets |> push("  {json_string(row.name)}: \{\n" + join(dims, ",\n") + "\n  }")
    }
    return "\{\n" + join(sets, ",\n") + "\n}\n"
}
