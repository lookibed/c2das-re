options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require ../line_wrap.das

// a call of `n` arguments `argument_<k>`, its commas marked
def private marked_call(name : string; n : int) : string => "{name}(" + join([for (k in range(n)); "argument_{k}"], ",{LIST_MARK} ") + ")"

[test]
def test_line_wrap(t : T?) {
    t |> run("a line that fits loses its marks and keeps its text") @(t : T?) {
        t |> equal(laid_out("    f(a,{LIST_MARK} b +{OPERATOR_MARK} c)\n"), "    f(a, b + c)\n")
        t |> equal(laid_out("no marks at all"), "no marks at all")
    }
    t |> run("a long call breaks after commas, filling each line, continuations 8 spaces past the statement") @(t : T?) {
        let text = laid_out("    " + marked_call("call", 20))
        let lines <- split(text, "\n")
        t |> equal(length(lines) > 1, true, text)
        for (l in lines) {
            t |> equal(length(l) <= LINE_WIDTH, true, l)
        }
        t |> equal(lines[0] |> starts_with("    call(argument_0, argument_1,"), true, text)
        t |> equal(lines[1] |> starts_with("            argument_"), true, text)
        t |> equal(replace(replace(text, "\n", ""), "            ", " ") |> find(",,") < 0, true, text)
    }
    t |> run("the shallowest parentheses break first, a list's commas before && and || before other operators") @(t : T?) {
        let inner = join([for (k in range(12)); "operand_number_{k} +{OPERATOR_MARK} {k}"], ",{LIST_MARK} ")
        let logic = join([for (k in range(8)); "value_number_{k} >{OPERATOR_MARK} {k}"], " &&{LOGIC_MARK} ")
        let text = laid_out("    if (outer({inner}) == 0 &&{LOGIC_MARK} {logic}) \{")
        let lines <- split(text, "\n")
        // the condition's `&&` breaks first; its first part, still too long, at `outer`'s commas,
        // 4 spaces deeper; no line breaks at `+` or `>`
        t |> equal(length(lines), 4, text)
        t |> equal(lines[0] |> ends_with("operand_number_5 + 5,"), true, text)
        t |> equal(lines[1] |> starts_with("                operand_number_6") && lines[1] |> ends_with(") == 0 &&"), true, text)
        t |> equal(lines[2] |> starts_with("            value_number_0 > 0 &&"), true, text)
        for (l in lines) {
            t |> equal(l |> ends_with(" +") || l |> ends_with(" >"), false, text)
        }
    }
    t |> run("a mark outside every parenthesis, inside a [ ] or \{ \}, a string, a character literal or a comment never breaks") @(t : T?) {
        let long = repeat("x", 170)
        t |> equal(laid_out("    return {long} +{OPERATOR_MARK} y"), "    return {long} + y")
        t |> equal(laid_out("    a[{long} +{OPERATOR_MARK} y] = 0"), "    a[{long} + y] = 0")
        t |> equal(laid_out("    f(\"{long}(,{LIST_MARK} \")"), "    f(\"{long}(, \")")
        t |> equal(laid_out("    f('(') // ({long},{LIST_MARK} y)"), "    f('(') // ({long}, y)")
    }
}
