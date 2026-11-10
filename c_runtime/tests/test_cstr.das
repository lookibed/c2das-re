options gen2
require dastest/testing_boost public
require c_runtime/cstr
require strings
require daslib/fio
require daslib/ast
require daslib/ast_boost
require ../../probes/_daslang_child.das

// a module global and a function taking literals through the macro, no `unsafe` written
let CSTR_SOURCE = "options gen2\nrequire c_runtime/cstr\nvar g : uint8? = cstr(\"ab\\0c\")\n[export]\ndef take : uint8? => cstr(\"xyz\")\n"

class private CallCount : AstVisitor {
    calls : int
    def override preVisitExprCall(expr : ExprCall?) {
        if (expr.func != null && starts_with(string(expr.func.name), "cstr")) {
            calls++
        }
    }
}

var private literal : uint8? = cstr("glob\x41l")

[test]
def test_cstr(t : T?) {
    t |> run("a literal is its NUL-terminated bytes, in a function and in a global initializer, with no unsafe written") @(t : T?) {
        let p = cstr("hi\n")
        unsafe {
            t |> equal(int(p[0]), 'h')
            t |> equal(int(p[2]), '\n')
            t |> equal(int(p[3]), 0)
            t |> equal(int(literal[4]), 'A')
            t |> equal(int(literal[6]), 0)
        }
    }
    t |> run("the literal expands in place to the reinterpret, no call left") @(t : T?) {
        var dir_error : string
        let dir = create_temp_directory("c2das_cstr", dir_error)
        t |> equal(dir_error, "")
        let path = path_join(dir, "literals.das")
        fwrite(path, CSTR_SOURCE)
        var inscope access <- make_file_access("")
        using() $(var mg : ModuleGroup) {
            using() $(var cop : CodeOfPolicies) {
                compile_file(path, access, unsafe(addr(mg)), cop) $(ok, program, output) {
                    t |> success(ok, string(output))
                    var counter = new CallCount()
                    make_visitor(*counter) $(adapter) {
                        visit(program, adapter)
                    }
                    t |> equal(counter.calls, 0)
                    unsafe {
                        delete counter
                    }
                }
            }
        }
        remove(path)
        rmdir(dir)
    }
    t |> run("a call whose argument is no string literal reaches a program's own cstr") @(t : T?) {
        let r = runtime_child("cstr_own", "options gen2\nrequire c_runtime/cstr\ndef cstr(a : int) : int => a + 1\n[export]\ndef main \{\n    let p = cstr(\"q\")\n    unsafe \{\n        print(\"\{cstr(4)\} \{int(p[0])\}\\n\")\n    \}\n\}\n", false)
        t |> equal(r.rc, 0, r.out)
        t |> equal(r.out |> find("5 113") >= 0, true, r.out)
    }
}
