options gen2

module c_volatile public

require crt public
require daslib/ast
require daslib/ast_boost
require daslib/macro_boost
require daslib/templates_boost
require daslib/tune

//! C's volatile access: `c_volatile_load(x)` reads object `x` and `c_volatile_store(x, v)` writes
//! it, each once per call, so no tier folds a read or drops a write: the interpreter and the AOT
//! host through the `crt` forwarders, which access it through a `volatile` pointer, the JIT through
//! the `[llvm_code]` bodies of `c_volatile_jit.das`, one inlined `load volatile` or `store volatile`
//! each (c_runtime/ARCHITECTURE.md, the c_volatile.das entry). The object
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
    unsafe {
        return reinterpret<TT -const -&>(crt::c_volatile_load_u64(addr<uint64 const?>(x)))
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
//! `c_volatile_read`. Under the JIT every load goes through `c_volatile_load_jit`.
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
        if (prog.policies.jit_enabled) {
            var generated <- qmacro(c_volatile::c_volatile_load_jit($e(arg)))
            generated.at = expr.at
            return <- generated
        }
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

//! The JIT's load: a generic, so each instance lands in the das module of its caller and the
//! JIT's per-module partitions (`--jit-split-modules`, the cached DLL's default) still inline the
//! one `load volatile` its `[llvm_code]` generator emits; the body is the read on every other path.
[llvm_code(name = "c_volatile::load", version = 1)]
def c_volatile_load_jit(x : auto(TT) const&) : TT -const -& => c_volatile_read(x)

//! `bool` written as its byte: the JIT rejects a reinterpret of a `bool` to `uint8` (an `i1` to
//! `i8` bitcast), so it stays outside the generic.
def c_volatile_store(var x : bool&; v : bool) {
    unsafe {
        crt::c_volatile_store_u8(addr<uint8?>(x), v ? 1u8 : 0u8)
    }
}

//! `c_volatile_store(x, v)`: one write of object `x`, its bits through the unsigned forwarder of
//! its size (a pointer or a function value as its eight bytes). A generic for
//! the reason `c_volatile_load_jit` is one: under the JIT its `[llvm_code]` generator emits one
//! `store volatile` in the caller's module.
[llvm_code(name = "c_volatile::store", version = 1)]
def c_volatile_store(var x : auto(TT)&; v : TT) {
    static_assert(typeinfo sizeof(type<TT>) == 1 || typeinfo sizeof(type<TT>) == 2 || typeinfo sizeof(type<TT>) == 4 || typeinfo sizeof(type<TT>) == 8,
        "c_volatile_store: a scalar, a pointer or a function value")
    unsafe {
        static_if (typeinfo sizeof(type<TT>) == 1) {
            crt::c_volatile_store_u8(addr<uint8?>(x), reinterpret<uint8>(v))
        } static_elif (typeinfo sizeof(type<TT>) == 2) {
            crt::c_volatile_store_u16(addr<uint16?>(x), reinterpret<uint16>(v))
        } static_elif (typeinfo sizeof(type<TT>) == 4) {
            crt::c_volatile_store_u32(addr<uint?>(x), reinterpret<uint>(v))
        } else {
            crt::c_volatile_store_u64(addr<uint64?>(x), reinterpret<uint64>(v))
        }
    }
}
