# 02-temporaries: machine temporaries, self-assignments, stray braces

Research note, 2026-11-02, branch `research/idiomatic`. Prototypes in
`/root/wt-research/research/02-temporaries/` (kernel `pinned_copy.c`, the converted and the
hand-folded module under `composed/out/`, `measure.sh`, `measure.log`, `measured.json`,
`classify_temps.py`, `proposed_lua.das`).

## For the owner

The problem. The converter proves C's evaluation order by spelling every side effect inside an
expression as its own statement first, with a numbered temporary (`_t0`, `_t1`, ...). The Lua
port has 468 such declarations, 24 `_first` loop flags, 901 lines holding a lone `{`, and one
`L.top.p = L.top.p`. Most of this is correct but needless: the temporary is read once, on the
next line, and nothing in between could change what it holds.

What a human port writes. `b.b[b.n] = *strfrmt; b.n++; strfrmt++` instead of three temporaries;
`if (!(cond)) argerror()` instead of `let _t0 = cond || argerror()`; `true` instead of `1 != 0`;
a `while (true) { ...; if (!(c)) break }` instead of a `_first` flag; no `{ { ... } }`.

The proposal. Six small rules in the emitter, each a local check with a strict safety test:
(T1) a postfix step whose old value is read exactly once, by the statement it sits in, with no
call, no volatile read and no other mention of the stepped object in that statement, is written
as the plain read followed by the step; (T2) a discarded `a || f()` or `a && f()` is an `if`,
and a discarded expression with no effect is no statement; (T3) `1 != 0` is `true`; (T4) a
do-while without `continue` tests its condition at the bottom, no flag; (S1) a store of an
object into itself, no volatile, is not printed; (B1) a bare C block that is the only statement
of its parent, or declares nothing that clashes, loses its braces. The ternary temporaries (133
in lvm, llex and ldo) stay: das cannot carry statements inside `?:`.

What it buys. In lvm/llex/lstrlib/ldo, 122 of 313 temporaries go (the postfix class), 28 discards
become `if`s, 4 `1 != 0` become `true`, all 24 `_first` flags go (no body holds a `continue`), and 482 of the 901 lone
braces go by clause (a) alone (a block that is the sole statement of a headed body; 45 of them
are `{ {` pairs). Speed: the folded kernel runs 1.15x
faster under the interpreter (fewer locals and copies) and the same under the JIT (0.91x,
inside the sample spread). So this is a readability change that costs nothing at run time.

What it costs. About 250 lines in `converter/emit.das` across three small PRs, plus tests; two
days of coder time with the review round. The risk is evaluation order: the ledger records two
past bugs of exactly this family (`arr[k++].a++`, `*p++ = *q++`), and the safety tests above
are what keeps them out. The fixtures and probes that pin those bugs exist and stay green.

Verdict under ruling 23: readable-default, no flag. The readable form is at least as fast.

## The C

- Postfix step as a value: `lstrlib.c:1283-1284`

```c
    if (*strfrmt != L_ESC)
      luaL_addchar(&b, *strfrmt++);
```

  where `lauxlib.h:207-209` defines

```c
#define luaL_addchar(B,c) \
  ((void)((B)->n < (B)->size || luaL_prepbuffsize((B), 1)), \
   ((B)->b[(B)->n++] = (c)))
```

  One statement, three effects: the discarded `||` (a call on its right), the index `n++`, the
  argument `strfrmt++`.

- A discarded `||`: `lauxlib.h:133-134`, `luaL_argcheck(L, cond, arg, msg)` is
  `((void)(luai_likely(cond) || luaL_argerror(L, (arg), (extramsg))))`; 27 sites in lstrlib.c.

- `1 != 0`: `lvm.c:130`, `return lua_numbertointeger(f, p)`, the macro is
  `(n) >= ... && (n) < ... && (*(p) = (LUA_INTEGER)(n), 1)`: a `&&` whose right side holds a
  store and the literal `1`.

