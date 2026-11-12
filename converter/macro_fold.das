options gen2

module macro_fold public

require strings
require daslib/strings_boost
require cir

//! Whether a whole expansion of a function-like macro (`docs/c-ir-spec.md` section 6.3) may print
//! as a call of an `[inline] def` (`ARCHITECTURE_EMITTER_MACROS.md#fold-verdict`): read from the
//! expansion's node alone, where its argument copies are, what the rest of it names, writes and
//! leaves; nothing here knows das syntax.

//! A verdict on one expansion: `reason` empty when it folds, else why it stays expanded (`never`,
//! `incomplete`, `capture`, `flow`, `shape`, `lvalue`, `effects`, `faulting`, `order`); `copies`
//! the argument copies by parameter, in evaluation order; `refs` the parameters the def takes by
//! reference, a caller's local the body stores into or steps.
struct FoldSite {
    reason : string
    copies : array<array<CirExpr const?>>
    refs : array<bool>
}

//! What a verdict needs of the function holding the expansion: the names its parameters and
//! locals take, the ones whose address it takes, and the macro names the sidecar's `no_fold` lists.
struct FoldScope {
    locals : table<string>
    addressed : table<string>
    no_fold : table<string>
}

let private CALLS_NEVER_FOLDED <- {"alloca", "__builtin_alloca", "setjmp", "_setjmp", "__sigsetjmp", "longjmp", "_longjmp", "__builtin_va_start", "__builtin_va_end", "__builtin_va_copy"}

// the walk over one expansion: the copies of its arguments by parameter and whether any copy sits
// where it is evaluated only on some paths, an effect evaluated before the walk's point, the names
// the expansion itself declares, the loops and switches around the point
struct private SiteWalk {
    site : int
    copies : array<array<CirExpr const?>>
    conditional : array<bool>
    effectful : array<bool>
    refs : array<bool>
    effect_seen : bool
    unstable_after_effect : bool
    lvalue : bool
    captures : bool
    flow : bool
    shape : bool
    declared : table<string>
    loops : int
    switches : int
}

def private copy_of(x : CirExpr const?; site : int) : int {
    for (a in x.macro_args) {
        if (a.site == site) {
            return a.k
        }
    }
    return -1
}

def private below_casts(x : CirExpr const?) : CirExpr const? {
    var at = x
    while (at != null && at.e == "cast") {
        at = at.a
    }
    return at
}

def private is_step_or_store(x : CirExpr const?) : bool =>
    x.e == "assign" || x.e == "call" || x.e == "va_arg" || (x.e == "un" && (x.op == "preinc" || x.op == "predec" || x.op == "postinc" || x.op == "postdec"))

//! Whether evaluating `x` writes, calls or reads a volatile object anywhere.
def has_effect(x : CirExpr const?) : bool {
    if (x == null) {
        return false
    }
    if (is_step_or_store(x) || x.e == "comma" || (x.e == "cast" && x.cast_kind == "LValueToRValue" && x.a != null && x.a.vol) || has_effect(x.a) || has_effect(x.b) || has_effect(x.c) || has_effect(x.fn) || has_effect(x.base) || has_effect(x.i) || has_effect(x.list) || has_effect(x.init)) {
        return true
    }
    for (arg in x.args) {
        if (has_effect(arg)) {
            return true
        }
    }
    for (item in x.init_items) {
        if (has_effect(item.v)) {
            return true
        }
    }
    return false
}

let private SAFE_BINARY <- {"add", "sub", "mul", "shl", "shr", "lt", "gt", "le", "ge", "eq", "ne", "band", "bor", "bxor", "land", "lor"}
let private SAFE_UNARY <- {"neg", "plus", "bnot", "lnot"}

