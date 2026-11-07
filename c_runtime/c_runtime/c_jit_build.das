options gen2

module c_jit_build shared

require daslib/ast_boost

//! The JIT build of a converted program: declares the program option `jit_split_modules`, dasLLVM's
//! script pin of its partitioning (`docs/probe-findings.md` F92), so an entry module requiring this
//! piece may write `options jit_split_modules = 0` and compile under every tier. dasLLVM declares
//! the option only in a program that requires `llvm/llvm_jit`, which would load the JIT compiler
//! into every tier's startup, and daslang refuses an undeclared option; the JIT reads the pin by
//! name from the entry module's options, the interpreter, the AOT host and the exe build ignore it.

[_macro, macro_function]
def private declare_jit_options {
    if (is_compiling_macros_in_module("c_jit_build")) {
        this_module() |> add_module_option("jit_split_modules", Type.tInt)
    }
}
