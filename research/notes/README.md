# Research notes (c2das-re RESEARCH session, 2026-11-02 night)

Branch `research/idiomatic`, worktree `/root/wt-research`, pushed to origin. Research only: no
PR, no merge. Each note has an owner part first (plain, no das assumed), then the technical part
for the coders. Prototypes, kernels and raw numbers live under `/root/wt-research/research/<NN>-<topic>/`
on the branch; generated output (converted modules, module caches) is not committed, the scripts
beside them recreate it. All numbers were taken on the owner's WSL box while three coder streams
ran heavy jobs (load 5 to 11), five samples, medians; treat ratios as reliable, absolute times as rough.

| Note | Topic | Prototype folder |
|---|---|---|
| `01-macro-blowup.md` | function-like C macros expanded in place (setobj, vmfetch, checkGC, luai_num*, next(ls)) | `research/01-macro-blowup/` |
| `02-temporaries.md` | machine temporaries `_tN`, `_first`, self-assignments, stray braces | `research/02-temporaries/` |
| `03-goto-backjumps.md` | the `_goto` back-jumps in luaV_execute and llex, a structured form | `research/03-goto-backjumps/` |
| `04-benchmark-profile.md` | binary_trees and nbody end to end under the interpreter, the top costs | `research/04-benchmark-profile/` |

`.brief.md` is the shared brief the four subagents worked from; `.convert.log` the Lua conversion log.

## The findings in one screen

1. **Macro lifting is readable and free.** Lifting each outermost function-like macro expansion
   into a `def` named after the macro (82 `setobj` sites, 41 `next`, 298 `GETARG_*`, 256 union
   accessors ...) costs nothing under the JIT (0.90x to 1.08x) and 1.02x to 1.17x under the
   interpreter on the worst kernel. No libclang preprocessing record is needed: clang's JSON dump
   already carries `expansionLoc` and `isMacroArgExpansion`, which the dumper drops today.
   Verdict: readable-default (`macros = lift`), the expanded form opt-in. Nested macros are
   invisible (one def per outermost name); macros that use the enclosing function's locals
   (`vmfetch`, `Protect`, `checkGC`) stay expanded in a first version.
   Side finding: `[inline]` makes the interpreter 1.69x slower, not faster (the splice leaves a
   block with a local per argument at each site). Do not put `[inline]` on lifted defs.
2. **Temporaries, self-stores and braces are droppable under strict local tests, at no speed cost.**
   Six emitter rules (postfix step sunk below its one reader, discarded `a || f()` as `if`,
   `1 != 0` as `true`, do-while without `continue` bottom-tested, self-store not printed, bare
   nested block flattened) remove 122 of 313 temporaries in the hot modules, all 24 `_first`
   flags, 482 of 901 lone braces and the one `L.top.p = L.top.p`. Kernel: 1.15x faster interp,
   JIT within spread. The ternary temporaries stay (das `?:` carries no statements). Verdict:
   readable-default, three small PRs, about 250 emitter lines.
3. **The `_goto` state machine is another 2x on dispatch, on top of P7.0c.** P7.0c keeps the
   re-dispatch label, the `_goto == 0 &&` term and the `c_label_end()` call. Four recognizers
   (top label with only backward gotos as `while (true)`; forward-only shared tail inlined or
   written once under a bool; short fall-through duplicated; llex's label cascade as an enum
   choice) give luaV_execute the shape `while (true) { ...; while (true) { if/elif ...; break } }`
   with no label. Kernel: converted 0.0568 s, P7.0c if-chain 0.0291 s, structured 0.0144 to
   0.0157 s, so 3.6x to 4.0x in all; JIT within noise. Verdict: readable-default, the state machine
   stays only as the fallback. Blocker found and filed: lookibed/daScript#33, a `private` function
   whose outer `while (true)` ends in an inner `while (true)` holding the `return` never returns
   under the interpreter (public, or a statement after the inner loop, works); the coder uses the
   bool form until it is fixed.
4. **binary_trees under the interpreter is about 65x native net, nbody about 90x; half of it is
   the switch chain.** Moving 16 hot opcodes to the front of the chain by hand (output
   byte-identical) cut the net run from 15.3 s to 10.1 s, about 20 ns per chain test; the full
   fix is P7.0c's opt-in computed goto, since a plain if/elif chain halves it at best. NEW costs
   not in any row: every `[c_union]` member access is a real call under the interpreter (8 ns, 7.6
   per VM instruction in binary_trees, 9.2 in nbody, 5 to 8 percent of the run) because
   `c_union.das` marks the accessor `generated` and daScript's auto-inliner refuses generated,
   property and cross-module functions (`ast_inline.cpp`); the fix is in the daslang fork, not the
   converter (probe `research/04-benchmark-profile/union_probe.das`, issue not yet filed).
   `c_label_end()` is a real call 0.55 times per instruction (1 percent, trivial). The source
   layout compiles 60 modules on every run, 7.7 s, `lcode_cluster` alone 4.8 s: the module cache
   is not saving it (question for P7.0a's owner). The das GC heap is idle, `[c_function]` has no
   runtime frame, the instrumenting profiler distorts 30x (its counts are trustworthy, its times
   are not; `perf` is not on the box). After the chain, the accessors, the enum cast and the
   marker the estimate is 20 to 25x native, the floor the audit measured for the Rust dispatch kernel.

## Suggested order for the coders (after P7.0c-k land)

1. Topic 2's six rules (small, no speed risk, three PRs).
2. Topic 3's recognizers, bool form first, once P7.0c is merged; file the Lua benches with it.
3. Topic 1's macro lifting (the largest, two PRs; composes with P7.0k, whose constant names then
   land inside the lifted bodies).
4. The daslang-side items: issue #33; an issue for the `[c_union]` accessor inlining with
   `union_probe.das` as the test; an issue or probe for `[inline]` under the interpreter.
