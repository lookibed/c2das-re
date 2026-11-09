options gen2
require dastest/testing_boost public
require daslib/fio
require daslib/ast
require daslib/ast_boost

// what the compiled AST keeps of a module's text, which the readability metric counts over
let SOURCE = "options gen2\n\nenum E \{\n    A\n    B = 7\n\}\n\nvar arr = fixed_array(1, 2, 3, 4)\nvar gp = unsafe(unsafe(addr(arr[0])) + 3)\n\ndef f : int \{\n    unsafe \{\n        return int(E.B) + deref(gp)\n    \}\n\}\n\n[export]\ndef main \{\n    print(\"\{f()\}\\n\")\n\}\n"

class private Facts : AstVisitor {
    step_flagged : bool
    step_column : int
    addr_flagged : bool
    unsafe_blocks : int
    folded_enum : bool
    def override preVisitExprCall(expr : ExprCall?) {
        if (expr.func != null && expr.func.name == "i_das_ptr_add") {
            step_flagged = expr.genFlags.userSaidItsSafe
            step_column = int(expr.at.column)
        }
    }
    def override preVisitExprRef2Ptr(expr : ExprRef2Ptr?) {
        addr_flagged ||= expr.genFlags.userSaidItsSafe
    }
    def override preVisitExprUnsafe(expr : ExprUnsafe?) {
        unsafe_blocks++
    }
    def override preVisitExprConstInt(expr : ExprConstInt?) {
        folded_enum ||= expr.value == 7 && expr.flags.constexpression
    }
}

// a module whose one reinterpret is a c_runtime call macro's expansion: line 7 spells
// `enum_from_int` from column 22
let MACRO_SOURCE = "options gen2\nrequire c_runtime/enum_from_int\n\nenum E \{\n    A\n\}\ndef f(v : int) : E => enum_from_int(type<E>, v)\n"

class private MacroFacts : AstVisitor {
    casts : int
    generated : bool
    line : int
    column : int
    def override preVisitExprCast(expr : ExprCast?) {
        if (expr.castFlags.reinterpretCast) {
            casts++
            generated ||= expr.genFlags.generated
            line = int(expr.at.line)
            column = int(expr.at.column)
        }
    }
}

[test]
def test_ast_facts(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_ast_facts", dir_error)
    t |> equal(dir_error, "")
    let path = path_join(dir, "facts.das")
    fwrite(path, SOURCE)
    t |> run("an as-written compile keeps unsafe blocks, flags unsafe(addr(...)), loses the flag of unsafe(p + i) and folds int(E.X)") @(t : T?) {
        var inscope access <- make_file_access("")
        using() $(var mg : ModuleGroup) {
            using() $(var cop : CodeOfPolicies) {
                cop.no_fold_unsafe = true
                cop.no_optimizations = true
                compile_file(path, access, unsafe(addr(mg)), cop) $(ok, program, output) {
                    t |> success(ok, string(output))
                    var facts = new Facts()
                    make_visitor(*facts) $(adapter) {
                        visit(program, adapter)
                    }
                    t |> equal(facts.unsafe_blocks, 1)
                    t |> equal(facts.addr_flagged, true)
                    t |> equal(facts.step_flagged, false)
                    // the step sits at its left operand, `unsafe(addr(arr[0]))` of
                    // `var gp = unsafe(unsafe(addr(arr[0])) + 3)`, where daScript before abf1d40e35
                    // put it at the operator (37)
                    t |> equal(facts.step_column, 16)
                    t |> equal(facts.folded_enum, true)
                    unsafe {
                        delete facts
                    }
                }
            }
        }
    }
    t |> run("a call macro's expansion carries no generated flag: its reinterpret sits at the call, the text there the macro's name") @(t : T?) {
        let macro_path = path_join(dir, "macro_facts.das")
        fwrite(macro_path, MACRO_SOURCE)
        var inscope access <- make_file_access("")
        using() $(var mg : ModuleGroup) {
            using() $(var cop : CodeOfPolicies) {
                cop.no_fold_unsafe = true
                cop.no_optimizations = true
                cop.export_all = true
                compile_file(macro_path, access, unsafe(addr(mg)), cop) $(ok, program, output) {
                    t |> success(ok, string(output))
                    var facts = new MacroFacts()
                    make_visitor(*facts) $(adapter) {
                        visit(program, adapter)
                    }
                    t |> equal(facts.casts, 1)
                    t |> equal(facts.generated, false)
                    t |> equal(facts.line, 7)
                    t |> equal(facts.column, 22)
                    unsafe {
                        delete facts
                    }
                }
            }
        }
    }
    rmdir_rec(dir)
}
