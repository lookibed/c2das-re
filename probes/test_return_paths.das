options gen2
require dastest/testing_boost public
require _daslang_child

// das's "not all control paths return value" (error 30310) over the shapes a converted function
// ends in (docs/probe-findings.md F101): an `if` chain needs its `else`, a `while (true)` counts by
// its own body, and a `break` out of that loop is not seen: the function falls off its end
def private returning(name, body : string) : string =>
    "options gen2\n\ndef {name}(x0 : int) : int \{\n    var x = x0\n{body}\n\}\n\n[export]\ndef main \{\n    print(\"\{{name}(3)\} \{{name}(-1)\}\\n\")\n\}\n"

let private CHAIN = "    if (x > 0) \{\n        return 1\n    \} elif (x < 0) \{\n        return 2\n    \} else \{\n        return 3\n    \}"
let private BARE_IF = "    if (x > 0) \{\n        return 1\n    \}"
let private LOOP_BODY_RETURNS = "    while (true) \{\n        x++\n        if (x > 0) \{\n            return 1\n        \} else \{\n            return 2\n        \}\n    \}"
let private LOOP_NESTED_RETURN = "    while (true) \{\n        if (x > 10) \{\n            return x\n        \}\n        x += 3\n    \}"
let private LOOP_BREAK = "    while (true) \{\n        if (x > 0) \{\n            break\n        \}\n        return 1\n    \}"
let private BLOCK_CHAIN = "    \{\n        if (x > 0) \{\n            return 1\n        \} else \{\n            return 2\n        \}\n    \}"

[test]
def test_return_paths(t : T?) {
    t |> run("an `if` chain with an `else` whose arms return, and a bare block of one, end the function (F101)") @(t : T?) {
        let chain = daslang_child("ret_chain", returning("f", CHAIN), false)
        t |> equal(program_output(chain.out), "1 2\n", chain.out)
        let braced = daslang_child("ret_block", returning("f", BLOCK_CHAIN), false)
        t |> equal(program_output(braced.out), "1 2\n", braced.out)
    }
    t |> run("an `if` without `else` does not, nor a `while (true)` whose return is inside an `if` of its body (F101)") @(t : T?) {
        child_rejects(t, "ret_bare_if", daslang_child("ret_bare_if", returning("f", BARE_IF), true), "not all control paths return value")
        child_rejects(t, "ret_loop_nested", daslang_child("ret_loop_nested", returning("f", LOOP_NESTED_RETURN), true), "not all control paths return value")
    }
    t |> run("a `while (true)` whose body returns ends the function (F101)") @(t : T?) {
        let loop = daslang_child("ret_loop", returning("f", LOOP_BODY_RETURNS), false)
        t |> equal(program_output(loop.out), "1 2\n", loop.out)
    }
    t |> run("a `break` out of such a loop is accepted and falls off the end: the converter keeps its zero return there (F101)") @(t : T?) {
        let r = daslang_child("ret_loop_break", returning("f", LOOP_BREAK), true)
        t |> equal(r.rc, 0, r.out)
    }
}
