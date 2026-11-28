options gen2
options indenting = 4

module c_exprs public

require math
require strings
require daslib/strings_boost
require c_floats public
require c_types public

//! The expressions of a unit as Dumper A writes them (`ARCHITECTURE_EXPRS.md`): each parser
//! expression a C-IR expression node whose `t` is its pool type, with every conversion clang makes
//! as a `cast` node of clang's `castKind` on the node clang puts it on. `c_exprs_use` turns the
//! pool types into table indices, in the order Dumper A interns them.

//! What an identifier names where the walk stands: a variable or a function, its declared pool
//! type, the parameter types an old-style definition's calls convert to, and whether its
//! declaration has a prototype.
struct CId {
    t : int
    is_function : bool
    proto : bool
    old_style : int     //!< the pool function type an old-style definition's calls convert by, -1 for none
    builtin : bool      //!< a builtin function of `BUILTIN_FUNCTIONS`, referenced only as a callee
}

//! The builtin functions the builder types, each with its prototype's result and parameter
//! spellings as clang declares it.
let BUILTIN_FUNCTIONS <- [(name = "__builtin_expect", ret = "long", params = ["long", "long"])]

//! The state of a unit's expressions: the type builder, the identifiers in scope and the return
//! type of the function being read.
struct CIr {
    b : CTypes
    ids : table<int; CId>
    id_undo : array<tuple<sym : int; had : bool; was : CId>>
    id_marks : array<int>
    ret : int
}

//! Bind identifier `sym` to `id` in the innermost scope.
def c_ir_bind(var r : CIr; sym : int; id : CId) {
    let had = key_exists(r.ids, sym)
    r.id_undo |> push((sym = sym, had = had, was = had ? r.ids?[sym] ?? id : id))
    r.ids[sym] = id
}

//! Open a scope of identifiers.
def c_ir_open(var r : CIr) {
    r.id_marks |> push(length(r.id_undo))
}

//! Close the innermost scope of identifiers: its bindings are undone.
def c_ir_close(var r : CIr) {
    let mark = r.id_marks[length(r.id_marks) - 1]
    r.id_marks |> pop()
    var at = length(r.id_undo) - 1
    while (at >= mark) {
        let entry = r.id_undo[at]
        if (entry.had) {
            r.ids[entry.sym] = entry.was
        } else {
            r.ids |> erase(entry.sym)
        }
        at--
    }
    r.id_undo |> resize(mark)
}

// the kind of pool type `t`
def private kind_of(r : CIr; t : int) : string => r.b.pool[t].k

def private is_int(r : CIr; t : int) : bool => r.b.pool[t].k == "int"

def private is_float(r : CIr; t : int) : bool => r.b.pool[t].k == "float"

def private is_arith(r : CIr; t : int) : bool => is_int(r, t) || is_float(r, t)

def private is_ptr(r : CIr; t : int) : bool => r.b.pool[t].k == "ptr"

def private is_bool(r : CIr; t : int) : bool => r.b.pool[t].k == "int" && r.b.pool[t].spell == "_Bool"

def private unq(r : CIr; t : int) : int => r.b.unqualified[t]

// whether pool type `t` is a pointer to unqualified `void`
def private is_void_ptr(r : CIr; t : int) : bool => is_ptr(r, t) && r.b.pool[r.b.pool[t].to].k == "void" && r.b.quals[r.b.pool[t].to] == 0

// whether pool type `t` points at `void`, qualified or not
def private points_at_void(r : CIr; t : int) : bool => is_ptr(r, t) && r.b.pool[r.b.pool[t].to].k == "void"

//! Pool type `t` with no qualifier at any level: the type the table gives it.
def c_bare(var r : CIr; t : int) : int {
    let u = unq(r, t)
    let k = r.b.pool[u].k
    if (k == "ptr") {
        let to = c_bare(r, r.b.pool[u].to)
        return c_pointer(r.b, to)
    } elif (k == "array") {
        let count = r.b.pool[u].count
        let elem = c_bare(r, r.b.pool[u].elem)
        return c_array(r.b, elem, count)
    } elif (k == "func") {
        let variadic = r.b.pool[u].variadic
        let parts := r.b.pool[u].params
        var params <- [for (x in parts); c_bare(r, x)]
        let ret = c_bare(r, r.b.pool[u].ret)
        return c_function(r.b, ret, params, variadic)
    }
    return u
}

// a new implicit or explicit cast of `kind` to pool type `t` over `x`
def private cast_node(var x : CirExpr?; t : int; kind : string; is_explicit : bool = false) : CirExpr? =>
    new CirExpr(e = "cast", t = t, cast_kind = kind, explicit_cast = is_explicit, a = x)

//! `x` converted to pool type `t` by an implicit cast of `kind`, as clang's `ImpCastExprToType`:
//! none when `x` has that type already, the cast `x` is retyped when it is an implicit one of the
//! same kind (a promotion and the conversion after it are one cast).
[arch(at="ARCHITECTURE_EXPRS.md#c-exprs-casts")]
def c_implicit(var x : CirExpr?; t : int; kind : string) : CirExpr? {
    return x if (x.t == t)
    if (x.e == "cast" && !x.explicit_cast && x.cast_kind == kind) {
        x.t = t
        return x
    }
    return cast_node(x, t, kind)
}

// whether node `x` designates an object: a variable, a string literal, a subscript, a dereference
// of an object pointer
def private is_lvalue(r : CIr; x : CirExpr?) : bool {
    if (x.e == "ref" || x.e == "index" || x.e == "str_lit") {
        return kind_of(r, x.t) != "func"
    }
    return x.e == "un" && x.op == "deref" && kind_of(r, x.t) != "func"
}

//! `x` as a value (C11 6.3.2.1): a function decays to a pointer to it, an array lvalue to a
//! pointer to its first element, any other lvalue is read (`LValueToRValue`, its type unqualified).
[arch(at="ARCHITECTURE_EXPRS.md#c-exprs-casts")]
def c_rvalue(var r : CIr; var x : CirExpr?) : CirExpr? {
    let k = kind_of(r, x.t)
    if (k == "func") {
        return cast_node(x, c_pointer(r.b, x.t), "FunctionToPointerDecay")
    } elif (k == "array" && is_lvalue(r, x)) {
        return cast_node(x, c_pointer(r.b, r.b.pool[x.t].elem), "ArrayToPointerDecay")
    } elif (is_lvalue(r, x)) {
        return cast_node(x, unq(r, x.t), "LValueToRValue")
    }
    return x
}

// the pool type `int`
def private int_t(var r : CIr) : int => c_builtin(r.b, "int")

//! `x` as a value under the integer promotions (C11 6.3.1.1p2): an integer narrower than `int`
//! is `int` (clang's usual unary conversions).
[arch(at="ARCHITECTURE_EXPRS.md#c-exprs-operands")]
def c_promote(var r : CIr; var x : CirExpr?) : CirExpr? {
    var v = c_rvalue(r, x)
    if (is_int(r, v.t) && r.b.pool[v.t].w < r.b.tu.target.int_w) {
        return c_implicit(v, int_t(r), "IntegralCast")
    }
    return v
}

