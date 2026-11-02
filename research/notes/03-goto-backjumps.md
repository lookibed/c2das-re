# 03-goto-backjumps: the manual `_goto` back-jumps and shared tails (luaV_execute, llex, lstrlib, ltable)

Research note, 2026-11-02 night. Prototypes, kernel, hand spellings and the raw numbers:
`/root/wt-research/research/03-goto-backjumps/` (`kernels/exec_backjump.c`, `hand/*.das`,
`gen_hand.py`, `measure.das`, `results_run1.json`, `proposed_luaV_execute.das`, `proposed_read_string.das`).

## For the owner

The problem. The Lua VM's main loop (`luaV_execute`) is one big `switch` inside a `for (;;)`, and
Lua jumps around it with five `goto`s: to `startfunc` and `returning` above the loop when a
Lua function is called or returns, to `ret` inside the switch from every return opcode, and to
`l_tforcall`/`l_tforloop` inside the next opcode's case. The converter keeps every one of those
jumps as a jump. The two labels above the loop become real das labels (`label 2:`, `goto label 2`),
which is fine for the machine but is exactly what a das programmer never writes. The jumps into
another case cannot be das labels at all (a case is its own `if` branch), so the converter builds
a small state machine: a number `_goto`, a `goto label 1` back to the top of the switch, and a
`_goto == 0 &&` test on every case. One Lua function return walks that whole chain again, about
seventy tests, before it reaches `ret`. The same machinery appears in the lexer (`read_string`:
three labels in a row), in `string.format` (`intcase`), in the pattern matcher (`match`: `init`,
`dflt`) and in the garbage collector (`remove`, `remain`).

What a human port writes. `while (true)` loops with `break` and `continue`, one small named
choice where several cases share a tail, and the shared tail written once after the loop or
inlined where it is three lines. No labels, no `_goto`, no re-dispatch. The sketch for
`luaV_execute` is in `proposed_luaV_execute.das`; for the lexer in `proposed_read_string.das`.

The proposal. Four recognizers on top of P7.0c's plain-case chain: (1) a label above a loop that
only backward gotos reach is a `while (true)` and the gotos are `break`/`continue`; (2) a label
inside a case that only forward gotos reach, whose tail leaves the switch, is written once after
the loop (or inlined when short); (3) a fall-through into a short next case duplicates that
case's body; (4) a cascade of labels at the end of one case becomes a named choice and guarded
tails. Each is a line in `docs/lowering-examples.md` under "goto / labels" and a ledger row.

