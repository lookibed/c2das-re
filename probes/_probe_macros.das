options gen2

module _probe_macros public

require daslib/strings_boost
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

// `[probe_apply_types]`: adds `def apply_types_<Struct> : string` naming each field's base type
// and size as `apply` saw them, before inference, `name:base:size`, a fixed array's dimension
// as `:dim<N>`, `:alias` after a type `isAutoOrAlias` holds for, joined by spaces
[structure_macro(name = "probe_apply_types")]
class ProbeApplyTypes : AstStructureAnnotation {
    def override apply(var st : StructurePtr; var group : ModuleGroup; var args : AnnotationArgumentList; var errors : das_string) : bool {
        var seen : array<string>
        for (f in st.fields) {
            let unfolded = f._type.baseType == Type.tFixedArray && f._type.fixedDim <= 0
            let size = f._type.baseType == Type.alias || unfolded ? "-" : "{f._type.sizeOf}"
            let dim = f._type.baseType == Type.tFixedArray ? ":dim{f._type.fixedDim}" : ""
            seen |> push("{f.name}:{f._type.baseType}:{size}{dim}{f._type.isAutoOrAlias ? ":alias" : ""}")
        }
        let text = join(seen, " ")
        var fn <- qmacro_function("apply_types_{st.name}") $() : string {
            return $v(text)
        }
        return compiling_module() |> add_function(fn)
    }
}

// `[probe_count_annotations]`: adds `def annotations_<Struct> : int`, the length of the struct's
// annotation list as `apply` saw it
[structure_macro(name = "probe_count_annotations")]
class ProbeCountAnnotations : AstStructureAnnotation {
    def override apply(var st : StructurePtr; var group : ModuleGroup; var args : AnnotationArgumentList; var errors : das_string) : bool {
        let count = length(st.annotations)
        var fn <- qmacro_function("annotations_{st.name}") $() : int {
            return $v(count)
        }
        return compiling_module() |> add_function(fn)
    }
}