// a constant, a local or parameter (`locals`), a field of one through `.`, the address of either,
// or arithmetic over those without `/` or `%`: evaluating it cannot fault; with `stable` also its value no write
// of the expansion can change (the local's address is never taken), division allowed
def private settled(x : CirExpr const?; scope : FoldScope; stable : bool) : bool {
    if (x == null) {
        return false
    }
    if (x.e == "int_lit" || x.e == "float_lit" || x.e == "enum_ref" || x.e == "sizeof_v" || x.e == "alignof_v") {
        return true
    }
    if (x.e == "ref") {
        return key_exists(scope.locals, x.name) && !(stable && key_exists(scope.addressed, x.name))
    }
    if (x.e == "cast") {
        return x.cast_kind != "LValueToRValue" || x.a == null || !x.a.vol ? settled(x.a, scope, stable) : false
    }
    if (x.e == "member") {
        return !x.arrow && settled(x.base, scope, stable)
    }
    if (x.e == "un") {
        // the address of a local or of its field is a constant
        return x.op == "addr" ? settled(x.a, scope, false) : key_exists(SAFE_UNARY, x.op) && settled(x.a, scope, stable)
    }
    if (x.e == "bin") {
        return (key_exists(SAFE_BINARY, x.op) || (stable && (x.op == "div" || x.op == "rem"))) && settled(x.a, scope, stable) && settled(x.b, scope, stable)
    }
    if (x.e == "cond") {
        return settled(x.c, scope, stable) && settled(x.a, scope, stable) && settled(x.b, scope, stable)
    }
    return false
}

// whether `x` reads local `name` anywhere
def private reads_name(x : CirExpr const?; name : string) : bool {
    if (x == null) {
        return false
    }
    if (x.e == "ref" && x.name == name) {
        return true
    }
    for (part in fixed_array<CirExpr const?>(x.a, x.b, x.c, x.fn, x.base, x.i, x.list, x.init)) {
        if (reads_name(part, name)) {
            return true
        }
    }
    for (arg in x.args) {
        if (reads_name(arg, name)) {
            return true
        }
    }
    return false
}

// a copy read as a value: an rvalue, or an lvalue under its load; the store, step, address,
// field or element of an argument would act on the def's parameter, not the caller's object
def private read_as_value(x, parent : CirExpr const?) : bool {
    let lvalue = x.e == "ref" || x.e == "member" || x.e == "index" || (x.e == "un" && x.op == "deref") || x.e == "str_lit" || x.e == "compound_lit"
    return !lvalue || (parent != null && parent.e == "cast" && parent.cast_kind == "LValueToRValue")
}

def private walk_expr(var w : SiteWalk; scope : FoldScope; x, parent : CirExpr const?; cond : bool) {
    if (x == null) {
        return
    }
    let k = copy_of(x, w.site)
    if (k >= 0 && k < length(w.copies)) {
        w.copies[k] |> push(x)
        w.conditional[k] ||= cond
        if (!read_as_value(x, parent)) {
            // a caller's local the body writes is the def's reference parameter; its address is not
            let local = x.e == "ref" && key_exists(scope.locals, x.name)
            w.refs[k] ||= local
            w.lvalue ||= !local || (parent != null && parent.e == "un" && parent.op == "addr")
        }
        // a copy read again on a loop's next turn or after a write sees what that write left
        w.unstable_after_effect ||= (w.effect_seen || w.loops > 0) && !settled(x, scope, true)
        if (has_effect(x)) {
            w.effectful[k] = true
            w.effect_seen = true
        }
        return
    }
    if (x.e == "ref" && key_exists(scope.locals, x.name) && !key_exists(w.declared, x.name)) {
        w.captures = true
    }
    if (x.e == "compound_lit" || x.e == "init_list" || x.e == "va_arg" || x.e == "offsetof") {
        w.shape = true
    }
    if (x.e == "call") {
        let callee = below_casts(x.fn)
        w.shape ||= callee != null && callee.e == "ref" && key_exists(CALLS_NEVER_FOLDED, callee.name)
    }
    if (x.e == "cond") {
        walk_expr(w, scope, x.c, x, cond)
        walk_expr(w, scope, x.a, x, true)
        walk_expr(w, scope, x.b, x, true)
    } elif (x.e == "bin" && (x.op == "land" || x.op == "lor")) {
        walk_expr(w, scope, x.a, x, cond)
        walk_expr(w, scope, x.b, x, true)
    } else {
        walk_expr(w, scope, x.fn, x, cond)
        for (arg in x.args) {
            walk_expr(w, scope, arg, x, cond)
        }
        for (part in fixed_array<CirExpr const?>(x.base, x.i, x.a, x.b, x.list, x.init)) {
            walk_expr(w, scope, part, x, cond)
        }
        for (item in x.init_items) {
            walk_expr(w, scope, item.v, x, cond)
        }
    }
    if (is_step_or_store(x) || (x.e == "cast" && x.cast_kind == "LValueToRValue" && x.a != null && x.a.vol)) {
        w.effect_seen = true
    }
}

