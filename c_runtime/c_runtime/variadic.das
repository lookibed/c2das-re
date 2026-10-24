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
//! site `f(a, 1, 2.5)` stays spelled as C spells it. A C `va_list` is a `CVaCursor` over that
//! list, and `va_arg(v, T)` is a typed pop at it; a mismatch panics, which is the C undefined
//! behavior made visible.

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

//! A list already built, which a late-bound variadic call forwards from its wrapper
//! (`converter/ARCHITECTURE_LAYOUT.md`): the list as it is, copied.
def to_cvalist(va : CVaList) : CVaList => <- clone_to_move(va)

//! The prologue converter: one `CVal` per tuple field, C's default argument promotions applied -
//! `float` widens to `double`, every integer class including `bool` and enums widens to `int64`,
//! any pointer or function value travels as `void?`.
def to_cvalist(va : auto) : CVaList {
    var lst : CVaList
    apply(va) $(name, field) {
        static_if (typeinfo is_pointer(field) || typeinfo is_function(field)) {
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

//! A C `va_list` object: the address of the function's list and the position of the next
//! argument. Assignment copies both, which is `va_copy`; a `var` parameter of this type is the
//! caller's own cursor, which is the linux `va_list` parameter (an array decayed to a pointer).
struct CVaCursor {
    list : CVaList const?
    at : int
}

//! `va_start`: a cursor at the first trailing argument of `va`, the list the prologue bound.
def va_begin(va : CVaList) : CVaCursor => CVaCursor(list = unsafe(addr(va)), at = 0)

// the arms of `CVal` by variant index, as the pops name them
let private ARM_NAMES = fixed_array("an integer", "a double", "a pointer")

let private ARM_I = 0

let private ARM_D = 1

let private ARM_P = 2

def private va_take(var v : CVaCursor; arm : int) : CVal {
    if (v.list == null) {
        panic("va_arg reads {ARM_NAMES[arm]} from a va_list no va_start began")
    }
    let count = length(deref(v.list))
    if (v.at >= count) {
        panic("va_arg reads {ARM_NAMES[arm]} at trailing argument {v.at}, past the {count} passed")
    }
    let c = deref(v.list)[v.at]
    let found = variant_index(c)
    let zero_pointer = arm == ARM_P && c is i && c as i == 0l
    if (found != arm && !(arm == ARM_I && found == ARM_P) && !zero_pointer) {
        panic("va_arg reads {ARM_NAMES[arm]} where trailing argument {v.at} is {ARM_NAMES[found]}")
    }
    v.at++
    return c
}

//! `va_arg` of an integer type: the `int64` the argument was promoted to, or a pointer's bits.
def va_i(var v : CVaCursor) : int64 {
    let c = va_take(v, ARM_I)
    return c is p ? int64(intptr(c as p)) : c as i
}

//! `va_arg` of `double` (and of `float`, which no argument arrives as).
def va_d(var v : CVaCursor) : double => va_take(v, ARM_D) as d

//! `va_arg` of a pointer type, a function pointer included; an integer zero reads as null.
def va_p(var v : CVaCursor) : void? {
    let c = va_take(v, ARM_P)
    return c is i ? null : c as p
}

//! The arguments from the cursor on, as the list a `CVaList` callee takes (`c_vprintf`): the
//! forwarding of a `va_list`.
def va_rest(v : CVaCursor) : CVaList {
    if (v.list == null) {
        var none : CVaList
        return <- none
    }
    return <- subarray(deref(v.list), range(v.at, length(deref(v.list))))
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

def private is_va_args(t : TypeDeclPtr) : bool =>
    t != null && t.baseType == Type.tStructure && t.structType != null && t.structType.name == "va_args"

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
