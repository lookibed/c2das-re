options gen2
require dastest/testing_boost public

[test]
def test_goto(t : T?) {
    t |> run("forward goto to a lexically enclosing label") @(t : T?) {
        var n = 0
        goto label 1
        n = 100
        label 1:
        n++
        t |> equal(n, 1)
    }
    t |> run("backward goto loops") @(t : T?) {
        var n = 0
        label 1:
        n++
        if (n < 3) {
            goto label 1
        }
        t |> equal(n, 3)
    }
    t |> run("computed goto jumps to the label numbered by an expression") @(t : T?) {
        var out : array<int>
        out |> reserve(3)
        for (k in range(3)) {
            goto 1 + k
            label 1:
            out |> push(10)
            goto 4
            label 2:
            out |> push(20)
            goto 4
            label 3:
            out |> push(30)
            label 4:
        }
        t |> equal(out[0], 10)
        t |> equal(out[1], 20)
        t |> equal(out[2], 30)
    }
    t |> run("goto over a declaration skips its initializer") @(t : T?) {
        var calls = 0
        goto 5
        let _skipped = ++calls
        label 5:
        t |> equal(calls, 0)
    }
}
