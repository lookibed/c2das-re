# 04 - Benchmark profile: binary_trees (then nbody) under the interpreter

Status: 2026-11-02 night, complete: binary_trees and nbody measured.

## For the owner

The question was: where does the converted Lua spend its time on binary_trees under the
interpreter, and is each cost already on the ledger. Tonight binary_trees 12 runs about 15 s of
work after a 5 s load, against 0.2 s native: about 65x. Half of that work is one thing: the
converted `switch` of the VM loop tests the opcode against every case in turn, 83 tests, and the
hot opcodes (call, return, table build) sit at the end of the list. Moving 16 hot cases to the
front of the list by hand, nothing else changed, cut the run by a third; the whole chain is
about half the run. That is P7.0c's construct; its readable default (a plain if/elif chain)
halves the cost at best, and only its opt-in computed `goto` removes it. The next cost is new
and not on the ledger: every read of a C union member (`L.top.p`, `ra.val`, the value payload
of a Lua value: 7 or 8 per VM instruction) is a function call in daslang, because the union macro
generates a tiny accessor function that daslang's inliner refuses to inline (it is marked
`generated`, it lives in another module, and property functions cannot be `[inline]`). That is 5
to 8% of the run, and the right fix is in the daslang fork (let the inliner splice those one-line
accessors), not in the converter: the output does not change. The rest is small: the opcode's
enum cast (P7.0h, 2 to 3%), the call path (P7.0e/f, 3%), the allocator and GC call depth (4%),
a no-op label marker that is a real call (1%, new, trivial), the volatile trap read (P7.0g, under
1% here). After the chain, the union accessors, the enum cast and the marker, the benchmark would
run at about 20 to 25x native, which is the floor the audit measured for the Rust translation's
dispatch. The load (5 s for 28 modules) is a quarter of the wall time and is not a construct.
Verdict under ruling 23: nothing here changes the output's readability except the chain, which
P7.0c already decides; the union fix is a daslang change, default once it lands.

## Numbers: mine versus the committed capture

Committed capture (`perf/audit_linux.json`, P7.0b, Ryzen 7 7435HS, the former default layout with
slots, now called source-cut): startup 0.80 s, binary_trees 12 13.92 s, net 13.1 s; native 0.30 s,
net 0.2 s. The capture's "source" column is NOT today's source layout (P7.0a moved the cycles into
one module and the ledger says its start-up is 5.3 s against 1.0 s).

Mine, tonight, this box (16 cores, load 4 to 6 from three coders' jobs, one run each, wall clock,
source layout `lua/work/lua/lua.das`, `research/04-benchmark-profile/baseline.txt`):

| run | seconds |
|---|---|
| startup `-e print(1)` (after one warm run) | 5.05, 4.69 |
| binary_trees 12 | 18.65 (net about 13.8 s) |
| binary_trees 9 | 5.61 (net about 0.75 s) |
| binary_trees 6 | 4.54 (net under the resolution) |
| native startup | 0.003 |
| native binary_trees 12 | 0.216 |

Net factor over native tonight: 13.8 / 0.21 = about 65x. The load (about 4.9 s) is not run time:
every per-construct share below is a share of the 13.8 s net, and the 4.9 s load is its own row
in the table (not a construct, see "costs that are not constructs").

## The expected costs, before running (the C and the das)

binary_trees builds `{ bottom_up(d), bottom_up(d) }` trees and walks them with `check`. One node
costs about 20 VM instructions: in `bottom_up` EQI, JMP, ADDI, GETUPVAL, MOVE, CALL (twice),
NEWTABLE, SETLIST, RETURN1; in `check` GETI, TEST, GETUPVAL, GETI, CALL (twice), ADD, ADD,
RETURN1 (a leaf: GETI, TEST, LOADI, RETURN1). Depth 12 builds about 680 k nodes, so about 14 M
instructions in 13.8 s: about 1 us per VM instruction (native Lua spends 5 to 10 ns).

