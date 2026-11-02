options gen2
require dastest/testing_boost public
require c_runtime/enum_from_int
require strings
require daslib/fio
require daslib/ast
require daslib/ast_boost
require ../../probes/_daslang_child.das

enum mobjtype_t {
    MT_PLAYER
    MT_SHOTGUN = 5
    NUMMOBJTYPES
}

// a conversion whose operand is no constant, so the compiled program keeps it
let CONVERTING_SOURCE = "options gen2\nrequire c_runtime/enum_from_int\nenum E \{\n    A\n    B = 5\n\}\n[export]\ndef conv(k : int) : E => enum_from_int(type<E>, k)\n"

class private CallCount : AstVisitor {
    calls : int
    def override preVisitExprCall(expr : ExprCall?) {
        // a generic's instance is named `enum_from_int`enum_from_int`<hash>`
        if (expr.func != null && starts_with(string(expr.func.name), "enum_from_int")) {
            calls++
        }
    }
}

[test]
def test_enum_from_int(t : T?) {
    t |> run("an in-range int becomes the enumerator") @(t : T?) {
        var mtype = enum_from_int(type<mobjtype_t>, 5)
        t |> equal(mtype == mobjtype_t.MT_SHOTGUN, true)
        mtype = enum_from_int(type<mobjtype_t>, int(mtype) + 1)
        t |> equal(mtype == mobjtype_t.NUMMOBJTYPES, true)
    }
    t |> run("an out-of-range int survives by value and prints as enum N") @(t : T?) {
        let stray = enum_from_int(type<mobjtype_t>, 99)
        t |> equal(int(stray), 99)
        t |> equal("{stray}", "enum 99")
        t |> equal(stray == enum_from_int(type<mobjtype_t>, 99), true)
    }
    t |> run("the conversion expands in place to the reinterpret, no call left") @(t : T?) {
        var dir_error : string
        let dir = create_temp_directory("c2das_enum_from_int", dir_error)
        t |> equal(dir_error, "")
        let path = path_join(dir, "converting.das")
        fwrite(path, CONVERTING_SOURCE)
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
    t |> run("a call without a type witness reaches a program's own enum_from_int") @(t : T?) {
        let r = runtime_child("enum_from_int_own", "options gen2\nrequire c_runtime/enum_from_int\nenum E \{\n    A\n    B = 5\n\}\ndef enum_from_int(a : int; b : int) : int => a + b\n[export]\ndef main \{\n    print(\"\{enum_from_int(2, 3)\} \{enum_from_int(type<E>, 5)\}\\n\")\n\}\n", false)
        t |> equal(r.rc, 0, r.out)
        t |> equal(r.out |> find("5 B") >= 0, true, r.out)
    }
    t |> run("a witness that is no enum, or a value that is no int, fails at the call site") @(t : T?) {
        let r = runtime_child("enum_from_int_witness", "options gen2\nrequire c_runtime/enum_from_int\n[export]\ndef main \{\n    let x = enum_from_int(type<int>, 3)\n\}\n", true)
        t |> equal(r.rc != 0, true, r.out)
        t |> equal(r.out |> find("the witness is an enum type") >= 0, true, r.out)
        let u = runtime_child("enum_from_int_value", "options gen2\nrequire c_runtime/enum_from_int\nenum E \{\n    A\n\}\n[export]\ndef main \{\n    let x = enum_from_int(type<E>, 3u)\n\}\n", true)
        t |> equal(u.rc != 0, true, u.out)
        t |> equal(u.out |> find("the value is an int") >= 0, true, u.out)
    }
}
