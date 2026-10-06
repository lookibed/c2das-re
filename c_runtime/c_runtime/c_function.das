options gen2

module c_function public

require daslib/ast
require daslib/ast_boost
require daslib/templates_boost

//! `[c_function]`: the whole body of the function runs under one `unsafe`, so a converted C
//! body full of pointer arithmetic, `deref`, `reinterpret` and raw allocation carries no
//! per-operation wrap. The converter emits it only on functions whose body needs it.
[function_macro(name = "c_function")]
class CFunctionAnnotation : AstFunctionAnnotation {
    def override apply(var func : FunctionPtr; var group : ModuleGroup; var args : AnnotationArgumentList; var errors : das_string) : bool {
        func.body = qmacro_block() {
            unsafe {
                $e(func.body)
            }
        }
        return true
    }
}
