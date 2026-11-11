options gen2
require dastest/testing_boost public
require c_runtime/c_switch
require c_runtime/c_do_while
require strings
require daslib/strings_boost
require daslib/fio
require daslib/ast
require daslib/ast_boost
require ../../probes/_daslang_child.das

// pairs of functions whose bodies differ only in `c_switch` against the shape it stands for: the
// if-chain, the matched-flag loop with an arm falling into the next and a `default` in the middle, and the loop
// with an own `continue` over a value read through a `let`
let SWITCH_SOURCE = "options gen2\nrequire c_runtime/c_switch\n\ndef chain_macro(x : int) : int \{\n    var r = 0\n    c_switch (x) \{\n        case (1) \{\n            r = 10\n            break\n        \}\n        case (2, 3) \{\n            r = 20\n            break\n        \}\n        case (_) \{\n            r = -1\n        \}\n    \}\n    return r\n\}\n\ndef chain_spelled(x : int) : int \{\n    var r = 0\n    if (x == 1) \{\n        r = 10\n    \} elif (x == 2 || x == 3) \{\n        r = 20\n    \} else \{\n        r = -1\n    \}\n    return r\n\}\n\ndef flag_macro(x : int) : int \{\n    var r = 0\n    c_switch (x) \{\n        case (1) \{\n            r += 1\n        \}\n        case (2) \{\n            r += 2\n            break\n        \}\n        case (_) \{\n            r += 50\n            break\n        \}\n        case (3) \{\n            r += 300\n        \}\n    \}\n    return r\n\}\n\ndef flag_spelled(x : int) : int \{\n    var r = 0\n    while (true) \{\n        var flag = false\n        flag ||= x == 1\n        if (flag) \{\n            r += 1\n        \}\n        flag ||= x == 2\n        if (flag) \{\n            r += 2\n            break\n        \}\n        if (!(x == 1 || x == 2 || x == 3)) \{\n            r += 50\n            break\n        \}\n        if (x == 3) \{\n            r += 300\n        \}\n        break\n    \}\n    return r\n\}\n\ndef cont_macro(n : int) : int \{\n    var seen = 0\n    for (i in range(n)) \{\n        c_switch (i % 3) \{\n            case (1) \{\n                continue\n            \}\n            case (2) \{\n                seen += 100\n            \}\n            case (_) \{\n                seen += 1\n            \}\n        \}\n        seen += 1000\n    \}\n    return seen\n\}\n\ndef cont_spelled(n : int) : int \{\n    var seen = 0\n    for (i in range(n)) \{\n        \{\n            let c = i % 3\n            var cont = false\n            while (true) \{\n                var flag = false\n                if (c == 1) \{\n                    cont = true\n                    break\n                \}\n                flag ||= c == 2\n                if (flag) \{\n                    seen += 100\n                \}\n                flag ||= !(c == 1 || c == 2)\n                if (flag) \{\n                    seen += 1\n                \}\n                break\n            \}\n            if (cont) \{\n                continue\n            \}\n        \}\n        seen += 1000\n    \}\n    return seen\n\}\n"

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

// C's `switch (x) { case 1: a; case 5: b; if (stop) break; c; break; default: d; case 9: n; }`
// with a mid-arm `break`: the arms run, one digit each (a 1, b 2, c 3, d 4, n 5)
def private trace(x : int; stop : bool) : int {
    var t = 0
    c_switch(x) {
        case(1) {
            t = t * 10 + 1
        }
        case(5) {
            t = t * 10 + 2
            if (stop) {
                break
            }
            t = t * 10 + 3
            break
        }
        case(_) {
            t = t * 10 + 4
        }
        case(9) {
            t = t * 10 + 5
        }
    }
    return t
}

// an empty arm falls into the next, a default in the middle here: C's `case 1: ; default: ...`
def private empty_first(x : int) : int {
    var r = 0
    c_switch(x) {
        case(1) {
        }
        case(_) {
            r = 9
            break
        }
        case(2) {
            r = 2
            break
        }
    }
    return r
}

// a value with an effect is read once, whichever arm runs
def private once(var k : int&; arms : int) : int {
    var r = 0
    c_switch(k++) {
        case(0) {
            r = 10
        }
        case(1) {
            r += arms
            break
        }
        case(_) {
            r = -1
        }
    }
    return r
}

// an inner switch's `continue` reaches the loop around both, through the outer one's loop; its
// `break` is its own
def private nested(n : int) : int {
    var acc = 0
    for (i in range(n)) {
        c_switch(i & 1) {
            case(0) {
                c_switch(i % 3) {
                    case(0) {
                        continue
                    }
                    case(1) {
                        acc += 10
                        break
                    }
                    case(_) {
                        acc += 20
                    }
                    case(5) {
                        acc++
                    }
                }
                acc += 100
            }
            case(_) {
                acc += 1000
            }
        }
        acc += 10000
    }
    return acc
}

// an arm's `continue` inside a c_do_while's body reaches its test; a loop in an arm keeps its own
// `break`; a `return` leaves the function
def private in_loops(n : int) : int {
    var i = 0
    var acc = 0
    c_do_while(i < n) {
        i++
        c_switch(i) {
            case(2) {
                continue
            }
            case(4) {
                for (k in range(10)) {
                    if (k == 3) {
                        break
                    }
                    acc += 100
                }
            }
            case(7) {
                return acc + i
            }
            case(_) {
                acc += i
            }
        }
        acc += 1000
    }
    return acc
}

