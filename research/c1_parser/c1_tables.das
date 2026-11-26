options gen2
options indenting = 4

// The LR candidate's tables measured outside the macro: `-- <c1_lr.das> [rounds]` reads the
// `rule(...)` and `prec_left(...)` calls of the grammar, builds the LALR(1) tables through
// dasBison's core (`grammar_from_text`, `build_lalr`, `resolve_precedence`) the way `[bison]` does
// at compile time, and prints their size and the build time (median of the rounds).

require daslib/fio
require strings
require daslib/strings_boost
require daslib/enum_trait
require math
require bison/lalr
require bison/prec
require bison/grammar_text
require c1_ast

//! The quoted arguments of a call line `name("a", "b", ...)`.
def quoted_args(line : string) : array<string> {
    var out : array<string>
    var at = find(line, "(")
    while (at >= 0) {
        let open = find(line, "\"", at)
        if (open < 0) {
            break
        }
        let close = find(line, "\"", open + 1)
        if (close < 0) {
            break
        }
        out |> push(slice(line, open + 1, close))
        at = close + 1
        // the arguments end at the call's closing parenthesis
        let next_quote = find(line, "\"", at)
        let paren = find(line, ")", at)
        if (paren >= 0 && (next_quote < 0 || paren < next_quote)) {
            break
        }
    }
    return <- out
}

[export]
def main() {
    let args <- get_command_line_arguments()
    let at = find_index(args, "--")
    let text = fread(args[at + 1])
    let rounds = at + 2 < length(args) ? to_int(args[at + 2]) : 5
    var rules : array<TextRule>
    var precs : array<TextPrec>
    for (line in split(text, "\n")) {
        let s = strip(line)
        if (starts_with(s, "rule(\"")) {
            let a <- quoted_args(s)
            rules |> push(TextRule(lhs = a[0], rhs = a[1]))
        } elif (starts_with(s, "prec_left(\"")) {
            precs |> emplace(TextPrec(assoc = PrecAssoc.left, names <- quoted_args(s)))
        }
    }
    var tokens : table<string; int>
    for (k in each(type<TK>)) {
        tokens[string(k)] = int(k)
    }
    var times : array<float>
    var nstates = 0
    var nterms = 0
    var nrules = 0
    var nprods = 0
    var conflicts = 0
    var nonzero = 0
    for (_ in range(rounds)) {
        let t0 = ref_time_ticks()
        var g <- grammar_from_text(rules, precs, "translation_unit", tokens)
        if (!empty(g.err)) {
            print("grammar error: {g.err}\n")
            return
        }
        let tables <- build_lalr(g.builder, g.root)
        let res <- resolve_precedence(tables, g.builder)
        times |> push(float(get_time_usec(t0)) / 1000.0)
        nstates = res.tables.nstates
        nterms = res.tables.nterms
        nrules = res.tables.nrules
        nprods = length(res.tables.prods)
        conflicts = res.report.shift_reduce + res.report.reduce_reduce
        nonzero = 0
        for (a in res.tables.action) {
            if (a != 0) {
                nonzero++
            }
        }
    }
    sort(times)
    let action_cells = nstates * nterms
    let goto_cells = nstates * nrules
    print("productions {nprods}, terminals {nterms}, nonterminals {nrules}, states {nstates}\n")
    print("action cells {action_cells} ({nonzero} non-error), goto cells {goto_cells}; {(action_cells + goto_cells) * 4} bytes as int32\n")
    print("conflicts left to the default {conflicts}\n")
    print("build (grammar_from_text + build_lalr + resolve_precedence): median {times[length(times) / 2]} ms, min {times[0]}, max {times[length(times) - 1]} over {rounds}\n")
}
