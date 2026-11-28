options gen2
options indenting = 4

module c_consts public

require math
require strings
require c_exprs public

//! The constant evaluator's forms beside `c_fold` (`ARCHITECTURE_CONSTS.md`): the `offsetof` node,
//! `_Alignof` and `__alignof__`, `__builtin_types_compatible_p` and `__builtin_constant_p` as
//! Dumper A writes them, a `case` value checked against Dumper A's own fold, and the constant
//! check of a static object's initializer. What clang's answer is not certain for is refused.

// what clang's evaluator makes of an expression, as far as the builder can tell
enum private Fold {
    folds       // a value: an arithmetic constant, a null pointer or an integer cast to a pointer
    literal     // a pointer to a string literal's first character
    address     // the address of an object or a function, a constant with no integer value
    fails       // no value: a read of a variable, a call, an effect, a division by zero
    unsure      // a form the builder cannot answer for
}

def private unq(r : CIr; t : int) : int => r.unqualified[t]

def private kind_of(r : CIr; t : int) : string => r.pool[r.unqualified[t]].k

def private is_int(r : CIr; t : int) : bool => kind_of(r, t) == "int" || kind_of(r, t) == "enum"

def private is_float(r : CIr; t : int) : bool => kind_of(r, t) == "float"

def private is_ptr(r : CIr; t : int) : bool => kind_of(r, t) == "ptr"

def private is_record(r : CIr; t : int) : bool => kind_of(r, t) == "struct" || kind_of(r, t) == "union"

// whether an object of pool type `t` is const-qualified: its own qualifiers, or an array's element's
def private is_const(r : CIr; t : int) : bool {
    return true if ((r.quals[t] & C_CONST) != 0)
    let u = r.unqualified[t]
    return r.pool[u].k == "array" && is_const(r, r.pool[u].elem)
}

// whether pool type `t` is linux's `long double`, x87's type, whose alignment clang gives as 16
// where the C-IR's 64-bit model gives 8; an array's element counts
def private is_x87(r : CIr; t : int) : bool {
    let u = r.unqualified[t]
    return is_x87(r, r.pool[u].elem) if (r.pool[u].k == "array")
    return !is_msvc(r.tu.target) && r.pool[u].k == "float" && r.pool[u].spell == "long double"
}

//! The C-IR of an `offsetof`, `_Alignof`, `__alignof__` or `__builtin_types_compatible_p` node, or
//! of a `__builtin_constant_p` call, at parser node `n`; null with the error set.
[arch(at="ARCHITECTURE_CONSTS.md#c-consts-forms")]
def c_constant_expr(var r : CIr; var p : CParser; n : int) : CirExpr? {
    let node = p.ast.nodes[n]
    if (node.kind == CNode.OFFSETOF) {
        return offsetof_node(r, p, node)
    } elif (node.kind == CNode.TYPES_COMPATIBLE) {
        return types_compatible_node(r, p, node)
    } elif (node.kind == CNode.ALIGNOF_TYPE || node.kind == CNode.ALIGNOF_EXPR) {
        return alignof_node(r, p, node)
    }
    return constant_p_node(r, p, node)
}

// `offsetof(T, m)` of node `node`: Dumper A's node, the record and the index of its direct field,
// the byte offset kept for the evaluator until `c_exprs_use`
def private offsetof_node(var r : CIr; var p : CParser; node : CNodeRec) : CirExpr? {
    let of_t = c_type_name_type(r, p, node.a)
    return null if (of_t < 0 || !c_tag_complete(r, p))
    let desig = p.ast.nodes[node.b]
    if (desig.next >= 0) {
        c_refuse(r, p, node.tok, "an offsetof of a member path (`a.b`, `a[i]`)", ", which Dumper A does not lower")
        return null
    }
    let rec = unq(r, of_t)
    if (!is_record(r, rec) || !key_exists(r.layouts, rec)) {
        c_reject(r, p, node.tok, "an offsetof of other than a complete struct or union")
        return null
    }
    let name = c_symbol_text(p.unit, desig.a)
    var field = -1
    for (f, idx in r.pool[rec].fields, count()) {
        if (field < 0 && f.name == name) {
            field = idx
        }
    }
    if (field < 0 && !empty(c_member_path(r, rec, name))) {
        c_refuse(r, p, desig.tok, "an offsetof of a member '{name}' an anonymous member holds", ", which Dumper A does not lower")
        return null
    } elif (field < 0) {
        c_reject(r, p, desig.tok, "an offsetof of a member '{name}' its record does not have")
        return null
    } elif (r.pool[rec].fields[field].is_bitfield) {
        c_reject(r, p, desig.tok, "an offsetof of a bit-field")
        return null
    }
    var bits = 0l
    get(r.layouts, rec) $(l) {
        bits = l.offsets[field]
    }
    return new CirExpr(e = "offsetof", t = c_size_t(r), of_t = rec, field = field, trait_v = uint64(bits / 8l))
}

