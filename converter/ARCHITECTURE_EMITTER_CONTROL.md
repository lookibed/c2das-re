# converter Architecture - the emitter's switch and labels

Companion to `ARCHITECTURE.md` in this folder, continuing section 4 of `ARCHITECTURE_EMITTER.md`.

### switch

A `switch` follows the three-tier ladder of `docs/lowering-examples.md`. Its body is read as
groups, one run of labels and the statements under them; a statement before the first label
or a label below the switch's own level (Duff's device, P7.7) fails closed, a nested switch's
labels being its own. The condition is evaluated once into `_condN` (numbered per switch
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
goto (O6) is the optimization tier's.

### Labels and goto {#goto-labels}

A C label is `label N:  // name`, numbered per function in order of appearance, and a goto
is `goto label N` (`docs/lowering-examples.md` "goto / labels"); das resolves a label lexically
upward, so a goto reaches a label in its own block or an enclosing one, and a goto into a
deeper block has every bare block between them (a block that is its parent's statement)
emitted without braces, so the label lands in a scope the goto sees, its locals renamed where
they would meet a global or another local of their name (`ARCHITECTURE_EMITTER.md` section 4); an
`if`, loop or switch body on that way is Duff's device (P7.7) and fails closed. A goto over a declaration skips its
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
spells.

A goto into another case group of a switch around both (`goto dflt` from a `case` of lstrlib.c's
`match`, `goto l_tforcall` and `goto ret` in lvm.c's `luaV_execute`) re-dispatches the switch:
each group lands in its own branch, so the label could sit in no scope the goto sees. The switch
takes the matched-flag loop whatever its groups, with `var _gotoN = 0` before the loop, and each
such label (at its group's level once the bare blocks on the way lose their braces) becomes a case
of its own number, 1 up in order of appearance, in that variable: no value of the condition stands
in for a label, since the condition can hold any value of its type. Every ordinary case test and
`default`'s reads `_gotoN == 0 && ...`. The label splits its group's `if (_flag)` branch with
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