- The self-assignment: `lvm.c:1588`, `checkGC(L, L->top.p)` in OP_CONCAT; `lvm.c:1134-1137`
  expands to `luaC_condGC(L, (savepc(L), L->top.p = (c)), updatetrap(ci))`, and `lgc.h:167-169`
  to `{ if (G(L)->GCdebt > 0) { pre; luaC_step(L); pos;}; condchangemem(L,pre,pos); }`. With
  `c` = `L->top.p` the `pre` is `L->top.p = L->top.p`. The other two callers pass `ra + 1`.

- The do-while: `lstrlib.c` `nospecials`, `do { ... } while (upto <= l);` and 23 more; no body
  among the 24 holds a `continue` at the loop's own level (a brace-depth scan over the port).

- Braces: `ldo.c:91-108` `luaD_seterrorobj`, every `case X: { macro; break; }` where the macro
  (`setsvalue2s`, `setobjs2s`) is itself a `{ ... }` block with its own locals (`io`, `x_`,
  `io1`, `io2`); `lgc.c:1585` `singlestep`, the same shape with plain statements.

## Today's das

`lua/work/lua/lstrlib.das:1303-1309` (the `luaL_addchar` site):

```
        if (int(deref(strfrmt)) != 37) {
            let _t0 = addr(b).n < addr(b).size || luaL_prepbuffsize(addr(b), uint64(1)) != null
            let _t1 = addr(b).n
            addr(b).n++
            var _t2 = strfrmt
            strfrmt = strfrmt + 1
            deref(addr(b).b + _t1) = deref(_t2)
```

`lua/work/lua/lstrlib.das:304` (a `luaL_argcheck`):

```
            let _t0 = int64((c <= uint64(127 * 2 + 1) ? 1 : 0) != 0 ? 1 : 0) != 0 || luaL_argerror(L, i, reinterpret<uint8?>("value out of range")) != 0
```

`lua/work/lua/lvm.das.inc:36-41` (`luaV_flttointeger`):

```
    var _t0 = f >= double(-9223372036854775807l - 1l) && f < -double(-9223372036854775807l - 1l)
    if (_t0) {
        deref(p) = int64(f)
        _t0 = 1 != 0
    }
    return _t0 ? 1 : 0
```