// `__builtin_types_compatible_p(T, U)` of node `node`: the `int` literal of clang's answer, the
// two types compatible once their own qualifiers are dropped, an array's element's at every level
// too (clang's getUnqualifiedArrayType: GCC ignores cv-qualifiers on arrays); the operands add no
// table entry
def private types_compatible_node(var r : CIr; var p : CParser; node : CNodeRec) : CirExpr? {
    let a = c_type_name_type(r, p, node.a)
    let b = a < 0 ? -1 : c_type_name_type(r, p, node.b)
    return null if (b < 0)
    if (holds_unprototyped(r, a) || holds_unprototyped(r, b)) {
        c_refuse(r, p, node.tok, "a type trait over a function type with no parameter", " (whether it has a prototype is not in its type)")
        return null
    }
    let ua = array_unqualified(r, a)
    let ub = array_unqualified(r, b)
    let same = c_composite(r, ua, ub) >= 0
    return new CirExpr(e = "int_lit", t = c_builtin(r, "int"), v = same ? "1" : "0")
}

// pool type `t` without its own qualifiers, an array's element without its own at every level
def private array_unqualified(var r : CIr; t : int) : int {
    let u = unq(r, t)
    return u if (r.pool[u].k != "array")
    let count = r.pool[u].count
    return c_array(r, array_unqualified(r, r.pool[u].elem), count)
}

// whether pool type `t` holds a function type with no parameter, through pointers, arrays and
// functions' parts: the pool keeps `()` and `(void)` as one type
def private holds_unprototyped(r : CIr; t : int) : bool {
    let u = unq(r, t)
    let k = r.pool[u].k
    if (k == "ptr") {
        return holds_unprototyped(r, r.pool[u].to)
    } elif (k == "array") {
        return holds_unprototyped(r, r.pool[u].elem)
    } elif (k != "func") {
        return false
    }
    return true if (empty(r.pool[u].params) || holds_unprototyped(r, r.pool[u].ret))
    for (q in r.pool[u].params) {
        return true if (holds_unprototyped(r, q))
    }
    return false
}

// whether the unit spells an `aligned` attribute or `_Alignas` anywhere: then a typedef, a
// variable or a member may carry an alignment the pool's types do not hold
def private spells_aligned(var r : CIr; p : CParser) : bool {
    if (r.aligned_spelled < 0) {
        r.aligned_spelled = 0
        for (t in range(length(p.unit.toks))) {
            let word = c_spelling(p.unit, t)
            if (word == "aligned" || word == "__aligned__" || word == "_Alignas" || word == "alignas") {
                r.aligned_spelled = 1
                break
            }
        }
    }
    return r.aligned_spelled == 1
}

// whether type-name node `t`'s specifiers name a typedef or a `typeof`, either of which can carry
// an alignment its pool type does not hold
def private names_alias(p : CParser; t : int) : bool {
    var at = p.ast.nodes[t].a
    while (at >= 0) {
        let k = p.ast.nodes[at].kind
        return true if (k == CNode.SPEC_TYPEDEF_NAME || k == CNode.SPEC_TYPEOF_EXPR || k == CNode.SPEC_TYPEOF_TYPE)
        at = p.ast.nodes[at].next
    }
    return false
}