// the rank of integer pool type `t` (C11 6.3.1.1p1) by its spelling
def private rank(r : CIr; t : int) : int {
    let spell = r.b.pool[t].spell
    let base = starts_with(spell, "unsigned ") ? slice(spell, length("unsigned ")) : spell
    return base == "long long" ? 5 : base == "long" ? 4 : base == "int" ? 3 : base == "short" ? 2 : base == "_Bool" ? 0 : 1
}

// the unsigned type of the rank of signed integer pool type `t`
def private unsigned_of(var r : CIr; t : int) : int => c_builtin(r.b, "unsigned {r.b.pool[t].spell}")

// the castKind of an arithmetic conversion from pool type `from` to `to`
def private arith_kind(r : CIr; from, to : int) : string {
    if (is_bool(r, to)) {
        return is_float(r, from) ? "FloatingToBoolean" : "IntegralToBoolean"
    } elif (is_int(r, from)) {
        return is_int(r, to) ? "IntegralCast" : "IntegralToFloating"
    }
    return is_int(r, to) ? "FloatingToIntegral" : "FloatingCast"
}

// the common real type of promoted arithmetic pool types `a` and `b` (C11 6.3.1.8)
def private common_type(var r : CIr; a, b : int) : int {
    return a if (a == b)
    if (is_float(r, a) || is_float(r, b)) {
        let wa = is_float(r, a) ? (r.b.pool[a].spell == "long double" ? 3 : r.b.pool[a].w == 64 ? 2 : 1) : 0
        let wb = is_float(r, b) ? (r.b.pool[b].spell == "long double" ? 3 : r.b.pool[b].w == 64 ? 2 : 1) : 0
        return wa >= wb ? a : b
    }
    let sa = r.b.pool[a].is_signed
    let sb = r.b.pool[b].is_signed
    if (sa == sb) {
        return rank(r, a) >= rank(r, b) ? a : b
    }
    let u = sa ? b : a
    let s = sa ? a : b
    if (rank(r, u) >= rank(r, s)) {
        return u
    } elif (r.b.pool[s].w > r.b.pool[u].w) {
        return s
    }
    return unsigned_of(r, s)
}

//! The usual arithmetic conversions of `a` and `b` (C11 6.3.1.8): each promoted, then the one of
//! the other type converted to the common type; the common type returned.
[arch(at="ARCHITECTURE_EXPRS.md#c-exprs-operands")]
def c_arith(var r : CIr; var a, b : CirExpr?&) : int {
    a = c_promote(r, a)
    b = c_promote(r, b)
    let common = common_type(r, a.t, b.t)
    a = c_implicit(a, common, arith_kind(r, a.t, common))
    b = c_implicit(b, common, arith_kind(r, b.t, common))
    return common
}

// the value `v` held in integer pool type `t`: wrapped to its width, sign-extended when signed
def private held_in(r : CIr; t : int; v : int64) : int64 {
    let w = r.b.pool[t].w
    return v if (r.b.pool[t].k != "int" || w >= 64)
    let low = v & ((1l << int64(w)) - 1l)
    return r.b.pool[t].is_signed && (low >> int64(w - 1)) != 0l ? low - (1l << int64(w)) : low
}

//! The value of integer constant expression `x` (C11 6.6) into `v`: literals, integer casts, the
//! unary, binary, logical and conditional operators, `sizeof`; false for any other node.
[arch(at="ARCHITECTURE_EXPRS.md#c-exprs-constants")]
def c_fold(r : CIr; x : CirExpr?; var v : int64&) : bool {
    return false if (x == null || !is_int(r, x.t))
    if (x.e == "int_lit") {
        var u = 0ul
        for (ch in x.v) {
            u = u * 10ul + uint64(ch - '0')
        }
        v = held_in(r, x.t, int64(u))
        return true
    } elif (x.e == "sizeof_v") {
        v = int64(x.trait_v)
        return true
    } elif (x.e == "cast") {
        return fold_cast(r, x, v)
    } elif (x.e == "un") {
        var a = 0l
        return false if (!c_fold(r, x.a, a))
        v = held_in(r, x.t, x.op == "neg" ? -a : x.op == "bnot" ? ~a : x.op == "not" ? (a == 0l ? 1l : 0l) : a)
        return x.op == "neg" || x.op == "bnot" || x.op == "not" || x.op == "plus"
    } elif (x.e == "cond") {
        var c = 0l
        return false if (!c_fold(r, x.c, c))
        return c_fold(r, c != 0l ? x.a : x.b, v)
    }
    var a, b : int64
    return false if (x.e != "bin" || !c_fold(r, x.a, a) || !c_fold(r, x.b, b) || !fold_binary(x.op, !r.b.pool[x.a.t].is_signed, a, b, v))
    v = held_in(r, x.t, v)
    return true
}

// the value of integer cast `x` into `v`: of an integer constant expression, or of a floating
// constant cast at once to the integer type (C11 6.6p6), truncated toward zero
def private fold_cast(r : CIr; x : CirExpr?; var v : int64&) : bool {
    var inner = 0l
    if (x.explicit_cast && x.a != null && x.a.e == "float_lit") {
        // a floating constant's value the integer type does not hold is no integer constant (C11 6.3.1.4p1)
        return false if (!c_float_integer(x.a.v, inner) || (!is_bool(r, x.t) && held_in(r, x.t, inner) != inner))
    } elif (x.a == null || !is_int(r, x.a.t) || !c_fold(r, x.a, inner)) {
        return false
    }
    v = is_bool(r, x.t) ? (inner != 0l ? 1l : 0l) : held_in(r, x.t, inner)
    return true
}

// the value of binary C-IR operator `op` over `a` and `b`, unsigned when `unsigned_operands`;
// false for a division by zero
def private fold_binary(op : string; unsigned_operands : bool; a, b : int64; var v : int64&) : bool {
    if ((op == "div" || op == "rem") && b == 0l) {
        return false
    } elif (op == "add" || op == "sub" || op == "mul") {
        v = op == "add" ? a + b : op == "sub" ? a - b : a * b
    } elif (op == "div" || op == "rem") {
        let ua = uint64(a)
        let ub = uint64(b)
        v = unsigned_operands ? int64(op == "div" ? ua / ub : ua % ub) : op == "div" ? a / b : a % b
    } elif (op == "shl" || op == "shr") {
        v = op == "shl" ? a << b : unsigned_operands ? int64(uint64(a) >> uint64(b)) : a >> b
    } elif (op == "band" || op == "bor" || op == "bxor") {
        v = op == "band" ? (a & b) : op == "bor" ? (a | b) : (a ^ b)
    } else {
        v = truth_of(op, unsigned_operands, a, b) ? 1l : 0l
    }
    return true
}

// the truth of logical or comparison C-IR operator `op` over `a` and `b`, unsigned when
// `unsigned_operands`
def private truth_of(op : string; unsigned_operands : bool; a, b : int64) : bool {
    if (op == "land" || op == "lor") {
        return op == "land" ? a != 0l && b != 0l : a != 0l || b != 0l
    }
    let less = unsigned_operands ? uint64(a) < uint64(b) : a < b
    let greater = unsigned_operands ? uint64(a) > uint64(b) : a > b
    return op == "lt" ? less : op == "gt" ? greater : op == "le" ? !greater : op == "ge" ? !less : op == "eq" ? a == b : a != b
}

