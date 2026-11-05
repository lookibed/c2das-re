options gen2

module c_volatile_jit shared

require llvm/daslib/llvm_boost
require llvm/daslib/llvm_jit_code
require daslib/ast_boost

//! The JIT half of `c_volatile`: the `[llvm_code]` generators that emit the body of
//! `c_volatile_load_jit` and `c_volatile_store` as one LLVM `load volatile` or `store volatile`
//! through the object argument, which the JIT then inlines into its caller. The das bodies (the
//! `crt` forwarders) stay the interpreter's and the AOT host's, and the JIT's for `bool` and a
//! function value. Registered through the `llvm_code_generator` module group (`c_runtime/.das_module`).

// the C scalar widths the generators access as their own LLVM type, beside a pointer; `bool` and
// a function value keep the das body
let private ACCESSED_AS_IS = fixed_array(Type.tInt8, Type.tUInt8, Type.tInt16, Type.tUInt16, Type.tInt, Type.tUInt, Type.tInt64, Type.tUInt64, Type.tFloat, Type.tDouble)

def private accessed_as_is(t : TypeDeclPtr) : bool => t.isPointer || ACCESSED_AS_IS |> has_value(t.baseType)

// whether `t` is the object a generator accesses: a reference or a pointer
def private is_object(t : TypeDeclPtr) : bool => t.isPointer || t.isRef

// `(x : T const&) : T`: a volatile load of `T` through `x`
def private load_gen(var gc : LlvmCodeCtx) : bool {
    if (length(gc.fn.arguments) != 1 || !is_object(gc.fn.arguments[0]._type) || !accessed_as_is(gc.fn.result)) {
        return false
    }
    var entry = LLVMAppendBasicBlockInContext(gc.jit.ctx, gc.impl, "entry")
    LLVMPositionBuilderAtEnd(gc.jit.builder, entry)
    var value = LLVMBuildLoad2(gc.jit.builder, LLVMGetReturnType(gc.impl_type), LLVMGetParam(gc.impl, 0u), "c_volatile.load")
    LLVMSetVolatile(value, 1)
    LLVMSetAlignment(value, uint(gc.fn.result.alignOf))
    LLVMBuildRet(gc.jit.builder, value)
    return true
}

// `(var x : T&; v : T)`: a volatile store of `v` through `x`
def private store_gen(var gc : LlvmCodeCtx) : bool {
    if (length(gc.fn.arguments) != 2 || !is_object(gc.fn.arguments[0]._type) || !accessed_as_is(gc.fn.arguments[1]._type) || !gc.fn.result.isVoid) {
        return false
    }
    var entry = LLVMAppendBasicBlockInContext(gc.jit.ctx, gc.impl, "entry")
    LLVMPositionBuilderAtEnd(gc.jit.builder, entry)
    var store = LLVMBuildStore(gc.jit.builder, LLVMGetParam(gc.impl, 1u), LLVMGetParam(gc.impl, 0u))
    LLVMSetVolatile(store, 1)
    LLVMSetAlignment(store, uint(gc.fn.arguments[1]._type.alignOf))
    LLVMBuildRetVoid(gc.jit.builder)
    return true
}

//! The `llvm_code_generator` group member: dasLLVM's `llvm_user_modules` calls it before the
//! first generator lookup.
[macro_function]
def register_llvm_code_generators {
    register_llvm_code_generator("c_volatile::load", @@load_gen)
    register_llvm_code_generator("c_volatile::store", @@store_gen)
}