// `_Alignof` or `__alignof__` (`node.op`) of node `node`: Dumper A's `alignof_v`, the operand type
// kept as `sizeof_v` keeps it. `_Alignof` is the type's alignment, as Dumper A computes it from
// the type; `__alignof__` clang's preferred alignment, and a declaration's own for a function
[arch(at="ARCHITECTURE_CONSTS.md#c-consts-alignof")]
def private alignof_node(var r : CIr; var p : CParser; node : CNodeRec) : CirExpr? {
    let gnu = node.op == int(CTok.GNU_ALIGNOF)
    var of_t = -1
    var operand : CirExpr? = null
    var align = -1
    if (node.kind == CNode.ALIGNOF_TYPE) {
        of_t = c_type_name_type(r, p, node.a)
        return null if (of_t < 0)
        if (names_alias(p, node.a) && spells_aligned(r, p)) {
            c_refuse(r, p, node.tok, "an alignment of a type a typedef or `typeof` names in a unit that spells `aligned` or `_Alignas`")
            return null
        }
    } else {
        operand = c_expr(r, p, node.a)
        return null if (operand == null)
        of_t = operand.t
        if (operand.e == "ref" && kind_of(r, of_t) == "func") {
            align = gnu ? function_alignment(r, p, node.a) : -1
            if (align < 0) {
                delete_expr(operand)
                c_refuse(r, p, node.tok, "an alignment of a function other than GNU's of one an `aligned(N)` attribute aligns")
                return null
            }
        } elif (operand.e == "member" || spells_aligned(r, p)) {
            delete_expr(operand)
            c_refuse(r, p, node.tok, "an alignment of a member, or of an expression in a unit that spells `aligned` or `_Alignas`")
            return null
        }
    }
    if (align < 0) {
        align = c_type_align(r, of_t)
        if (align < 0 || kind_of(r, of_t) == "func" || (kind_of(r, of_t) == "array" && r.pool[unq(r, of_t)].count < 0)) {
            delete_expr(operand)
            c_refuse(r, p, node.tok, "an alignment of a type without one")
            return null
        } elif (is_x87(r, of_t) && !gnu) {
            delete_expr(operand)
            c_refuse(r, p, node.tok, "`_Alignof` of linux's `long double`", ": clang's 16 is not the 8 Dumper A gives from the C-IR's 64-bit type")
            return null
        }
        align = is_x87(r, of_t) ? 16 : align
    }
    return new CirExpr(e = "alignof_v", t = c_size_t(r), trait_v = uint64(align), of_t = of_t, a = operand)
}

// the alignment GNU `__alignof__` gives the function an identifier node `n` names: the largest
// `aligned(N)` its file-scope declarations before `n` spell in their specifiers and attribute
// lists; -1 when none does, when a declaration spells `aligned` where those lists do not show it,
// and when the function definition holding `n` spells `aligned` before it, a block's redeclaration
// clang's answer would take
def private function_alignment(var r : CIr; var p : CParser; n : int) : int {
    var named = n
    while (p.ast.nodes[named].kind == CNode.PAREN) {
        named = p.ast.nodes[named].a
    }
    let target = p.ast.nodes[named]
    return -1 if (target.kind != CNode.IDENT || r.unit_items < 0)
    var align = -1
    var at = r.unit_items
    while (at >= 0 && p.ast.nodes[at].tok < target.tok) {
        let item = p.ast.nodes[at]
        let end = item.next >= 0 ? p.ast.nodes[item.next].tok : target.tok
        var seen = 0
        var counted = 0
        var inscope lists : array<int>
        lists |> push(item.a)
        if (item.kind == CNode.FUNC_DEF || item.kind == CNode.DECL) {
            var id = item.b
            while (id >= 0 && p.ast.nodes[id].kind == CNode.INIT_DECL) {
                if (c_declarator_name(p.ast, p.ast.nodes[id].a) == target.a) {
                    lists |> push(p.ast.nodes[id].d)
                    seen++
                }
                id = item.kind == CNode.FUNC_DEF ? -1 : p.ast.nodes[id].next
            }
        }
        if (seen > 0) {
            for (t in range(item.tok, end)) {
                let word = c_spelling(p.unit, t)
                counted += word == "aligned" || word == "__aligned__" ? 1 : 0
            }
            var found = 0
            var packed = false
            for (list in lists) {
                var largest = -1
                return -1 if (!c_layout_attributes(r, p, list, packed, largest))
                found += aligned_words(p, list)
                align = max(align, largest)
            }
            return -1 if (found != counted || seen > 1)
        } elif (item.kind == CNode.FUNC_DEF && (item.next < 0 || p.ast.nodes[item.next].tok > target.tok)) {
            // a block of the function holding the operand may redeclare it with an `aligned` of its own
            for (t in range(item.tok, target.tok)) {
                let word = c_spelling(p.unit, t)
                return -1 if (word == "aligned" || word == "__aligned__")
            }
        }
        at = item.next
    }
    return align
}