//! Whether `x` is a null pointer constant (C11 6.3.2.3p3): an integer constant expression of value
//! 0, or one cast to `void *`.
[arch(at="ARCHITECTURE_EXPRS.md#c-exprs-constants")]
def c_is_null(r : CIr; x : CirExpr?) : bool {
    var v = 1l
    if (is_int(r, x.t)) {
        return c_fold(r, x, v) && v == 0l
    }
    return x.e == "cast" && x.explicit_cast && x.cast_kind == "NullToPointer" && is_void_ptr(r, x.t)
}

//! The composite of pool types `a` and `b` with no qualifier at any level (C11 6.2.7p3), -1 for
//! incompatible ones: an array of unknown size takes the other's size, a function with no
//! parameter the other's list (the pool keeps no prototype mark, so `()` and `(void)` are one).
def c_composite(var r : CIr; a, b : int) : int {
    return a if (a == b)
    // copies: the pool grows below, which moves its elements
    let x := r.b.pool[a]
    let y := r.b.pool[b]
    return -1 if (x.k != y.k)
    if (x.k == "ptr") {
        let to = c_composite(r, x.to, y.to)
        return to < 0 ? -1 : c_pointer(r.b, to)
    } elif (x.k == "array") {
        let elem = c_composite(r, x.elem, y.elem)
        return -1 if (elem < 0 || (x.count >= 0 && y.count >= 0 && x.count != y.count))
        return c_array(r.b, elem, x.count >= 0 ? x.count : y.count)
    } elif (x.k == "func") {
        return composite_function(r, a, b, x, y)
    }
    return -1
}

// the composite of function types `a` and `b` (`x` and `y`, their copies), -1 for incompatible ones
def private composite_function(var r : CIr; a, b : int; x, y : CirType) : int {
    let ret = c_composite(r, x.ret, y.ret)
    return -1 if (ret < 0)
    let x_open = empty(x.params) && !x.variadic
    let y_open = empty(y.params) && !y.variadic
    return (y_open ? a : b) if (x_open || y_open)
    return -1 if (length(x.params) != length(y.params) || x.variadic != y.variadic)
    var params : array<int>
    params |> reserve(length(x.params))
    for (p, q in x.params, y.params) {
        let bare_p = c_bare(r, p)
        let bare_q = c_bare(r, q)
        let c = c_composite(r, bare_p, bare_q)
        return -1 if (c < 0)
        params |> push(c)
    }
    return c_function(r.b, ret, params, x.variadic)
}

// the composite of the types pointers `a` and `b` point at, qualifiers aside; -1 for incompatible ones
def private pointee_composite(var r : CIr; a, b : int) : int {
    let to_a = c_bare(r, r.b.pool[a].to)
    let to_b = c_bare(r, r.b.pool[b].to)
    return c_composite(r, to_a, to_b)
}

// whether a pointer of pool type `from` assigns to one of type `to` (C11 6.5.16.1p1): pointers to
// compatible types, qualifiers aside, or one to `void`; and, as clang takes it with a warning
// (`pointer-sign`), pointers to integer types of one width that differ in sign
def private pointers_assign(var r : CIr; from, to : int) : bool {
    return true if (points_at_void(r, from) || points_at_void(r, to))
    let a = c_bare(r, r.b.pool[from].to)
    let b = c_bare(r, r.b.pool[to].to)
    return true if (is_int(r, a) && is_int(r, b) && r.b.pool[a].w == r.b.pool[b].w)
    return pointee_composite(r, from, to) >= 0
}

//! `x` converted as by assignment to pool type `to` (C11 6.5.16.1, clang's copy initialization):
//! read as a value, then cast by the two types; `to`'s own qualifiers are dropped first. A pair
//! of types clang rejects - an integer and a pointer either way but a null pointer constant and
//! `_Bool`, pointers to incompatible types, a value of no scalar type for a scalar - is invalid C,
//! null with the error set at token `tok`.
[arch(at="ARCHITECTURE_EXPRS.md#c-exprs-slots")]
def c_assigned(var r : CIr; var p : CParser; var x : CirExpr?; target, tok : int) : CirExpr? {
    let to = unq(r, target)
    let is_null = c_is_null(r, x)
    var v = c_rvalue(r, x)
    return v if (v.t == to)
    if (is_arith(r, to) && is_arith(r, v.t)) {
        return c_implicit(v, to, arith_kind(r, v.t, to))
    } elif (is_ptr(r, to) && is_null) {
        return c_implicit(v, to, "NullToPointer")
    } elif (is_ptr(r, to) && is_ptr(r, v.t) && pointers_assign(r, v.t, to)) {
        return c_implicit(v, to, c_bare(r, v.t) == c_bare(r, to) ? "NoOp" : "BitCast")
    } elif (is_bool(r, to) && is_ptr(r, v.t)) {
        return c_implicit(v, to, "PointerToBoolean")
    }
    c_reject(r.b, p, tok, "a value of this type in a slot of that type")
    return null
}

// the castKind of explicit cast of value `v` to pool type `to`, "" for a pair clang refuses
def private explicit_kind(var r : CIr; v : CirExpr?; to : int) : string {
    let from = v.t
    if (kind_of(r, to) == "void") {
        return "ToVoid"
    } elif (c_bare(r, from) == c_bare(r, to)) {
        return "NoOp"
    } elif (is_arith(r, to) && is_arith(r, from)) {
        return arith_kind(r, from, to)
    } elif (is_ptr(r, to)) {
        return c_is_null(r, v) && is_int(r, from) ? "NullToPointer" : is_int(r, from) ? "IntegralToPointer" : is_ptr(r, from) ? "BitCast" : ""
    } elif (is_ptr(r, from)) {
        return is_bool(r, to) ? "PointerToBoolean" : is_int(r, to) ? "PointerToIntegral" : ""
    }
    return ""
}

// the C-IR operator of a binary operator token
def private binary_op(k : int) : string {
    let ops <- {'+' => "add", '-' => "sub", '*' => "mul", '/' => "div", '%' => "rem",
                int(CTok.SHL) => "shl", int(CTok.SHR) => "shr", '<' => "lt", '>' => "gt", int(CTok.LE) => "le",
                int(CTok.GE) => "ge", int(CTok.EQ) => "eq", int(CTok.NE) => "ne", '&' => "band", '|' => "bor",
                '^' => "bxor", int(CTok.AND_AND) => "land", int(CTok.OR_OR) => "lor"}
    return ops?[k] ?? ""
}

// the C-IR operator of a compound assignment token, "" for plain `=`
def private assign_op(k : int) : string {
    let ops <- {int(CTok.MUL_ASSIGN) => "mul", int(CTok.DIV_ASSIGN) => "div", int(CTok.MOD_ASSIGN) => "rem",
                int(CTok.ADD_ASSIGN) => "add", int(CTok.SUB_ASSIGN) => "sub", int(CTok.SHL_ASSIGN) => "shl",
                int(CTok.SHR_ASSIGN) => "shr", int(CTok.AND_ASSIGN) => "band", int(CTok.XOR_ASSIGN) => "bxor",
                int(CTok.OR_ASSIGN) => "bor"}
    return ops?[k] ?? ""
}

