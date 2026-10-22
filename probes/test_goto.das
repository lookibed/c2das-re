options gen2
require dastest/testing_boost public
require strings
require _daslang_child

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

// a goto from an `if` whose branch ends in `break` to a label after that `if` in the loop body
let private FOLDED_TAIL = "options gen2\ndef m(c : int; p : uint8?) : int \{\n    var r = 0\n    while (true) \{\n        if (c == 37) \{\n            if (c != 98) \{\n                goto label 2\n            \}\n            break\n        \}\n        label 2:\n        r += 10\n        break\n    \}\n    return r\n\}\n[export]\ndef main : int \{\n    print(\"\{m(37, null)\}\\n\")\n    return 0\n\}\n"

// a goto out of a loop body that holds a label, to an outer label numbered `outer`
def private outer_goto(outer : int) : string => "options gen2\ndef bw(c : int) : int \{\n    var r = 0\n    var n = c\n    label {outer}:\n    r += 1\n    while (true) \{\n        if (n > 0) \{\n            n--\n            goto label {outer}\n        \}\n        label 2:\n        r += 100\n        break\n    \}\n    return r\n\}\n[export]\ndef main : int \{\n    print(\"\{bw(2)\}\\n\")\n    return 0\n\}\n"

// a goto to a label that ends an `if` branch and one that ends a function body, each followed by
// `tail`
def private block_end(tail : string) : string => "options gen2\nvar r = 0\ndef b(c : int) : int \{\n    var q = 0\n    if (c > 0) \{\n        if (c == 1) \{\n            goto label 3\n        \}\n        q += 100\n        label 3:\n        {tail}\n    \}\n    return q\n\}\ndef f(c : int) \{\n    if (c == 1) \{\n        goto label 3\n    \}\n    r += 100\n    label 3:\n    {tail}\n\}\n[export]\ndef main : int \{\n    print(\"\{b(1)\} \{b(2)\}\\n\")\n    f(1)\n    f(2)\n    print(\"\{r\}\\n\")\n    return 0\n\}\n"

[test]
def test_goto_in_loops(t : T?) {
    t |> run("a label with nothing after it in a non-loop block is no goto target under the interpreter, and an empty block after it is folded away (docs/probe-findings.md F62)") @(t : T?) {
        child_rejects(t, "goto_block_end", daslang_child("goto_block_end", block_end(""), false), "jump to label 3 failed")
        child_rejects(t, "goto_block_end_empty", daslang_child("goto_block_end_empty", block_end("\{\}"), false), "jump to label 3 failed")
        let assigned = daslang_child("goto_block_end_store", block_end("r += 0"), false)
        t |> equal(assigned.out, "0 100\n100\n")
    }
    t |> run("a label that ends a loop body is a goto target: the loop runs its next iteration") @(t : T?) {
        var r = 0
        for (i in range(3)) {
            if (i == 1) {
                goto label 3
            }
            r += 10
            label 3:
        }
        t |> equal(r, 20)
    }
    t |> run("an `if` whose branch ends in `break` takes the rest of its block as an else, a label in it too: a goto from the branch misses the label (docs/probe-findings.md F60)") @(t : T?) {
        let res = daslang_child("goto_folded_tail", FOLDED_TAIL, false)
        t |> equal(res.out |> starts_with("10\n"), false, res.out)
    }
    t |> run("a loop takes a goto whose number is below its body's label count as its own: one to a label outside numbered above them leaves the loop") @(t : T?) {
        let above = daslang_child("goto_out_above", outer_goto(9), false)
        t |> equal(above.out, "103\n")
        let below = daslang_child("goto_out_below", outer_goto(1), false)
        t |> equal(below.rc != 0 || below.out != "103\n", true, below.out)
    }
    t |> run("the re-dispatch: a label at the top of a loop body restarts it, the case chosen by the stored condition") @(t : T?) {
        var trace : array<int>
        var cond = 1
        var steps = 0
        while (true) {
            label 1:
            steps++
            var flag = false
            flag ||= cond == 1
            if (flag) {
                trace |> push(1)
                cond = 7
                goto label 1
            }
            flag ||= cond == 7
            if (flag) {
                trace |> push(7)
                break
            }
            break
        }
        t |> equal(length(trace), 2)
        t |> equal(trace[1], 7)
        t |> equal(steps, 2)
    }
}