// the `aligned` words attribute list `at` spells
def private aligned_words(p : CParser; at : int) : int {
    var count = 0
    var n = at
    while (n >= 0) {
        let node = p.ast.nodes[n]
        if (node.kind == CNode.ATTRIBUTE) {
            for (t in range(node.a, node.b + 1)) {
                let word = c_spelling(p.unit, t)
                count += word == "aligned" || word == "__aligned__" ? 1 : 0
            }
        }
        n = node.next
    }
    return count
}

// whether expression node `n` holds a comma operator or a `__builtin_constant_p` call, where the
// pinned clang's -O0 answer is its code generator's
def private holds_codegen_answer(var p : CParser; n : int) : bool {
    return false if (n < 0)
    let node = p.ast.nodes[n]
    if (node.kind == CNode.BINARY && node.op == ',') {
        return true
    } elif (node.kind == CNode.CALL) {
        let callee = p.ast.nodes[node.a]
        return true if (callee.kind == CNode.IDENT && c_symbol_text(p.unit, callee.a) == CONSTANT_P)
        var arg = node.b
        while (arg >= 0) {
            return true if (holds_codegen_answer(p, arg))
            arg = p.ast.nodes[arg].next
        }
        return holds_codegen_answer(p, node.a)
    } elif (node.kind == CNode.IDENT || node.kind == CNode.INT || node.kind == CNode.FLOAT || node.kind == CNode.CHAR || node.kind == CNode.STRING
            || node.kind == CNode.FUNC_NAME || node.kind == CNode.SIZEOF_TYPE || node.kind == CNode.ALIGNOF_TYPE || node.kind == CNode.OFFSETOF
            || node.kind == CNode.TYPES_COMPATIBLE || node.kind == CNode.MEMBER) {
        return node.kind == CNode.MEMBER && holds_codegen_answer(p, node.a)
    } elif (node.kind == CNode.CAST || node.kind == CNode.VA_ARG) {
        return holds_codegen_answer(p, node.kind == CNode.CAST ? node.b : node.a)
    } elif (node.kind == CNode.PAREN || node.kind == CNode.EXTENSION || node.kind == CNode.UNARY || node.kind == CNode.POSTFIX
            || node.kind == CNode.SIZEOF_EXPR || node.kind == CNode.ALIGNOF_EXPR) {
        return holds_codegen_answer(p, node.a)
    } elif (node.kind == CNode.BINARY || node.kind == CNode.ASSIGN || node.kind == CNode.INDEX) {
        return holds_codegen_answer(p, node.a) || holds_codegen_answer(p, node.b)
    } elif (node.kind == CNode.COND) {
        return holds_codegen_answer(p, node.a) || holds_codegen_answer(p, node.b) || holds_codegen_answer(p, node.c)
    }
    // a compound literal, a statement expression: the builder does not look inside
    return true
}

