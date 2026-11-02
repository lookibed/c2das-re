options gen2

module c_volatile public

require crt public
require daslib/ast
require daslib/ast_boost
require daslib/macro_boost
require daslib/templates_boost

//! C's volatile access: `c_volatile_load(x)` reads object `x` and `c_volatile_store(x, v)` writes
//! it, each once per call, through the `crt` forwarders that access it through a `volatile`
//! pointer, so neither the JIT nor the AOT host's clang++ folds a read or drops a write. The object
//! comes by reference, so a converted module spells the access with no `addr`. One overload per C
//! scalar width, `bool` (C's `_Bool`) through its byte, and a pointer or function value through
//! its eight bytes.

def c_volatile_read(x : int8 const&) : int8 => unsafe(crt::c_volatile_load_i8(unsafe(addr(x))))
def c_volatile_read(x : uint8 const&) : uint8 => unsafe(crt::c_volatile_load_u8(unsafe(addr(x))))
def c_volatile_read(x : int16 const&) : int16 => unsafe(crt::c_volatile_load_i16(unsafe(addr(x))))
def c_volatile_read(x : uint16 const&) : uint16 => unsafe(crt::c_volatile_load_u16(unsafe(addr(x))))
def c_volatile_read(x : int const&) : int => unsafe(crt::c_volatile_load_i32(unsafe(addr(x))))
def c_volatile_read(x : uint const&) : uint => unsafe(crt::c_volatile_load_u32(unsafe(addr(x))))
def c_volatile_read(x : int64 const&) : int64 => unsafe(crt::c_volatile_load_i64(unsafe(addr(x))))
def c_volatile_read(x : uint64 const&) : uint64 => unsafe(crt::c_volatile_load_u64(unsafe(addr(x))))
def c_volatile_read(x : float const&) : float => unsafe(crt::c_volatile_load_f32(unsafe(addr(x))))
def c_volatile_read(x : double const&) : double => unsafe(crt::c_volatile_load_f64(unsafe(addr(x))))

def c_volatile_read(x : bool const&) : bool {
    unsafe {
        return crt::c_volatile_load_u8(addr<uint8 const?>(x)) != 0u8
    }
}

//! A pointer or a function value read once through its bits; the type rides through the reinterpret.
def c_volatile_read(x : auto(TT) const&) : TT -const -& {
    static_assert(typeinfo sizeof(type<TT>) == 8, "c_volatile_read: a scalar, a pointer or a function value")
    // the bits land in a local first: the interpreter refuses a reinterpret of the extern call's
    // result itself ("typed eval on wrong extern return kind")
    unsafe {
        let bits = crt::c_volatile_load_u64(addr<uint64 const?>(x))
        return reinterpret<TT -const -&>(bits)
    }
}

// the forwarder of each scalar type a load reaches directly
let private LOAD_FORWARDERS <- {
    Type.tInt8 => "c_volatile_load_i8", Type.tUInt8 => "c_volatile_load_u8",
    Type.tInt16 => "c_volatile_load_i16", Type.tUInt16 => "c_volatile_load_u16",
    Type.tInt => "c_volatile_load_i32", Type.tUInt => "c_volatile_load_u32",
    Type.tInt64 => "c_volatile_load_i64", Type.tUInt64 => "c_volatile_load_u64",
    Type.tFloat => "c_volatile_load_f32", Type.tDouble => "c_volatile_load_f64"
}

//! `c_volatile_load(x)`: one read of object `x`. A number expands in place to its `crt` forwarder
//! over `addr(x)`, so the interpreter makes one extern call where a function around it would add a
//! das call; `bool`, a pointer, a function value and a by-value parameter go through
//! `c_volatile_read`.
[call_macro(name = "c_volatile_load")]
class CVolatileLoadMacro : AstCallMacro {
    def override visit(prog : ProgramPtr; mod : Module?; var expr : ExprCallMacro?) : ExpressionPtr {
        macro_verify(length(expr.arguments) == 1, prog, expr.at, "c_volatile_load takes one object")
        var arg = expr.arguments[0]
        if (arg._type == null) {
            return <- default<ExpressionPtr>
        }
        var object = arg
        if (object is ExprRef2Value) {
            object = (object as ExprRef2Value).subexpr
        }
        let forwarder = LOAD_FORWARDERS?[arg._type.baseType] ?? ""
        // a by-value parameter is a reference the optimizer may replace with a caller's constant,
        // which has no address: its read goes through the fallback, whose `const&` binds anything
        let parameter = object is ExprVar && (object as ExprVar).varFlags.argument
        if (empty(forwarder) || !object._type.isRef || parameter) {
            // the module's own `c_volatile_read` by its qualified name, so a program's function of
            // that name cannot take the read; the error of a wrong argument names the call site
            var fallback <- qmacro(c_volatile::c_volatile_read($e(arg)))
            fallback.at = expr.at
            return <- fallback
        }
        // the object's address and the forwarder are the expansion's own, safe as the read is
        var ptr = new ExprRef2Ptr(at = expr.at, subexpr = clone_expression(object))
        ptr.genFlags.alwaysSafe = true
        var call = new ExprCall(at = expr.at, name := "crt::{forwarder}")
        call.genFlags.alwaysSafe = true
        call.arguments |> emplace(ptr)
        return <- call
    }
}

def c_volatile_store(var x : int8&; v : int8) => unsafe(crt::c_volatile_store_i8(unsafe(addr(x)), v))
def c_volatile_store(var x : uint8&; v : uint8) => unsafe(crt::c_volatile_store_u8(unsafe(addr(x)), v))
def c_volatile_store(var x : int16&; v : int16) => unsafe(crt::c_volatile_store_i16(unsafe(addr(x)), v))
def c_volatile_store(var x : uint16&; v : uint16) => unsafe(crt::c_volatile_store_u16(unsafe(addr(x)), v))
def c_volatile_store(var x : int&; v : int) => unsafe(crt::c_volatile_store_i32(unsafe(addr(x)), v))
def c_volatile_store(var x : uint&; v : uint) => unsafe(crt::c_volatile_store_u32(unsafe(addr(x)), v))
def c_volatile_store(var x : int64&; v : int64) => unsafe(crt::c_volatile_store_i64(unsafe(addr(x)), v))
def c_volatile_store(var x : uint64&; v : uint64) => unsafe(crt::c_volatile_store_u64(unsafe(addr(x)), v))
def c_volatile_store(var x : float&; v : float) => unsafe(crt::c_volatile_store_f32(unsafe(addr(x)), v))
def c_volatile_store(var x : double&; v : double) => unsafe(crt::c_volatile_store_f64(unsafe(addr(x)), v))

def c_volatile_store(var x : bool&; v : bool) {
    unsafe {
        crt::c_volatile_store_u8(addr<uint8?>(x), v ? 1u8 : 0u8)
    }
}

//! A pointer or a function value written once through its bits.
def c_volatile_store(var x : auto(TT)&; v : TT) {
    static_assert(typeinfo sizeof(type<TT>) == 8, "c_volatile_store: a scalar, a pointer or a function value")
    unsafe {
        crt::c_volatile_store_u64(addr<uint64?>(x), reinterpret<uint64>(v))
    }
}
