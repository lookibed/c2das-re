# 01-macro-blowup: function-like C macros expanded in place

Research note, 2026-11-02 (night). Prototypes, kernels and numbers:
`/root/wt-research/research/01-macro-blowup/` (`kernels/*.c`, `measure.das`, `*_helper.das`,
`*_inline.das`, `measured.txt`, `hand_written_lvm_llex.das.txt`).

## For the owner

The problem. A C macro with arguments is a named shortcut: `setobj(L, a, b)` means "copy a Lua
value", `next(ls)` "read the next byte". The preprocessor pastes the body at every use before
clang sees the code, so the converter translates the pasted body every time: one word of C
becomes 4 to 60 lines of das. `luaV_execute` is 746 lines of C and 2689 of das, the lexer 118
against 339. The reader sees the mechanism, never the name, 82 times for `setobj` alone.

What a human writes: one small function per macro, named after it, called by name:
`setobj(ra, slot)`, `next(ls)`, `GETARG_B(i)`, `ttisinteger(v1)`.

The proposal: the converter already knows which code came from a macro and where it was used;
the name is a slice of the C source at that spot (no new libclang feature needed). A pass
marks each use, the emitter prints the name as a call and writes the function once per module.
A first version lifts macros that are one expression or one statement over their arguments;
macros that touch the surrounding function's own variables (`vmfetch`, `Protect`, `checkGC`,
`op_arith`) stay pasted, but the macros inside them become calls, which is where the lines go.