// a `__builtin_constant_p(e)` call of node `node`: the `int` literal of clang's answer, 1 when
// its evaluator folds `e`, 0 when it certainly cannot; `e` is typed but never written
[arch(at="ARCHITECTURE_CONSTS.md#c-consts-constant-p")]
def private constant_p_node(var r : CIr; var p : CParser; node : CNodeRec) : CirExpr? {
    let arg = node.b
    if (arg < 0 || p.ast.nodes[arg].next >= 0) {
        c_reject(r, p, node.tok, "a `__builtin_constant_p` call of other than one argument")
        return null
    } elif (holds_codegen_answer(p, arg)) {
        c_refuse(r, p, node.tok, "a `__builtin_constant_p` over a comma operator, another such call, a compound literal or a statement expression", " (the -O0 answer is the code generator's)")
        return null
    }
    var x = c_expr(r, p, arg)
    return null if (x == null)
    x = c_rvalue(r, x)
    let k = kind_of(r, x.t)
    let state = k == "int" || k == "enum" || k == "float" || k == "ptr" ? fold_state(r, x, NO_STATIC) : Fold.fails
    delete_expr(x)
    if (state == Fold.unsure) {
        c_refuse(r, p, node.tok, "a `__builtin_constant_p` whose answer clang's evaluator gives and the builder cannot")
        return null
    }
    let answer = state == Fold.folds || state == Fold.literal
    return new CirExpr(e = "int_lit", t = c_builtin(r, "int"), v = answer ? "1" : "0")
}

// what a constant is evaluated for: `__builtin_constant_p`, a block's static object, a
// file-scope object, whose compound literals are static objects too
let private NO_STATIC = 0
let private BLOCK_STATIC = 1
let private FILE_STATIC = 2

// the verdict of clang's evaluator on value `x`, evaluated for `statics`: in a static object's
// initializer the address of an automatic object is no constant
def private fold_state(r : CIr; x : CirExpr?; statics : int) : Fold {
    return Fold.unsure if (x == null)
    let e = x.e
    if (e == "int_lit" || e == "float_lit" || e == "enum_ref" || e == "sizeof_v" || e == "alignof_v" || e == "offsetof") {
        return Fold.folds
    } elif (e == "cast") {
        return cast_state(r, x, statics)
    } elif (e == "un") {
        return unary_state(r, x, statics)
    } elif (e == "bin") {
        return binary_state(r, x, statics)
    } elif (e == "cond") {
        let c = fold_state(r, x.c, statics)
        return c if (c == Fold.fails)
        var v = 0l
        return Fold.unsure if (c != Fold.folds || !c_fold(r, x.c, v))
        return fold_state(r, v != 0l ? x.a : x.b, statics)
    } elif (e == "call") {
        // a builtin can fold; a function never does
        return x.fn != null && x.fn.e == "cast" && x.fn.a != null && x.fn.a.e == "ref" && starts_with(x.fn.a.name, "__builtin_") ? Fold.unsure : Fold.fails
    } elif (e == "assign") {
        return Fold.fails
    }
    return Fold.unsure
}

def private cast_state(r : CIr; x : CirExpr?; statics : int) : Fold {
    let ck = x.cast_kind
    if (ck == "LValueToRValue") {
        return read_state(r, x.a, statics)
    } elif (ck == "ArrayToPointerDecay") {
        return x.a.e == "str_lit" ? Fold.literal : place_state(r, x.a, statics)
    } elif (ck == "FunctionToPointerDecay") {
        return place_state(r, x.a, statics)
    }
    let a = fold_state(r, x.a, statics)
    if (ck == "NoOp" || ck == "BitCast") {
        return a
    } elif (ck == "NullToPointer" || ck == "IntegralToPointer") {
        return a == Fold.folds || a == Fold.fails ? a : Fold.unsure
    } elif (ck == "PointerToIntegral") {
        // an address as an integer of the pointer's width is a constant clang relocates
        let wide = r.pool[unq(r, x.t)].w == r.tu.target.ptr_w
        return a == Fold.fails ? a : a == Fold.address && wide ? Fold.address : Fold.unsure
    } elif (ck == "FloatingToIntegral") {
        var v = 0l
        return a == Fold.fails ? a : c_fold(r, x, v) ? Fold.folds : Fold.unsure
    } elif (ck == "IntegralCast" || ck == "IntegralToBoolean" || ck == "IntegralToFloating" || ck == "FloatingCast" || ck == "FloatingToBoolean") {
        return a == Fold.folds || a == Fold.fails ? a : Fold.unsure
    }
    return a == Fold.fails ? a : Fold.unsure
}

