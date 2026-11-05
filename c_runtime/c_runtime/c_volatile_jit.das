options gen2

module c_volatile_jit shared private

require llvm/daslib/llvm_boost
require llvm/daslib/llvm_jit_code
require daslib/ast_boost

//! The JIT half of `c_volatile`: the `[llvm_code]` generators that emit the body of each
//! `c_volatile::volatile_load_*` and `volatile_store_*` as one LLVM `load volatile` or `store
//! volatile` through the pointer argument, which the JIT then inlines into its caller. The das
//! bodies (the `crt` forwarders) stay the interpreter's and the AOT host's. Registered through
//! the `llvm_code_generator` module group (`c_runtime/.das_module`).

// `(p : T const?) : T`: a volatile load of `T` through `p`
def private load_gen(var gc : LlvmCodeCtx) : bool {
    if (length(gc.fn.arguments) != 1 || !(gc.fn.arguments[0]._type.isPointer || gc.fn.arguments[0]._type.isRef)) {
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

// `(p : T?; v : T)`: a volatile store of `v` through `p`
def private store_gen(var gc : LlvmCodeCtx) : bool {
    if (length(gc.fn.arguments) != 2 || !(gc.fn.arguments[0]._type.isPointer || gc.fn.arguments[0]._type.isRef) || !gc.fn.result.isVoid) {
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
def public register_llvm_code_generators {
    register_llvm_code_generator("c_volatile::load", @@load_gen)
    register_llvm_code_generator("c_volatile::store", @@store_gen)
}