What it buys. On a kernel in the audit's shape with luaV_execute's frame of labels, the
interpreter runs the structured form 3.6x to 4.0x faster than today's output and 1.9x to 2.0x faster
than P7.0c's plain-case chain alone (numbers below); the JIT is within noise either way. Readability:
luaV_execute loses 3 labels, 2 `c_label_end()`, 95 `_goto` mentions and 8 `goto label` lines; the
whole port loses its 14 labels, 39 `goto label` lines, 128 `_goto` lines and 9 `c_label_end()`
(the critic's finding 5), and with P7.0c most of the 487 `_flag` lines.

Cost and risk. About 250 to 400 lines in `converter/emit.das` (label planning and the switch
emitter), a probe for das `break` out of nested `while`, four lowering examples, fixtures for
each shape, and the Lua port re-converted and re-hashed. Risk: moderate. The recognizers decide
by syntax (where the gotos are, what the tails end with); a shape they do not recognize keeps
today's `_goto` form, so nothing is lost when they refuse.

Verdict per ruling 23: readable-default. The structured form is both faster and more readable,
so it is the default and needs no flag. The `_goto` state machine stays as the fallback for
shapes the recognizers refuse (and for P7.7's Duff's device), not as an opt-in.

## The C

- `lvm.c:1154-1190` `luaV_execute`: `startfunc:` (1163), `returning:` (1165), the `for (;;)` (1173).
  `goto startfunc` at 1689 (OP_CALL, a Lua callee) and 1711 (OP_TAILCALL); `goto ret` at 1716
  (OP_TAILCALL, a C callee), 1739 (OP_RETURN), 1756 (OP_RETURN0); `ret:` at 1779 inside
  OP_RETURN1's case, reached by fall-through from it; `goto returning` at 1784. `goto l_tforcall`
  1820 from OP_TFORPREP into OP_TFORCALL's body (1823); `goto l_tforloop` 1837 into OP_TFORLOOP's (1840).
- `llex.c:382-433` `read_string`: nine `goto read_save`, two `goto only_save`, three
  `goto no_save` from the escape switch; the labels 426, 429, 433 are a cascade ending in `break`.
  `llex.c:297/312` `read_long_string`: `goto endloop` out of the `for (;;)` to the label after it.
- `lstrlib.c:570-665` `match`: `init:` (573) above the switch, five `goto init` from inside cases
  (tail recursion by hand); `dflt:` (629) on the default group, `goto dflt` from `case '$'` (589)
  and from the inner switch's default (625). `lstrlib.c:1301-1309` `str_format`: `goto intcase`
  from `'d'/'i'` and `'u'`, `intcase:` inside `'o'/'x'/'X'` reached by fall-through.
- `ltable.c:803-817` `luaH_get`: `case LUA_VNUMFLT` falls through into `default:` (one statement).
- `ldo.c:552/581, 596/621` `luaD_pretailcall`, `luaD_precall`: `retry:` above the switch,
  `goto retry` from `default:`.
- `lgc.c:1177-1196` `correctgraylist`: `remove:` and `remain:` at the end of the loop body, each
  `stmt; continue;`, four forward gotos from an if-chain.

## Today's das

`lua/work/lua/lvm.das.inc:879-3568` (`luaV_execute`, 2689 lines):

```
    label 2:  // startfunc
    c_label_end()
    trap = c_volatile_load(L.hookmask)
    label 3:  // returning
    c_label_end()
    ...
            var _goto = 0
            while (true) {
                label 1:  // re-dispatch
                var _flag = false
                _flag ||= _goto == 0 && _cond == OpCode.OP_MOVE
                ...                                                 (83 such cases)
                _flag ||= _goto == 0 && _cond == OpCode.OP_CALL
                if (_flag) { ... ci = newci; goto label 2 ... }     (3228)
                _flag ||= _goto == 0 && _cond == OpCode.OP_RETURN
                if (_flag) { ... _goto = 1; goto label 1 }          (3292; also 3257, 3319)
                _flag ||= _goto == 0 && _cond == OpCode.OP_RETURN1
                if (_flag) { ... }                                  (falls into ret)
                _flag ||= _goto == 1  // ret                        (3356)
                if (_flag) {
                    _goto = 0
                    if ((int(ci.callstatus) & 1 << 2) != 0) { return }
                    else { ci = ci.previous; goto label 3 }
                }
                _flag ||= _goto == 0 && _cond == OpCode.OP_TFORPREP
                if (_flag) { ... _goto = 2; goto label 1 }          (3421)
                _flag ||= _goto == 0 && _cond == OpCode.OP_TFORCALL
                _flag ||= _goto == 2  // l_tforcall                 (3426)
```

Which gotos became `_goto` state (grep `goto label|_goto =` over `lua/work/lua/`): lvm 17
lines (`ret`, `l_tforcall`, `l_tforloop` as `_goto` 1, 2, 3; `startfunc`/`returning` as das
labels 2 and 3), lstrlib 18 (`dflt` and `intcase` as `_goto = 1`; `init` as das label 2 with
five `goto label 2`), llex 15 (all das labels: `endloop` 386, `read_save`/`only_save`/`no_save`
645-663), lgc 4 (das labels 1084, 1087), ldo 2 (das label `retry` 483, 543). `ltable.das.inc:642-674`
`luaH_get` has no goto: the fall-through alone forces the flag loop (34 lines for 15 of C, and a
dead `return null`).

- `lstrlib.das:1332-1372`: `_goto = 1; goto label 1` at 1348, 1354; `_flag ||= _goto == 1  // intcase` 1363.
- `lstrlib.das:663-760` `_c_match`: `label 2:  // init`, `goto label 2` x5, `_goto = 1` for `dflt` at 693, 737.
- `llex.das.inc:571-663` `read_string`: `goto label 1` x9, `goto label 2` x2, `goto label 3` x3.
- `ldo.das.inc:483-535` `luaD_pretailcall`: `label 1:  // retry` ... `goto label 1` in the `else`.
- `lgc.das.inc:1063-1091` `correctgraylist`: four `goto label 1/2` from an if-chain to two labels at the loop's end.

## Proposed das

Full sketches: `research/03-goto-backjumps/proposed_luaV_execute.das` (the frame with OP_ADD,
OP_CALL, OP_TAILCALL, OP_RETURN) and `proposed_read_string.das`. The frame of luaV_execute:

```
    trap = c_volatile_load(L.hookmask)                  // startfunc:
    while (true) {                                      // returning:
        cl = ...; k = cl.p.k; pc = ci.u.l.savedpc
        if (trap != 0) { trap = luaG_tracecall(L) }
        base = ci.func.p + 1
        while (true) {                                  // for (;;)
            vmfetch...
            if (op == OpCode.OP_MOVE) {
                ...
            } elif (op == OpCode.OP_CALL) {
                ...
                newci = luaD_precall(L, ra, nresults)
                if (newci == null) {
                    trap = c_volatile_load(ci.u.l.trap)
                } else {
                    ci = newci                          // goto startfunc
                    trap = c_volatile_load(L.hookmask)
                    break
                }
            } elif (op == OpCode.OP_RETURN) {
                ...
                luaD_poscall(L, ci, n)
                trap = c_volatile_load(ci.u.l.trap)
                if ((int(ci.callstatus) & CIST_FRESH) != 0) {   // ret:
                    return
                }
                ci = ci.previous                        // goto returning
                break
            }
        }
    }
```

How each C jump maps: `startfunc:` has one statement before `returning:`, so that statement is
inlined at the two `goto startfunc` sites and the label disappears; `returning:` is the outer
`while (true)`, and `goto returning` is `break` out of the dispatch loop (the dispatch is an
if-chain after P7.0c, so `break` leaves the inner `while`); `ret:` has a three-line tail that
ends in `return` or `goto returning`, so it is inlined at its four sites (OP_TAILCALL,
OP_RETURN, OP_RETURN0, OP_RETURN1's own fall-through). When a tail is long the coder keeps one
copy after the dispatch loop under a named bool (`returned`), the second form in the sketch
file; the kernel measures both. `l_tforcall`/`l_tforloop`: OP_TFORPREP ends with
`i = *(pc++); goto l_tforcall`, and l_tforcall ends with `i = *(pc++); goto l_tforloop`; the
structured form inlines OP_TFORCALL's body into OP_TFORPREP and OP_TFORLOOP's body into both
(a forward goto into the next case whose body ends in `vmbreak`: shape 3 with a long body; a
helper `def private tforcall(...)` is the alternative, a coder's call). Lua's own
`LUA_USE_JUMPTABLE` build does the same with `vmfetch` macros.

`luaH_get` (shape 3, fall-through into a one-statement default):

```
def luaH_get(var t : Table?; var key : TValue?) : TValue? {
    let tag = int(key.tt_) & 63
    if (tag == 4) {
        return luaH_getshortstr(t, addr(reinterpret<GCUnion?>(key.value_.gc).ts))
    } elif (tag == 3) {
        return luaH_getint(t, key.value_.i)
    } elif (tag == 0) {
        return addr(absentkey)
    } elif (tag == 19) {
        var k : int64
        if (luaV_flttointeger(key.value_.n, addr(k), F2Imod.F2Ieq) != 0) {
            return luaH_getint(t, k)
        }
        return getgeneric(t, key, 0)
    } else {
        return getgeneric(t, key, 0)
    }
}
```

`str_format`'s `intcase` (shape 2, every goto is the last statement of a prefix-only group):

```
    } elif (c == 'd' || c == 'i' || c == 'u' || c == 'o' || c == 'x' || c == 'X') {
        if (c == 'd' || c == 'i') {
            flags = "-+0 "
        } elif (c == 'u') {
            flags = "-0"
        } else {
            flags = "-#0"
        }
        var n : int64 = luaL_checkinteger(L, arg)        // intcase:
        checkformat(L, addr(form[0]), flags, 1)
        addlenmod(addr(form[0]), "ll")
        nb = snprintf(buff, uint64(maxitem), addr(form[0]), n)
    }
```

`read_string` (shape 4, a cascade of three labels): the escape chain assigns `c` and a choice
`escape : Escape` (an enum named from the labels), then `if (escape == Escape.read_save) { next(ls) }`
and `if (escape != Escape.no_save) { ls.buff.n -= 1; save(ls, c) }`. `read_long_string`'s
`goto endloop` from inside the if-chain becomes `break` (the label is the statement after the
loop). `luaD_pretailcall`'s `retry:` becomes `while (true) { if (tag == ...) { return ... } ...
else { func = tryfuncTM(L, func); narg1++; continue } }` (shape 1). `correctgraylist`'s
`remove`/`remain` are two-statement tails ending in `continue`: inlined at the four sites
(shape 2, short). `match`'s `dflt` needs a guard hoist first: `case '$': if (p + 1 != ms.p_end)
goto dflt; ...` becomes `elif (c == '$' && p + 1 == ms.p_end)` and the inner switch's
`default: goto dflt` becomes the inner chain's missing `else`, so `dflt` is the outer `else`;
then `init` is shape 1 with five `continue`.

## Measured effect

Kernel `kernels/exec_backjump.c`: the audit's `dispatch_switch` (48 cases, 64 "instructions",
hot opcodes late) with luaV_execute's frame on top: `startfunc:` / `returning:` above the
`for (;;)`, a frame stack of depth 3, `goto startfunc` on opcode 40 (OP_CALL), `goto ret` from
41 and 42, `ret:` inside 46's case (fall-through), `goto returning` from `ret`. Composed by the
dasProfile method (`perf_compose.das`), converted by the converter, each hand spelling edited
from that output by `gen_hand.py`; five samples per lane, each its own process, the median
(`perf_measure.das`), the result checked against native (2693995 everywhere). Seconds per
run; the box was shared with three coders (load 5-6 on 16 cores).

| spelling | what it is | interp | x native | JIT |
|---|---|---|---|---|
| native | clang -O3 | 0.000157 | 1 | |
| converted | today: flag loop, `_goto`, re-dispatch, das labels | 0.0568 | 362 | 0.000127 |
| ifchain | P7.0c alone: plain cases as `if (_goto == 0 && _cond == K)`, `ret` and the fall-through case keep the flag, re-dispatch kept | 0.0291 | 185 | 0.000132 |
| structured | the proposal with one copy of `ret` under a named bool (`returned`) and `fresh` | 0.0157 | 100 | 0.000166 |
| structured_goto | if-chain, `ret` inlined, das `goto label` to the two top labels kept | 0.0141 | 90 | 0.000109 |
| structured_inline | the proposal as sketched: `ret` and the startfunc line inlined, no bool, no label | never ends (daslang bug, below) | | |
| structured_inline_pad | the same with one statement after the inner loop | 0.0144 | 92 | 0.000153 |

(`results_run3.json`, five samples, spread 3-9 percent; run 1 in `results_run1.json` agrees
except for a noisier `converted` cell.)

Ratios: converted / ifchain 1.95x, the audit's `dispatch_switch` cell for the same rewrite
(2.08x) reproduced; ifchain / structured 1.86x and ifchain / structured_inline_pad 2.02x: that
is what this item adds on top of P7.0c; converted / structured_inline_pad 3.96x in all.
Against the audit's cells (`perf/audit_linux.json`: converted 0.105 s, if-chain 0.051 s, Rust
computed goto 0.006 s on 128k dispatches), this kernel dispatches fewer instructions per run
(each round ends at the first return at depth 0), so only the ratios compare, not the times.
The JIT is within noise for every spelling (0.7-1.1x native, the kernel is tiny). `goto label N`
to a function-top label costs the interpreter no more than `break` out of the nested `while`
(structured_goto 0.0141 against structured_inline_pad 0.0144): a das goto sets `stopFlags` and
unwinds block by block exactly as `break` does (`SimNode_BlockWithLabels::eval`,
`simulate.cpp:611`); what costs is the re-dispatch, the `_goto == 0 &&` term on every case
test, the `_flag` chain, and `c_label_end()` (a call per label pass under the interpreter).
So the structured form wins on speed by removing the state machine, not by avoiding the label
node; it wins on readability by removing both. The bool form (`structured`) costs 9 percent
over the inlined one for its two tests per frame switch.

A daslang bug found on the way (`probe_nested_loops.das`, 40 lines, no modules): a `private`
function whose body is an outer `while (true)` ending in an inner `while (true)` that holds a
`return` never returns under the interpreter with the optimizer on. The same function public,
or `options optimize = false`, or any statement after the inner loop, or the `return` moved
after the inner loop, runs and prints the right value. The converter writes every static C
function as `def private`, and the proposal's exact sketch is this shape, so the coder emits
the named-bool form (`structured`, the `if (returned)` after the inner loop is the statement
that saves it) until the bug is fixed in `lookibed/daScript`, or the inlined form with the
tail after the loop. The pattern matches F60's family (a loop node claiming a goto numbered
below its label count; a private function's inlined `return` is such a goto): a hypothesis,
not checked in the daScript source. The lead files it; the probe is the repro.

On the real port: fib's returns are OP_RETURN1 (one result), which reaches `ret` by fall-through,
not by re-dispatch, so fib pays today's `_goto == 0 &&` term on every case test it walks (OP_ADD
is case 35 of 83, OP_CALL 69, OP_RETURN1 73) but no re-dispatch; OP_RETURN (several results),
OP_RETURN0 and the C-function tail call re-dispatch through 70-odd tests each. The 1.9x of
this kernel over P7.0c is therefore an upper bound for fib and nearer the mark for code that
returns nothing or many values; the item's PR measures the four benches before and after.

## Where in the converter

`converter/tiers.das` is the execution tiers (interp/jit/exe/aot), not the lowering tiers; the
switch ladder lives in `docs/lowering-examples.md` "switch - three-tier ladder" and in
`converter/emit.das`. The change, in order:

1. `converter/emit.das` `walk_labels` (3453) and `plan_labels` (3337): classify every label by
   its gotos. New fields on `LabelPlan` (3325): for each label, whether all gotos are backward
   and the label stands at function top or directly before a loop (shape 1); whether all gotos
   are forward from case groups of one switch and the label's tail leaves the switch (shape 2);
   whether the label is in a cascade at the tail of one group (shape 4). `plan_cross_group`
   (3439) today marks every cross-group label as a re-dispatch case: it marks only the labels no
   shape takes.
2. `converter/emit.das` `goto_target` (3367) and `emit_goto` (4002): a goto of shape 1 emits
   `continue` (or `break` plus the inlined prefix when the label is the outer of two top labels,
   as `startfunc`); shape 2 short emits the tail inline; shape 2 long emits `<label>_reached = true`
   and `break`; shape 4 emits `<choice> = <Enum>.<label>`. The re-dispatch branch stays for the rest.
3. `converter/emit.das` `emit_label` (3972): shape 1 opens `while (true)` around the statements
   from the label to the end of its block (the loop closes where the block ends; the block's
   tail after a `return` is unreachable and is left out); shape 2 emits nothing at the label and
   the tail after the switch loop (long) or nothing (short, inlined); shape 4 emits the guarded tails.
4. `converter/emit.das` `is_if_chain` (3646) and `emit_switch` (3698): a group that falls into the
   next whose body is at most N statements (N = 3 to start; `luaH_get`, `match` '+', `intcase`)
   is an if-chain group with that body appended (shape 3); a group whose every goto is the last
   statement of a straight-line prefix to a label heading a later group merges into that group
   (the `intcase` form). `emit_flag_loop` (3810) is unchanged: it is the fallback.
5. `converter/ARCHITECTURE_EMITTER_CONTROL.md` "Labels and goto" (`{#goto-labels}`, cited by
   `check_labelled_groups`, `plan_cross_group`, `emit_label`): the four shapes as present-tense
   statements, the state machine described as the fallback.
6. `docs/lowering-examples.md` "goto / labels" (line 119) says today: "Backward and forward jumps
   ✓; computed `goto expr` exists ... goto INTO a nested block: das label lookup is lexical-upward
   - converter flattens the target block into the parent scope first. goto into a loop body
   (Duff): switch state-machine fallback only." And "Tier 2 in full": "No labels, no goto: a
   single-iteration `while (true)` makes C `break` map verbatim". The documents are normative
   and `docs/` is never edited to match the code: the new tier is a ledger row (after P7.0k) and a
   lowering example per shape, the four examples given above, with the `retry`/`while (true)`
   form as the first.
7. Probes: `probes/test_goto.das` gains the nested `while (true)` with `break` from an if-chain
   branch under the interpreter and the JIT (F60/F63 concern labelled blocks; a loop without
   labels is the ordinary case, but the probe records it). Fixtures: `converter/tests/fixtures/`
   one C file per shape (`p5_lua_exprs.c` already has `match` and `execute`).
8. `lua/` re-conversion, the hashes, `perf/audit_constructs.das`: the `if_chain` rewrite's text
   no longer occurs in lvm once the switch is an if-chain; the audit's rewrite fails loudly by
   design, so its `dispatch_switch` construct is re-recorded or retired in the same PR.

## Size and risk

- Size: 250 to 400 lines in `emit.das` (planning 80, the four emitters 150, the if-chain
  extensions 60), 4 fixtures, 4 lowering examples, 1 probe, the architecture section rewritten,
  the Lua hashes. One PR per shape is possible (shape 1 and 3 are small and independent; shape 2
  carries luaV_execute; shape 4 is llex only). Estimated 2 to 3 coder sessions in all.
- Tests: each fixture converted and run under interp and JIT against native; the Lua suite (the
  lexer's escapes `\z`, `\u`, `\ddd` exercise shape 4; `string.format("%d")` shape 2;
  `string.find` with `$` and `%b` shape 1 and the guard hoist; every table read shape 3).
- What can break: a shape-1 loop placed around statements that a later label or an outer goto
  also reaches (the recognizer refuses when any other label sits inside the would-be loop);
  shape 2's inlined tail duplicating a declaration (refuse when the tail declares); a C
  `continue` inside the new `while (true)` of shape 1 that meant the outer loop (`_cont` logic
  of `emit_flag_loop` applies; refuse at first); the guard hoist moving an expression with side
  effects (refuse unless the guard is a pure comparison of locals and loads).
- Interactions: P7.0c is the precondition (the dispatch loop must be an if-chain for `break` to
  leave it); its computed-goto opt-in is unaffected (a `goto <expr>` jump table still needs the
  cases as labelled blocks; the shapes here act before that choice and leave the `ret` tail
  after the loop, which the jump table reaches by `break` too). P7.0e/d/g change expressions
  only. P7.0j (comments) wants the C labels' names kept as comments on the `while`/`break`
  lines, as the sketch does. P7.7 (Duff) keeps the state machine as its fallback.

## Verdict

Readable-default. Faster (3.6x to 4.0x over today, 1.9x to 2.0x over P7.0c on the kernel under the interpreter,
JIT unchanged) and more readable (no labels, no `_goto`, no `c_label_end`, the C's own control
shape back). Ruling 23's first clause applies: the structured form is the default and needs no
flag. The state machine is not an option; it is the fallback for shapes the recognizers refuse.

## Open questions

1. The inline threshold for a shared tail (shape 2 short) and a fall-through body (shape 3):
   3 statements? `ret` is 4 (with the `if`), `remove`/`remain` 2, `luaH_get` 1. Proposal: tails
   of at most 4 statements with no declaration inline; longer ones take the named-bool form.
2. `l_tforcall`/`l_tforloop`: inline OP_TFORCALL's body into OP_TFORPREP (it is 12 lines) or a
   private helper per label? Inline keeps the C's reading order; the helper is shorter.
3. The named bool's name: `<label>_reached`, or the label's name itself (`returned` from `ret`
   is a human choice the converter cannot make; `ret_reached` is mechanical but honest).
4. Does the computed-goto opt-in (P7.0c) want the `ret` tail inside the jump table as its own
   label? If so shape 2 long emits the bool form under that flag as well; the short form is
   independent of it.
5. The daslang bug above: filed as lookibed/daScript#33 (the probe is the repro) 2026-11-02 01:35Z; watch it before the
   item starts, since it decides whether the inlined form or the bool form is the default
   spelling; the bool form is safe today.
6. The guard hoist for `match`'s `dflt`: a separate small recognizer (a case whose first
   statement is `if (pure) goto <default label>`), or leave `match` on the state machine? It is
   one function; the first is 40 lines and makes `init` a plain loop.
