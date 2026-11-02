options gen2

module enum_from_int public

require daslib/ast
require daslib/ast_boost
require daslib/macro_boost
require daslib/templates_boost

//! `enum_from_int(type<E>, i)`: the C implicit int-to-enum conversion. An out-of-range value
//! survives by value, compares by value and prints as `enum N`. The call expands in place to the
//! one `unsafe(reinterpret<E>(i))`, so converted code carries no `unsafe` and the interpreter
//! makes no call per conversion. A call without the witness is left to a program's own
//! `enum_from_int`.
[call_macro(name = "enum_from_int")]
class EnumFromIntMacro : AstCallMacro {
    def override visit(prog : ProgramPtr; mod : Module?; var expr : ExprCallMacro?) : ExpressionPtr {
        if (length(expr.arguments) != 2 || !(expr.arguments[0] is ExprTypeDecl)) {
            // no type witness: a call of a program's own `enum_from_int`, which overloading resolves
            var call = new ExprCall(at = expr.at, name := expr.name)
            for (arg in expr.arguments) {
                call.arguments |> emplace_new(clone_expression(arg))
            }
            return <- call
        }
        let witness = expr.arguments[0]._type
        let value = expr.arguments[1]._type
        if (witness == null || value == null) {
            return <- default<ExpressionPtr>
        }
        macro_verify(witness.isEnum, prog, expr.at, "enum_from_int: the witness is an enum type")
        macro_verify(value.baseType == Type.tInt, prog, expr.at, "enum_from_int: the value is an int")
        var expansion <- qmacro(reinterpret<$t(witness)>($e(expr.arguments[1])))
        expansion.at = expr.at
        expansion.genFlags.alwaysSafe = true
        return <- expansion
    }
}