// the pool type of `ptrdiff_t`, the dialect's pointer-wide signed integer
def private ptrdiff_t(var r : CIr) : int => c_builtin(r.b, r.b.tu.target.long_w == r.b.tu.target.ptr_w ? "long" : "long long")

//! The pool type of `size_t`, the dialect's pointer-wide unsigned integer.
def c_size_t(var r : CIr) : int => c_builtin(r.b, r.b.tu.target.long_w == r.b.tu.target.ptr_w ? "unsigned long" : "unsigned long long")

// a binary operator `op` over `a` and `b` at token `tok`, each operand converted as C11 6.5.5 to
// 6.5.14 say: arithmetic by the usual arithmetic conversions, a shift's operands each promoted, a
// pointer operand read, a null pointer constant compared against a pointer converted to it
[arch(at="ARCHITECTURE_EXPRS.md#c-exprs-operands")]
def private binary(var r : CIr; var p : CParser; op : string; var a, b : CirExpr?; tok : int) : CirExpr? {
    if (!operands_valid(r, op, a.t, b.t)) {
        c_reject(r.b, p, tok, "this operator on operands of these types")
        return null
    }
    if (op == "land" || op == "lor") {
        a = c_promote(r, a)
        b = c_promote(r, b)
        return new CirExpr(e = "bin", t = int_t(r), op = op, a = a, b = b)
    } elif (op == "shl" || op == "shr") {
        a = c_promote(r, a)
        b = c_promote(r, b)
        return new CirExpr(e = "bin", t = a.t, op = op, a = a, b = b)
    }
    let a_null = c_is_null(r, a)
    let b_null = c_is_null(r, b)
    let compare = op == "lt" || op == "gt" || op == "le" || op == "ge" || op == "eq" || op == "ne"
    let pa = kind_of(r, a.t) == "array" || kind_of(r, a.t) == "func" || is_ptr(r, a.t)
    let pb = kind_of(r, b.t) == "array" || kind_of(r, b.t) == "func" || is_ptr(r, b.t)
    if (!pa && !pb) {
        let common = c_arith(r, a, b)
        return new CirExpr(e = "bin", t = compare ? int_t(r) : common, op = op, a = a, b = b)
    } elif (compare) {
        a = c_rvalue(r, a)
        b = c_rvalue(r, b)
        if (is_int(r, b.t)) {
            b = c_implicit(b, a.t, b_null ? "NullToPointer" : "IntegralToPointer")
        } elif (is_int(r, a.t)) {
            a = c_implicit(a, b.t, a_null ? "NullToPointer" : "IntegralToPointer")
        } elif (a.t != b.t) {
            if (a_null && !b_null) {
                a = c_implicit(a, b.t, "BitCast")
            } else {
                b = c_implicit(b, a.t, "BitCast")
            }
        }
        return new CirExpr(e = "bin", t = int_t(r), op = op, a = a, b = b)
    } elif (op == "sub" && pa && pb) {
        a = c_rvalue(r, a)
        b = c_rvalue(r, b)
        if (pointee_composite(r, a.t, b.t) < 0) {
            c_reject(r.b, p, tok, "a difference of pointers to incompatible types")
            return null
        }
        return new CirExpr(e = "bin", t = ptrdiff_t(r), op = op, a = a, b = b)
    } elif (op == "add" || op == "sub") {
        a = pa ? c_rvalue(r, a) : c_promote(r, a)
        b = pb ? c_rvalue(r, b) : c_promote(r, b)
        return new CirExpr(e = "bin", t = pa ? a.t : b.t, op = op, a = a, b = b)
    }
    c_reject(r.b, p, tok, "this operator on operands of these types")
    return null
}

// whether pool type `t` decays to or is a pointer
def private pointer_like(r : CIr; t : int) : bool => is_ptr(r, t) || kind_of(r, t) == "array" || kind_of(r, t) == "func"

// whether binary C-IR operator `op` takes operands of pool types `a` and `b` (C11 6.5.5 to
// 6.5.14): integers for `%`, the shifts and the bitwise operators; arithmetic for `*` and `/`;
// arithmetic, or a pointer and an integer, for `+`; that, or two pointers, for `-`; arithmetic, or
// a pointer and a pointer or an integer, for a comparison; scalars for `&&` and `||`
def private operands_valid(r : CIr; op : string; a, b : int) : bool {
    let pa = pointer_like(r, a)
    let pb = pointer_like(r, b)
    if (op == "rem" || op == "shl" || op == "shr" || op == "band" || op == "bor" || op == "bxor") {
        return is_int(r, a) && is_int(r, b)
    } elif (op == "mul" || op == "div") {
        return is_arith(r, a) && is_arith(r, b)
    } elif (op == "add") {
        return (is_arith(r, a) && is_arith(r, b)) || (pa && is_int(r, b)) || (is_int(r, a) && pb)
    } elif (op == "sub") {
        return (is_arith(r, a) && is_arith(r, b)) || (pa && (is_int(r, b) || pb))
    } elif (op == "land" || op == "lor") {
        return (is_arith(r, a) || pa) && (is_arith(r, b) || pb)
    }
    return (is_arith(r, a) && is_arith(r, b)) || (pa && (pb || is_int(r, b))) || (is_int(r, a) && pb)
}

// the pool type of an integer literal of value `v`: the first of `candidates` (spellings) that
// holds it; -1 for none
def private literal_type(var r : CIr; v : uint64; candidates : array<string>) : int {
    for (spell in candidates) {
        let t = c_builtin(r.b, spell)
        let w = r.b.pool[t].w
        let limit = r.b.pool[t].is_signed ? (1ul << uint64(w - 1)) - 1ul : (w >= 64 ? 0xFFFFFFFFFFFFFFFFul : (1ul << uint64(w)) - 1ul)
        return t if (v <= limit)
    }
    return -1
}

// the types an integer literal may take, in order (C11 6.4.4.1p5), by its `u` suffix, its count of
// `l`s and whether it is decimal
def private literal_candidates(unsigned_suffix : bool; longs : int; decimal : bool) : array<string> {
    if (unsigned_suffix) {
        return <- longs == 0 ? ["unsigned int", "unsigned long", "unsigned long long"] : longs == 1 ? ["unsigned long", "unsigned long long"] : ["unsigned long long"]
    } elif (longs == 0) {
        return <- decimal ? ["int", "long", "long long"] : ["int", "unsigned int", "long", "unsigned long", "long long", "unsigned long long"]
    } elif (longs == 1) {
        return <- decimal ? ["long", "long long"] : ["long", "unsigned long", "long long", "unsigned long long"]
    }
    return <- decimal ? ["long long"] : ["long long", "unsigned long long"]
}