def private walk_stmt(var w : SiteWalk; scope : FoldScope; st : CirStmt const?; cond : bool) {
    if (st == null) {
        return
    }
    let s = st.s
    if (s == "return" || s == "goto" || s == "label" || ((s == "case" || s == "default") && w.switches == 0) || (s == "break" && w.loops + w.switches == 0) || (s == "continue" && w.loops == 0)) {
        w.flow = true
        return
    }
    if (s == "decl") {
        w.declared |> insert(st.name)
    }
    let loop = s == "while" || s == "do" || s == "for"
    let branch = cond || loop || s == "if" || s == "switch"
    walk_stmt(w, scope, st.init_s, cond)
    walk_expr(w, scope, st.init, null, cond)
    walk_expr(w, scope, st.e, null, cond)
    if (loop) {
        w.loops++
    }
    walk_expr(w, scope, st.cond, null, s == "do" ? branch : cond)
    if (s == "switch") {
        w.switches++
    }
    walk_expr(w, scope, st.inc, null, branch)
    walk_stmt(w, scope, st.then_s, branch)
    walk_stmt(w, scope, st.else_s, branch)
    walk_stmt(w, scope, st.body_s, branch)
    for (child in st.body) {
        walk_stmt(w, scope, child, branch && s != "compound" ? true : cond)
    }
    if (loop) {
        w.loops--
    }
    if (s == "switch") {
        w.switches--
    }
}

// the zero-use argument `text`, which no node holds: a decimal literal or a local's name
def private settled_text(text : string; scope : FoldScope) : bool {
    if (empty(text)) {
        return false
    }
    var digits = true
    peek_data(text) $(b) {
        for (c in b) {
            digits = digits && is_number(int(c))
        }
    }
    return digits || key_exists(scope.locals, text)
}

// the expansions folding would make harder to read (`fn_macros_part1.md` 7.5): a body that is
// `((void)0)`, an argument under casts alone, one operator over arguments one of which it never reads
def private never_folded(m : CirMacro; x : CirExpr const?; site : int) : bool {
    let at = below_casts(x)
    if (at == null || copy_of(at, site) >= 0 || (x.e == "cast" && x.cast_kind == "ToVoid" && (at.e == "int_lit" || at.e == "float_lit"))) {
        return true
    }
    if (!has_value(m.uses, 0) || (at.e != "bin" && at.e != "un")) {
        return false
    }
    let a = below_casts(at.a)
    let b = below_casts(at.b)
    return (a != null && copy_of(a, site) >= 0) && (at.e == "un" || (b != null && copy_of(b, site) >= 0))
}

// why the expansion's node cannot be a def's body at all: its shape, its flow, its copies counted
// against `uses`, a captured local, an argument used as an object
def private body_reason(m : CirMacro; use : CirMacroUse; w : SiteWalk) : string {
    if (w.shape || w.flow) {
        return w.shape ? "shape" : "flow"
    }
    if (length(use.args) != length(m.params)) {
        return "incomplete"
    }
    for (k, n in count(), m.uses) {
        if (n < 0 || length(w.copies[k]) != n) {
            return "incomplete"
        }
    }
    return w.captures ? "capture" : w.lvalue ? "lvalue" : ""
}

