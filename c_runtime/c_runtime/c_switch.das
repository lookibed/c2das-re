options gen2

module c_switch public

require daslib/ast
require daslib/ast_boost
require daslib/macro_boost
require daslib/templates_boost

// one `case (v, ...) { body }` arm: `_` among the values is `default`
struct private Arm {
    values : array<ExpressionPtr>
    is_default : bool
    body : array<ExpressionPtr>
}

// the `break` and `continue` of the switch's own level: outside every loop and inner do_while the
// arms nest; an own `continue` becomes `cont = true; break` when `cont` is set, the epilogue after
// the switch's loop continuing the real one
class private OwnJumps : AstVisitor {
    depth : int
    breaks : bool
    continues : bool
    cont : string
    def override preVisitExprWhile(expr : ExprWhile?) {
        depth++
    }
    def override visitExprWhile(var expr : ExprWhile?) : ExpressionPtr {
        depth--
        return expr
    }
    def override preVisitExprFor(expr : ExprFor?) {
        depth++
    }
    def override visitExprFor(var expr : ExprFor?) : ExpressionPtr {
        depth--
        return expr
    }
    def override preVisitExprCallMacro(expr : ExprCallMacro?) {
        if (expr.name == "c_do_while") {
            depth++
        }
    }
    def override visitExprCallMacro(var expr : ExprCallMacro?) : ExpressionPtr {
        if (expr.name == "c_do_while") {
            depth--
        }
        return expr
    }
    def override preVisitExprBreak(expr : ExprBreak?) {
        breaks ||= depth == 0
    }
    def override preVisitExprContinue(expr : ExprContinue?) {
        continues ||= depth == 0
    }
    def override visitExprBlock(var expr : ExprBlock?) : ExpressionPtr {
        if (depth != 0 || empty(cont) || !has_value([for (e in expr.list); e is ExprContinue], true)) {
            return expr
        }
        var list : array<ExpressionPtr>
        for (e in expr.list) {
            if (e is ExprContinue) {
                var stmt = qmacro_expr() {
                    $i(cont) = true
                }
                list |> push(at_call(stmt, e.at))
                list |> push(new ExprBreak(at = e.at))
            } else {
                list |> push(e)
            }
        }
        expr.list |> clear()
        for (e in list) {
            expr.list |> push(e)
        }
        return expr
    }
}

// expands every inner switch first, innermost out, so an arm's own jumps are plain loops and
// blocks when the outer one scans them
class private InnerSwitches : AstVisitor {
    failed : bool
    def override visitExprCallMacro(var expr : ExprCallMacro?) : ExpressionPtr {
        if (expr.name != "c_switch") {
            return expr
        }
        var expansion = expand_switch(expr)
        if (expansion == null) {
            failed = true
            return expr
        }
        return expansion
    }
}

// finds a `case` call left inside an arm once the inner switches are expanded: a case label in a
// nested block of an arm, C's Duff's device, which the macro does not take
class private StrayCase : AstVisitor {
    found : bool
    at : LineInfo = LineInfo()
    def override preVisitExprCall(expr : ExprCall?) {
        if (!found && expr.name == "case") {
            found = true
            at = expr.at
        }
    }
}

// visits each arm's statements as a block of their own, so that an arm's own `continue` is a block's
def private visit_arms(var arms : array<Arm>; adapter : VisitorAdapter?) {
    for (arm in arms) {
        var blk = visit(block_of(LineInfo(), arm.body), adapter) as ExprBlock
        arm.body |> clear()
        for (e in blk.list) {
            arm.body |> push(e)
        }
    }
}

// the jumps of the arms' statements; `cont` set rewrites the own continues
def private own_jumps(var arms : array<Arm>; cont : string; var breaks, continues : bool&) {
    var scan = new OwnJumps(cont = cont)
    make_visitor(*scan) $(adapter) {
        visit_arms(arms, adapter)
    }
    breaks = scan.breaks
    continues = scan.continues
    unsafe {
        delete scan
    }
}

