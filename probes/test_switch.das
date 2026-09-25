options gen2
require dastest/testing_boost public

var calls : array<string>

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
}
