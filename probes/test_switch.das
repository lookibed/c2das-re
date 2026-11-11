options gen2
require dastest/testing_boost public
require _daslang_child

var calls : array<string>

struct Cell {
    a : int
    b : int
}

def a { calls |> push("a") }
def b { calls |> push("b") }
def c { calls |> push("c") }
def d { calls |> push("d") }

def flag_switch(x : int) {
    while (true) {
        var flag = false
        let cond = x
        flag ||= cond == 1
        if (flag) {
            a()
            break
        }
        flag ||= cond == 5
        if (flag) {
            b()
        }
        flag ||= cond == 9
        if (flag) {
            c()
            break
        }
        flag ||= !(cond == 1 || cond == 5 || cond == 9)
        if (flag) {
            d()
        }
        break
    }
}

[test]
def test_switch(t : T?) {
    t |> run("matched-flag loop: tail break, fallthrough, default") @(t : T?) {
        calls |> clear()
        flag_switch(1)
        t |> equal("{calls}", "[ a]")
        calls |> clear()
        flag_switch(5)
        t |> equal("{calls}", "[ b, c]")
        calls |> clear()
        flag_switch(9)
        t |> equal("{calls}", "[ c]")
        calls |> clear()
        flag_switch(7)
        t |> equal("{calls}", "[ d]")
    }
    t |> run("C continue inside a switch reaches the enclosing loop through the cont epilogue") @(t : T?) {
        var seen : array<int>
        for (i in range(4)) {
            var cont = false
            while (true) {
                var flag = false
                let cond = i
                flag ||= cond == 1
                if (flag) {
                    cont = true
                    break
                }
                flag ||= !(cond == 1)
                if (flag) {
                    seen |> push(i)
                }
                break
            }
            if (cont) {
                continue
            }
            seen |> push(100 + i)
        }
        t |> equal("{seen}", "[ 0, 100, 2, 102, 3, 103]")
    }
    t |> run("an arm block's `default \{` is a syntax error and `switch` no module name; `case (_) \{` is an expression, `_` a variable (F105)") @(t : T?) {
        let arm_default = daslang_child("switch_default_arm", "options gen2\ndef f(a : int) \{\n    g(a) \{\n        default \{\n        \}\n    \}\n\}\n", true)
        child_rejects(t, "switch_default_arm", arm_default, "30151")
        let module_name = daslang_child("switch_module", "options gen2\nmodule switch public\n", true)
        child_rejects(t, "switch_module", module_name, "invalid module name 'switch'")
        // with no macro to take them, the arms reach inference as expressions, `_` a variable
        let arms = daslang_child("switch_arms", "options gen2\ndef f(a : int) \{\n    g(a) \{\n        case (1, _) \{\n        \}\n    \}\n\}\n", true)
        child_rejects(t, "switch_arms", arms, "can't locate variable '_'")
    }
    t |> run("a local declared bare before an if chain is zero and one variable for every branch; a fixed array and a struct take their literals by assignment") @(t : T?) {
        var seen : array<int>
        for (k in range(3)) {
            let cond = k
            var v : int
            var row : int[3]
            var cell : Cell
            t |> equal(v, 0)
            if (cond == 0) {
                v = 1
                row = fixed_array(1, 2, 3)
                cell = Cell(a = 4, b = 5)
                seen |> push(v + row[2] + cell.b)
            } elif (cond == 1) {
                v = 7
                seen |> push(v + row[0] + cell.a)
            } else {
                row = fixed_array(10, 20, 30)
                seen |> push(row[1])
            }
        }
        t |> equal("{seen}", "[ 9, 7, 20]")
    }
}
