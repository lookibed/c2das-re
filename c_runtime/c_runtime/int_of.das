options gen2

module int_of public

require daslib/ast
require daslib/ast_boost
require daslib/macro_boost
require daslib/templates_boost

//! `int_of(a < b)`: C's int value of a truth, 1 or 0. The call expands in place to `a < b ? 1 : 0`
//! once its argument is inferred, so the interpreter makes no call for it and every tier runs the
//! node the spelled ternary is. A call whose argument is no `bool` is a compile error: das has no
//! `int(bool)`, and the name is the converter's, never a program's.
[call_macro(name = "int_of")]
class IntOfMacro : AstCallMacro {
    def override visit(prog : ProgramPtr; mod : Module?; var expr : ExprCallMacro?) : ExpressionPtr {
        if (length(expr.arguments) != 1) {
            macro_error(prog, expr.at, "int_of takes one bool")
            return <- default<ExpressionPtr>
        }
        if (expr.arguments[0]._type == null) {
            return <- default<ExpressionPtr>
        }
        if (!expr.arguments[0]._type.isBool) {
            macro_error(prog, expr.at, "int_of takes a bool, not {describe(expr.arguments[0]._type)}")
            return <- default<ExpressionPtr>
        }
        var expansion <- qmacro($e(expr.arguments[0]) ? 1 : 0)
        expansion.at = expr.at
        return <- expansion
    }
}