// an integer literal node from token `tok` (C11 6.4.4.1): its value and the type its base, suffix
// and value give
[arch(at="ARCHITECTURE_EXPRS.md#c-exprs-literals")]
def private int_literal(var r : CIr; var p : CParser; tok : int) : CirExpr? {
    let spelled = to_lower(c_spelling(p.unit, tok))
    var end = length(spelled)
    var unsigned_suffix = false
    var longs = 0
    peek_data(spelled) $(text) {
        while (end > 0 && (text[end - 1] == uint8('u') || text[end - 1] == uint8('l'))) {
            unsigned_suffix ||= text[end - 1] == uint8('u')
            longs += text[end - 1] == uint8('l') ? 1 : 0
            end--
        }
    }
    let digits = slice(spelled, 0, end)
    let hex = starts_with(digits, "0x")
    let base = hex ? 16ul : starts_with(digits, "0") && length(digits) > 1 ? 8ul : 10ul
    var value = 0ul
    var ok = true
    for (ch in hex ? slice(digits, 2) : digits) {
        let d = is_number(ch) ? ch - '0' : ch >= 'a' && ch <= 'f' ? ch - 'a' + 10 : 99
        ok &&= uint64(d) < base && value <= (0xFFFFFFFFFFFFFFFFul - uint64(d)) / base
        value = value * base + uint64(d)
    }
    let decimal = base == 10ul
    let t = ok ? literal_type(r, value, literal_candidates(unsigned_suffix, longs, decimal)) : -1
    if (t < 0) {
        c_refuse(r.b, p, tok, "the integer literal '{c_spelling(p.unit, tok)}', which no type of its list holds,")
        return null
    }
    return new CirExpr(e = "int_lit", t = t, v = decimal(value))
}

// `v` in decimal digits
def private decimal(v : uint64) : string {
    return "0" if (v == 0ul)
    var digits : array<uint8>
    var rest = v
    while (rest != 0ul) {
        digits |> push(uint8(int(rest % 10ul) + '0'))
        rest /= 10ul
    }
    return build_string() $(var w) {
        for (i in range(length(digits))) {
            w |> write_char(int(digits[length(digits) - 1 - i]))
        }
    }
}

// the code point of the universal character name of `digits` hex digits at `at` of `text`
def private ucn(text : array<uint8>#; at, digits : int) : int {
    var code = 0
    for (k in range(digits)) {
        let h = int(text[at + k])
        code = code * 16 + (is_number(h) ? h - '0' : (h | 0x20) - 'a' + 10)
    }
    return code
}

// the bytes of code point `c` in UTF-8 appended to `out`
def private put_utf8(var out : array<uint8>; c : int) {
    if (c < 0x80) {
        out |> push(uint8(c))
    } elif (c < 0x800) {
        out |> push(uint8(0xC0 | (c >> 6)))
        out |> push(uint8(0x80 | (c & 0x3F)))
    } elif (c < 0x10000) {
        out |> push(uint8(0xE0 | (c >> 12)))
        out |> push(uint8(0x80 | ((c >> 6) & 0x3F)))
        out |> push(uint8(0x80 | (c & 0x3F)))
    } else {
        out |> push(uint8(0xF0 | (c >> 18)))
        out |> push(uint8(0x80 | ((c >> 12) & 0x3F)))
        out |> push(uint8(0x80 | ((c >> 6) & 0x3F)))
        out |> push(uint8(0x80 | (c & 0x3F)))
    }
}

// the character simple escape `\\e` stands for, -1 for a letter that is no simple escape
def private simple_escape(e : int) : int => e == 'n' ? 10 : e == 't' ? 9 : e == 'r' ? 13 : e == 'a' ? 7 : e == 'b' ? 8 : e == 'f' ? 12 : e == 'v' ? 11 : e == 'e' ? 27 : -1

// the bytes between the quotes of a character or string literal spelling, escapes decoded
// (C11 6.4.4.4), a universal character name as its UTF-8 bytes
def private literal_body(spelled : string; var out : array<uint8>) {
    peek_data(spelled) $(text) {
        let stop = length(text) - 1
        var i = 1
        while (i < stop) {
            let b = int(text[i])
            i++
            if (b != '\\') {
                out |> push(uint8(b))
                continue
            }
            let e = int(text[i])
            i++
            let simple = simple_escape(e)
            if (simple >= 0) {
                out |> push(uint8(simple))
            } elif (e == 'x') {
                var v = 0
                while (i < stop && is_hex(int(text[i]))) {
                    let h = int(text[i])
                    v = v * 16 + (is_number(h) ? h - '0' : (h | 0x20) - 'a' + 10)
                    i++
                }
                out |> push(uint8(v & 255))
            } elif (e >= '0' && e <= '7') {
                var v = e - '0'
                var digits = 1
                while (i < stop && digits < 3 && int(text[i]) >= '0' && int(text[i]) <= '7') {
                    v = v * 8 + int(text[i]) - '0'
                    i++
                    digits++
                }
                out |> push(uint8(v & 255))
            } elif (e == 'u' || e == 'U') {
                let digits = e == 'u' ? 4 : 8
                put_utf8(out, ucn(text, i, digits))
                i += digits
            } else {
                out |> push(uint8(e))
            }
        }
    }
}

//! The string literal node of the `count` adjacent literals from token `first`: its bytes, the
//! NUL appended, typed `char[N]`; null with the error set for a prefixed one.
[arch(at="ARCHITECTURE_EXPRS.md#c-exprs-literals")]
def c_string_literal(var r : CIr; var p : CParser; first, count : int) : CirExpr? {
    var x = new CirExpr(e = "str_lit")
    for (t in range(first, first + count)) {
        let spelled = c_spelling(p.unit, t)
        if (!starts_with(spelled, "\"")) {
            c_refuse(r.b, p, t, "a prefixed string literal")
            unsafe {
                delete x
            }
            return null
        }
        literal_body(spelled, x.bytes)
    }
    x.bytes |> push(uint8(0))
    x.t = c_array(r.b, c_builtin(r.b, "char"), length(x.bytes))
    return x
}

// the code point UTF-8 bytes `b` spell when they spell exactly one, -1 otherwise
def private one_code_point(b : array<uint8>) : int {
    return -1 if (empty(b))
    let lead = int(b[0])
    let size = lead < 0x80 ? 1 : lead < 0xE0 ? 2 : lead < 0xF0 ? 3 : 4
    return -1 if (length(b) != size)
    var code = size == 1 ? lead : lead & (0xFF >> (size + 1))
    for (k in range(1, size)) {
        code = (code << 6) | (int(b[k]) & 0x3F)
    }
    return code
}

// the value of the escape whose letter is at `at` of `text` (past the backslash) and the index
// past it, by C11 6.4.4.4: a simple escape its character, an octal or hex one its whole value (-1
// past 32 bits), a universal character name its code point
def private escape_unit(text : array<uint8>#; at, stop : int) : tuple<v : int64; next : int> {
    let e = int(text[at])
    var i = at + 1
    let simple = simple_escape(e)
    if (simple >= 0) {
        return (v = int64(simple), next = i)
    } elif (e == 'u' || e == 'U') {
        let digits = e == 'u' ? 4 : 8
        return (v = int64(ucn(text, i, digits)), next = i + digits)
    } elif (e != 'x' && (e < '0' || e > '7')) {
        return (v = int64(e), next = i)
    }
    let hex = e == 'x'
    var v = hex ? 0l : int64(e - '0')
    var digits = hex ? 0 : 1
    while (i < stop && (hex ? is_hex(int(text[i])) : int(text[i]) >= '0' && int(text[i]) <= '7' && digits < 3)) {
        let h = int(text[i])
        v = min(v * (hex ? 16l : 8l) + int64(is_number(h) ? h - '0' : (h | 0x20) - 'a' + 10), 4294967296l)
        i++
        digits++
    }
    return (v = v > 4294967295l ? -1l : v, next = i)
}

