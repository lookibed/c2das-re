options gen2

module cstr_array public

require daslib/ast
require daslib/ast_boost
require daslib/macro_boost
require daslib/templates_boost

//! `cstr_array("abc", 16)`: the C `char buf[16] = "abc"` initializer as a `uint8[16]`
//! literal built at compile time - the bytes, a NUL, zero padding to the dimension. A string
//! that fills the array exactly gets no NUL, as in C; a longer one is a compile error.
[call_macro(name = "cstr_array")]
class CstrArrayMacro : AstCallMacro {
    def override visit(prog : ProgramPtr; mod : Module?; var expr : ExprCallMacro?) : ExpressionPtr {
        macro_verify(length(expr.arguments) == 2, prog, expr.at, "cstr_array takes a string literal and a dimension")
        macro_verify(expr.arguments[0] is ExprConstString, prog, expr.at, "cstr_array: the first argument is a string literal")
        macro_verify(expr.arguments[1] is ExprConstInt, prog, expr.at, "cstr_array: the second argument is an integer literal")
        let text = string((expr.arguments[0] as ExprConstString).value)
        let dim = (expr.arguments[1] as ExprConstInt).value
        macro_verify(length(text) <= dim, prog, expr.at, "cstr_array: `{text}` does not fit {dim} bytes")
        var items : array<ExpressionPtr>
        items |> reserve(dim)
        for (ch in text) {
            items |> push(new ExprConstUInt8(at = expr.at, value = uint8(ch)))
        }
        for (_pad in range(dim - length(text))) {
            items |> push(new ExprConstUInt8(at = expr.at, value = uint8(0)))
        }
        return qmacro(fixed_array($a(items)))
    }
}