// the arms of the switch's block, inner switches expanded; false with the error set
def private parse_arms(expr : ExprCallMacro?; var arms : array<Arm>) : bool {
    let blk = (expr.arguments[1] as ExprMakeBlock)._block as ExprBlock
    if (length(blk.arguments) != 0 || !empty(blk.finalList)) {
        macro_error(compiling_program(), expr.at, "switch's block takes no arguments and has no finally section")
        return false
    }
    var seen : table<string>
    for (st in blk.list) {
        let call = st is ExprCall ? st as ExprCall : null
        if (call == null || call.name != "case" || length(call.arguments) < 2 || !(call.arguments[length(call.arguments) - 1] is ExprMakeBlock)) {
            macro_error(compiling_program(), st.at, "c_switch holds only arms: case (v, ...) \{ ... \}, `_` the default")
            return false
        }
        var arm : Arm
        let n = length(call.arguments) - 1
        for (idx in range(n)) {
            let v = call.arguments[idx]
            // a case value is a constant (C requires it), so comparing its text finds a duplicate
            let is_default = v is ExprVar && (v as ExprVar).name == "_"
            let key = is_default ? "_" : describe(v)
            if (key_exists(seen, key)) {
                macro_error(compiling_program(), v.at, "c_switch: duplicate case value {key}")
                return false
            }
            seen |> insert(key)
            if (is_default) {
                arm.is_default = true
            } else {
                arm.values |> push(clone_expression(v))
            }
        }
        let body = (call.arguments[n] as ExprMakeBlock)._block as ExprBlock
        for (e in body.list) {
            arm.body |> push(clone_expression(e))
        }
        arms |> emplace(arm)
    }
    return expand_inner(arms)
}

// the arms' inner switches expanded, innermost first; false with the error set, a case left in a
// nested block of an arm (Duff's device) among the errors
def private expand_inner(var arms : array<Arm>) : bool {
    var inner = new InnerSwitches()
    make_visitor(*inner) $(adapter) {
        visit_arms(arms, adapter)
    }
    let failed = inner.failed
    unsafe {
        delete inner
    }
    if (failed) {
        return false
    }
    var stray = new StrayCase()
    make_visitor(*stray) $(adapter) {
        visit_arms(arms, adapter)
    }
    let found = stray.found
    let at = stray.at
    unsafe {
        delete stray
    }
    if (found) {
        macro_error(compiling_program(), at, "c_switch: a case inside a nested block of an arm (Duff's device) is not supported; the converter spells such a switch open")
    }
    return !found
}

// expression `e` placed at the call's line
def private at_call(var e : ExpressionPtr; at : LineInfo) : ExpressionPtr {
    e |> force_at(at)
    return e
}

// `a || b || ...` of the tests, left to right as the spelled chain groups them
def private any_of(tests : array<ExpressionPtr>; at : LineInfo) : ExpressionPtr {
    var acc = clone_expression(tests[0])
    for (idx in range(1, length(tests))) {
        let t = tests[idx]
        acc = at_call(qmacro($e(acc) || $e(t)), at)
    }
    return acc
}

// `c == v` for each value, each with its own copy of `c` and `v` (the splice clones)
def private value_tests(c : ExpressionPtr; values : array<ExpressionPtr>; at : LineInfo) : array<ExpressionPtr> => <- [for (v in values); at_call(qmacro($e(c) == $e(v)), at)]

// whether control cannot run past the end of statements `body` into the next arm: they end in a
// `break`, `return`, `continue` or `goto`, a trailing block looked through
def private ends(body) : bool {
    if (empty(body)) {
        return false
    }
    let last = body[length(body) - 1]
    if (last is ExprBlock) {
        return ends((last as ExprBlock).list)
    }
    return last is ExprBreak || last is ExprReturn || last is ExprContinue || last is ExprGoto
}

// statements `body` without their tail `break`, a trailing block looked through
def private drop_tail_break(var body : array<ExpressionPtr>) {
    if (empty(body)) {
        return
    }
    let n = length(body) - 1
    if (body[n] is ExprBreak) {
        body |> erase(n)
    } elif (body[n] is ExprBlock) {
        var inner <- [for (e in (body[n] as ExprBlock).list); e]
        drop_tail_break(inner)
        (body[n] as ExprBlock).list |> clear()
        for (e in inner) {
            (body[n] as ExprBlock).list |> push(e)
        }
    }
}