// C's `switch (x) { default: r += 1; if (stop) break; r += 10; }`: a lone default in the flag loop
def private only_default(x : int; stop : bool) : int {
    var r = 0
    c_switch(x) {
        case(_) {
            r += 1
            if (stop) {
                break
            }
            r += 10
        }
    }
    return r
}

// a flag loop with an own `continue` whose arm holds a `for` and a `c_do_while`, each continuing
// itself: their `continue`s are no switch's
def private inner_loops(n : int) : int {
    var acc = 0
    for (i in range(n)) {
        c_switch(i % 3) {
            case(0) {
                for (k in range(4)) {
                    if (k == 1) {
                        continue
                    }
                    acc += 1
                }
                var j = 0
                c_do_while(j < 3) {
                    j++
                    if (j == 2) {
                        continue
                    }
                    acc += 10
                }
            }
            case(1) {
                if (i == 4) {
                    continue
                }
                acc += 100
                break
            }
            case(_) {
                acc += 1000
            }
        }
        acc += 10000
    }
    return acc
}

// the variable switched on, changed by the arm that matched, decides no later arm: x = 1 falls
// through the default and into `case (5)`
def private retarget(var x : int) : int {
    var r = 0
    c_switch(x) {
        case(1) {
            x = 5
            r += 1
        }
        case(_) {
            r += 10
        }
        case(5) {
            r += 100
            r += 1000
            break
        }
    }
    return r
}

// an if-chain switch whose arm continues the loop around it
def private chain_continue(n : int) : int {
    var acc = 0
    for (i in range(n)) {
        c_switch(i) {
            case(1) {
                continue
            }
            case(_) {
                acc += i
                break
            }
        }
        acc += 100
    }
    return acc
}

// a switch with no arms still reads its value once
def private empty_switch(var k : int&) {
    c_switch(k++) {
    }
}

[test]
def test_c_switch(t : T?) {
    t |> run("arms run in C's order: an arm with no break falls into the next, a default in the middle, a mid-arm break") @(t : T?) {
        t |> equal(trace(1, false), 123)
        t |> equal(trace(1, true), 12)
        t |> equal(trace(5, false), 23)
        t |> equal(trace(7, false), 45)
        t |> equal(trace(9, false), 5)
        t |> equal(empty_first(1), 9)
        t |> equal(empty_first(2), 2)
        t |> equal(empty_first(3), 9)
    }
    t |> run("a lone default in the flag loop, loops with their own continue in an arm, a value changed in its arm, an if-chain's continue (C's values)") @(t : T?) {
        t |> equal(only_default(3, false), 11)
        t |> equal(only_default(3, true), 1)
        t |> equal(inner_loops(6), 52346)
        t |> equal(retarget(1), 1111)
        t |> equal(retarget(5), 1100)
        t |> equal(chain_continue(5), 409)
    }
    t |> run("the value is read once") @(t : T?) {
        var k = 0
        t |> equal(once(k, 5), 15)
        t |> equal(k, 1)
        t |> equal(once(k, 5), 5)
        t |> equal(once(k, 5), -1)
        t |> equal(k, 3)
        empty_switch(k)
        t |> equal(k, 4)
    }
    t |> run("continue reaches the enclosing loop through nested switches and a c_do_while; break and return keep theirs") @(t : T?) {
        t |> equal(nested(7), 55231)
        t |> equal(in_loops(3), 2004)
        t |> equal(in_loops(5), 2308)
        t |> equal(in_loops(9), 2308)
    }
    t |> run("the call expands in place to the spelled shape: the same nodes in the same order, no call macro left") @(t : T?) {
        var dir_error : string
        let dir = create_temp_directory("c2das_switch", dir_error)
        t |> equal(dir_error, "")
        let path = path_join(dir, "c_switch.das")
        fwrite(path, SWITCH_SOURCE)
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
                    for (form in ["chain", "flag", "cont"]) {
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
    t |> run("a duplicate case value, a second default, a statement that is no arm and a case in a nested block (Duff's device) are compile errors") @(t : T?) {
        let duff = runtime_child("switch_duff", "options gen2\nrequire c_runtime/c_switch\ndef f(var a : int) \{\n    c_switch (a) \{\n        case (0) \{\n            if (a > 2) \{\n                case (1) \{\n                    a++\n                \}\n            \}\n        \}\n    \}\n\}\n", true)
        child_rejects(t, "switch_duff", duff, "a case inside a nested block of an arm (Duff's device)")
        for (name, body, needle in ["dup", "default2", "stray"], ["case (1) \{\n        \}\n        case (2, 1) \{\n        \}", "case (_) \{\n        \}\n        case (1, _) \{\n        \}", "case (1) \{\n        \}\n        a++"], ["duplicate case value 1", "duplicate case value _", "c_switch holds only arms"]) {
            let r = runtime_child("switch_{name}", "options gen2\nrequire c_runtime/c_switch\ndef f(var a : int) \{\n    c_switch (a) \{\n        {body}\n    \}\n\}\n", true)
            child_rejects(t, "switch_{name}", r, needle)
        }
    }
}
