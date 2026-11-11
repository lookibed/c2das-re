options gen2

module c_do_while public

require daslib/ast
require daslib/ast_boost
require daslib/macro_boost
require daslib/templates_boost

// finds a `continue` of the c_do_while's own loop: one outside every loop the body nests, an
// inner c_do_while included; a match arm's `continue` is the loop's, so blocks are walked
class private OwnContinue : AstVisitor {
    depth : int
    found : bool
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
    def override preVisitExprContinue(expr : ExprContinue?) {
        if (depth == 0) {
            found = true
        }
    }
}

def private continues_own_loop(body : array<ExpressionPtr>) : bool {
    var scan = new OwnContinue()
    make_visitor(*scan) $(adapter) {
        for (e in body) {
            visit(e, adapter)
        }
    }
    let found = scan.found
    unsafe {
        delete scan
    }
    return found
}

//! `c_do_while (c) { body }`: C's `do { body } while (c);`, the body run once before the first test.
//! The call expands in place before its arguments are inferred, the block's statements spliced
//! into the loop, so a `break` leaves the loop, a `return` the function and a `continue` reaches
//! the test, as in C. A body with no `continue` of its own loop is
//! `while (true) { body; if (!(c)) { break } }`, otherwise
//! `var first = true; while (first || c) { first = false; body }` under a fresh name. The test
//! is a das `bool`, which the `!` or `||` of the expansion checks.
[call_macro(name = "c_do_while")]
class CDoWhileMacro : AstCallMacro {
    def override canVisitArgument(expr : ExprCallMacro?; argIndex : int) : bool => false
    def override canFoldReturnResult(expr : ExprCallMacro?) : bool => false
    def override visit(prog : ProgramPtr; mod : Module?; var expr : ExprCallMacro?) : ExpressionPtr {
        if (length(expr.arguments) != 2 || !(expr.arguments[1] is ExprMakeBlock)) {
            macro_error(prog, expr.at, "c_do_while takes a condition and a block: c_do_while (c) \{ ... \}")
            return <- default<ExpressionPtr>
        }
        let blk = (expr.arguments[1] as ExprMakeBlock)._block as ExprBlock
        if (length(blk.arguments) != 0 || !empty(blk.finalList)) {
            macro_error(prog, expr.at, "c_do_while's block takes no arguments and has no finally section")
            return <- default<ExpressionPtr>
        }
        var body <- [for (e in blk.list); clone_expression(e)]
        var cond = expr.arguments[0]
        var expansion : ExpressionPtr
        var loop : ExprWhile?
        var at = 0
        if (!continues_own_loop(body)) {
            expansion = qmacro_expr() {
                while (true) {
                    if (!($e(cond))) {
                        break
                    }
                }
            }
            loop = expansion as ExprWhile
        } else {
            let first = make_unique_private_name("_first", expr.at)
            expansion = qmacro_block() {
                var $i(first) = true
                while ($i(first) || $e(cond)) {
                    $i(first) = false
                }
            }
            loop = (expansion as ExprBlock).list[1] as ExprWhile
            at = 1
        }
        // the loop's own nodes take the call's line, the body's keep theirs; the body's statements go
        // into the loop's own block, as the spelled loop holds them
        expansion |> force_at(expr.at)
        var loop_block = loop.body as ExprBlock
        for (e in body) {
            loop_block.list |> emplace(e, at)
            at++
        }
        return <- expansion
    }
}
