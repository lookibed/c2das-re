options gen2

module cstr public

require daslib/ast
require daslib/ast_boost
require daslib/macro_boost
require daslib/templates_boost

//! `cstr("abc")`: a C string literal as the `uint8?` of its bytes, NUL-terminated as C's. The call
//! expands in place to the one `reinterpret<uint8?>("abc")`, flagged safe, so converted code
//! carries no `unsafe` for it and the interpreter makes no call per literal. A call whose argument
//! is no string literal is left to a program's own `cstr`.
[call_macro(name = "cstr")]
class CstrMacro : AstCallMacro {
    def override visit(prog : ProgramPtr; mod : Module?; var expr : ExprCallMacro?) : ExpressionPtr {
        if (length(expr.arguments) != 1 || !(expr.arguments[0] is ExprConstString)) {
            var call = new ExprCall(at = expr.at, name := expr.name)
            for (arg in expr.arguments) {
                call.arguments |> emplace_new(clone_expression(arg))
            }
            return <- call
        }
        var expansion <- qmacro(reinterpret<uint8?>($e(expr.arguments[0])))
        expansion.at = expr.at
        expansion.genFlags.alwaysSafe = true
        return <- expansion
    }
}
