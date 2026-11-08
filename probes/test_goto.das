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

// a goto out of an `if` branch that holds a label, to a label above the `if` (C: 23)
let private BLOCK_TRAP = "options gen2\ndef f(c : int) : int \{\n    var r = 0\n    var n = c\n    label 1:\n    r += 1\n    if (n > 0) \{\n        label 2:\n        r += 10\n        n--\n        if (n == 5) \{\n            goto label 2\n        \}\n        goto label 1\n    \}\n    return r\n\}\n[export]\ndef main : int \{\n    print(\"\{f(2)\}\\n\")\n    return 0\n\}\n"

// a goto to a label that ends an `if` branch and one that ends a function body, each followed by
// `tail`
def private block_end(tail : string) : string => "options gen2\nvar r = 0\ndef b(c : int) : int \{\n    var q = 0\n    if (c > 0) \{\n        if (c == 1) \{\n            goto label 3\n        \}\n        q += 100\n        label 3:\n        {tail}\n    \}\n    return q\n\}\ndef f(c : int) \{\n    if (c == 1) \{\n        goto label 3\n    \}\n    r += 100\n    label 3:\n    {tail}\n\}\n[export]\ndef main : int \{\n    print(\"\{b(1)\} \{b(2)\}\\n\")\n    f(1)\n    f(2)\n    print(\"\{r\}\\n\")\n    return 0\n\}\n"

// a computed goto to labels each after an `if` whose branch ends in `break`, the issue's numbers: no `else`
let private FOLD_BARE = "options gen2\nvar g = 0\n[sideeffects]\ndef private label_end() \{\n    g += 0\n\}\ndef run(c : int) : int \{\n    var r = 0\n    while (true) \{\n        goto c + 1000\n        label 1000:\n        if (c == 0) \{\n            r = 10\n            break\n        \}\n        label 1001:\n        if (c == 1) \{\n            r = 11\n            break\n        \}\n        r = -1\n        break\n    \}\n    return r\n\}\n[export]\ndef main() \{\n    for (j in range(2)) \{\n        print(\"\{run(j)\} \")\n    \}\n    print(\"\\n\")\n\}\n"

// the same, each `if` with an `else` the optimizer keeps
let private FOLD_GUARDED = "options gen2\nvar g = 0\n[sideeffects]\ndef private label_end() \{\n    g += 0\n\}\ndef run(c : int) : int \{\n    var r = 0\n    while (true) \{\n        goto c + 1000\n        label 1000:\n        if (c == 0) \{\n            r = 10\n            break\n        \} else \{\n            label_end()\n        \}\n        label 1001:\n        if (c == 1) \{\n            r = 11\n            break\n        \} else \{\n            label_end()\n        \}\n        r = -1\n        break\n    \}\n    return r\n\}\n[export]\ndef main() \{\n    for (j in range(2)) \{\n        print(\"\{run(j)\} \")\n    \}\n    print(\"\\n\")\n\}\n"

// a jump table in a loop: a bounds guard, case labels 1-5 with an `else` on each case, two labels
// in a row for the values no case holds, a goto out of the loop to label 9 (C: 1010 2010 1020 1020
// 1040 1020 1020)
let private DISPATCH_LOW = "options gen2\nvar r = 0\n[sideeffects]\ndef private label_end() \{\n    r += 0\n\}\ndef run(c0 : int) : int \{\n    var n = 0\n    var c = c0\n    label 9:\n    n += 1000\n    while (true) \{\n        if (c < 0 || c > 4) \{\n            goto label 3\n        \}\n        goto c + 1\n        label 1:\n        if (c == 0) \{\n            n += 10\n            break\n        \} else \{\n            label_end()\n        \}\n        label 2:\n        if (c == 1) \{\n            c = 0\n            goto label 9\n        \} else \{\n            label_end()\n        \}\n        label 3:\n        label 4:\n        if (!(c == 0 || c == 1 || c == 4)) \{\n            n += 20\n            break\n        \} else \{\n            label_end()\n        \}\n        label 5:\n        if (c == 4) \{\n            n += 40\n            break\n        \}\n        break\n    \}\n    return n\n\}\n[export]\ndef main() \{\n    print(\"\{run(0)\} \{run(1)\} \{run(2)\} \{run(3)\} \{run(4)\} \{run(9)\} \{run(-1)\}\\n\")\n\}\n"

// the same with the case labels numbered 11-15, above the label outside
let private DISPATCH_HIGH = "options gen2\nvar r = 0\n[sideeffects]\ndef private label_end() \{\n    r += 0\n\}\ndef run(c0 : int) : int \{\n    var n = 0\n    var c = c0\n    label 9:\n    n += 1000\n    while (true) \{\n        if (c < 0 || c > 4) \{\n            goto label 13\n        \}\n        goto c + 11\n        label 11:\n        if (c == 0) \{\n            n += 10\n            break\n        \} else \{\n            label_end()\n        \}\n        label 12:\n        if (c == 1) \{\n            c = 0\n            goto label 9\n        \} else \{\n            label_end()\n        \}\n        label 13:\n        label 14:\n        if (!(c == 0 || c == 1 || c == 4)) \{\n            n += 20\n            break\n        \} else \{\n            label_end()\n        \}\n        label 15:\n        if (c == 4) \{\n            n += 40\n            break\n        \}\n        break\n    \}\n    return n\n\}\n[export]\ndef main() \{\n    print(\"\{run(0)\} \{run(1)\} \{run(2)\} \{run(3)\} \{run(4)\} \{run(9)\} \{run(-1)\}\\n\")\n\}\n"