def private unary_state(r : CIr; x : CirExpr?; statics : int) : Fold {
    let op = x.op
    if (op == "addr") {
        return place_state(r, x.a, statics)
    } elif (op == "preinc" || op == "predec" || op == "postinc" || op == "postdec") {
        return Fold.fails
    }
    let a = fold_state(r, x.a, statics)
    return a == Fold.folds && (op == "neg" || op == "plus" || op == "bnot" || op == "not") ? a : a == Fold.fails ? a : Fold.unsure
}

def private binary_state(r : CIr; x : CirExpr?; statics : int) : Fold {
    let op = x.op
    let a = fold_state(r, x.a, statics)
    if (op == "land" || op == "lor") {
        var v = 0l
        if (a == Fold.folds && c_fold(r, x.a, v)) {
            // the left operand decides, or the right one is the value
            return Fold.folds if ((v != 0l) == (op == "lor"))
            let b = fold_state(r, x.b, statics)
            return b == Fold.folds || b == Fold.fails ? b : Fold.unsure
        }
        return a == Fold.fails && fold_state(r, x.b, statics) == Fold.fails ? Fold.fails : Fold.unsure
    }
    let b = fold_state(r, x.b, statics)
    return Fold.fails if (a == Fold.fails || b == Fold.fails)
    if ((op == "add" || op == "sub") && is_ptr(r, x.t)) {
        let pointer = is_ptr(r, x.a.t) ? a : b
        let offset = is_ptr(r, x.a.t) ? b : a
        // a string literal stepped is no first character, which `__builtin_constant_p` asks for
        let addressed = pointer == Fold.address || (pointer == Fold.literal && statics != NO_STATIC)
        return addressed && offset == Fold.folds ? Fold.address : Fold.unsure
    }
    return Fold.unsure if (a != Fold.folds || b != Fold.folds)
    var d = 0l
    if ((op == "div" || op == "rem") && is_int(r, x.b.t)) {
        return Fold.unsure if (!c_fold(r, x.b, d))
        return d == 0l ? Fold.fails : Fold.folds
    } elif (op == "shl" || op == "shr") {
        return c_fold(r, x.b, d) && d >= 0l ? Fold.folds : Fold.unsure
    }
    return Fold.folds
}

// the verdict on reading lvalue `x`'s value
def private read_state(r : CIr; x : CirExpr?; statics : int) : Fold {
    if (x.e == "ref") {
        // a const object's initializer clang may fold; any other object's value it does not know
        return is_const(r, x.t) ? Fold.unsure : Fold.fails
    } elif (x.e == "member") {
        let base = x.arrow ? fold_state(r, x.base, statics) : Fold.unsure
        return Fold.fails if (base == Fold.fails)
        return !x.arrow && !is_const(r, x.t) && root_is_mutable(r, x.base) ? Fold.fails : Fold.unsure
    } elif (x.e == "index") {
        let base = fold_state(r, x.base, statics)
        let i = fold_state(r, x.i, statics)
        return Fold.fails if (base == Fold.fails || i == Fold.fails)
        var v = 0l
        if (base == Fold.literal && i == Fold.folds && c_fold(r, x.i, v)) {
            let lit = x.base.a
            return v >= 0l && v < long_length(lit.bytes) ? Fold.folds : Fold.unsure
        }
        let decayed = x.base.e == "cast" && x.base.cast_kind == "ArrayToPointerDecay" && x.base.a.e == "ref"
        return decayed && !is_const(r, x.base.a.t) ? Fold.fails : Fold.unsure
    } elif (x.e == "un" && x.op == "deref") {
        return fold_state(r, x.a, statics) == Fold.fails ? Fold.fails : Fold.unsure
    } elif (x.e == "compound_lit" && statics == FILE_STATIC) {
        return initializer_state(r, x.init, statics)
    }
    return Fold.unsure
}

