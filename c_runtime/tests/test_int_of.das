options gen2
require dastest/testing_boost public
require c_runtime/int_of
require strings
require daslib/strings_boost
require daslib/fio
require daslib/ast
require daslib/ast_boost
require ../../probes/_daslang_child.das

// two functions whose bodies differ only in `int_of(c)` against the ternary it stands for
let INT_OF_SOURCE = "options gen2\nrequire c_runtime/int_of\n\ndef by_macro(a, b : int) : int \{\n    var x = int_of(a < b)\n    x += int_of(a != 0 && b != 0) * 2\n    return x\n\}\n\ndef by_ternary(a, b : int) : int \{\n    var x = a < b ? 1 : 0\n    x += (a != 0 && b != 0 ? 1 : 0) * 2\n    return x\n\}\n"

// the node kinds of each function's body in visit order, and the calls the bodies make
class private Shapes : AstVisitor {
    current : string
    kinds : table<string; array<string>>
    calls : int
    def override preVisitFunction(fun : FunctionPtr) {
        current = string(fun.name)
    }
    def override preVisitExpression(expr : ExpressionPtr) {
        kinds[current] |> push(expr.__rtti)
    }
    def override preVisitExprCall(expr : ExprCall?) {
        calls++
    }
}

def private side(dy : int) : int => int_of(dy > 0)

def private is_zero(f : float) : int => int_of(f == 0.0f)

[test]
def test_int_of(t : T?) {
    t |> run("a truth reads as 1 or 0") @(t : T?) {
        t |> equal(side(3), 1)
        t |> equal(side(-3), 0)
        t |> equal(is_zero(0.0f), 1)
        t |> equal(is_zero(1.0f), 0)
        var x = 5
        x += int_of(x < 9) * 10
        t |> equal(x, 15)
    }
    t |> run("the call expands in place to the ternary: the same nodes in the same order, no call left") @(t : T?) {
        var dir_error : string
        let dir = create_temp_directory("c2das_int_of", dir_error)
        t |> equal(dir_error, "")
        let path = path_join(dir, "int_of.das")
        fwrite(path, INT_OF_SOURCE)
        var inscope access <- make_file_access("")
        using() $(var mg : ModuleGroup) {
            using() $(var cop : CodeOfPolicies) {
                cop.no_optimizations = true
                cop.export_all = true
                compile_file(path, access, unsafe(addr(mg)), cop) $(ok, program, output) {
                    t |> success(ok, string(output))
                    var shapes = new Shapes()
                    make_visitor(*shapes) $(adapter) {
                        visit(program, adapter)
                    }
                    let by_macro <- shapes.kinds?["by_macro"] ?? default<array<string>>
                    let by_ternary <- shapes.kinds?["by_ternary"] ?? default<array<string>>
                    t |> success(!empty(by_macro))
                    t |> equal(join(by_macro, " "), join(by_ternary, " "))
                    t |> equal(shapes.calls, 0)
                    unsafe {
                        delete shapes
                    }
                }
            }
        }
        remove(path)
        rmdir(dir)
    }
    t |> run("an argument that is no bool is a compile error naming its type") @(t : T?) {
        let r = runtime_child("int_of_int", "options gen2\nrequire c_runtime/int_of\ndef f(a : int) : int => int_of(a)\n", true)
        child_rejects(t, "int_of_int", r, "int_of takes a bool, not int")
    }
}