// the values of the characters between the quotes of a wide character constant's spelling (C11
// 6.4.4.4p9-11): each escape's (`escape_unit`), and a UTF-8 sequence of the source its code point
def private wide_units(spelled : string) : array<int64> {
    var units : array<int64>
    peek_data(spelled) $(text) {
        let stop = length(text) - 1
        var i = 1
        while (i < stop) {
            let b = int(text[i])
            i++
            if (b == '\\') {
                let unit = escape_unit(text, i, stop)
                units |> push(unit.v)
                i = unit.next
                continue
            }
            let size = b < 0x80 ? 1 : b < 0xE0 ? 2 : b < 0xF0 ? 3 : 4
            var code = size == 1 ? b : b & (0xFF >> (size + 1))
            for (_ in range(1, size)) {
                code = (code << 6) | (int(text[i]) & 0x3F)
                i++
            }
            units |> push(int64(code))
        }
    }
    return <- units
}

// a character constant node from token `tok` (C11 6.4.4.4): plain, an `int` of the one byte it
// holds, read as the dialect's plain `char` does; `L`, `u` or `U`, of the dialect's `wchar_t`
// (`int`, msvc's `unsigned short`), `char16_t` or `char32_t`, the one character it holds
[arch(at="ARCHITECTURE_EXPRS.md#c-exprs-literals")]
def private char_literal(var r : CIr; var p : CParser; tok : int) : CirExpr? {
    let spelled = c_spelling(p.unit, tok)
    let quote = find(spelled, "'")
    let prefix = slice(spelled, 0, quote)
    var bytes : array<uint8>
    literal_body(slice(spelled, quote), bytes)
    if (empty(prefix) && length(bytes) == 1) {
        let b = int(bytes[0])
        let v = b
        return new CirExpr(e = "int_lit", t = int_t(r), v = "{v}", is_char = true)
    }
    let units <- wide_units(slice(spelled, quote))
    let code = length(units) == 1 ? units[0] : -1l
    let wide = is_msvc(r.b.tu.target) ? "unsigned short" : "int"
    let spell = prefix == "L" ? wide : prefix == "u" ? "unsigned short" : prefix == "U" ? "unsigned int" : ""
    let limit = spell == "unsigned short" ? 65535l : spell == "int" ? 2147483647l : 4294967295l
    if (empty(spell) || code < 0l || code > limit) {
        c_refuse(r.b, p, tok, "the character constant {spelled}")
        return null
    }
    return new CirExpr(e = "int_lit", t = c_builtin(r.b, spell), v = "{code}", is_char = true)
}

// a floating literal node from token `tok` (C11 6.4.4.2): `float` with an `f` suffix, `long
// double` with an `l`, else `double`; its value as Dumper A spells it (`c_float_literal`)
[arch(at="ARCHITECTURE_EXPRS.md#c-exprs-literals")]
def private float_literal(var r : CIr; p : CParser; tok : int) : CirExpr? {
    let spelled = c_spelling(p.unit, tok)
    let last = to_lower(slice(spelled, length(spelled) - 1))
    let kind = last == "f" ? "float" : last == "l" ? "long double" : "double"
    let digits = kind == "double" ? spelled : slice(spelled, 0, length(spelled) - 1)
    // under msvc `long double` is a double; under linux it is x87's 64-bit significand
    let extended = kind == "long double" && !is_msvc(r.b.tu.target)
    return new CirExpr(e = "float_lit", t = c_builtin(r.b, kind), v = c_float_literal(digits, extended ? "extended" : kind))
}

//! The size in bytes Dumper A gives pool type `t`: a scalar's width, a pointer's and a function's
//! the pointer width, an array its count of elements; -1 for one it has none for.
def c_size_of(r : CIr; t : int) : int64 {
    let k = r.b.pool[t].k
    if (k == "int" || k == "float") {
        return int64(r.b.pool[t].w / 8)
    } elif (k == "ptr" || k == "func") {
        return int64(r.b.tu.target.ptr_w / 8)
    } elif (k == "array" && r.b.pool[t].count >= 0) {
        let elem = c_size_of(r, r.b.pool[t].elem)
        return elem < 0l ? -1l : int64(r.b.pool[t].count) * elem
    }
    return -1l
}

// a `sizeof` node of pool type `of_t` at token `tok`, its operand expression (or null) kept in
// `a` until `c_exprs_use` has interned its types
def private sizeof_node(var r : CIr; var p : CParser; of_t : int; var operand : CirExpr?; tok : int) : CirExpr? {
    let size = c_size_of(r, of_t)
    if (size < 0l) {
        c_refuse(r.b, p, tok, "sizeof of a type without a size")
        return null
    }
    return new CirExpr(e = "sizeof_v", t = c_size_t(r), trait_v = uint64(size), of_t = of_t, a = operand)
}

// a call of `fn` with the argument nodes `n_args` (a list) at token `tok`: the callee read, each
// argument converted to its parameter's type, or, past the parameters or with no prototype, by the
// default argument promotions; an old-style definition's call to its promoted parameter types
[arch(at="ARCHITECTURE_EXPRS.md#c-exprs-slots")]
def private call(var r : CIr; var p : CParser; var fn : CirExpr?; n_args, tok : int) : CirExpr? {
    var old_style = -1
    var proto = true
    var builtin = -1
    if (fn.e == "ref" && fn.name != "") {
        let sym = c_symbol(p.unit, fn.name)
        let id = r.ids?[sym] ?? CId(t = -1, old_style = -1)
        old_style = id.old_style
        proto = id.proto
        builtin = id.builtin ? id.t : -1
    }
    var callee = builtin >= 0 ? cast_node(fn, c_pointer(r.b, builtin), "FunctionToPointerDecay") : c_rvalue(r, fn)
    let target = is_ptr(r, callee.t) ? r.b.pool[callee.t].to : -1
    if (target < 0 || kind_of(r, target) != "func") {
        c_refuse(r.b, p, tok, "a call of a value that is no function")
        return null
    }
    let shape = old_style >= 0 ? old_style : unq(r, target)
    let params := r.b.pool[shape].params
    let typed = old_style >= 0 || proto || !empty(params) || r.b.pool[shape].variadic
    // a prototype fixes the count of arguments: a call to a declared one, or through a type with
    // parameters (a type of no parameter may be `()`, which fixes none)
    let fixed = old_style < 0 && (fn.e == "ref" && fn.name != "" ? proto : !empty(params) || r.b.pool[shape].variadic)
    var given = 0
    var counted = n_args
    while (counted >= 0) {
        given++
        counted = p.ast.nodes[counted].next
    }
    if (fixed && (given < length(params) || (given > length(params) && !r.b.pool[shape].variadic))) {
        c_reject(r.b, p, tok, "a call with {given} arguments of a function whose prototype has {length(params)}")
        return null
    }
    var x = new CirExpr(e = "call", t = unq(r, r.b.pool[target].ret), fn = callee)
    var arg = n_args
    while (arg >= 0) {
        var a = c_expr(r, p, arg)
        return null if (a == null)
        let idx = length(x.args)
        if (typed && idx < length(params)) {
            a = c_assigned(r, p, a, params[idx], p.ast.nodes[arg].tok)
            return null if (a == null)
        } else {
            a = c_promote(r, a)
            if (is_float(r, a.t) && r.b.pool[a.t].w == 32) {
                a = c_implicit(a, c_builtin(r.b, "double"), "FloatingCast")
            }
        }
        x.args |> push(a)
        arg = p.ast.nodes[arg].next
    }
    return x
}

