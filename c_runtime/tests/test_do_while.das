options gen2
require dastest/testing_boost public
require c_runtime/do_while
require strings
require daslib/strings_boost
require daslib/fio
require daslib/ast
require daslib/ast_boost
require daslib/match
require ../../probes/_daslang_child.das

// pairs of functions whose bodies differ only in `do_while` against the loop it stands for: the
// bottom test, the first-pass flag for a body with a `continue` of its own, and the bottom test
// again where the only `continue` is an inner loop's
let DO_WHILE_SOURCE = "options gen2\nrequire c_runtime/do_while\n\ndef bottom_macro(n : int) : int \{\n    var i = 0\n    do_while (i < n) \{\n        i++\n    \}\n    return i\n\}\n\ndef bottom_spelled(n : int) : int \{\n    var i = 0\n    while (true) \{\n        i++\n        if (!(i < n)) \{\n            break\n        \}\n    \}\n    return i\n\}\n\ndef flag_macro(n : int) : int \{\n    var i = 0\n    do_while (i < n) \{\n        i++\n        if (i == 2) \{\n            continue\n        \}\n        i++\n    \}\n    return i\n\}\n\ndef flag_spelled(n : int) : int \{\n    var i = 0\n    \{\n        var first = true\n        while (first || i < n) \{\n            first = false\n            i++\n            if (i == 2) \{\n                continue\n            \}\n            i++\n        \}\n    \}\n    return i\n\}\n\ndef inner_macro(n : int) : int \{\n    var i = 0\n    do_while (i < n) \{\n        for (k in range(3)) \{\n            if (k == 1) \{\n                continue\n            \}\n            i++\n        \}\n    \}\n    return i\n\}\n\ndef inner_spelled(n : int) : int \{\n    var i = 0\n    while (true) \{\n        for (k in range(3)) \{\n            if (k == 1) \{\n                continue\n            \}\n            i++\n        \}\n        if (!(i < n)) \{\n            break\n        \}\n    \}\n    return i\n\}\n"

// the node kinds of each function's body in visit order, and the call macros left in them
class private Shapes : AstVisitor {
    current : string
    kinds : table<string; array<string>>
    macros : int
    def override preVisitFunction(fun : FunctionPtr) {
        current = string(fun.name)
    }
    def override preVisitExpression(expr : ExpressionPtr) {
        kinds[current] |> push(expr.__rtti)
    }
    def override preVisitExprCallMacro(expr : ExprCallMacro?) {
        macros++
    }
}

// C's `do { i++; if (i == stop) break; if (i == bail) return -1; acc += i; } while (i < n);`
def private sum_to(n, stop, bail : int) : int {
    var i = 0
    var acc = 0
    do_while(i < n) {
        i++
        if (i == stop) {
            break
        }
        if (i == bail) {
            return -1
        }
        acc += i
    }
    return acc
}

// a `continue` of the do_while's own loop reaches the test; an inner do_while's reaches its own
def private skip_even(n : int) : int {
    var i = 0
    var acc = 0
    do_while(i < n) {
        i++
        if ((i & 1) == 0) {
            continue
        }
        var j = 0
        do_while(j < 2) {
            j++
            if (j == 1) {
                continue
            }
            acc += 100
        }
        acc += i
    }
    return acc
}

// a condition with an effect runs once per pass, after the body
def private counted(n : int) : int {
    var k = 0
    var passes = 0
    do_while(k++ < n) {
        passes++
    }
    return passes * 100 + k
}

// a match arm's `continue` is the do_while's, as the converter's switch arms are
def private arm_continue(n : int) : int {
    var i = 0
    var acc = 0
    do_while(i < n) {
        i++
        match (i % 3) {
            0 => $ {
                continue
            }
            _ => $ {
                acc += i
            }
        }
        acc += 1000
    }
    return acc
}

// a goto out of the body and a label inside it
def private jumps(n : int) : int {
    var i = 0
    var acc = 0
    do_while(i < n) {
        i++
        if (i == 3) {
            goto label 1
        }
        acc += i
    }
    return acc
    label 1:
    return -acc
}

[test]
def test_do_while(t : T?) {
    t |> run("the body runs once before the first test; break leaves the loop, return the function") @(t : T?) {
        t |> equal(sum_to(3, 100, 100), 6)
        t |> equal(sum_to(0, 100, 100), 1)
        t |> equal(sum_to(10, 7, 100), 21)
        t |> equal(sum_to(10, 100, 5), -1)
        t |> equal(counted(3), 404)
        t |> equal(counted(0), 101)
    }
    t |> run("a continue reaches the test, of its own loop only; a match arm's is the loop's") @(t : T?) {
        t |> equal(skip_even(5), 309)
        t |> equal(skip_even(0), 101)
        // the last pass's `continue` meets a false test: a skipped test would run on
        t |> equal(skip_even(4), 204)
        t |> equal(arm_continue(3), 2003)
        t |> equal(arm_continue(5), 4012)
    }
    t |> run("a goto leaves the body") @(t : T?) {
        t |> equal(jumps(2), 3)
        t |> equal(jumps(5), -3)
    }
    t |> run("the call expands in place to the spelled loop: the same nodes in the same order, no call macro left") @(t : T?) {
        var dir_error : string
        let dir = create_temp_directory("c2das_do_while", dir_error)
        t |> equal(dir_error, "")
        let path = path_join(dir, "do_while.das")
        fwrite(path, DO_WHILE_SOURCE)
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
                    for (form in ["bottom", "flag", "inner"]) {
                        var inscope by_macro <- shapes.kinds?["{form}_macro"] ?? default<array<string>>
                        var inscope spelled <- shapes.kinds?["{form}_spelled"] ?? default<array<string>>
                        t |> success(!empty(by_macro), form)
                        t |> equal(join(by_macro, " "), join(spelled, " "), form)
                    }
                    t |> equal(shapes.macros, 0)
                    unsafe {
                        delete shapes
                    }
                }
            }
        }
        remove(path)
        rmdir(dir)
    }
    t |> run("a condition that is no bool and an argument that is no block are compile errors") @(t : T?) {
        let int_cond = runtime_child("do_while_int", "options gen2\nrequire c_runtime/do_while\ndef f(a : int) \{\n    var i = a\n    do_while (i) \{\n        i--\n    \}\n\}\n", true)
        t |> success(int_cond.rc != 0, int_cond.out)
        let no_block = runtime_child("do_while_no_block", "options gen2\nrequire c_runtime/do_while\ndef f(a : int) \{\n    do_while (a < 3, a)\n\}\n", true)
        child_rejects(t, "do_while_no_block", no_block, "do_while takes a condition and a block")
    }
}
