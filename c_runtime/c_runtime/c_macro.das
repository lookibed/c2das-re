options gen2

module c_macro public

require daslib/ast
require daslib/ast_boost
require daslib/templates_boost
require daslib/macro_boost

//! `[c_macro]` on a def: every call is replaced, once the call is inferred, by the def's body with
//! each parameter substituted by its argument expression as written, the textual expansion of a C
//! function-like macro. No argument copy, result temporary or lowered condition is left for the
//! interpreter. An expression body (`=> e`, also under `[c_function]`'s `unsafe`) becomes the
//! expression; a void def's statement body becomes a block in the call's place, its locals renamed
//! apart from the caller's. A body of any other shape is a compile error.

// the expansions so far in this compile; it numbers the locals a statement body declares
var private expansion_serial = 0

class private MarkSafe : AstVisitor {
    def override preVisitExpression(var expr : ExpressionPtr) : void {
        expr.genFlags.alwaysSafe = true
    }
}

// every node of `e` is flagged safe: `unsafe` of `[c_function]` does not reach a lifted expression
def private mark_safe(var e : Expression?) {
    var v = new MarkSafe()
    make_visitor(*v) $(adapter) {
        visit(e, adapter)
    }
    unsafe {
        delete v
    }
}

class private CollectLocals : AstVisitor {
    names : array<string>
    def override preVisitExprLetVariable(expr : ExprLet?; arg : VariablePtr; lastArg : bool) : void {
        names |> push(string(arg.name))
    }
    def override preVisitExprForVariable(expr : ExprFor?; svar : VariablePtr; last : bool) : void {
        names |> push(string(svar.name))
    }
}

// the names `body` declares: `let`/`var` locals and `for` iterators
def private local_names(var body : Expression?) : array<string> {
    var v = new CollectLocals()
    make_visitor(*v) $(adapter) {
        visit(body, adapter)
    }
    var names <- v.names
    unsafe {
        delete v
    }
    return <- names
}

// the def's written body: a generic instance's is its generic's
def private source_body(var fn : Function?) : Expression? {
    var src = fn
    while (src.fromGeneric != null) {
        src = src.fromGeneric
    }
    return src.body
}

// `body` without the one-statement blocks and the `unsafe` around it; `wrapped` tells whether an
// `unsafe` was taken off
def private unwrap(var body : Expression?; var wrapped : bool&) : Expression? {
    var cur = body
    while (cur != null) {
        if (cur is ExprBlock) {
            var blk = cur as ExprBlock
            if (length(blk.list) != 1 || length(blk.finalList) != 0) {
                break
            }
            let inner = blk.list[0]
            if (!(inner is ExprBlock || inner is ExprUnsafe || inner is ExprReturn)) {
                break
            }
            cur = blk.list[0]
        } elif (cur is ExprUnsafe) {
            cur = (cur as ExprUnsafe).body
            wrapped = true
        } else {
            break
        }
    }
    return cur
}

[function_macro(name = "c_macro")]
class CMacroAnnotation : AstFunctionAnnotation {
    def override transform(var expr : ExprCallFunc?; var errors : das_string) : Expression? {
        if (expr.func == null) {
            return null
        }
        var fn = expr.func
        var wrapped = false
        var body = unwrap(source_body(fn), wrapped)
        if (body == null) {
            errors := "[c_macro] {fn.name}: no body"
            return null
        }
        var res : Expression?
        if (body is ExprReturn) {
            let ret = body as ExprReturn
            if (ret.subexpr == null) {
                errors := "[c_macro] {fn.name}: a return without a value"
                return null
            }
            if (ret.subexpr is ExprConstPtr && fn.result.isPointer) {
                // a bare `null` keeps the def's result type
                res = qmacro(default<$t(fn.result)>)
            } else {
                res = clone_expression(ret.subexpr)
            }
        } elif (body is ExprBlock && fn.result.isVoid) {
            res = clone_expression(body)
            expansion_serial ++
            let names <- local_names(res)
            if (!empty(names)) {
                res = apply_template(res) $(rules) {
                    for (n in names) {
                        rules |> renameVariable(n, "_cm{expansion_serial}_{n}")
                    }
                }
            }
        } else {
            errors := "[c_macro] {fn.name}: the body is neither one expression nor a void def's statements"
            return null
        }
        if (wrapped) {
            mark_safe(res)
        }
        res = apply_template(res) $(rules) {
            for (farg, a in fn.arguments, expr.arguments) {
                rules |> replaceVariable(string(farg.name)) <| clone_expression(a)
            }
        }
        if (wrapped && res is ExprBlock) {
            res = qmacro_block() {
                unsafe {
                    $e(res)
                }
            }
        }
        res |> force_at(expr.at)
        return res
    }
}
