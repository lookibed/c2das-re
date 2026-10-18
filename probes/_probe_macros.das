options gen2

module _probe_macros public

require daslib/ast
require daslib/ast_boost
require daslib/templates_boost

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

[call_macro(name = "vsum")]
class VSumMacro : AstCallMacro {
    def override visit(prog : ProgramPtr; mod : Module?; var expr : ExprCallMacro?) : ExpressionPtr {
        var tail = new ExprMakeTuple(at = expr.at)
        for (i in range(1, length(expr.arguments))) {
            tail.values |> push(clone_expression(expr.arguments[i]))
        }
        var tailExpr : ExpressionPtr = tail
        return qmacro(vsum_impl($e(expr.arguments[0]), $e(tailExpr)))
    }
}

// `[probe_reshape(storage = "uint")]`: erases field `gone`, renames field `keep` to `_store` of
// the named storage type, and adds the property pair `x` over `_store`
[structure_macro(name = "probe_reshape")]
class ProbeReshape : AstStructureAnnotation {
    def override apply(var st : StructurePtr; var group : ModuleGroup; var args : AnnotationArgumentList; var errors : das_string) : bool {
        let storage = find_arg(args, "storage") ?as tString ?? ""
        if (storage != "uint") {
            errors := "probe_reshape: storage `{storage}`"
            return false
        }
        for (idx in range(length(st.fields))) {
            if (st.fields[idx].name == "gone") {
                st.fields |> erase(idx)
                break
            }
        }
        for (fld in st.fields) {
            if (fld.name == "keep") {
                fld.name := "_store"
                fld._type = new TypeDecl(baseType = Type.tUInt, at = fld.at)
            }
        }
        var getter <- qmacro_function(".`x") $(s : $t(st)) : uint {
            return s._store
        }
        var setter <- qmacro_function(".`x`clone") $(var s : $t(st); v : uint) : void {
            s._store = v
        }
        return compiling_module() |> add_function(getter) && compiling_module() |> add_function(setter)
    }
}