// a block holding `stmts`, the arm's body
def private block_of(at : LineInfo; var stmts : array<ExpressionPtr>) : ExprBlock? {
    var blk = new ExprBlock(at = at)
    for (e in stmts) {
        blk.list |> push(e)
    }
    return blk
}

// no arm falls into the next and none breaks but at its tail, which is gone: the if-chain,
// `default` its `else`
def private if_chain(at : LineInfo; c : ExpressionPtr; var arms : array<Arm>) : ExpressionPtr {
    var otherwise : ExpressionPtr
    var chain : array<ExprIfThenElse?>
    for (arm in arms) {
        if (arm.is_default) {
            otherwise = block_of(at, arm.body)
        } else {
            let tests <- value_tests(c, arm.values, at)
            chain |> push(new ExprIfThenElse(at = at, cond = any_of(tests, at), if_true = block_of(at, arm.body)))
        }
    }
    if (empty(chain)) {
        return otherwise
    }
    for (idx in range(length(chain) - 1)) {
        chain[idx].if_false = chain[idx + 1]
    }
    chain[length(chain) - 1].if_false = otherwise
    return chain[0]
}

// the matched-flag loop, the arms as written: an arm the arm before cannot enter and that cannot
// enter the next (or is the last) tests its values in its own `if`; any other sets `flag` from its
// values and runs while it is set, so falling into the next keeps it set; the loop's own `break`
// follows the last
def private flag_loop(at : LineInfo; c : ExpressionPtr; var arms : array<Arm>) : ExpressionPtr {
    let flag = make_unique_private_name("_flag", at)
    var all_tests : array<ExpressionPtr>
    for (arm in arms) {
        var tests <- value_tests(c, arm.values, at)
        all_tests |> push_from(tests)
    }
    let count = length(arms)
    let plain <- [for (idx in range(count)); !empty(arms[idx].body) && !(arms[idx].is_default && empty(all_tests)) && (idx == 0 || ends(arms[idx - 1].body)) && (idx == count - 1 || ends(arms[idx].body))]
    var list : array<ExpressionPtr>
    // an empty arm but the last still sets the flag its values match, for the arm it falls into
    let flagged <- [for (idx in range(count)); !plain[idx] && (!empty(arms[idx].body) || idx < count - 1)]
    if (has_value(flagged, true)) {
        var stmt = qmacro_expr() {
            var $i(flag) = false
        }
        list |> push(at_call(stmt, at))
    }
    for (idx in range(count)) {
        if (!flagged[idx] && !plain[idx]) {
            continue
        }
        var tests <- value_tests(c, arms[idx].values, at)
        if (arms[idx].is_default && !empty(all_tests)) {
            let none_of = any_of(all_tests, at)
            tests |> push(at_call(qmacro(!($e(none_of))), at))
        }
        if (plain[idx]) {
            list |> push(new ExprIfThenElse(at = at, cond = any_of(tests, at), if_true = block_of(at, arms[idx].body)))
            continue
        }
        list |> reserve(length(list) + length(tests) + 2)
        for (t in tests) {
            var stmt = qmacro_expr() {
                $i(flag) ||= $e(t)
            }
            list |> push(at_call(stmt, at))
        }
        if (arms[idx].is_default && empty(all_tests)) {
            var stmt = qmacro_expr() {
                $i(flag) = true
            }
            list |> push(at_call(stmt, at))
        }
        if (!empty(arms[idx].body)) {
            list |> push(new ExprIfThenElse(at = at, cond = at_call(qmacro($i(flag)), at), if_true = block_of(at, arms[idx].body)))
        }
    }
    list |> push(new ExprBreak(at = at))
    var loop = qmacro_expr() {
        while (true) {
            break
        }
    }
    loop |> force_at(at)
    var loop_block = (loop as ExprWhile).body as ExprBlock
    loop_block.list |> clear()
    for (e in list) {
        loop_block.list |> push(e)
    }
    return loop
}