// the conditional `c ? a : b` at token `tok` (C11 6.5.15): the condition promoted, arithmetic arms
// by the usual arithmetic conversions, a null pointer constant arm converted to the other arm's
// pointer type, a `void *` arm taking the other, two other pointers both made `void *`
[arch(at="ARCHITECTURE_EXPRS.md#c-exprs-operands")]
def private conditional(var r : CIr; var p : CParser; var c, a, b : CirExpr?; tok : int) : CirExpr? {
    c = c_promote(r, c)
    let a_null = c_is_null(r, a)
    let b_null = c_is_null(r, b)
    var t = -1
    if (is_arith(r, a.t) && is_arith(r, b.t)) {
        t = c_arith(r, a, b)
    } else {
        a = c_rvalue(r, a)
        b = c_rvalue(r, b)
        if (kind_of(r, a.t) == "void" && kind_of(r, b.t) == "void") {
            t = a.t
        } elif (is_ptr(r, a.t) && b_null) {
            t = a.t
            b = c_implicit(b, t, "NullToPointer")
        } elif (is_ptr(r, b.t) && a_null) {
            t = b.t
            a = c_implicit(a, t, "NullToPointer")
        } elif (is_ptr(r, a.t) && is_ptr(r, b.t)) {
            if (a.t == b.t) {
                t = a.t
            } elif (points_at_void(r, a.t)) {
                t = a.t
                b = c_implicit(b, t, "BitCast")
            } elif (points_at_void(r, b.t)) {
                t = b.t
                a = c_implicit(a, t, "BitCast")
            } elif (c_bare(r, a.t) != c_bare(r, b.t)) {
                t = pointer_arms(r, p, a, b, tok)
                return null if (t == -2)
            }
        }
    }
    if (t < 0) {
        c_refuse(r.b, p, tok, "a conditional of these arms")
        return null
    }
    return new CirExpr(e = "cond", t = t, c = c, a = a, b = b)
}

// the type of `?:` arms `a` and `b`, two pointers to types with no qualifier apart that differ
// (C11 6.5.15p6): to compatible types, their composite, the arm of another type converted to it;
// to incompatible ones `void *`, both converted, as clang does; -2 with the error set where one
// points at a function with no parameter, as the pool cannot tell `()` from `(void)` there
def private pointer_arms(var r : CIr; var p : CParser; var a, b : CirExpr?&; tok : int) : int {
    let ta = c_bare(r, r.b.pool[a.t].to)
    let tb = c_bare(r, r.b.pool[b.t].to)
    for (t in fixed_array(ta, tb)) {
        if (kind_of(r, t) == "func" && empty(r.b.pool[t].params) && !r.b.pool[t].variadic && ta != tb) {
            c_refuse(r.b, p, tok, "a conditional of function pointers one of which takes no parameter", " (whether it has a prototype is not in its type)")
            return -2
        }
    }
    let composite = c_composite(r, ta, tb)
    if (composite < 0) {
        let void_ptr = c_pointer(r.b, c_builtin(r.b, "void"))
        a = c_implicit(a, void_ptr, "BitCast")
        b = c_implicit(b, void_ptr, "BitCast")
        return void_ptr
    }
    let t = c_pointer(r.b, composite)
    if (c_bare(r, a.t) != t) {
        a = c_implicit(a, t, "BitCast")
    }
    if (c_bare(r, b.t) != t) {
        b = c_implicit(b, t, "BitCast")
    }
    return t
}

// a unary operator `k` over `a` at token `tok` (C11 6.5.3): `-`, `+` and `~` promote, `!` reads,
// `&` takes the address, `*` reads the pointer, `++` and `--` keep the operand
[arch(at="ARCHITECTURE_EXPRS.md#c-exprs-operands")]
def private unary(var r : CIr; var p : CParser; k : int; var a : CirExpr?; post : bool; tok : int) : CirExpr? {
    if (k == int(CTok.INC) || k == int(CTok.DEC)) {
        let op = k == int(CTok.INC) ? (post ? "postinc" : "preinc") : (post ? "postdec" : "predec")
        return new CirExpr(e = "un", t = unq(r, a.t), op = op, a = a)
    } elif (k == '&') {
        return new CirExpr(e = "un", t = c_pointer(r.b, a.t), op = "addr", a = a)
    } elif (k == '*') {
        a = c_rvalue(r, a)
        if (!is_ptr(r, a.t)) {
            c_refuse(r.b, p, tok, "a dereference of a value that is no pointer")
            return null
        }
        var x = new CirExpr(e = "un", t = r.b.pool[a.t].to, op = "deref", a = a)
        x.vol = (r.b.quals[x.t] & C_VOLATILE) != 0
        return x
    } elif (k == '!') {
        a = c_rvalue(r, a)
        return new CirExpr(e = "un", t = int_t(r), op = "not", a = a)
    }
    a = c_promote(r, a)
    return new CirExpr(e = "un", t = a.t, op = k == '-' ? "neg" : k == '+' ? "plus" : "bnot", a = a)
}

// an assignment `k` of `b` to `a` (C11 6.5.16): plain, the right operand converted to the left's
// type; compound, the right operand converted to the computation type, a shift's and a pointer's
// promoted alone
[arch(at="ARCHITECTURE_EXPRS.md#c-exprs-slots")]
def private assignment(var r : CIr; var p : CParser; k : int; var a, b : CirExpr?; tok : int) : CirExpr? {
    let op = assign_op(k)
    let t = unq(r, a.t)
    if (empty(op)) {
        b = c_assigned(r, p, b, t, tok)
        return null if (b == null)
    } elif (op == "shl" || op == "shr" || is_ptr(r, t)) {
        b = c_promote(r, b)
    } else {
        b = c_promote(r, b)
        let lhs = is_int(r, t) && r.b.pool[t].w < r.b.tu.target.int_w ? int_t(r) : t
        let common = common_type(r, lhs, b.t)
        b = c_implicit(b, common, arith_kind(r, b.t, common))
    }
    return new CirExpr(e = "assign", t = t, op = op, a = a, b = b)
}