The C: `lvm.c:1184` `vmdispatch (GET_OPCODE(i)) { vmcase(OP_MOVE) ...` with `LUA_USE_JUMPTABLE=0`
(the sidecar), so a plain `switch`; the cases `lvm.c:1280` OP_GETI, `:1364` OP_NEWTABLE, `:1659`
OP_TEST, `:1676` OP_CALL, `:1758` OP_RETURN1, `:1848` OP_SETLIST. Behind them `ltable.c:745`
`luaH_getint`, `:626` `luaH_new`, `:553` `luaH_resize`, `:480` `setnodevector`; `lgc.c:1690`
`luaC_step`, `:1667` `incstep`, `:1585` `singlestep`, `:258` `luaC_newobjdt`; `ldo.c:595`
`luaD_precall`, `:509` `prepCallInfo`, `:492` `luaD_poscall`, `:440` `moveresults`; `lmem.c:201`
`luaM_malloc_`; `lauxlib.c:1026` `l_alloc`. The value types `lobject.h:49` `union Value`, `:67`
`TValue`, `:148` `union StackValue`, `:699` `union Node`, `:737` `Table`.

Today's das (`lua/work/lua/lvm.das.inc`, the `lcode_cluster` module):

1. The dispatch, `lvm.das.inc:908-915`: `let _cond = enum_from_int(type<OpCode>, ...)`, then
   `while (true) { label 1: var _flag = false; _flag ||= _goto == 0 && _cond == OpCode.OP_MOVE;
   if (_flag) {...; break}; _flag ||= _goto == 0 && _cond == OpCode.OP_LOADI; ...` - 83 cases in
   enum order, one `||=` test each, so an instruction pays as many tests as its enum position:
   GETI 13, NEWTABLE 19, ADDI 21, ADD 34, JMP 56, EQI 61, TEST 66, CALL 68, RETURN1 72,
   SETLIST 78. The audit's `dispatch_switch` kernel (48 cases, hot ones late) puts a chain test
   at about 9 ns under the interpreter (0.105 s - 0.051 s over 128 k dispatches, 48 tests each),
   so the chain alone is 300 to 700 ns of the ~1 us per instruction here. Covered by P7.0c; but
   note that P7.0c's default (plain `if/elif` cases) is still a linear chain of 83 tests, about
   half the cost at best (the kernel's `if-chain` cell is 0.051 s against native 0.00025 s); the
   computed `goto` opt-in is the form that removes it (the Rust translation's 23.9x native).
2. Every `[c_union]` member read or write is a call, `lvm.das.inc` everywhere: `addr(ra.val)`
   (StackValue is a union), `L.top.p` and `ci.func.p` (StkIdRel), `rb.value_.gc`, `io.value_.i`
   (Value), `reinterpret<GCUnion?>(o).h` (`.h` of GCUnion is a union member too), `n.u.key_val.i`.
   `c_runtime/c_runtime/c_union.das:177` generates `operator . name` per member with
   `fn.flags.generated = true`; daslang's heuristic inliner refuses it twice
   (`src/ast/ast_inline.cpp:652` `if (fn->generated) return false;` and `:654` cross-module), and
   `[inline]` "does not support property functions" (`:1533`). NEW: no audit construct isolates it
   (`union_access.c` has `union Value` in both of its cells). My probe
   (`research/04-benchmark-profile/union_probe.das`, 2.56 M reads, 5 samples, medians): accessor
   46 ms, the accessor's body inline 27 ms, a plain field 20 ms under the interpreter; under the
   JIT all three 75 us. About 8 ns per access; a hot instruction makes 5 to 15 of them (OP_GETI
   about 6, OP_CALL with `luaD_precall` and `prepCallInfo` about 15).
3. `c_volatile_load(ci.u.l.trap)` after every jump, GETI miss, CALL (P7.0g, 1.32x on its kernel),
   and `int64(trap != 0 ? 1 : 0) != 0` at the top of the loop (P7.0e, 1.58x on its kernel).
4. `enum_from_int(type<OpCode>, ...)` once per instruction (P7.0h, 1.12x).
5. `reinterpret<GCUnion?>(rb.value_.gc).h` on every table access (P7.0f, 1.17x) and
   `addr((base + i).val)` (P7.0f, 1.53x) - the second is the `[c_union]` call of item 2 again.
6. The wrap compare `uint64(c) - uint64(1u) < uint64(...alimit)` in OP_GETI and `luaH_getint`
   (P7.0d's family, 2.10x on its kernel; one site per table read).
7. The allocation path per node: NEWTABLE -> `luaH_new` -> `luaC_newobj` -> `luaC_newobjdt` ->
   `luaM_malloc_` -> `invoke(g.frealloc, ...)` -> `l_alloc` -> `crt::realloc`; `setnodevector`
   (the dummy node); then SETLIST -> `luaH_resizearray` -> `luaH_resize` -> `setnodevector`,
   `luaM_realloc_` -> `invoke` -> `l_alloc` -> `crt::realloc`, `reinsert`, `freehash`. About 20
   das calls and two mallocs per node; the GC later `sweeplist` -> `freeobj` -> `luaH_free` ->
   `luaM_free_` x2 -> `invoke` -> `l_alloc` -> `crt::free`, and `propagatemark` ->
   `traversetable` -> `traversestrongtable` -> `reallymarkobject` (its own `_flag` chain, 9
   cases). Expected a minor share: about 40 das calls per node against 20 instructions at ~1 us.
8. The call: `luaD_precall` (`_cond == 6` branch), `prepCallInfo`, `luaE_extendCI` the first
   time; RETURN1 inline. Three das calls per Lua call; minor.

## The profile

Tool: daslang's instrumenting profiler (`--das-profiler --das-profiler-time-unit us`, the tree
summary folded by `research/04-benchmark-profile/tree_top.py` into self and inclusive time per
function; raw trees `profile_bt6.txt`, `profile_bt9.txt`). `perf` is not on the box. The profiler
distorts heavily here: binary_trees 9 runs 0.75 s net unprofiled and 26.9 s profiled (3.1 GB of
events, the 3G cap's edge), because it pays two agent dispatches per das call and this program
makes about 8 das calls per VM instruction. So the profile's times rank by call count more than by
real cost; what is trustworthy in it is the call counts and the inclusive shape. The real split
comes from the reorder delta below and the union probe above.

binary_trees 9 (747 378 VM instructions, the profiler's `main` 6.30 s): self time, calls, calls
per instruction:

| function | self s | calls | per instr |
|---|---|---|---|
| `luaV_execute` (the chain and the opcode bodies) | 2.14 (34%) | 1 | - |
| `enum_from_int` (the opcode cast) | 1.18 (19%) | 747 k | 1.0 |
| `lobject_h_cluster::.p` (StkIdRel union: `L.top.p`, `ci.func.p`) | 0.60 (10%) | 1.39 M | 1.85 |
| `.val` (StackValue union: `addr(ra.val)`) | 0.34 (5%) | 1.59 M | 2.1 |
| `luaD_precall` | 0.28 (4%) | 103 k | 0.14 |
| `.gc` (Value union) | 0.15 | 835 k | 1.1 |
| `.l` (Closure union: `cl.l` at every startfunc/returning) | 0.14 | 827 k | 1.1 |
| `c_volatile_load` | 0.10 | 285 k | 0.38 |
| `luaH_resize` | 0.09 | 51 k | - |
| `c_label_end` (the label marker, a real call) | 0.08 | 412 k | 0.55 |
| `l_alloc` -> `crt::realloc` | 0.08 | 207 k | - |
| `traversestrongtable` | 0.08 | 27 k | - |
| `.h`, `.cl`, `.i` (more union members) | 0.18 | 1.04 M | 1.4 |
| `prepCallInfo` | 0.07 | 103 k | - |

Union accessor calls in all: 5.7 M, 7.6 per VM instruction. Inclusive: `luaC_step` 0.55 s (8.7%
of the profiled time, 158 steps; generational mode, `lua.c` turns it on: `youngcollection`,
`atomic`, `propagateall`, `sweepgen`); the allocation path `luaH_new` + `luaH_resize` +
`luaM_*` + `l_alloc` about 0.35 s inclusive (5.5%). The das GC: see "costs that are not
constructs".

The reorder delta (`reorder_delta.txt`, `reorder_cases.py`, `lua_reorder/`, committed as `lvm_reorder.patch` against `lua/work/lua/lvm.das.inc` since generated output is not committed): a copy of
`lvm.das.inc` with 16 hot cases (CALL, SETLIST, TEST, GETI, NEWTABLE, ADD, EQI, JMP, GETUPVAL,
MOVE, ADDI, LOADI, GETTABUP, GETFIELD, MUL, SUB) moved to the front of the `_flag` chain, every
case block unchanged and the output byte-identical (md5 equal). binary_trees 12, two rounds
back to back, startup first: converted 19.99 and 21.38 s, reordered 14.88 and 15.97 s, startup
5.0 to 5.7 s in both. Net: converted about 15.3 s, reordered about 10.1 s: 5.2 s, 34% of the
run, is the chain tests those 16 opcodes no longer pay. From the opcode mix of the two Lua
functions (about 26 tests saved per instruction on average) that is about 20 ns per chain test
on this loaded box (the audit's idle Ryzen kernel said 9 ns), and the full chain (39 tests per
instruction on average, RETURN1 at 72 still paying) is about 0.8 us of the 1.5 us one instruction
costs tonight: about half the run.


## The table: cost -> share -> construct -> covered by -> what it takes

Shares are of binary_trees 12's net run time tonight (about 15.3 s; the load is a separate row).
The first row is measured by the reorder delta; the others are call counts from the profile
times the per-call cost of the kernel probes (union: 8 ns, a das call: about 20 ns), so they are
estimates within a factor of two.

| cost | share | construct (the das) | covered by | what it takes |
|---|---|---|---|---|
| 1. the dispatch chain | ~50% (34% measured on 16 opcodes, the rest estimated) | `_flag \|\|= _goto == 0 && _cond == OpCode.OP_X; if (_flag) {...}` x 83 per instruction, `lvm.das.inc:910-3560` | P7.0c | the default (plain `if/elif`) halves it at best, still a linear chain; the opt-in computed `goto <expr>` (daslang has it, `statements.rst` "label and goto") removes it: `converter/emit.das:3810 emit_flag_loop`, `:3739 emit_if_chain`, `:3698 emit_switch`. A cheaper third form that stays readable: emit the cases in a hot-first order is not legal in general (fall-through); but a binary split of the `elif` chain by case value (`if (_cond < 42) {...} else {...}`) is a 7-test chain for 83 cases, readable, no flag. See open questions |
| 2. `[c_union]` member access as a call | ~5-8% (7.6 calls per instruction, 8 ns each, more when the box is loaded) | `addr(ra.val)`, `L.top.p`, `v.value_.i`, `reinterpret<GCUnion?>(o).h`: generated `operator . name`, never inlined (`ast_inline.cpp:652` `generated`, `:654` cross-module, `:1533` no `[inline]` on properties) | NEW | two options. (a) daslang fork: let the splicer inline tiny property functions (one `addr` node) or stop refusing `generated` ones: a daslang change, issue to lookibed/daScript, no converter change, the output stays as it is. (b) converter: lower a union whose members are all scalars/pointers as a struct of its widest member plus `reinterpret` reads at the sites: unreadable, opt-in only. (a) is the right fix |
| 3. `enum_from_int` on the opcode | ~2-3% (1 per instruction, a generic cross-module call) | `let _cond = enum_from_int(type<OpCode>, int(...))`, `lvm.das.inc:908` | P7.0h | `emit.das:1535 emit_enum_cast`: emit `unsafe(reinterpret<OpCode>(i))` inline; small |
| 4. the Lua call path | ~3% | `luaD_precall` + `prepCallInfo` + `luaE_extendCI`, each with 5 to 15 union calls, the `_cond` `if/elif` on the tag, `int64(... ? 1 : 0) != 0` stack test (P7.0e), `reinterpret<GCUnion?>(...).cl.l` (P7.0f) | P7.0e, P7.0f, and row 2 | nothing new: rows 2 and 3 of the ledger plus the union fix cover it |
| 5. allocation and GC through `invoke` | ~4% | `invoke(g.frealloc, g.ud, ...)` -> `l_alloc` -> `crt::realloc`, twice per node, and `luaM_free_` twice per node; the generational GC's `sweepgen`/`youngcollection` loops with `reinterpret<GCUnion?>` and union calls per object | NEW but small | the `invoke` through a C function pointer is what C does too; the das-side cost is the call depth (`luaH_new` -> `luaC_newobj` -> `luaC_newobjdt` -> `luaM_malloc_` -> `invoke` -> `l_alloc` -> `crt::realloc`, 6 das frames where C has 2 inlined ones). Auto-inline would take the same-module ones (`luaC_newobj`, `luaM_malloc_` are loop-free and small) if they were not `[c_function]`-wrapped `unsafe` bodies: check whether `[c_function]` sets a flag the inliner refuses (open question) |
| 6. `c_label_end()` | ~1% (0.55 per instruction: startfunc, returning, retry) | `label 2: c_label_end()` as a `[sideeffects] def private` with `pass`: a real call | NEW, tiny | `emit.das:777 LABEL_END_DEF`, `:3972 emit_label`: a built-in no-op the optimizer keeps, or no marker at all when the label is a loop's or function's first statement |
| 7. `c_volatile_load` | ~0.5% here (0.38 per instruction; more in nbody's jumps) | `trap = c_volatile_load(ci.u.l.trap)` | P7.0g | as the ledger says |

The remaining 30 to 35% is the interpreter's floor for these bodies: the operand decode (folded
constants, 1.0x in the audit), the tag tests, the TValue copies, pointer arithmetic; a hand
port pays it too. With rows 1 (the computed goto), 2, 3 and 6 taken, binary_trees would run at
about 0.5 us per instruction: about 20 to 25x native, where the audit's Rust dispatch kernel sits.

## The costs that are not constructs

- Load: 4.7 to 5.7 s tonight for the 28-module source layout, against 13.8 to 15.7 s of run
  (`baseline.txt`, `reorder_delta.txt`), the same for the reordered copy. The capture's 0.80 s
  startup was the slot layout. That is 25% of the wall time of the audit's benchmark argument
  and dominates any small argument. `load_split.txt` (`-log-compile-time`): 60 modules are
  compiled on every run, 7.68 s of compiler time in all (this run's load was 7 to 8), of which
  `lcode_cluster` (677 functions, the VM cluster) takes 4.83 s, `lauxlib` 0.25 s, `lstrlib`
  0.19 s. The load is the compile of the cluster, every run: a question for P7.0a's owner about
  the module cache (open question 4).
- The das GC heap: idle after start by construction and by the profile: every allocation of the
  program goes `luaM_*` -> `invoke(g.frealloc)` -> `l_alloc` -> `crt::realloc`/`crt::free`
  (207 k `l_alloc` calls in binary_trees 9), and no das heap function (`new`, `push`, string
  building) appears anywhere in the 9 783-row tree below `luaV_execute`. The direct check
  (`--das-profiler-memory`, `memprofile_bt6.txt`) agrees: the only das-heap allocations are the
  library tables' `push` at init (`lstrlib`, `loadlib`, `lauxlib`, 3.5 KB in all) and `printf`'s
  10 `reserve`s of 16 bytes for the format directives; nothing per node, nothing in the VM.
- `[c_function]`'s `unsafe` wrap: no runtime form (the audit), confirmed: no such frame in the
  profile.
- The interpreter's call overhead: the hot path makes 8 to 10 das calls per VM instruction where
  C makes none (the union accessors, `enum_from_int`, `c_label_end`, `c_volatile_load`) plus the
  same calls C makes (`luaD_precall`, `luaH_*`, `luaC_*`, `luaM_*`, `l_alloc`). The extra ones
  are rows 2, 3, 6, 7.

## nbody

Static reading first (the profile run follows the binary_trees job). nbody's inner loop
(`ports/lua/bench/nbody.lua` `advance`) is GETFIELD, SUB, MUL, ADD, DIV, SETFIELD on floats, a
`math.sqrt` call, and FORLOOP. The C: `lvm.c` OP_GETFIELD (`luaV_fastget` with `luaH_getshortstr`,
`lvm.h:85`), OP_MUL and OP_ADD through `op_arith` -> `op_arith_aux` -> `tonumberns` (`lvm.h:56`,
a tag test and a union read) and `luai_nummul` (`llimits.h:348`, `(a)*(b)`). Today's das: 

- OP_GETFIELD `lvm.das.inc:1179`: `addr(reinterpret<GCUnion?>(rc.value_.gc).ts)` (two union calls
  and a reinterpret), `luaH_getshortstr(addr(reinterpret<GCUnion?>(rb.value_.gc).h), key)` (a das
  call; inside it `n.u.key_tt`, `n.u.key_val.gc`, `.ts`, `addr(n.i_val)`: four union calls per
  probe step), then `addr(ra.val)` and the copy. About 8 union calls per GETFIELD, plus a call.
- OP_MUL `lvm.das.inc:2204`: the integer fast path first (`int(v1.tt_) == (3 | 0 << 4) && ...`),
  then the float path as the `tonumberns` macro lowered: nested `if` with `_t66`/`_t67`/`_t70`
  temporaries, an `int` flag per operand, `v1.value_.n` (a union call), then `io.value_.n = n1 *
  n2` (a union call) and `io.tt_ = ...`. The temporaries are research topic 02's; here they cost
  a few sim nodes each, less than the union calls around them.
- SETFIELD `lvm.das.inc:1348`: `luaH_getshortstr` again, `addr(ra.val)` three times, the
  barrier test `addr(ra.val).value_.gc.marked` (three union calls).

So nbody's instruction mix is heavier in union calls (8 to 12 per instruction) than
binary_trees' (5 to 8), the chain position of its opcodes is similar (GETFIELD 14, SETFIELD 18,
MUL 36, ADD 34, SUB 35, DIV 39, FORLOOP 73), and `luaH_getshortstr` is a das call per field read:
expected order: the chain, the union calls, the call, then P7.0e/g/h.

Measured (`nbody_baseline.txt`, `profile_nbody1000.txt`, box load 7 to 8 at 01:25Z): nbody 20000
20.25 s wall with a 7.3 s startup, about 13 s net; native 0.141 s: about 90x, worse than
binary_trees' 65x. The profile at 1000 steps (560 423 VM instructions, 3.1 GB of events):

| function | self s (profiled) | calls | per instr |
|---|---|---|---|
| `luaV_execute` | 1.50 (39%) | 1 | - |
| `luaH_getshortstr` (a loop, so a real frame) | 0.88 (23%) | 186 k | 0.33 |
| `.val` | 0.35 | 1.54 M | 2.7 |
| `.n` (the float payload) | 0.14 | 832 k | 1.5 |
| `.u`, `.ts`, `.i_val` (inside `luaH_getshortstr`'s probe) | 0.26 | 1.48 M | 2.6 |
| `.gc`, `.h`, `.p`, `.i` | 0.27 | 1.28 M | 2.3 |
| `builtin intptr` (the key compare in `luaH_getshortstr`) | 0.11 | 649 k | 1.2 |
| `enum_from_int` | 0.10 | 560 k | 1.0 |
| `c_volatile_load` | 0.01 | 48 k | 0.09 |

So nbody's order is: the chain (GETFIELD 14, SETFIELD 18, ADD 34, SUB 35, MUL 36, DIV 39,
FORLOOP 73: about 30 tests per instruction, about 40% by the binary_trees rate of 20 ns a test
against about 1.5 us per instruction here, less than binary_trees because its opcodes sit
earlier), then the union accessors at 9.2 calls per instruction (about 75 ns, 5 to 8%), then
`luaH_getshortstr` itself: one das call per field access plus two `intptr` builtin calls per
probe step (`intptr(addr(reinterpret<GCUnion?>(n.u.key_val.gc).ts)) == intptr(key)`, a
pointer-equality test C writes as `keystrval(n) == key`; daslang can compare the pointers
directly: NEW, small, `emit.das`'s pointer-compare lowering), then `enum_from_int`. The float
arithmetic itself (`n1 * n2`, the `tonumberns` temporaries) is not visible as a cost beyond the
`.n` accessor calls: the `luai_num*` macros fold to one operator node each.

## Where in the converter

In order of payoff:

1. The chain: `converter/emit.das:3810 emit_flag_loop` (the `_flag ||= ...` loop), `:3739
   emit_if_chain`, `:3698 emit_switch`, `:3729 label_cases`. P7.0c owns these; the finding here
   is the magnitude on the real benchmark (half the run) and that the default form only halves it.
2. The union accessors: no converter file. `c_runtime/c_runtime/c_union.das:177 make_operator`
   generates them; the refusal is `DASLANG_ROOT/src/ast/ast_inline.cpp:652` (`generated`), `:654`
   (cross-module), `:1533` (`[inline]` refuses property functions). A daslang-side issue: allow
   the heuristic tier (or an explicit flag the macro sets) to splice a property function whose
   body is one `addr` node, across modules.
3. The enum cast: `emit.das:1535 emit_enum_cast` (P7.0h's "enum_from_int inline").
4. The label marker: `emit.das:777 LABEL_END_DEF`, `:3972 emit_label`: make `c_label_end` a
   built-in no-op the optimizer keeps without a call, or drop the marker where the next statement
   already keeps the label.

## Size and risk

- Row 1 is P7.0c's; nothing to add but the numbers above for its PR body.
- Row 2 (daslang): a few lines in `ast_inline.cpp` plus a test in daScript's inline suite; risk:
  the inliner's reorder rules on property sites (an `addr` into `_storage` is reorder-safe).
  Converter side zero. Until it lands, an opt-in that emits `reinterpret` at the sites is not
  worth its readability cost.
- Row 3: P7.0h, tens of lines.
- Row 4: about 10 lines in `emit.das`, a probe that the label survives the optimizer without the
  call (`[sideeffects]` was added for that; a built-in no-op needs the same guarantee).
- Interactions: P7.0c's reorder of case blocks is not legal in general (fall-through, `goto`
  into a case); the reorder here was a measurement on break-terminated blocks only.

## Verdict

- The chain: as ruling 23 already says (plain cases default, computed `goto` opt-in); this note
  adds that the opt-in is where the 2x lives, so the ports' perf tables should carry both modes.
- The union accessors: readable-default once the daslang inliner change lands (no output
  change); no converter opt-in form proposed.
- The enum cast and the label marker: readable-default (both read the same or better).

## Open questions

1. For P7.0c's coder: measure the plain if/elif default on binary_trees 12 the way this note
   measured the reorder (the kernel's if-chain cell is still 200x native); and whether a split
   chain (`if (_cond < OP_X)` halves, 7 tests for 83 cases) is acceptable as readable.
2. Does the inliner splice same-module `[c_function]` bodies (`luaC_newobj`, `luaM_malloc_`,
   `prepCallInfo` are loop-free and small)? The profile shows `prepCallInfo` as a frame, so at
   least that one is not; is it the `unsafe` wrap or the node budget (32)?
3. The daslang issue for the union accessors: to lookibed/daScript (memory rule), with the probe
   `research/04-benchmark-profile/union_probe.das` as the test.
4. The load: 5 s for 28 modules on every run is a quarter of the audit's wall time; is the module
   cache working for the source layout (the warm run is 7.4 s, the next 4.7 to 5.7 s)?
