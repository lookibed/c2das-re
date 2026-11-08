# converter Architecture - the emitter's switch and labels

Companion to `ARCHITECTURE.md` in this folder, continuing section 4 of `ARCHITECTURE_EMITTER.md`.

### switch

A `switch` follows the three-tier ladder of `docs/lowering-examples.md`. Its body is read as
groups, one run of labels and the statements under them; a statement before the first label
fails closed, and a switch with a label below its own level (Duff's device) is spelled open
(below), a nested switch's labels being its own. The condition is evaluated once into `_condN` (numbered per switch
within a function), the enum below C's promotion when there is one, so a case compares as
`_cond == E.X` (`int(_cond) == v` for a value no enumerator has) and otherwise against a
literal in the condition's type. The if-chain holds when no group falls into the next (each
ends in `break`, `return`, `goto` or `continue`, a trailing block looked through) and every
`break` that leaves the switch is that tail - a `break` inside a nested loop or switch is that
construct's own; the tail `break` is dropped, the groups become `if`/`elif` and the default
group `else`, wherever it stood. Otherwise the matched-flag loop: `while (true)` holding
`var _flagN = false`, one `_flag ||= _cond == v` per label and `_flag ||= !(every case value)`
for `default`, each group's statements under `if (_flag)`, a trailing `break`; C `break` is
das's. A C `continue` under such a loop would restart the switch, so it spells
`_contN = true` and `break`, with `if (_contN) { continue }` after the loop - itself through
the same translation when the switch sits in an outer flag loop; a real loop body resets the
translation. C scopes a declaration at the switch body's own level to the rest of the body, while
each group lands in its own branch: a declaration that a statement under a later label names is
declared right after `_condN` as a bare `var v : T` (das's zero where C leaves it indeterminate)
and its initializer is the assignment that stands where C declares it; one filled by stores (a
union's list, a sparse array) fails closed, since the stores rely on a zero a second pass through
the case would not give again; any other declaration keeps its branch's scope (F53). Computed
goto (O6) is the opt-in below.

### Cases that do nothing {#inert-cases}

A group whose statements do nothing - a `;`, an expression statement with no effect and no volatile
read (`((void)0)`, an `assert` under `NDEBUG`), a block of only those - falls into the next group
with nothing on the way, so it joins that group's labels (`_cond == A || _cond == B`) and its
fall-through is gone; a run of such groups joins the first group after it that acts, the last
group included. The rule covers case labels only: a group holding `default`, or followed by one,
keeps its own branch, as does a group holding a C label, a declaration, a `break`, a nested switch
or any statement that acts (a step, a call, an assignment, a comma). A switch with a case label in a
nested block is spelled open (below) before any grouping. With no fall-through left, the switch is
the if-chain; binjgb's CpuState switch, whose first case is an emptied `assert`, is one.

### Plain cases in the flag loop {#plain-cases}

A group of the matched-flag loop that only its own labels enter - the group before it ends in a
leaving statement, no goto re-dispatches into it, and it ends in one itself or is the last - is a
plain `if` on its tests (`if (_cond == 5)`, `if (_cond == 2 || _cond == 3)`, `default` as
`if (!(every case value))`): no `_flagN ||=` line, and the flag stays unset, which
the next group's `_flagN ||=` needs, since control reaches that group only past a group that
left. The loop declares `_flagN` only when a group still needs it, and a group with no
statements (the switch's last) writes nothing. The interpreter runs a VM dispatch so 2.33 times
faster than through the flag chain (`perf/ARCHITECTURE_AUDIT.md`, the `dispatch_switch` kernel),
and the text is the one a person writes.

### Computed goto dispatch {#goto-dispatch}

Under `switch_dispatch` `goto` (the sidecar key, the converter's `--switch-dispatch`; `chain` is the
default), a dense switch takes the matched-flag loop with a jump table in front: 8 or more case
values in `int`'s range filling at least half of [lo, hi], no group falling into the next (each but
the last `leaves_at_end`), the switch not spelled open (`dispatch_plan`). The loop body opens with a
bounds guard, `if (_cond < lo || _cond > hi) { goto label D }`, then `goto _cond + (base - lo)`
(`int(_cond)` for an enum or another integer type, compared as `int(_cond)` for an enum and in its
type otherwise); each group stands after `label base + v - lo:  // case v` for each of its values,
and at `default`, or before the loop's closing `break` when the switch has none, stand a label per
value of [lo, hi] no case holds and `label D`. A plain case keeps its `if (_cond == v)`, a flag
case its `_flag ||=` lines, so the text still names every case; under the jump no case test runs
before the matching one; the jump lands on a group whose test holds, since the guard keeps
every other value out and each value's label stands before its own group, so a failing test there,
which would fall into the next group, never runs. A goto into another case group jumps straight to the das label put before
the label's `_flag ||= _gotoN == k` line: no re-dispatch label, no chain walk, no sentinel, and
every case test reads `_cond == v` alone; `_gotoN` still selects and clears the split. Every group's
branch ends in `else { c_label_end() }`: daslang's optimizer moves what follows an `if` with no
`else` whose branch ends in `break`, `return` or `continue` into one, the next labels too, and the
jump would then miss them under the interpreter (lookibed/daScript#35, the fold of #8). The jump
table's labels take the numbers below every C label of the function, after the inner switches',
and the C labels move up past them: a loop takes a goto whose number is below its body's label
count as its own, so case labels above `startfunc` would capture lvm's `goto startfunc` (F60). Both
facts are `probes/test_goto.das`'s; the interpreter and the JIT run the form alike. A sparse
switch, one that falls through, one under 8 values or past `int`, and Duff's device keep the forms
above.

### Labels and goto {#goto-labels}

A C label is `label N:  // name`, numbered per function in order of appearance, and a goto
is `goto label N` (`docs/lowering-examples.md` "goto / labels"); das resolves a label lexically
upward, so a goto reaches a label in its own block or an enclosing one, and a goto into a
deeper block has every bare block between them (a block that is its parent's statement)
emitted without braces, so the label lands in a scope the goto sees, its locals renamed where
they would meet a global or another local of their name (`ARCHITECTURE_EMITTER.md` section 4); an
`if`, loop or switch on that way is spelled open (below). A goto over a declaration skips its
initializer, which is C's rule too (`probes/test_goto.das`). A label in a das block other
than a loop's body (llex.c's `no_save: break;` once a switch's if-chain drops the tail `break`, a
label ending a function body or an `if` branch, one before `if (DEBUG) {...}`) is followed at once by
`c_label_end()`, a `[sideeffects]` no-op the module itself defines (`def private`): daslang's
interpreter jumps only to a statement inside such a block, and its optimizer folds an empty block
or a statement without effect away, an `if` or `while` whose body it can drop included
(`docs/probe-findings.md` F62). The definition lives in the module because the JIT inlines a
module-local call to nothing, where a call into a c_runtime piece stays a call: the switch_local
kernel's jit lane paid 17 percent for it. A C program that names `c_label_end` itself fails
closed. A loop body takes a jump to its end as the next iteration and gets
none; the block is a loop's when the line that opens it is a `while`, the only loop the lowering
spells. daslang's optimizer also moves the statements after an `if` with no `else` whose
branch ends in `return`, `break` or `continue` into an `else`, a label among them, so a goto above
that `if` misses the label under the interpreter (lookibed/daScript#8). `emit_if` marks the closing
line of each C `if` with no `else` whose branch ends so as spelled (`closes`: a `return`, a `break`
or `continue` that stays das's, or an `if` whose every arm does, which the optimizer turns into one
`return` of a `?:`), and once a function with labels is spelled `guard_label_folds` gives each
marked `if` with a label after it in its block, which a goto above the `if`'s end names,
`else { c_label_end() }`, an `else` the optimizer keeps. A goto after the `if`
sits in the folded tail with its label and needs none, so Duff's `if (count <= 0) { return 0 }`
before its dispatch stays as written.

A goto into another case group of a switch around both (`goto dflt` from a `case` of lstrlib.c's
`match`, `goto l_tforcall` and `goto ret` in lvm.c's `luaV_execute`) re-dispatches the switch:
each group lands in its own branch, so the label could sit in no scope the goto sees. The switch
takes the matched-flag loop whatever its groups, with `var _gotoN = 0` before the loop, and each
such label (at its group's level once the bare blocks on the way lose their braces) becomes a case
of its own number, 1 up in order of appearance, in that variable: no value of the condition stands
in for a label, since the condition can hold any value of its type. The goto also stores into the
condition, then `var _condN`, a value no case holds: one below the smallest case value, else one
above the largest, in the condition's type (an enum's an `int` through `enum_from_int`, whose
out-of-range value compares by value). So a case test reads `_cond == v` alone and the case the goto
left cannot match again on the restart, where with the condition unchanged it would loop forever;
`default`, which that value would match, reads `_gotoN == 0 && !(every case value)`, the one goto
test of a dispatch, and the plain cases of lvm's 83 skip a test each (`restart_sentinel`). Cases
spanning the condition's whole type leave no such value, and every test reads `_gotoN == 0 && ...`.
The label splits its group's `if (_flag)` branch with
`_flag ||= _gotoN == k  // name`, so control falling into it keeps the flag, and the branch opens
with `_gotoN = 0`, which consumes the pending goto; every goto to the label, one from the label's
own group too, stores `k` into `_gotoN` and jumps to `label K:  // re-dispatch`, the first
statement of the loop body, before the flag's declaration. A label after a declaration of its own
group fails closed, since the split would end the declaration's scope. The re-dispatch label stands
at the top of the loop body because daslang's optimizer moves the statements after an `if` whose
branch ends in `break` into an `else`, so a label among them escapes a goto from that branch, and
no such tail holds the top; the re-dispatch labels take the numbers below the C labels, an inner
switch's below the one around it, because daslang's loop node takes a goto whose number is below
the count of its body's labels as one of its own (`docs/probe-findings.md` F60,
`probes/test_goto.das`). No numbering serves a case group of such a switch that holds a plain C
label and makes a goto that leaves the group, a re-dispatch or a goto out of the switch: under the
interpreter its branch is a labelled block that passes no goto outward, and a labelled loop in it
claims every goto numbered below its label count (F60, F63), so `check_labelled_groups` refuses it
with the label and the goto named.

### A goto into a body {#goto-into-body}

An `if`, loop or switch whose arm or body a goto enters from outside, every one between the goto's
block and the label, and a switch with a case label below its own level together with every
construct between that label and the switch's level, is spelled open: at its parent's level, its
control flow as das labels and gotos, its entered body flat like a bare block, so the label lands in
a scope the goto sees; this is the plan's goto-into-nested-block flattening and its Duff fallback
(`docs/very-detailed-plan.md` section 3, step 4), and no state variable or dispatch loop is
involved. Every other construct of the function keeps its structured form. An `if` is
`if (!(c)) { <the arm no goto enters>; goto label E }`, the entered arm, `label E:  // end if`,
the test kept as written (`if (c)`) when the entered arm is `else`; both arms flat are
`if (!(c)) { goto label L }`, the then arm, `goto label E` unless it leaves, `label L:  // else`, the
else arm, `label E`. An arm no goto enters is flat as well when it holds a label of its own, since
braced it would be a labelled block passing no goto outward (F63), or ends in a leaving statement,
since daslang's optimizer moves the statements after an `if` whose branch ends in `return`, `break`
or `continue` into an `else`, a later label among them (lookibed/daScript#8). A `while` or `for` is
its initializer, `label T:`, `if (!(c)) { goto label E }`, the body, a `label N:  // for next`
before the increment when the body holds a `continue` of the loop, `goto label T`, `label E:`; a
`do` is `label T:`, the body, the `continue` label, `if (c) { goto label T }`, and its end label
when a `break` needs it. A switch is `let _condN = x` (a declaration a later case reads after it),
one `if`/`elif` per case label to that label's `goto`, `else` to `default` or the end, then the body
flat with every case label `label K:  // case v`. A C `break` of an open loop or switch is a goto to
its end and a `continue` of an open loop one to its test or increment (`break_gotos`, `cont_flags`);
a das loop or matched-flag switch inside keeps das's own. A block left braced that holds an open
construct holds its labels, and a goto leaving such a block fails under the interpreter: a das
loop's body claims a goto numbered below its label count and jumps to a slot of -1 (F60,
lookibed/daScript#19), any other labelled block passes no goto outward (F63); so every such block a
goto leaves is opened as well (`open_left_blocks`: a bare block loses its braces, an arm or body
opens its `if`, loop or switch), until none is left. The labels the lowering adds are numbered
after the function's C labels, which keep their numbers, and the comment names the construct. A
goto into an arm of a setjmp `if`, or an open switch that a goto from another case re-dispatches,
fails closed. The open form is the C's own jumps made explicit: no flag is tested and no loop
dispatches, so it costs the interpreter what the C's control flow does, and it reads less like the
C than the structured form, which is why only constructs on a goto's way into a body take it.

### Truth tests {#truth-tests}

A truth test - the condition of an `if` or a loop, an operand of `!`, `&&` or `||`, the condition
of `?:` - tests what is left past three spellings that cannot change it: a `__builtin_expect(e,
c)` hint (its value is `e`), an integer conversion to a type no narrower (a value keeps its zero),
and `!= 0` on a truth value (a comparison, `&&`, `||` or `!`, already 0 or 1). Lua's
`l_unlikely(trap)`, `__builtin_expect((long) (trap != 0), 0)`, is `if (trap != 0)` and
`l_likely(a < b)` is `a < b`, where the plain bool view spelled `int64(trap != 0 ? 1 : 0) != 0`;
the interpreter runs the `trap_check` kernel 1.75 times faster so
(`perf/ARCHITECTURE_AUDIT.md`). A narrowing conversion stays (`(char) 256` is zero), and a hint
read as a number is its operand's value.

### Pure helpers at the call site {#inline-helpers}

Under the sidecar's `inline_helpers` (`--inline-helpers`), a direct call of a pure helper is the
helper's expression at the call site, where the interpreter otherwise pays a call per use (pl_mpeg's
`plm_clamp`, 19 M calls per 7 frames, the Rust translator's `inline.rs`). A pure helper is a `static`
function of at most four parameters, each an integer other than `_Bool` or a floating type, with
such a result, never K&R, whose value the program never takes (`@@f` anywhere keeps every call),
whose body is `return <expr>;` or the clamp shape (`if (n > 255) n = 255; else if (n < 0) n = 0;
return n;`, every arm assigning one parameter, the `return` reading it under casts), and whose
expressions read only its parameters, literals and enumerators through operators, value casts and
`?:`; `return <expr>` may call other pure helpers, the clamp calls nothing, and a helper reaching
itself is none. Each argument crosses at its parameter's type as a call's does and is evaluated
once, in C's order: one with an effect (a call, a store, a step, a volatile read), or one the body
reads twice that is not a variable, a literal or an enumerator, lands in a `let _tN` ahead of the
statement; the others are spelled where the body reads them. The clamp is a chain of `?:`, `c0 ? v0
: (c1 ? v1 : n)`, at the parameter's type, which the `return`'s conversion takes; `return <expr>`
is the expression under its own conversion, so the call's result keeps C's type. A call evaluated
for its effect alone, one in a global's initializer, one inside the same helper's expansion, and
one in a conditional arm (`?:`, the right of `&&` or `||`) that would need a temporary stay calls.
The definition stays for those. The default keeps every call: the site then names the helper, which
the expression does not (owner ruling 23).