// class B (a parameter read twice, never or on some paths): no argument with an effect, and every
// argument not read exactly once settled
def private class_b_reason(m : CirMacro; use : CirMacroUse; w : SiteWalk; scope : FoldScope) : string {
    var b_class = false
    for (k, n in count(), m.uses) {
        b_class ||= n != 1 || w.conditional[k]
    }
    if (b_class && has_value(w.effectful, true)) {
        return "effects"
    }
    for (k, n in count(), m.uses) {
        if ((n == 0 && !settled_text(use.args[k], scope)) || ((n != 1 || w.conditional[k]) && !all_settled(w.copies[k], scope, false))) {
            return "faulting"
        }
    }
    return ""
}

def private all_settled(copies : array<CirExpr const?>; scope : FoldScope; stable : bool) : bool {
    for (c in copies) {
        if (!settled(c, scope, stable)) {
            return false
        }
    }
    return true
}

// a copy C reads later than the call would: after the body writes the local another argument
// takes by reference, after a store or on a loop's next turn; or arguments with effects das may
// run in another order: two of them, or one beside an argument whose value can change
def private order_reason(m : CirMacro; w : SiteWalk; scope : FoldScope) : string {
    for (k in range(length(m.uses))) {
        if (w.refs[k]) {
            let name = w.copies[k][0].name
            for (j in range(length(m.uses))) {
                for (c in w.copies[j]) {
                    if (j != k && reads_name(c, name)) {
                        return "order"
                    }
                }
            }
        }
    }
    if (w.unstable_after_effect) {
        return "order"
    }
    var effects = 0
    for (k in range(length(m.uses))) {
        effects += w.effectful[k] ? 1 : 0
        if (!w.effectful[k] && has_value(w.effectful, true) && !all_settled(w.copies[k], scope, true)) {
            return "order"
        }
    }
    return effects > 1 ? "order" : ""
}

def private verdict(m : CirMacro; use : CirMacroUse; w : SiteWalk; scope : FoldScope) : string {
    let body = body_reason(m, use, w)
    if (!empty(body)) {
        return body
    }
    let b = class_b_reason(m, use, w, scope)
    return !empty(b) ? b : order_reason(m, w, scope)
}

def private new_walk(m : CirMacro; use : CirMacroUse) : SiteWalk {
    var w = SiteWalk(site = use.site)
    w.copies |> resize(length(m.params))
    w.conditional |> resize(length(m.params))
    w.effectful |> resize(length(m.params))
    w.refs |> resize(length(m.params))
    return <- w
}

//! The verdict on expansion `use` of macro `m`, whose whole node is expression `x`.
[arch(at="ARCHITECTURE_EMITTER_MACROS.md#fold-verdict")]
def fold_expr_site(m : CirMacro; use : CirMacroUse; x : CirExpr const?; scope : FoldScope) : FoldSite {
    if (key_exists(scope.no_fold, m.name) || never_folded(m, x, use.site)) {
        return FoldSite(reason = "never")
    }
    var w <- new_walk(m, use)
    walk_expr(w, scope, x, null, false)
    let reason = verdict(m, use, w, scope)
    return <- FoldSite(reason = reason, copies <- w.copies, refs <- w.refs)
}

//! The verdict on expansion `use` of statement macro `m`, whose whole node is `st`: a
//! `do { ... } while (0)`, whose loop the def drops, or a block.
[arch(at="ARCHITECTURE_EMITTER_MACROS.md#fold-verdict")]
def fold_stmt_site(m : CirMacro; use : CirMacroUse; st : CirStmt const?; scope : FoldScope) : FoldSite {
    var body : CirStmt const? = st
    if (st.s == "do") {
        body = st.body_s
    }
    let wrapped = st.s == "compound" || (st.s == "do" && st.cond != null && st.cond.e == "int_lit" && st.cond.v == "0")
    if (key_exists(scope.no_fold, m.name) || !wrapped || body == null || empty(body.body)) {
        return FoldSite(reason = "never")
    }
    var w <- new_walk(m, use)
    walk_stmt(w, scope, body, false)
    let reason = verdict(m, use, w, scope)
    return <- FoldSite(reason = reason, copies <- w.copies, refs <- w.refs)
}
