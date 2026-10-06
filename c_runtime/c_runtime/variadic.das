options gen2

module variadic public

require daslib/ast
require daslib/ast_boost
require daslib/apply
require daslib/macro_boost
require daslib/templates_boost

//! C varargs as a generic over a trailing tuple. `[variadic] def f(fixed...; va : va_args)`
//! becomes `f`va(fixed...; _va_tuple : auto)` whose body opens with `let va <- to_cvalist(_va_tuple)`,
//! and a call macro named `f` tuples every argument past the fixed ones, so a converted call
//! site `f(a, 1, 2.5)` stays spelled as C spells it. `va_arg(v, T)` is a typed `as` pop at a
//! cursor the body keeps; a mismatch panics, which is the C undefined behavior made visible.

variant CVal {
    i : int64
    d : double
    p : void?
}

typedef CVaList = array<CVal>

//! The declared type of the trailing parameter; the annotation replaces it.
struct va_args {}

//! The call shape with no trailing argument at all.
struct VaNone {}

[unused_argument(va)]
def to_cvalist(va : VaNone) : CVaList {
    var lst : CVaList
    return <- lst
}

//! The prologue converter: one `CVal` per tuple field, C's default argument promotions applied -
//! `float` widens to `double`, every integer class including `bool` and enums widens to `int64`,
//! any pointer travels as `void?`.
def to_cvalist(va : auto) : CVaList {
    var lst : CVaList
    apply(va) $(name, field) {
        static_if (typeinfo is_pointer(field)) {
            lst |> push(CVal(p = unsafe(reinterpret<void?>(field))))
        } static_elif (typeinfo is_float(field)) {
            lst |> push(CVal(d = double(field)))
        } static_elif (typeinfo is_double(field)) {
            lst |> push(CVal(d = field))
        } static_elif (typeinfo stripped_typename(field) == "bool") {
            lst |> push(CVal(i = field ? 1l : 0l))
        } else {
            lst |> push(CVal(i = int64(field)))
        }
    }
    return <- lst
}

class VariadicCallMacro : AstCallMacro {
    target : string
    fixed : int
    def override visit(prog : ProgramPtr; mod : Module?; var expr : ExprCallMacro?) : ExpressionPtr {
        let n = length(expr.arguments)
        macro_verify(n >= fixed, prog, expr.at, "{expr.name} takes at least {fixed} argument(s)")
        var fixed_args : array<ExpressionPtr>
        fixed_args |> reserve(fixed)
        for (idx in range(fixed)) {
            fixed_args |> push(clone_expression(expr.arguments[idx]))
        }
        var tail : ExpressionPtr
        if (n == fixed) {
            tail = qmacro(VaNone())
        } else {
            var tup = new ExprMakeTuple(at = expr.at)
            for (idx in range(fixed, n)) {
                tup.values |> push(clone_expression(expr.arguments[idx]))
            }
            tail = tup
        }
        return qmacro($c(target)($a(fixed_args), $e(tail)))
    }
}

def private is_va_args(t : TypeDeclPtr) : bool {
    return t != null && t.baseType == Type.tStructure && t.structType != null && t.structType.name == "va_args"
}

[function_macro(name = "variadic")]
class VariadicAnnotation : AstFunctionAnnotation {
    def override apply(var func : FunctionPtr; var group : ModuleGroup; var args : AnnotationArgumentList; var errors : das_string) : bool {
        let n = length(func.arguments)
        if (n == 0 || !is_va_args(func.arguments[n - 1]._type)) {
            errors := "[variadic] needs a trailing parameter of type va_args"
            return false
        }
        var last = func.arguments[n - 1]
        let list_name = string(last.name)
        last.name := "_va_tuple"
        last._type = new TypeDecl(baseType = Type.autoinfer, at = last.at)
        var wrapped = qmacro_block() {
            let $i(list_name) <- to_cvalist(_va_tuple)
            $e(func.body)
        }
        var prologue = unsafe(reinterpret<ExprBlock?>(wrapped))
        prologue.at = func.at
        for (idx in range(length(prologue.list))) {
            prologue.list[idx].at = func.at
        }
        func.body = prologue
        let c_name = string(func.name)
        let target = "{c_name}`va"
        func.name := target
        var macro = new VariadicCallMacro(target = target, fixed = n - 1)
        compiling_module() |> add_call_macro(make_call_macro(c_name, macro))
        return true
    }
}
