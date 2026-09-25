options gen2

module _probe_macros public

require daslib/ast
require daslib/ast_boost
require daslib/templates_boost

[function_macro(name = "c_function")]
class CFunctionAnnotation : AstFunctionAnnotation {
    def override apply(var func : FunctionPtr; var group : ModuleGroup; var args : AnnotationArgumentList; var errors : das_string) : bool {
        func.body = qmacro_block() {
            unsafe {
                $e(func.body)
            }
        }
        return true
    }
}

[call_macro(name = "vsum")]
class VSumMacro : AstCallMacro {
    def override visit(prog : ProgramPtr; mod : Module?; var expr : ExprCallMacro?) : ExpressionPtr {
        var tail = new ExprMakeTuple(at = expr.at)
        for (i in range(1, length(expr.arguments))) {
            tail.values |> push(clone_expression(expr.arguments[i]))
        }
        var tailExpr : ExpressionPtr = tail
        return qmacro(vsum_impl($e(expr.arguments[0]), $e(tailExpr)))
    }
}