// switch_goto's `run_code` as a flat label CFG in its loop body: a bounds guard, a computed goto to
// case labels 4-8, gotos between the cases to the C labels 1-2, `label 9` the switch's end; case 0's
// `if` returns and ends with `arm_end` (C: 11701 31076 -1 -1)
def private flat_cfg(arm_end : string) : string => "options gen2\nvar g = 0\nlet code = fixed_array<uint8>(uint8(0), uint8(1), uint8(2), uint8(3), uint8(4), uint8(1), uint8(0), uint8(2), uint8(3), uint8(4), uint8(0), uint8(0), uint8(1), uint8(2), uint8(4), uint8(3))\n[sideeffects]\ndef private label_end() \{\n    g += 0\n\}\ndef run(seed : int) : int \{\n    var acc = seed\n    var pc = 0\n    var n = 0\n    while (pc < 16) \{\n        let c = int(code[pc])\n        pc++\n        if (c < 0 || c > 4) \{\n            goto label 9\n        \}\n        goto c + 4\n        label 4:\n        acc += 3\n        if (acc > 60000) \{\n            return -1\n{arm_end}\n        goto label 9\n        label 5:\n        acc ^= pc\n        goto label 1\n        label 6:\n        label 1:\n        acc = acc * 5 + 1\n        goto label 2\n        label 7:\n        label 2:\n        acc -= n\n        n++\n        goto label 9\n        label 8:\n        if ((acc & 1) != 0) \{\n            acc >>= 1\n        \} else \{\n            acc += 7\n        \}\n        label 3:\n        acc &= 65535\n        label 9:\n    \}\n    return acc\n\}\n[export]\ndef main() \{\n    print(\"\{run(0)\} \{run(7)\} \{run(1000)\} \{run(59999)\}\\n\")\n\}\n"

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
    t |> run("the re-dispatch: a label at the top of a loop body restarts it, the case chosen by the goto variable while every case test requires it unset") @(t : T?) {
        var trace : array<int>
        let cond = 1
        var pending = 0
        var steps = 0
        while (true) {
            label 1:
            steps++
            var flag = false
            flag ||= pending == 0 && cond == 1
            if (flag) {
                trace |> push(1)
                pending = 1
                goto label 1
            }
            flag ||= pending == 0 && cond == 2
            if (flag) {
                trace |> push(2)
            }
            flag ||= pending == 1
            if (flag) {
                pending = 0
                trace |> push(7)
                break
            }
            break
        }
        t |> equal(length(trace), 2)
        t |> equal(trace[1], 7)
        t |> equal(steps, 2)
        t |> equal(pending, 0)
    }
    t |> run("a labelled block that is not a loop passes no goto outward under the interpreter, the JIT does (docs/probe-findings.md F63)") @(t : T?) {
        child_rejects(t, "goto_block_trap", daslang_child("goto_block_trap", BLOCK_TRAP, false), "jump to label 1 failed")
        let jit = daslang_child_flags("goto_block_trap_jit", BLOCK_TRAP, jit_flags())
        t |> equal(jit.out |> ends_with("23\n"), true, jit.out)
    }
}

[test]
def test_goto_dispatch(t : T?) {
    t |> run("a computed goto to a label after an `if` whose branch ends in `break` and has no `else` misses it under the interpreter; an `else` keeps it (lookibed/daScript#35, the fold of lookibed/daScript#8)") @(t : T?) {
        let bare = daslang_child("goto_fold_bare", FOLD_BARE, false)
        // run(0) lands right, run(1) misses its label and returns what the folded tail leaves
        t |> equal(bare.rc, 0, bare.out)
        t |> success(bare.out |> starts_with("10 ") && !(bare.out |> starts_with("10 11 ")), bare.out)
        let guarded = daslang_child("goto_fold_guarded", FOLD_GUARDED, false)
        t |> equal(guarded.out, "10 11 \n")
        let jit = daslang_child_flags("goto_fold_guarded_jit", FOLD_GUARDED, jit_flags())
        t |> equal(jit.out |> ends_with("10 11 \n"), true, jit.out)
    }
    t |> run("a jump table's case labels numbered below the labels outside its loop run under the interpreter and the JIT; numbered above, the loop claims the goto out (docs/probe-findings.md F60)") @(t : T?) {
        let low = daslang_child("goto_dispatch_low", DISPATCH_LOW, false)
        t |> equal(low.out, "1010 2010 1020 1020 1040 1020 1020\n")
        let jit = daslang_child_flags("goto_dispatch_low_jit", DISPATCH_LOW, jit_flags())
        t |> equal(jit.out |> ends_with("1010 2010 1020 1020 1040 1020 1020\n"), true, jit.out)
        // it compiles; the run crashes on the claimed goto
        let compiled = daslang_child("goto_dispatch_high_compile", DISPATCH_HIGH, true)
        t |> equal(compiled.rc, 0, compiled.out)
        let high = daslang_child("goto_dispatch_high", DISPATCH_HIGH, false)
        t |> equal(high.rc != 0 || high.out != "1010 2010 1020 1020 1040 1020 1020\n", true, high.out)
    }
    t |> run("a flat label CFG in a loop body, a computed goto to its case labels and gotos between the cases, runs under the interpreter and the JIT once an `if` that returns before a case label has an `else`; without it the interpreter misses the label (lookibed/daScript#35)") @(t : T?) {
        let guarded = daslang_child("goto_flat_cfg", flat_cfg("        \} else \{\n            label_end()\n        \}"), false)
        t |> equal(guarded.out, "11701 31076 -1 -1\n")
        let jit = daslang_child_flags("goto_flat_cfg_jit", flat_cfg("        \}"), jit_flags())
        t |> equal(jit.out |> ends_with("11701 31076 -1 -1\n"), true, jit.out)
        child_rejects(t, "goto_flat_cfg_bare", daslang_child("goto_flat_cfg_bare", flat_cfg("        \}"), false), "jump to label 9 failed")
    }
}