`lua/work/lua/lvm.das.inc:2863-2870` (OP_CONCAT's `checkGC`):

```
                        {
                            {
                                if (L.l_G.GCdebt > int64(0)) {
                                    ci.u.l.savedpc = pc
                                    L.top.p = L.top.p
                                    luaC_step(L)
                                    trap = c_volatile_load(ci.u.l.trap)
```

`lua/work/lua/ldo.das.inc:15-41` (`luaD_seterrorobj`, the `{ {` pairs):

```
    if (_cond == 4) {
        {
            {
                var io : TValue? = addr(oldtop.val)
                var x_ : TString? = L.l_G.memerrmsg
                io.value_.gc = addr(reinterpret<GCUnion?>(x_).gc)
                io.tt_ = uint8(int(x_.tt) | 1 << 6)
            }
        }
    } elif (_cond == 0) {
        {
            addr(oldtop.val).tt_ = uint8(0 | 0 << 4)
        }
```

`lua/work/lua/lstrlib.das:885-892` (`nospecials`, the `_first` flag):

```
    var _first = true
    while (_first || upto <= l) {
        _first = false
        if (crt::strpbrk(p + upto, reinterpret<uint8?>("^$*+?.([%-")) != null) {
            return 0
        }
        upto += crt::strlen(p + upto) + uint64(1)
    }
```

### Where each temporary comes from (`converter/emit.das`)

Every `_tN` is minted by `temp_name` (line 432) and hoisted through `em.pre` (`hoist`, line 428;
`pin_value` pushes to `em.pre` directly). The sites, and the class each makes:

| Class | Emitter site | Shape | Can it go? |
|---|---|---|---|
| A. postfix old value | `emit_unary`, 1816-1829 | `let _t = x` then `x++` (or `x = x + 1`) | yes, rule T1 |
| B. pinned lvalue part | `pin_value`, 2359-2374 (from `pin_lvalue`, 2329) | `var _t = p` for a pointer, index or base with an effect, every spelling of the target reads it | with A when the effect is A's step; otherwise stays (a call in the target) |
| C. ternary with a hoisted arm | `emit_cond`, 1793 | `var _t : T` + `if`/`else` | no: das `?:` carries no statements |
| D. `&&`/`\|\|` with a hoisted right side | `emit_binary`, 1684 | `var _t = lhs` + `if (_t) { ...; _t = rhs }` | stays; its `_t = 1 != 0` goes (T3) |
| E. discarded value | `emit_effect`, 2644 | `let _t = e` for an expression statement that is no call, store or step | yes, rule T2 |
| F. do-while flag | `emit_do`, 2997 | `var _first = true` | yes without `continue`, rule T4 |
| G. callee that is itself a call | `emit_call`, 1363 | `let _t = f()` before `invoke(_t, ...)` | no (JIT crash, F in probes/test_functions) |
| H. compound literal, init-list item, alloca, volatile discard | 2535-2543, 2392, 1196, 2638 | `var _t : T`, `let _t = item`, arena guard, one load | no; none in Lua's hot files |

Counts, per file, by `classify_temps.py` (a per-function pass, since the numbering restarts per
function):

| File | `_tN` decls | A postfix | C ternary | D flag | E discarded | `_first` | lone `{` | `{ {` pairs | self-assign |
|---|---|---|---|---|---|---|---|---|---|
| lvm.das.inc | 129 | 7 | 93 | 28 | 1 | 3 | 264 | 38 | 1 |
| llex.das.inc | 119 | 80 | 39 | 0 | 0 | 1 | 30 | 0 | 0 |
| lstrlib.das | 59 | 31 | 0 | 1 | 27 | 4 | 55 | 0 | 0 |
| ldo.das.inc | 6 | 4 | 1 | 1 | 0 | 0 | 33 | 2 | 0 |
| whole port | 468 | | | | | 24 | 901 | | 1 |

Class B is folded into A by the classifier (the `var _t2 = strfrmt` of the example is B made for
A's step). The 150 lone `{` of lvm that directly follow a headed line (`elif (...) {`, `if (...) {`)
are the C case-body blocks; 38 are `{ {` macro expansions.

## Proposed das

Rule by rule. Every rule is a local decision on one statement; none reorders two effects.

T1, postfix step as a value. Test, all four must hold: the stepped lvalue `x.a` has no effect of
its own (`!has_effects(x.a)`) and is not volatile; the statement that reads the old value holds no
call (a call could read or write the object through a pointer or as a global); the statement
mentions the stepped object nowhere else (`same_lvalue` against every lvalue subexpression, and
no `deref` or index through the same pointer); the old value is read once. Then the read spells
the lvalue itself and the step lands after the statement. Two steps on distinct objects in one
statement (`*d++ = *s++`, `b[n++] = *s++`) both sink, in source order; C leaves their mutual
order unsequenced, so any order is right. An assignment read as a value (`if ((*d++ = *s++))`)
reads the target after the store and before the step, which is what the fold gives.

```
            if (!(addr(b).n < addr(b).size)) {
                luaL_prepbuffsize(addr(b), uint64(1))
            }
            deref(addr(b).b + addr(b).n) = deref(strfrmt)
            addr(b).n++
            strfrmt = strfrmt + 1
```

(T2 gave the `if`; the `addr(b).n` spelling is critic [^7], not this topic.)

T2, discarded value. In `emit_effect`: a discarded `a || b` is `if (!(a)) { effect(b) }`, a
discarded `a && b` is `if (a) { effect(b) }`, which is the shape `void_conditional` already gives
a `void` ternary; a discarded expression with no effect and no volatile read is no statement
(C's semantics: an unused pure value). The `let _t3 = g[0]` the architecture names for `(void)
g[0]` goes with it; a volatile discard keeps its load (today's separate branch).

T3, `1 != 0`. `to_bool` on a text that is a decimal literal spells `true` or `false`:

```
    if (_t0) {
        deref(p) = int64(f)
        _t0 = true
    }
```

(A later peephole could drop the `_t0 = true` inside `if (_t0)` altogether. Optional.)

T4, do-while without `continue`. The condition moves to the bottom, no flag; a body with a
`continue` at its own level keeps today's flag, since the probe pins that `continue` reaches
the condition:

```
    while (true) {
        if (crt::strpbrk(p + upto, reinterpret<uint8?>("^$*+?.([%-")) != null) {
            return 0
        }
        upto += crt::strlen(p + upto) + uint64(1)
        if (!(upto <= l)) {
            break
        }
    }
```

With effects in the condition (`while (--n > 0)`) the condition's hoisted statements go before
the `if (!(c))` at the bottom, which is the form `emit_do` already uses for them, minus the flag.

S1, self-assignment. An assignment statement with no `op` whose right side, below its
`LValueToRValue` cast, is `same_lvalue` to the target, the target not volatile and without an
effect, is not printed. The OP_CONCAT site becomes:

```
                        if (L.l_G.GCdebt > int64(0)) {
                            ci.u.l.savedpc = pc
                            luaC_step(L)
                            trap = c_volatile_load(ci.u.l.trap)
                        }
```

A volatile self-store stays (`c_volatile_store(x, c_volatile_load(x))`, an access C keeps). A
self-store through a bitfield or marshal field is harmless to drop too (the value already fits),
but the rule may leave those alone for simplicity.

B1, bare blocks. A C compound statement loses its braces when it is (a) the only statement of
a headed body (a case group, an `if`/`else` arm, a loop body), or (b) a direct child of another
block whose own declarations clash with no declaration of the parent block or of a sibling
block that is flattened too; and in either case it holds no `label`. gen2 das keeps a block
after `if`, `while`, `for`, `elif`, `else`, and the switch lowering's case body is the if-chain's
block, so only nested lone blocks go; a bare block that remains a bare block is legal gen2.
das refuses a local that hides an enclosing local and sibling blocks reuse a name
(`probes/test_scalars.das:148`), so clause (b) is the whole scope question. `luaD_seterrorobj`:

```
    if (_cond == 4) {
        var io : TValue? = addr(oldtop.val)
        var x_ : TString? = L.l_G.memerrmsg
        io.value_.gc = addr(reinterpret<GCUnion?>(x_).gc)
        io.tt_ = uint8(int(x_.tt) | 1 << 6)
    } elif (_cond == 0) {
        addr(oldtop.val).tt_ = uint8(0 | 0 << 4)
    } else {
        var io1 : TValue? = addr(oldtop.val)
        var io2 : TValue? = addr((L.top.p - 1).val)
        io1.value_ = io2.value_
        io1.tt_ = io2.tt_
    }
    L.top.p = oldtop + 1
```

A case body with two `setobj` expansions side by side (two `{ var io1 ... }` siblings) keeps
the inner braces by clause (b) and loses only the outer pair. Lifetime: a das local lives to its
block's end, so flattening only lengthens a C object's life, never shortens it; a block inside a
loop body stays inside the loop body, so per-iteration re-initialization is unchanged.

## Measured effect

Kernel `research/02-temporaries/pinned_copy.c`: `while (s < src + 255 && (*d++ = *s++))`, a
`while (k < 255) { arr[k++].a++; ... }` loop and 255 discarded `(void)(dst[i] == src[i] ||
on_fail(1))` per round, 2000 rounds, both ledger families and the discard class. Converted by
the converter, then hand-folded into T1 + T2 form (`composed/out/pinned_copy_folded.das`; the
diff is the three folds of the Proposed section, nothing else). Method of `perf_compose.das`:
a 0.5 s budget loop, five processes per cell, medians, native `clang -O3 -w -funsigned-char`.
Every cell printed the same result (576045000), so the fold is behavior-preserving on this kernel.

| Lane | s per run (median of 5) | vs native | vs converted |
|---|---|---|---|
| native | 0.000508 | 1.00 | |
| converted interp | 0.0614 | 121x | 1.00 |
| folded interp | 0.0536 | 106x | 1.15x faster |
| converted JIT | 0.000560 | 1.10x | 1.00 |
| folded JIT | 0.000613 | 1.21x | 0.91x (inside the spread: 532..627 us vs 552..733 us) |

So: a small interpreter gain (fewer locals, fewer copies), nothing measurable under the JIT.
As expected, this is a readability change with no speed cost, which makes it the default per
ruling 23 without a flag. Raw lines: `measure.log`; numbers: `measured.json`.

## Where in the converter

In order, each a small PR.

PR 1, temporaries (T1, T2, T3):

1. `converter/emit.das` `emit_unary` (line 1816, the `postinc`/`postdec` branch): when the
   enclosing statement passes the T1 test, return the plain `lvalue_read` and push the step to a
   new `em.post` list instead of `em.pre`. The test needs the statement-level expression, so
   `emit_effect` (2611), the `return`, `if`, `while` and `decl` initializer paths set
   `em.stmt_expr` (or a precomputed `em.sinkable : table<uint64>` of step nodes that
   `plan_sinks(stmt_expr)` fills before the statement is spelled: one step per object, no call,
   no other mention of the object, `!has_effects(x.a)`, not volatile). `flush_pre` (410) empties
   `em.pre`, the statement is printed, then `em.post`. The `pin_lvalue` of the step's own target
   is skipped for a sunk step (nothing to pin: the target has no effect by the test).
2. `emit_effect` (2644): the `land`/`lor` discard as an `if` (reuse `void_conditional`'s shape;
   `em.narrow` must be raised while the right side is spelled, as `emit_binary` does); the pure
   discard dropped. `ARCHITECTURE_EMITTER.md` line 204 (the `let _t3 = g[0]` sentence) is
   restated.
3. `to_bool` (693): a decimal-literal text is `true`/`false`.

PR 2, identity statements and the do-while (S1, T4):

4. `emit_effect` (2619, the `assign` branch): the S1 test with the existing `same_lvalue` (1039)
   and `has_effects` (2306); nothing printed.
5. `emit_do` (2993): a `has_continue(body, nested = false)` walk in the style of `leaves_loop`
   (3028); without one, the bottom-tested `while (true)` form, the condition's pre-statements
   before the `if (!(c))`; `ARCHITECTURE_EMITTER_LOOPS.md`'s do-while paragraph restated.

PR 3, braces (B1):

6. A `plan_bare_blocks(body, flatten)` pass beside `plan_labels` (3337, the goto flattening that
   already fills `em.flatten`, which `emit_compound` at 3903 honors): marks the compounds of
   clauses (a) and (b) with no label inside. `moved_decls` (4282) called from
   `unshadow_locals` (4241) already turns every flattened block's declarations into `w.moved`
   and `unshadow_stmt` (4198) renames a moved local that would hide a global or another local,
   so the clash rule of clause (b) can lean on it or be stricter (keep the braces instead of
   renaming, which reads better: `io1_1` is noise too).
7. `emit_compound` itself does not change; `ARCHITECTURE_EMITTER_CONTROL.md` line 36 (the bare
   block sentence) gains the new reason a block loses its braces.

Tests that cover temporaries today and must stay green:

- `converter/tests/test_lowerings.das:116` "statement-ification: assignment as expression,
  steps, comma, side-effecting arms"; `:123` "loops: while, do-while with the first-pass flag,
  ..."; `:939` "csmith shapes: ... discards are fresh ..." (this one asserts the `let _tN`
  discard and changes under T2); `:1000` "scope fidelity: ... a target with an effect is
  pinned"; `:1037` "scope fidelity edges: array members and pointer bases with effects, an
  else-if step, a C name spelled like a temporary ..."; `:1278` "a `void` conditional whose
  arms have no effect is no statement".
- Fixtures: `converter/tests/fixtures/p4_scope_fidelity.c:114-115` (`arr[k++].a++`,
  `++arr[k++].a`), `:140` (`while ((*d++ = *s++))`), `:158-159` (`(a[i++] = 9)`), `:177`
  (`(p[n++].bf += 4)`); `p5_lua_exprs.c:92,181,185` (`code[pc++]`, `out[n++] = *s++`);
  `p1_statements.c`, `p7_loops.c`, `p4_csmith_walks.c`.
- Probes: `probes/test_loops.das:18` "do-while first-pass flag: condition skipped on entry,
  tested after every pass including continue" (T4 keeps the flag exactly where this probe
  needs it); `:128` "a range loop evaluates its start and its end once"; `probes/test_scalars.das:116`
  "a ternary evaluates only the taken arm"; `:148` "a local that shadows an enclosing local is
  refused, `_` included; sibling blocks reuse a name" (B1's scope rule).
- Ledger lines of the past order bugs: `docs/implementation_order.md:447-455` (P4.8's ledger:
  `int v = arr[k++].a++` printed `0 2 0 1` for gcc's `0 1 1 0`; `if ((*p++ = *q++))` printed
  `0 2` for `1 1`; `while ((*d++ = *s++))` copied nothing; P2.4's `(*next())++`). The
  differential suites (`suites/`, csmith) are the backstop: every fixture runs against native.

## Size and risk

Size: T1 about 100 lines (the sink plan and the `em.post` plumbing), T2 20, T3 5, S1 10, T4 25,
B1 60 to 90; tests about 150 lines across the three test groups plus a fixture
`p7_temporaries.c` with the Lua shapes (`luaL_addchar`, `luaL_argcheck`,
`lua_numbertointeger`, `checkGC`, a `do`/`while` with and without `continue`, `{ { } }` case
bodies with clashing and non-clashing locals). Three PRs under 600 lines each.

Risk, in order:

- Evaluation order (T1). The one real risk. The test is conservative on purpose: any call in the
  statement, any second mention of the object, any effect in the target itself, any volatile,
  and the step stays hoisted as today. The four fixture lines above fail loudly against native
  if the rule is wrong. A subtle case: `x = a[i++] + a[i]` mentions `i` twice, so no sink (right:
  the second read must see the old `i`). Another: `p->n = f(p->n++)`: a call, no sink.
- T2 drops statements. A discarded pure expression can hide a trap in C (`(void) *p` with `p`
  null) that the das `let _t = deref(p)` reproduces today. C's abstract machine lets the compiler
  drop the read too, so dropping it is within C's semantics; note it in the architecture doc.
- B1 and scopes. The only failure mode is a duplicate local in one das block, which compiles
  red, never silently wrong; clause (b) prevents it, and `compile_check` over the Lua port and the
  suites catches a miss.
- T4 and `continue`. Covered by the probe; a `continue` inside a nested loop does not count.
- Interactions. P7.0c rewrites the case-group emission around `emit_switch` (3698-3835); B1's
  clause (a) applies to the case body's compound whatever the head looks like, so the two
  compose, but the braces PR should land after P7.0c or rebase onto it. P7.0e (`x != 0` truth
  test) shares the `to_bool` neighborhood with T3; trivial to merge. P7.0g (volatile load) and
  S1 do not meet: S1 excludes volatile. P7.0j (comments by source line) wants statements to keep
  their source line; sinking a step after its statement keeps it on the same C line, so no
  conflict. None of this touches the dumper or the C-IR.

## Verdict

Readable-default, no opt-in flag, for all six rules. Per ruling 23 the readable form is the
default where speed and readability pull apart, and here they do not pull apart at all: the
folded form is 1.15x faster interpreted and equal under the JIT. The critic's finding 6 and
finding 10's brace item are both answered by this without a mode.

## Open questions

1. T1's call test: may a call be allowed when the stepped object is a local whose address is
   never taken (a call cannot see it)? That covers `luaL_addchar(&b, *strfrmt++)` where
   `strfrmt` is such a local, and the discarded `||` call sits in the same C statement. Without
   the relaxation, T2 splits the statement first (the `||` becomes its own `if`), so the step's
   statement is the store alone and T1 applies anyway. Confirm the split happens before the sink
   test.
2. Should the ternary temporaries (class C, 133 sites) get a name from the C macro instead of
   `_tN` (`tonumber(o, n)` gives `var _t0 : int` 93 times in lvm)? That is a naming rule, out of
   this note's scope, and needs the macro name from the expansion location (P7.0k's machinery).
3. B1 clause (b): rename a clashing local (`io1_1`) or keep the braces? I propose keep the braces.
4. Does the readability metric (`criteria`) count `_tN` declarations and lone braces? It should,
   so the ratchet records the drop (today it counts neither, per the critic's metric column).
5. T2 and the `discards are fresh` test (`test_lowerings.das:939`) encode today's behavior; the
   coder rewrites that assertion, not the rule.