// whether lvalue `x` is a member chain over a variable no qualifier makes const
def private root_is_mutable(r : CIr; x : CirExpr?) : bool {
    if (x.e == "ref") {
        return !is_const(r, x.t)
    } elif (x.e == "member" && !x.arrow) {
        return !is_const(r, x.t) && root_is_mutable(r, x.base)
    }
    return false
}

// the verdict on the address of lvalue `x` (under `&` or a decay): an object of static storage
// or a function, a member of one, an element at a constant index
def private place_state(r : CIr; x : CirExpr?; statics : int) : Fold {
    if (x.e == "ref") {
        return statics != NO_STATIC && (r.no_address_refs?[intptr(x)] ?? false) ? Fold.fails : Fold.address
    } elif (x.e == "str_lit") {
        return Fold.address
    } elif (x.e == "compound_lit") {
        // a file-scope compound literal is a static object; a block's is automatic
        let items = statics == FILE_STATIC ? initializer_state(r, x.init, statics) : Fold.unsure
        return items == Fold.folds ? Fold.address : items
    } elif (x.e == "member") {
        return x.arrow ? (fold_state(r, x.base, statics) == Fold.address ? Fold.address : Fold.unsure) : place_state(r, x.base, statics)
    } elif (x.e == "index") {
        let base = fold_state(r, x.base, statics)
        let i = fold_state(r, x.i, statics)
        return Fold.fails if (base == Fold.fails || i == Fold.fails)
        var v = 1l
        // a string literal's element 0 is its first character, which `__builtin_constant_p` takes
        return Fold.literal if (base == Fold.literal && i == Fold.folds && c_fold(r, x.i, v) && v == 0l)
        return (base == Fold.address || base == Fold.literal) && i == Fold.folds ? Fold.address : Fold.unsure
    } elif (x.e == "un" && x.op == "deref") {
        return fold_state(r, x.a, statics) == Fold.fails ? Fold.fails : Fold.unsure
    }
    return Fold.unsure
}

//! Whether static object initializer `x` (a list, a string literal, an expression in its slot)
//! is a constant clang takes; false with the error set: invalid C where clang's evaluator
//! certainly finds no constant (a variable read, a call, an effect, an automatic object's
//! address), refused where the builder cannot tell. At token `tok`.
[arch(at="ARCHITECTURE_CONSTS.md#c-consts-statics")]
def c_static_initializer(var r : CIr; p : CParser; x : CirExpr?; tok : int; file_scope : bool) : bool {
    let state = initializer_state(r, x, file_scope ? FILE_STATIC : BLOCK_STATIC)
    if (state == Fold.fails) {
        c_reject(r, p, tok, "a static object's initializer that is no constant")
        return false
    } elif (state == Fold.unsure) {
        c_refuse(r, p, tok, "a static object's initializer whose constancy clang's evaluator decides and the builder cannot")
        return false
    }
    return true
}

def private initializer_state(r : CIr; x : CirExpr?; statics : int) : Fold {
    if (x.e == "init_list") {
        var worst = Fold.folds
        for (item in x.init_items) {
            let s = initializer_state(r, item.v, statics)
            worst = s == Fold.fails || worst == Fold.fails ? Fold.fails : s == Fold.unsure ? Fold.unsure : worst
        }
        return worst
    } elif (x.e == "str_lit") {
        return Fold.folds
    }
    let s = x.e == "compound_lit" ? place_state(r, x, statics) : fold_state(r, x, statics)
    if (s == Fold.address && x.e == "compound_lit") {
        // a record or an array a compound literal copies: its own items decide
        return Fold.folds
    } elif (s == Fold.address || s == Fold.literal) {
        // an address fills a pointer, or an integer of the pointer's width
        return is_ptr(r, x.t) || is_int(r, x.t) ? Fold.folds : Fold.unsure
    }
    return s
}