What it buys: OP_ADD from 64 lines to 22, `read_numeral` from 75 to 31, `luaV_execute` toward
half its size. Speed, measured on two small kernels: under the JIT nothing measurable (0.90x
to 1.08x of today's time across runs); under the interpreter a call costs 1.07x to 1.17x on a
kernel that is only `setobj` copies (the worst case) and 1.02x on the byte fetch (tables
below). daslang's `[inline]` does not help: it is slower under the interpreter.

Cost: a medium item, 400 to 600 lines plus tests, two PRs. Risk: types and constness of the
lifted functions (one function per argument-type signature; `var` on pointers written through),
name clashes, and an interpreter speed loss of a few percent on the hottest paths.

Ruling-23 verdict: readable-default, since the helper form is what a human writes and loses
nothing under the JIT; the pasted form stays as the opt-in flag (`macros = expand`) because it
is faster under the interpreter, both modes tested and measured. A sidecar list of macro
names is a cheap second knob, not the mechanism; lift every function-like macro of the
project's own headers, never a system header's.

## The proposal

The converter already sees, for every node, that it came from a macro and where the macro was
used (clang's dump gives `spellingLoc`, `expansionLoc`, `isMacroArgExpansion`, and the macro
name's byte offset and length at the use site, so the name is a slice of the C source; no
libclang preprocessing record is needed). A pass marks the outermost C-IR node of each
expansion with the macro name and its argument subtrees; the emitter prints `name(args)` there
and emits one `def name(...)` per (macro, argument-type signature) from the expansion's body,
next to the functions of the module. A first version lifts only expression and
single-statement macros whose arguments are used as values, through pointers, or as assigned
lvalues (a reference parameter); the rest stay expanded as today. That covers the bulk:
`setobj*`, `next`, `zgetc`, `GETARG_*`, `ttis*`, `ivalue`, `tsvalue`, `hvalue`, `s2v`,
`savestack`, `restorestack`, `lua_pop`, `luai_num*`, `luaL_addchar`, `isempty`, `tonumberns`.
It does not cover `vmfetch`, `Protect`, `checkGC`, `op_arith` (they read and write locals of
`luaV_execute` that are not arguments): those stay expanded, their inner macros become calls.

## The C

- `setobj` (lobject.h:118-121), a block with two locals and two stores; `setobj2s`,
  `setobjs2s` (lobject.h:129-131) wrap it through `s2v` (lobject.h:172, `&(o)->val`).
- `vmfetch` (lvm.c:1141-1147): `if (l_unlikely(trap)) { trap = luaG_traceexec(L, pc);
  updatebase(ci); } i = *(pc++);`: reads and writes `trap`, `pc`, `i`, `base`, `ci`, all locals
  of `luaV_execute`.
- `checkGC(L, c)` (lvm.c:1134-1137) over `luaC_condGC(L, pre, pos)` (lgc.h:167-169): `pre`
  is `(savepc(L), L->top.p = (c))`; at the OP_CONCAT site `c` is `L->top.p` itself, so the
  expansion reads `L->top.p = L->top.p`. `luai_threadyield` (llimits.h:273) and
  `condchangemem` (llimits.h:374) expand to nothing: the two empty `{ }` blocks.
- `luai_numadd` and the `luai_num*` family (llimits.h:313-352): `((a)+(b))` with an unused `L`.
- `next(ls)` (llex.c:32) over `zgetc(z)` (lzio.h:20): a decrement, a test, a post-increment
  read or a refill call, then a store into `ls->current`; `save_and_next` (llex.c:51).
- `savestack`, `restorestack` (ldo.h:36-37): `char *` arithmetic on the stack base.
- `getarg(i, pos, size)` (lopcodes.h:121) and `GETARG_A/B/C/Bx/sBx/sJ` (lopcodes.h:125-152)
  with `MASK1` (lopcodes.h:105) and the `POS_*`, `SIZE_*` sums (lopcodes.h:38-58).
- `ttisinteger` (lobject.h:328), `ivalue` (lobject.h:333), `tsvalue` (lobject.h:369),
  `checktag`, `rawtt`, `makevariant` (lobject.h:42-91).
- `luaL_addchar` (lauxlib.h:207-209), a comma expression with a conditional refill call and a
  post-increment store; `lua_pop` (lua.h:376), `lua_settop(L, -(n)-1)`.

## Today's das

Converted Lua, `lua/work/lua/` (this run: 24518 lines, `[c_function]` on 776 of 1080):

| Macro | Sites in the das (grep) | das lines per site | Where |
|---|---|---|---|
| `setobj*` | 82 (`var io1 : TValue? = `) | 6 (a `{ }` with two locals and two stores) | lvm.das.inc 25, lapi.das 20, ltm 11, ldo 7 |
| `next(ls)`, `zgetc` | 41 (`= luaZ_fill(`), 39 in llex.das.inc | 11 | llex.das.inc:204-215 and every `save_and_next` |
| `GETARG_*` | 298 (`~(~uint(0) <<`), 200 in lvm | 1 long expression: `int(i >> uint(0 + 7 + 8 + 1) & ~(~uint(0) << 8u) << 0u)` | lvm.das.inc:2076-2079 |
| `ttisinteger`-style tag tests | 186 (`.tt_) == (`), plus 96 `& 15` (`novariant`) | 1: `int(v1.tt_) == (3 \| 0 << 4)` | lvm.das.inc:2080 |
| `tsvalue`/`hvalue`/`gco2*` | 256 (`reinterpret<GCUnion?>`) | 1: `addr(reinterpret<GCUnion?>(rc.value_.gc).ts)` | lvm.das.inc:1070 |
| `savepc`/`savestate`/`updatetrap` (`Protect`) | 44 / 36 / 47 | 3 lines around every protected call | lvm.das.inc:1088-1091 |
| `checkGC` | 24 (`GCdebt > 0`) | 11, with `L.top.p = L.top.p` and two empty blocks | lvm.das.inc:2863-2874 |
| `savestack`/`restorestack` | 41 (`reinterpret<uint8?>(L.stack.p)`) | 1: `reinterpret<StackValue?>(reinterpret<uint8?>(L.stack.p) + L.errfunc)` | ldo.das.inc |
| `lua_pop` | 68 (`lua_settop(L, -`) | 1: `lua_settop(L, -1 - 1)` | lapi, lauxlib, the libs |
| `luaL_addchar` | 31 (`luaL_prepbuffsize(`) | 5 | lauxlib.das, lstrlib.das |
| `luai_numadd` etc. | 8 in `op_arithf` bodies | 1, but inside the 40-line `tonumberns` expansion | lvm.das.inc:1550 |
| `vmfetch` | 1 (the loop head) | 7 | lvm.das.inc |

OP_ADD, `lua/work/lua/lvm.das.inc:2072-2135`: 64 lines for 4 lines of C (lvm.c:1463-1466);
the two `tonumberns` expansions alone are 34 lines with `_t56.._t60`. OP_GETTABUP,
`lvm.das.inc:1063-1096`: 34 lines for 12 of C (lvm.c:1252-1263). `read_numeral`,
`llex.das.inc:199-273`: 75 lines for 31 of C (llex.c:227-257), three `next` chains of 11.

## Proposed das

Full text: `research/01-macro-blowup/hand_written_lvm_llex.das.txt`. The shape:

```das
[c_function]
def private setobj(var io1 : TValue?; io2 : TValue?) {
    io1.value_ = io2.value_
    io1.tt_ = io2.tt_
}
def private ttisinteger(o : TValue?) : bool => int(o.tt_) == LUA_VNUMINT
def private ivalue(o : TValue?) : int64 => o.value_.i
def private GETARG_B(i : uint) : int => getarg(i, POS_B, SIZE_B)
[c_function]
def private next(var ls : LexState?) {
    ls.current = zgetc(ls.z)
}
```

OP_ADD as a human writes it (the `op_arith` body stays open: it moves `pc` and uses `i`,
`base`; its macros become calls; 64 lines become 22):

```das
        } elif (op == OpCode.OP_ADD) {
            var v1 = s2v(base + GETARG_B(i))
            var v2 = s2v(base + GETARG_C(i))
            var ra = base + GETARG_A(i)
            if (ttisinteger(v1) && ttisinteger(v2)) {
                let i1 = ivalue(v1)
                let i2 = ivalue(v2)
                pc = pc + 1
                setivalue(s2v(ra), l_addi(L, i1, i2))
            } else {
                var n1, n2 : double
                if (tonumberns(v1, n1) && tonumberns(v2, n2)) {
                    pc = pc + 1
                    setfltvalue(s2v(ra), luai_numadd(L, n1, n2))
                }
            }
```

`tonumberns(o, n)` assigns its second argument: in das it takes `var n : double&`, which is
the general rule for an argument a macro assigns (an lvalue argument becomes a reference
parameter; a pointer argument the macro writes through becomes `var p : T?`). `read_numeral`
goes from 75 lines to 31 with `save_and_next(ls)`, `lisxdigit(c)`, `ttisinteger(addr(obj))`.

The `elif (op == OpCode.OP_ADD)` head assumes P7.0c's plain-case dispatch; under today's
`_flag` chain the body is the same. A leaf accessor that only reads through a pointer
(`ttisinteger`, `ivalue`) compiles without `[c_function]` and as a one-line `=>` def
(`setobj_copy_expr.das`); a def that takes an address or writes through a pointer needs the
`[c_function]` context.

The names: `next` overloads daslang's iterator `next` by argument type and compiles
(`next_fetch_helper.das`). A def that returns a pointer into its argument needs `var` on that
parameter (`s2v(var o : StackValue?)`), else the result is `TValue const?` and the caller's
store is refused: the first compile error of my hand edit, and the rule the pass must apply
(a pointer parameter is `var` when the body writes through it or returns a pointer derived
from it; the converter's existing `var`-pointer-position analysis does this for functions).

## Measured effect

Method: `research/01-macro-blowup/measure.das` (the audit's method: the kernel composed by
the dasProfile protocol, built natively as the oracle, converted by the converter, each lane
its own process, 5 samples, medians; `heavy --low --max 3G`). Two kernels in the audit
shape: `setobj_copy.c` (an OP_MOVE and an OP_LOADK copy per step through `setobjs2s`,
`setobj2s`, `s2v`, `ttisinteger`, `ivalue`: nothing but macro bodies, the worst case for a
call) and `next_fetch.c` (`next(ls)` over `zgetc` with a refill, as `save_and_next` loops).
Three spellings: converted (today), helper (one plain `def` per macro, `[c_function]`), and
the same defs with `[inline]`. Ratios are against the converted cell of the same lane.
Raw numbers: `research/01-macro-blowup/measured.txt`.

| Kernel | native | interp converted | interp helper | interp `[inline]` | JIT converted | JIT helper | JIT `[inline]` |
|---|---|---|---|---|---|---|---|
| setobj_copy | 484 us | 27.29 ms (56x native) | 31.88 ms (1.17x) | 46.24 ms (1.69x) | 424 us (0.88x native) | 419 us (0.99x) | 420 us (0.99x) |
| next_fetch | 503 us | 38.51 ms (77x native) | 39.43 ms (1.02x) | 41.70 ms (1.08x) | 768 us (1.53x native) | 693 us (0.90x) | 682 us (0.89x) |

A second run of setobj_copy (3 samples, the box loaded by the coders' heavy jobs, so its
cells are noisier; `measured_setobj_variants.txt`) with two more spellings: `outer` is the v1
shape, one def per outermost macro name with the full expansion as its body, so one call per
copy instead of five; `expr` has the leaf accessors as `=>` one-liners without `[c_function]`.

| setobj_copy, run 2 | interp | JIT |
|---|---|---|
| converted | 28.10 ms | 401 us |
| helper (five small defs) | 30.01 ms (1.07x) | 432 us (1.08x) |
| outer (v1 shape, one call per copy) | 30.69 ms (1.09x) | 468 us (1.17x) |
| expr (leaf accessors as `=>`) | 36.45 ms (1.30x) | 437 us (1.09x) |

Between the two runs the helper form is 1.07x to 1.17x under the interpreter and 0.99x to
1.08x under the JIT; the run-to-run spread is as large as the call cost, so the honest
statement is "a few percent to 17 percent under the interpreter, within noise under the
JIT". Cutting the defs differently (one call per copy, or expression bodies) does not help;
the `expr` cell is worse in this run, unexplained, and would need a quiet box to trust.

Reference: the audit's `small_call` cell (perf/audit_linux.json): a small call against its
body inlined is 1.01x under the interpreter and 1.16x under the JIT, so the JIT was the tier
where a call showed. Here the JIT shows no call cost at all (0.99x, 0.90x: the JIT inlines a
small `def` and the helper form is even faster on the byte fetch), and the interpreter pays
1.17x on the all-copies kernel and 1.02x on the byte fetch. The three `[c_function]` helper
defs of setobj_copy are called 5 times per step (`setobjs2s` -> `setobj` -> `s2v` twice); the
1.17x is five calls per 16-byte copy, the worst shape in Lua (OP_MOVE, OP_LOADK). The whole
Lua benchmarks run 193x to 436x native under the interpreter and spend their time across
dispatch, table access and GC, so the effect on them is a fraction of 1.17x; not measured here
(a lifted lvm needs the pass, and a hand edit of 2689 lines is not a night's work).

`[inline]` is slower under the interpreter, 1.69x and 1.08x against the converted cell and
1.45x against the plain helper on setobj_copy. The post-inlining AST (`ast_dump` in source
mode on `setobj_copy_inline.das`) shows why: every inlined call becomes a block with one
local per argument and a `_res` local for the result, nested per level of helper, so one
`setobjs2s(base + a, base + a - 1)` runs 2 + 2 + 2 + 2 local initializations in four nested
blocks before the two stores:

```das
var _inl2_arg_o1:StackValue? = i_das_ptr_add(base,a,16);
var _inl2_arg_o2:StackValue? = i_das_ptr_add(i_das_ptr_add(base,a,16),-1,16);
{
    var _inl10_res:TValue?;
    { var _inl10_arg_o:StackValue? = _inl2_arg_o1; _inl10_res !== addr(_inl10_arg_o.val); }
    var _inl2_lu_inl0_arg_io1:TValue? = _inl10_res;
    ...
    _inl2_lu_inl0_arg_io1.value_ = _inl2_lu_inl0_arg_io2.value_;
```

The interpreter pays per local and per block; the JIT folds them away, which is why the JIT
cells are equal. So `[inline]` is not the interpreter fix and the lifted defs should not
carry it. The interpreter-fast form is today's expanded output, which is the opt-in. The
inliner's local-per-argument splice is a daslang finding (an issue on the fork, not a change
here): an argument that is a plain variable or a pointer could be substituted instead.

## Where in the converter

1. `converter/dumper_a.das`, `loc_given`/`loc_of` (lines 170-185) and `complete_locs`
   (219-240): today a macro-produced node takes its `expansionLoc` as its location and the
   `spellingLoc` is dropped. The pass needs, per node, the expansion offset, `tokLen` (the
   macro name's length at the use site) and `isMacroArgExpansion` on the expansion. The dump
   has all three (verified on `kernels/setobj_copy.c`: `expansionLoc.tokLen` is 9 for
   `setobjs2s`, 3 for `s2v`; nodes from an argument carry `"isMacroArgExpansion": true`). The
   name is `source[offset .. offset+tokLen]` of the C file the dumper already reads. No change
   to `collect_records` (line 721, `clang_parseTranslationUnit(..., 0u, 0u)`: no preprocessing
   record is requested today, and none is needed; `CXTranslationUnit_DetailedPreprocessingRecord`
   and `CXCursor_MacroExpansion` are bound in dasClangBind, `cbind_boost.das:23`, if a later
   version wants the macro definition's extent for nested macros).
2. `converter/cir.das`, `CirExpr` (line 69) and `CirStmt` (106): a `macro : string` field
   exists on `CirExpr` for object-like literals (c-ir-spec.md section 6.2, the P7.0k hook). Add
   `expansion : int` (the use-site offset, 0 for none) and `macro_arg : bool` to both, written
   and read in the JSON walkers (601, 1070). The outermost node of an expansion is the node with
   `expansion == E` whose parent has a different expansion (or none); its argument subtrees are
   the maximal descendants with `macro_arg` set.
3. New `converter/macros.das` (the pass over a `CirDecl` body): collects expansions, decides
   liftable (one expression or one statement; every argument subtree used as a value, through a
   pointer, or as an assigned lvalue; no free variable that is a local of the enclosing function
   and not an argument; no `return`, `goto`, `break`), computes the signature from the argument
   types the C-IR carries, and records `(macro, signature) -> body` plus the site's rewrite.
   `vmfetch`, `Protect`, `checkGC`, `op_arith` fail the free-variable test and stay expanded;
   their inner expansions are lifted on their own.
4. `converter/emit.das`, `emit_expr` (1912) and `emit_stmt` (3959): at a marked site print
   `name(args)`; `emit_functions` (5360) emits the lifted defs before the module's functions,
   with `[c_function]` when the body needs the C context; no `[inline]` (measured slower
   under the interpreter, equal under the JIT).
5. `converter/tiers.das`/the sidecar: the flag `macros = lift | expand` (default `lift`) and
   an optional `lift_only = [names]` list; `expand` is today's output.
6. Tests: a suite case per hard case below, the kernels of this folder as perf cells in
   `perf/audit_constructs.das` (`macro_call` construct, rewrite = the helper form).

## Size and risk

Size: dumper 40 lines, C-IR 30, the pass 250 to 350, emitter 80, tests 200. Two PRs.

Hard cases, named:
- Not one expression or statement: `setobj` is a `{ }` block with declarations (fine: a block
  is one statement); `luaC_condGC` holds `pre; luaC_step(L); pos;` where `pre`/`pos` are
  statement arguments. Statement-typed arguments are not liftable: stays expanded.
- Assigns to an argument: `next(ls)` writes `ls->current` through a pointer, fine;
  `tonumberns(o, n)` assigns `n` itself: a `var n : T&` parameter, and the call site passes
  the lvalue. `setobj` takes pointer values, fine. `luaV_fastget(L, t, k, slot, f)` assigns
  `slot` and takes a function name `f`: not liftable in v1.
- Locals not among the arguments: `vmfetch` (`pc`, `i`, `ra`, `trap`, `base`), `Protect`
  (`ci`, `pc`, `trap`), `op_arith` (`i`, `base`, `pc`, `ra`), `checkGC` (`ci`, `pc`, `trap`).
  Stay expanded; a v2 could pass them as reference parameters, but a human would not.
- Nested expansions: in clang's dump every node of `setobjs2s(...)` carries the same
  `expansionLoc` (the outermost use), whatever macro spelled it: `setobj` and `s2v` inside are
  not visible as expansions. v1 lifts the outermost name with the fully expanded body
  (`setobjs2s` = two stores through `addr(o.val)`), so one macro becomes a def per outermost
  name. Recovering the inner names needs the macro definitions' source ranges (the
  `spellingLoc` of an inner node falls in a different `#define`'s lines; libclang's
  `CXCursor_MacroDefinition` extents give those ranges).
- Type-dependent expansions: `GETARG_*` on `uint`, `ivalue` on `TValue?` versus `TValue const?`,
  `luai_numadd` on `double` only in Lua but `check_exp`'s `(void)(c), (e)` comma form in the
  asserting build. One def per signature; the name is overloaded, which daslang resolves.
- Self-assignment: `L.top.p = L.top.p` is the `checkGC(L, L->top.p)` argument folding into
  `pre`; a one-line emitter check drops an assignment whose two sides print the same.
- Argument evaluated twice in the macro but once in the def (`zgetc(z)` reads `z` three
  times): a def evaluates the argument once, which is what the C author meant; a macro that
  relies on double evaluation of a side effect is wrong C and does not occur in Lua.
- Name clashes: a lifted def named like a daslang builtin (`next`, `min`) overloads by type; a
  lifted def named like a C function of the module (`luaL_addchar` is a macro in lauxlib.h and
  nothing else, fine) would need the `_c_` rule. Macros of system headers are never lifted.
- Interactions: P7.0c (switch) is orthogonal; P7.0d/e fold inside lifted bodies the same;
  P7.0f (`addr((p + i).val)`) becomes `s2v(p + i)`, a call, so P7.0f's form lives in one def;
  P7.0g's `c_volatile_load` sits inside `updatetrap`, which stays expanded; P7.0k's named
  constants land inside the lifted bodies (`LUA_VNUMINT`), the two items compose.

## Verdict

Readable-default, per ruling 23: the helper form is what a human writes; it is not slower
under the JIT (0.90x to 1.08x across runs, within noise) and 1.07x to 1.17x slower under the
interpreter on the worst kernel, 1.02x on the other (tables above). Speed and readability pull apart in one tier, so
both modes: `macros = lift` default, `macros = expand` the opt-in fast form, both measured
in the audit (a `macro_call` construct row). Do not put `[inline]` on the lifted defs: it is
slower under the interpreter and buys nothing under the JIT. A sidecar
name list is a useful second knob (`lift_only`), not the mechanism.

## Open questions

1. `[inline]` splices a block with a local per argument and per result (AST shown above), so
   it costs the interpreter more than the call. Worth an issue on the fork (substitute plain
   variable and pointer arguments instead of copying them); until then the lifted defs are
   plain. Should the item's audit row measure a third spelling, expression-bodied defs
   (`=> int(o.tt_) == 3`), to see whether the inliner treats them differently?
2. One def per (macro, signature): named overloads or a suffix (`setobj_s`, `setobj_t`) when
   two signatures differ only in constness?
3. Does the emitter's existing `var`-pointer-position analysis run on a lifted def body as it
   does on a function, so `s2v(var o : StackValue?)` comes out right without a special rule?
4. Where should the lifted defs of a header macro live in the source layout: in every module
   that uses them (private, duplicated per module) or once in the `<header>_h.das` module the
   layout already emits (lobject_h.das.inc)? The second reads better and matches the C.
5. Nested names (`setobj` inside `setobjs2s`): is the macro-definition-range approach worth a
   v2, or is one def per outermost name enough for the critic?