// the expansion of one switch call, null with the error set
def private expand_switch(var expr : ExprCallMacro?) : ExpressionPtr {
    let at = expr.at
    if (length(expr.arguments) != 2 || !(expr.arguments[1] is ExprMakeBlock)) {
        macro_error(compiling_program(), at, "c_switch takes a value and a block of arms: c_switch (x) \{ case (1) \{ ... \} \}")
        return null
    }
    var arms : array<Arm>
    if (!parse_arms(expr, arms)) {
        return null
    }
    // the if-chain's arms: each without its tail `break`, which must leave no other own `break`
    var chain_arms : array<Arm>
    chain_arms |> reserve(length(arms))
    for (arm in arms) {
        var copy : Arm
        copy.is_default = arm.is_default
        copy.values := arm.values
        copy.body |> reserve(length(arm.body))
        for (e in arm.body) {
            copy.body |> push(clone_expression(e))
        }
        drop_tail_break(copy.body)
        chain_arms |> emplace(copy)
    }
    var breaks, continues : bool
    own_jumps(chain_arms, "", breaks, continues)
    let looped = breaks || has_value([for (idx in range(length(arms) - 1)); !ends(arms[idx].body)], true)
    let cont = looped && continues ? make_unique_private_name("_cont", at) : ""
    if (!empty(cont)) {
        own_jumps(arms, cont, breaks, continues)
    }
    // the value is read once: a variable in place, since no arm's store into it reaches a test
    // that decides (an arm runs only once its values or the arm entering it matched), any other
    // value through a `let`
    var value = expr.arguments[0]
    let bound = !(value is ExprVar)
    let name = bound ? make_unique_private_name("_cond", at) : ""
    let c = bound ? at_call(qmacro($i(name)), at) : value
    var dispatch = looped ? flag_loop(at, c, arms) : if_chain(at, c, chain_arms)
    if (!bound && empty(cont)) {
        if (dispatch == null) {
            return new ExprBlock(at = at)
        }
        return dispatch
    }
    var outer = new ExprBlock(at = at)
    if (bound) {
        var stmt = qmacro_expr() {
            let $i(name) = $e(value)
        }
        outer.list |> push(at_call(stmt, at))
    }
    if (!empty(cont)) {
        var stmt = qmacro_expr() {
            var $i(cont) = false
        }
        outer.list |> push(at_call(stmt, at))
    }
    if (dispatch != null) {
        outer.list |> push(dispatch)
    }
    if (!empty(cont)) {
        var stmt = qmacro_expr() {
            if ($i(cont)) {
                continue
            }
        }
        outer.list |> push(at_call(stmt, at))
    }
    return outer
}

//! `c_switch (x) { case (A, B) { body } ... case (_) { body } }`: C's switch with C's meaning, `_`
//! the `default` (alone or beside values) at any position. An arm that does not end in `break`,
//! `return`, `continue` or `goto` falls into the next; a `break` of the switch's own level (outside
//! every loop and inner `c_do_while`) leaves it, a `continue` reaches the enclosing loop, and `x` is
//! read once. The call expands in place before its arguments are inferred, inner switches first:
//! with no arm falling into the next and no own `break` but an arm's tail, to
//! `if (x == A || x == B) { body } elif ... else { default }`, the tail breaks dropped; otherwise to
//! the matched-flag loop `while (true) { var flag = false; flag ||= x == A; if (flag) { body } ...
//! break }`, in which an arm neither entered nor entering tests its values in its own `if`, and an
//! own `continue` sets a flag and leaves the loop, continuing after it. A duplicate case value, a
//! second `_` and a statement that is no arm are compile errors.
[call_macro(name = "c_switch")]
class CSwitchMacro : AstCallMacro {
    def override canVisitArgument(expr : ExprCallMacro?; argIndex : int) : bool => false
    def override canFoldReturnResult(expr : ExprCallMacro?) : bool => false
    def override visit(prog : ProgramPtr; mod : Module?; var expr : ExprCallMacro?) : ExpressionPtr => <- expand_switch(expr)
}