// a reference to identifier `sym` at token `tok`: the variable or function it names, its declared
// type; a builtin of `BUILTIN_FUNCTIONS`, typed `<builtin fn type>`, only as a `callee`
def private reference(var r : CIr; var p : CParser; sym, tok : int; callee : bool = false) : CirExpr? {
    let name = pp_symbol_text(p.unit.lx, sym)
    for (fn in BUILTIN_FUNCTIONS) {
        if (fn.name == name && !key_exists(r.ids, sym)) {
            var inscope params <- [for (x in fn.params); c_builtin(r.b, x)]
            let proto = c_function(r.b, c_builtin(r.b, fn.ret), params, false)
            r.ids[sym] = CId(t = proto, is_function = true, proto = true, old_style = -1, builtin = true)
        }
    }
    if (!key_exists(r.ids, sym)) {
        c_refuse(r.b, p, tok, "the identifier '{pp_symbol_text(p.unit.lx, sym)}', which names no variable or function the builder knows,")
        return null
    }
    let id = r.ids?[sym] ?? CId()
    if (id.builtin && !callee) {
        c_refuse(r.b, p, tok, "the builtin '{name}' other than as a callee")
        return null
    }
    var x = new CirExpr(e = "ref", t = id.builtin ? c_builtin_fn_type(r.b) : id.t, name = name)
    x.vol = (r.b.quals[id.t] & C_VOLATILE) != 0
    return x
}

// an operator node `node` (unary, postfix, binary, assignment, conditional) typed, its operands first
def private operator_expr(var r : CIr; var p : CParser; node : CNodeRec) : CirExpr? {
    let kind = node.kind
    if (kind == CNode.UNARY || kind == CNode.POSTFIX) {
        var a = c_expr(r, p, node.a)
        return a == null ? null : unary(r, p, node.op, a, kind == CNode.POSTFIX, node.tok)
    } elif (kind == CNode.COND) {
        if (node.b < 0) {
            c_refuse(r.b, p, node.tok, "GNU's ?: with no middle operand")
            return null
        }
        var c = c_expr(r, p, node.a)
        var a = c == null ? null : c_expr(r, p, node.b)
        var b = a == null ? null : c_expr(r, p, node.c)
        return b == null ? null : conditional(r, p, c, a, b, node.tok)
    }
    var a = c_expr(r, p, node.a)
    var b = a == null ? null : c_expr(r, p, node.b)
    return null if (b == null)
    if (kind == CNode.ASSIGN) {
        return assignment(r, p, node.op, a, b, node.tok)
    } elif (node.op != ',') {
        return binary(r, p, binary_op(node.op), a, b, node.tok)
    }
    a = c_rvalue(r, a)
    b = c_rvalue(r, b)
    return new CirExpr(e = "comma", t = b.t, a = a, b = b)
}

// a subscript node `node` typed: both operands values, the pointer one's target its type
def private subscript(var r : CIr; var p : CParser; node : CNodeRec) : CirExpr? {
    var base = c_expr(r, p, node.a)
    var i = base == null ? null : c_expr(r, p, node.b)
    return null if (i == null)
    base = c_rvalue(r, base)
    i = c_rvalue(r, i)
    let ptr = is_ptr(r, base.t) ? base.t : i.t
    if (!is_ptr(r, ptr)) {
        c_refuse(r.b, p, node.tok, "a subscript of a value that is no pointer")
        return null
    }
    var x = new CirExpr(e = "index", t = r.b.pool[ptr].to, base = base, i = i)
    x.vol = (r.b.quals[x.t] & C_VOLATILE) != 0
    return x
}

// an explicit cast node `node` typed: its operand a value, the kind by the two types
def private explicit_cast(var r : CIr; var p : CParser; node : CNodeRec) : CirExpr? {
    let to = c_type_name_type(r.b, p, node.a)
    var a = to < 0 ? null : c_expr(r, p, node.b)
    return null if (a == null)
    a = c_rvalue(r, a)
    let ck = explicit_kind(r, a, to)
    if (empty(ck)) {
        c_refuse(r.b, p, node.tok, "this cast")
        return null
    }
    return cast_node(a, unq(r, to), ck, true)
}

//! The C-IR expression of parser expression node `n`, typed by pool types, with no conversion at
//! its top; null with the error set at the first construct not typed yet.
[arch(at="ARCHITECTURE_EXPRS.md#c-exprs-nodes")]
def c_expr(var r : CIr; var p : CParser; n : int) : CirExpr? {
    let node = p.ast.nodes[n]
    let kind = node.kind
    if (kind == CNode.INT) {
        return int_literal(r, p, node.a)
    } elif (kind == CNode.FLOAT) {
        return float_literal(r, p, node.a)
    } elif (kind == CNode.CHAR) {
        return char_literal(r, p, node.a)
    } elif (kind == CNode.STRING) {
        return c_string_literal(r, p, node.a, node.b)
    } elif (kind == CNode.IDENT) {
        return reference(r, p, node.a, node.tok)
    } elif (kind == CNode.PAREN || kind == CNode.EXTENSION) {
        var inner = c_expr(r, p, node.a)
        if (inner != null && kind == CNode.PAREN) {
            inner.paren = true
        }
        return inner
    } elif (kind == CNode.UNARY || kind == CNode.POSTFIX || kind == CNode.BINARY || kind == CNode.ASSIGN || kind == CNode.COND) {
        return operator_expr(r, p, node)
    } elif (kind == CNode.CALL) {
        let callee = p.ast.nodes[node.a]
        var fn = callee.kind == CNode.IDENT ? reference(r, p, callee.a, callee.tok, true) : c_expr(r, p, node.a)
        return fn == null ? null : call(r, p, fn, node.b, node.tok)
    } elif (kind == CNode.INDEX) {
        return subscript(r, p, node)
    } elif (kind == CNode.CAST) {
        return explicit_cast(r, p, node)
    } elif (kind == CNode.SIZEOF_TYPE) {
        let of_t = c_type_name_type(r.b, p, node.a)
        return of_t < 0 ? null : sizeof_node(r, p, of_t, null, node.tok)
    } elif (kind == CNode.SIZEOF_EXPR) {
        var a = c_expr(r, p, node.a)
        return a == null ? null : sizeof_node(r, p, a.t, a, node.tok)
    }
    c_refuse(r.b, p, node.tok, "this expression")
    return null
}

//! Every pool type of expression `x` turned into its table index, in the order Dumper A interns
//! them: a node's type before its operands', left to right; a `sizeof`'s operand type, or its
//! operand expression's types, after its own, the operand then dropped.
[arch(at="ARCHITECTURE_EXPRS.md#c-exprs-order")]
def c_exprs_use(var r : CIr; var x : CirExpr?) {
    return if (x == null)
    x.t = c_types_use(r.b, x.t)
    if (x.e == "sizeof_v") {
        if (x.a != null) {
            c_exprs_use(r, x.a)
            x.of_t = x.a.t
            delete_expr(x.a)
            x.a = null
        } else {
            x.of_t = c_types_use(r.b, x.of_t)
        }
        return
    }
    if (x.e == "call") {
        c_exprs_use(r, x.fn)
        for (arg in x.args) {
            c_exprs_use(r, arg)
        }
        return
    }
    if (x.e == "init_list") {
        for (item in x.init_items) {
            c_exprs_use(r, item.v)
        }
        return
    }
    c_exprs_use(r, x.c)
    c_exprs_use(r, x.a)
    c_exprs_use(r, x.b)
    c_exprs_use(r, x.base)
    c_exprs_use(r, x.i)
}