//! The value of `case` label node `n` into `v`: clang's (`c_fold`), checked against Dumper A's own
//! fold of the label, which drops the casts and holds every step in 64 bits; false with the error
//! set when the label is no integer constant expression the builder folds, or when Dumper A's
//! fold gives another value than clang's.
[arch(at="ARCHITECTURE_CONSTS.md#c-consts-case")]
def c_case_value(var r : CIr; var p : CParser; n : int; tok : int; var v : int64&) : bool {
    var x = c_expr(r, p, n)
    let folded = x != null && c_fold(r, x, v)
    var theirs = 0l
    let dumper_a = folded ? dumper_a_fold(r, x, theirs) : 0
    delete_expr(x)
    if (!folded) {
        c_refuse(r, p, tok, "this case label")
        return false
    } elif (dumper_a < 0 || (dumper_a > 0 && theirs != v)) {
        c_refuse(r, p, tok, "a case value Dumper A folds apart from clang's", " (its fold drops the casts and holds every step in 64 bits)")
        return false
    }
    return true
}

// Dumper A's fold of a `case` label over typed `x` into `v` (`fold_constant` of
// `converter/dumper_a.das`): 1 with its value, 0 where it fails (so it dumps no C-IR), -1 where
// its value is not certain (a literal past 64 signed bits, a shift past 63, a 64-bit division
// overflow)
def private dumper_a_fold(r : CIr; x : CirExpr?; var v : int64&) : int {
    if (x.e == "int_lit") {
        return dumper_a_literal(x.v, v)
    } elif (x.e == "enum_ref") {
        v = int64(x.trait_v)
        return 1
    } elif (x.e == "cast") {
        return dumper_a_fold(r, x.a, v)
    } elif (x.e == "un") {
        var a = 0l
        let got = dumper_a_fold(r, x.a, a)
        return got if (got <= 0)
        let op = x.op
        v = op == "neg" ? int64(0ul - uint64(a)) : op == "bnot" ? ~a : op == "not" ? (a == 0l ? 1l : 0l) : a
        return op == "neg" || op == "bnot" || op == "not" || op == "plus" ? 1 : 0
    } elif (x.e != "bin" || !key_exists(DUMPER_A_BINARY, x.op)) {
        return 0
    }
    var a, b : int64
    let ga = dumper_a_fold(r, x.a, a)
    return ga if (ga <= 0)
    let gb = dumper_a_fold(r, x.b, b)
    return gb if (gb <= 0)
    return dumper_a_binary(x.op, a, b, v)
}

// the binary operators Dumper A's `case` fold takes
let private DUMPER_A_BINARY <- {"add", "sub", "mul", "div", "rem", "shl", "shr", "band", "bor", "bxor"}

// decimal literal text `digits` as Dumper A reads it into `v`: 1, or -1 past 63 bits
def private dumper_a_literal(digits : string; var v : int64&) : int {
    var u = 0ul
    for (ch in digits) {
        return -1 if (u > 0x0CCCCCCCCCCCCCCCul)
        u = u * 10ul + uint64(ch - '0')
    }
    v = int64(u)
    return u > 0x7FFFFFFFFFFFFFFFul ? -1 : 1
}

// binary operator `op` of Dumper A's `case` fold over `a` and `b` into `v`, each step in 64
// signed bits: 1, 0 for a division by zero, -1 where das's 64-bit arithmetic has no value
def private dumper_a_binary(op : string; a, b : int64; var v : int64&) : int {
    if (op == "div" || op == "rem") {
        return 0 if (b == 0l)
        return -1 if (b == -1l && a == -9223372036854775807l - 1l)
        v = op == "div" ? a / b : a % b
    } elif (op == "shl" || op == "shr") {
        return -1 if (b < 0l || b > 63l)
        v = op == "shl" ? int64(uint64(a) << uint64(b)) : a >> b
    } else {
        let ua = uint64(a)
        let ub = uint64(b)
        v = op == "add" ? int64(ua + ub) : op == "sub" ? int64(ua - ub) : op == "mul" ? int64(ua * ub) : op == "band" ? (a & b) : op == "bor" ? (a | b) : (a ^ b)
    }
    return 1
}
