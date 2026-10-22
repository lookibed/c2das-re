# C-To-DAS — Implementation Order

The execution plan for the `c2das` project, expanded from [very-detailed-plan.md](very-detailed-plan.md)
§9 into concrete, ordered work items. Read it with the normative companions open:
[lowering-examples.md](lowering-examples.md) and [stdlib-examples.md](stdlib-examples.md)
contain the *expected output code* for every construct — most work items below are
"transcribe the spec into the emitter", not design work. [c-feature-matrix.md](c-feature-matrix.md)
is the coverage checklist; [sidequest.md](sidequest.md) lists daslang-core follow-ups that
never block this plan.

**Working rules for the implementer**
1. The docs are normative. When your code and the docs disagree, one of them is a bug —
   stop and resolve it deliberately (usually with a probe), never silently diverge.
2. Probe before assuming. Every ✓ in the docs was verified on a live binary on 2026-08-21;
   re-run the probes suite (P0.3) on your binary before trusting them. A probe that
   contradicts the docs is a finding — report it, don't work around it.
3. Ratchet discipline: suite pass-counts only go up. Every skip gets a ledger line
   (feature, reason, phase that unblocks it). No silent exclusions.
4. Fixtures before machinery: every c_runtime piece and every lowering lands with a
   hand-written "as-if-converted" `.das` test first, converter integration second.
5. No hand edits to converted output, ever. Per-project judgment goes in the sidecar.

---

## Where to get everything

Pin exact versions in the repo (a `VERSIONS.md` or the fetch scripts themselves); never
"latest". URLs are the projects' stable homes — all long-lived.

| What | Where | Notes |
|---|---|---|
| daslang | https://github.com/GaijinEntertainment/daScript | build with dasClangBind enabled; dastest, dasImgui, dasAudio, MCP/LSP all in-tree — no separate downloads |
| LLVM/libclang 22.1.5 | https://github.com/llvm/llvm-project/releases — the `clang+llvm-22.1.5-x86_64-pc-windows-msvc` archive | must be the layout WITH `lib/cmake/clang` (the .exe installer lacks it); point `Clang_DIR` at it |
| PureDOOM | https://github.com/Daivuk/PureDOOM | GPL-2 — vendor under `doom/`, never mix into MIT dirs; single-header or `src/DOOM` multi-file, we convert the multi-file form |
| doomgeneric (reference only) | https://github.com/ozkl/doomgeneric | the canonical fallback if PureDOOM surprises us; not vendored by default |
| freedoom2.wad | https://freedoom.github.io/download.html (releases: https://github.com/freedoom/freedoom/releases) | BSD-licensed — the CI wad, fetched by script |
| doom2.wad | commercial — DOOM II on Steam or GOG | user-supplied, local only, NEVER committed or fetched |
| c-testsuite | https://github.com/c-testsuite/c-testsuite | single-file tests + `.expected` outputs; the V1 gate |
| GCC c-torture `execute` | https://github.com/gcc-mirror/gcc — subtree `gcc/testsuite/gcc.c-torture/execute`, pin a release tag (e.g. `releases/gcc-14.2.0`) | fetch script sparse-checkouts just the subtree |
| csmith | https://github.com/csmith-project/csmith | build from source; runs fine under WSL if the Windows build fights back |
| creduce / cvise | https://github.com/csmith-project/creduce · https://github.com/marxin/cvise | divergence minimizers (P4.5); cvise is the better-maintained choice, WSL |
| Lua 5.4 | https://www.lua.org/ftp/ (pin e.g. `lua-5.4.8.tar.gz`) + matching test suite from https://www.lua.org/tests/ | MIT; the test tarball is versioned — match it to the source tarball exactly |
| GM soundfont (Doom music) | GeneralUser GS — https://schristiancollins.com/generaluser.php | free license, the standard choice; any GM-complete .sf2/.sf3 works with dasAudio's player |

## P0 — Bootstrap

**Goal: the walking skeleton — every tool in the chain touched once.**

- **P0.1 Repo skeleton.** `c2das` external repo: `converter/`, `c_runtime/` (das),
  `dasCRuntime/` (C++ glue module), `probes/`, `suites/`, `doom/`, `lua/`, `docs/`
  (these six documents move in). License split: repo MIT/BSD, `doom/` subtree GPL-2.
- **P0.2 daslang dependency.** Consume a daslang build with dasClangBind enabled
  (libclang 22.1.5; `Clang_DIR`/`PATH_TO_LIBCLANG` resolves — works on MSVC). Standard
  external-module worktree pattern; MCP bootstrap for the working tree.
- **P0.3 Probes suite.** Port every probe from the plan's discussion into `probes/` as a
  dastest suite (~25 probes, all already written — they live in the docs and this repo's
  history). This is the das-facts regression net: it runs first in CI, and a probe
  failure after a daslang update is a *finding*, not noise.
  Acceptance: all probes green on the pinned daslang build.
- **P0.4 dasCRuntime v1.** The native glue module: CRT binds for malloc family, mem*,
  string.h list, libm exotica, errno accessors, time/clock, rand/srand, getenv, snprintf.
  `addExtern` lines only — no logic. Name policy per stdlib-examples.md (crt namespace).
  Acceptance: a das test calls each bind and checks a known value.
- **P0.5 C-IR spec + converter skeleton.** Write `c-ir-spec.md` — the versioned
  interchange contract (plan §4.0): types with layout baked in, pinned castKind enum,
  evaluated constants, positional initializers. Then the skeleton: a C-IR reader + das
  emitter for the trivial subset (main, return, integer literals), fed by **Dumper A**
  (`clang -ast-dump=json` + dasClangBind layout, thin normalizer). Dumper B (the C2Rust
  fork serializing C-IR) is a parallel track owned by its author; the byte-diff harness
  between dumpers lands as soon as both exist. Formatter + `compile_check` wired into the
  pipeline from day one.
- **P0.6 Exit criterion (the P0 gate).** `int main(){return 42;}` converts, compiles,
  and returns 42 under **interp, JIT, and AOT** (this run also closes the goto-tier
  confirmation — both emitters carry ExprGoto handlers, source-verified).

## P1 — c_runtime semantic layer + expression/statement core

**Goal: the language core over scalars, and the entire c_runtime, each tested standalone.**

Order matters: c_runtime first (it's converter-independent — fixtures are hand-written
"as-if-converted" das), then the suite runner, then the lowerings climb the ratchet.

- **P1.1 `[c_function]`.** ~15-line macro (spec + precedent in lowering-examples.md).
- **P1.2 `enum_from_int`, `c_exit`/`c_abort`/atexit (`[finalize]` walker), `cstr_array`
  macro.** All spec'd; atexit LIFO + exit()-path behavior probed.
- **P1.3 `[variadic]` machinery.** `to_cvalist` (code is in lowering-examples.md,
  probed), the call macro that tuples trailing args (probed), the packaging decision
  (annotation-registered vs converter-emitted per-function classes — try annotation
  first, fall back without ceremony), empty/1-element tuple cases.
- **P1.4 printf.** Format splitter + per-directive CRT `snprintf` calls; `c_vprintf` as
  the same splitter at runtime over a CVaList. Fixture: byte-diff against native printf
  output for a conversion battery (this fixture is also the differential-suite
  insurance policy).
- **P1.5 Suite runner + ratchet.** `suites/` fetches c-testsuite; runner converts, runs
  interp, diffs expected output and exit codes; ratchet state checked in; skip ledger.
  Acceptance: runner executes end-to-end on the P0-subset tests (however few pass).
- **P1.6 Lowerings, in spec order:** promotions/usual-arithmetic-conversions pass
  (emit-explicit-casts; small-int promote/truncate), statement-ification (temps,
  ++/--, comma, side-effecting &&/||/?:), all operators and the cast table, if/while
  (1:1), do-while (first-pass flag), general for (increment-first flag; O1 range-form
  recognition can wait for P7), scalar functions and locals/globals, `exit`.
  Each item = spec section + fixtures + ratchet delta.
- **P1.7 Profile race** (small, deferrable to P7): for-loop B' vs body-block `finally`.
- **Exit criterion:** c-testsuite scalar/control-flow tests green; ratchet
  infrastructure proven; c_runtime tests green standalone.

## P2 — Aggregates, pointers, enums, strings, globals

**Goal: the memory model — everything the layout law licenses.**

- **P2.1 Structs.** Layout read-out from clang (assert equal to das `typeinfo` for
  unpacked types — the layout law is probed, keep the assert anyway), plain-`=` copies,
  by-value param callee-copies (only when written), returns, prefix punning,
  `sizeof`/`offsetof` → `typeinfo` emission.
- **P2.2 Arrays.** Exact-size `fixed_array` literals (pad or decl+assign per spec),
  multi-dim, row pointers (`T[3]?` — mind `? [` spacing), decay, OOB-panic policy +
  sidecar demotion hook.
- **P2.3 Pointers + `[c_function]` application.** The cast table; annotate only
  functions containing unsafe ops (the count is the port-progress metric — report it).
- **P2.4 Enums.** das enums per spec (casts at arithmetic/relational/index sites,
  `enum_from_int`, count-as-dim).
  Ledger (fail closed or loud today, each a later row): an enumerator reached through a
  macro expansion (no main-file cursor; two constants of one expansion share a location),
  an enum defined in a header, an enum tag that is also an object name in scope
  (`enum color color`: das has one namespace, so `color.GREEN` resolves to the variable),
  an anonymous enum or record nested two levels deep, a typedef name shared by a record and
  an enum across scopes, a definition inside a `sizeof` or cast operand; and one silent
  divergence shared with the small-integer path since P1.6: `++`/`op=` on an lvalue with
  side effects (`(*next())++`) evaluates the lvalue twice, to be settled by a single
  address temporary (settled in P4.8: the target is pinned, its effects evaluated once).
- **P2.5 Strings.** Literal policy (das literal reinterpret for `char*`, `cstr_array`
  for mutable `char[]`), interning, the `reinterpret<string>` bridge at logging sites.
  Ledger: a C character literal reaches the das text as its number (`44`, not `','`),
  since the C-IR `int_lit` carries no character provenance - a readability row for the
  spec (an additive `char` marker) when the follow-up story asks for it.
- **P2.6 Globals & statics.** Zero-init pass-through, value inits at declaration,
  address-carrying inits inline-where-legal else `[init]`, statics naming, `var private`.
- **P2.7 Marshal-reader generator.** For packed/disk types from clang's packed layout
  (sidecar-flagged types only at this stage).
- **P2.8 gcc-torture `execute` import.** Filter script + ledger; ratchet begins.
- **Exit criterion:** c-testsuite ≥ 90% of applicable; torture ratchet climbing;
  struct/array/pointer sections green.

## P3 — Control-flow completeness

**Goal: everything that jumps.**

- **P3.1 switch.** Tier 1 if/elif (no fallthrough, tail-only breaks), tier 2
  matched-flag loop (fully spec'd + probed, incl. `_cont` epilogue), tier detection.
- **P3.2 goto.** Label allocation, C-names-as-comments, goto-into-nested-block
  flattening, goto-over-declaration (C-exact semantics probed — nothing to do, but add
  the fixture).
- **P3.3 Duff's device.** The state-machine fallback — this is the one place you get to
  design; write the spec into lowering-examples.md first, get it reviewed, then build.
- **P3.4 setjmp/longjmp.** The try/recover + `_c_jmp_target` protocol (fully probed);
  contained pattern first, general trampoline second.
- **P3.5 alloca.** das-stack fixed arena + limit guard + `options stack` sizing in the
  sidecar; torture's alloca tests join the ratchet.
- **Exit criterion:** torture control-flow and alloca sections green; no goto-family
  ledger entries left except Duff-class (if any survive, they're state-machine bugs).

## P4 — Punning tier + differential fuzzing

**Goal: the last semantic mile, then the truth cannon.**

- **P4.1 `[c_bitfields]` macro.** Generates the probed backing-unit + property-operator
  layer from clang bit offsets; fixtures replicate the probe battery (signed sign-extend,
  truncation, compound assign, layout).
  Ledger (fail closed today, each a later row): a bitfield of enum type (the property pair
  would convert through `enum_from_int`); a bitfield of a marshal-only record (the bits read
  and written through `memcpy` of the unit); a flexible array member; `aligned(N)` on a record
  with bitfields; and a `_Bool` step, plain or bitfield (`b++`, `s.f++`).
- **P4.2 `[c_union]` macro.** One ref-returning operator per member (probed); storage
  alignment via max-align member type; anonymous-union flattening.
  Ledger (fail closed today, each a later row): a union's bitfield member of enum type; a union
  the layout law finds unnatural - clang's alignment past 8 (`aligned(16)`: no unsigned storage
  type aligns there) or below a member's (`packed`) - which waits for marshal to cover unions; a
  union holding a marshal-only record, and a marshal-only record holding a union; a union
  initializer outside a declaration (compound literals); an initializer of a union naming an
  anonymous member (`field` names `""`); an anonymous member that makes no field name visible
  (`struct { int : 4; }`), whose offset libclang gives only through `clang_Type_visitFields`,
  which dasClangBind does not bind yet; two anonymous records one macro expansion makes
  indistinguishable (`#define TWO REC(a); REC(b)`, one key or one `(anonymous at f:l:c)`
  spelling); a C tag spelled `anon_<N>` beside an untagged record whose slot is `N` (both spell
  `anon_<N>`, which predates unions); and the forwarding operators that would spell `s._anon1.i`
  as `s.i` (F29). Outside the dialect: a GNU zero-length array (`char z[0]`, gcc-torture
  zerolen-1) and GNU's cast to a union type (`ToUnion`, 960416-1).
- **P4.3 Function-pointer shims.** The sidecar-declared dispatch groups (`actionf_t`
  class); qsort/bsearch typed generics land here too.
  Landed instead of the shim (`docs/probe-findings.md` F32): a union of function pointers is a
  `[c_union]` over one 8-byte storage and a cast between function types a `reinterpret`, which
  a call through any member or type takes as x86-64 C does, so no sidecar entry; `qsort` is the
  runtime's byte sort and `bsearch` a binary search in `c_runtime/c_sort` (F33); a function
  type's `var` positions are those of the value-taken functions of its signature (F34).
  Ledger (fail closed today): the value of a function the unit does not define (`strcmp` as a
  comparator), which needs a das function of C's type per libc function; a pointer to a
  variadic function (c-testsuite 00189, `fprintf`); a function returning a function pointer,
  whose spelling `int (*(int, int))(int)` the dumper does not parse (c-testsuite 00124); a call
  with arguments through an unprototyped function pointer `T (*)()`, which the C-IR spells as
  `T (*)(void)` until it marks it; a wide string literal (`L"ab"`; the torture filter skips its tests, 20010325-1 among
  them, which passed only because the narrow bytes indexed alike), whose bytes the dump gives
  narrow; and a `let` pointer passed into a `var` pointer parameter (P4.6).
- **P4.4 va_list completeness.** `va_copy`, forwarding, non-constant printf formats,
  scanf-family split.
  Landed: a variadic definition is `[variadic]`, and a call of one the module defines is
  spelled as the macro expands it, `f`va(…)` (`docs/probe-findings.md` F37); a `va_list` is the
  runtime's `CVaCursor`, the list's address and a position, `va_copy` its assignment and a
  `va_list` parameter the caller's cursor (F35); forwarding passes `va_rest` of the cursor to
  `c_vprintf`, `c_vsprintf`, `c_vsnprintf` and `c_vsscanf` (F36); a non-constant printf format
  takes `c_vprintf`'s run-time split as before; `sscanf` is `c_runtime/scanf`, one CRT `sscanf`
  per directive (`crt::sscanf_one`, `crt::sscanf_none`); an `l` directive of either family takes
  the dialect's `long` width (`c_long_bits`, set by the converted module), never the host CRT's;
  `va_list` is an opaque C-IR record (F39). gcc-torture: 27 of the 67 `va_start` tests pass
  (none before), and 20030914-2, a variadic definition reading no argument (652 to 680);
  c-testsuite holds at 192.
  Upstream (daScript): a failed module-cache write fails the compile
  (https://github.com/lookibed/daScript/issues/16), and the serializer refuses a same-module
  call macro inside a generic body (https://github.com/lookibed/daScript/issues/15), so a cold run of a `[variadic]` body
  calling its module's own macro exits 1 before `main` (F37); the converter spells the call as
  the macro expands it instead.
  Ledger (fail closed today): `va_arg` of a record and a record passed through `...`, for
  which `CVal` gains a bytes arm (gcc-torture 920625-1, 920908-1, 931004-2, -4, -6, -8, -10,
  -12, -14, pr44575, strct-stdarg-1, strct-varg-1); a `va_list` global, field, array or pointer
  (stdarg-1, stdarg-2, stdarg-3, va-arg-13, va-arg-14, va-arg-trap-1); `va_arg` of a `va_list`
  and a `va_list` passed through `...`; a pointer to a variadic function, which the tuple ABI
  gives no function-value form;
  `fprintf` and `vfprintf` to any stream, since `crt` writes stdout alone (vfprintf-1), and the
  stream scanf family (`scanf`, `fscanf`); a wide `%lc`/`%ls` under a dialect whose `wchar_t` is
  not the host's. Waiting on other rows: va-arg-4 (a `char[N]` member initialized from a string
  literal), 20041113-1 (`main` with arguments); va-arg-9, va-arg-10 (a `let` pointer into a
  `var` parameter) and multi-ix (forty `int[500]` locals past the 16 KiB default context stack)
  passed with P4.6's uniform `var` policy and 8 MiB module stack. Outside the dialect: GNU nested functions
  (nest-stdar-1) and GCC's `__builtin_va_arg_pack` and `__builtin_apply`, which clang does not
  know (va-arg-pack-1, pr47237; `filter.das` phase `never`).
- **P4.5 csmith differential.** Nightly N=1000 seeds vs `gcc -O0 -fwrapv`; any
  divergence is a converter bug by construction; creduce harness for minimization.
  Ledger: an address one past an array's end formed by indexing (`&a[N]`, gcc-torture
  strlen-5) trips das's range check; spell `&a[k]` as `addr(a[0]) + k` where `k` can reach `N`.
  Landed, run on demand (`scripts/run_suite.sh csmith`): `suites/csmith/fetch.sh` builds csmith
  at `0cdc710` and, with `--cvise`, cvise 2.12.0 at `134d6f6` against the pinned libclang
  (creduce is the alternative `reduce.sh` takes as its second argument); `run.das` judges each
  seed against the pinned gcc 14.2.0 at `-O0 -fwrapv -w -funsigned-char` in one worker process
  per seed, csmith run with `--no-argc --no-packed-struct` over its defaults, the seeds known
  clean the ratchet (`expected_pass.txt`), an `output` or `exit` verdict failing the run;
  `reduce.sh` minimizes a seed while it keeps its verdict. The ledger item: `&a[k]` whose `k`
  can reach `N` is `addr(a[0]) + end_index(k, N)` (`c_runtime/c_bounds`), a constant `N`
  `addr(a[0]) + N` (`docs/probe-findings.md` F45, F48). The classes csmith found, each fixed
  with its probe and a `p4_csmith_*` fixture: a shift's count in another type (F40), an all-null
  pointer array (F41), a local hiding an enclosing one and nested discards (F42), a
  small-integer subscript (F43), pointer equality across constness (F44), a pointer parameter
  returned or copied out (F46), and references rebound by spelling in the dumper (F47). Two
  samples of 200: seeds 1 to 200 while the row was built (114 pass, 25 native, 61 convert, every
  convert class fixed above or skipped below) and 200 random seeds after the fixes (126 pass, 24
  native, 50 convert, none diverging in output or exit). The ratchet holds the second sample's
  126 and seed 1; the 52 skipped seeds are other rows' fail-closed features: Duff-class gotos
  (24, P3.3), union bitfields and F5 layouts (26, P4.7) and a `let` pointer into a `var`
  parameter (2, P4.6). gcc-torture 680 to 732 (strlen-5, the shift family and 960116-1
  among them), c-testsuite 192 to 193 (00129).
  Open under the P4 exit criterion: the nightly N=1000 schedule, blocked on this box by the
  dumper's parse of clang's JSON dump (about 170 MB per csmith program, most of a seed's 5 to
  60 s). A coverage item: csmith's `--binary-constant` (GNU `0b` literals) stays off until the
  dialect reads them.
- **P4.5a Perf tracking.** `perf/results_linux.json` is re-recorded on the current tree (the
  capture of 2026-10-06 predates every item since P2.4, which `perf/REVIEW.md` already
  forbids) and from then on after every finished ledger item. `perf/run.das` gains the ratio
  table, lane time over native per kernel and lane, and the delta against the previous
  capture (the committed file before the run, or `--baseline <json>`); the ratio table and
  the delta go into the progress log entry and the commit message of the item. A lane that
  got slower by more than 10 percent on any kernel is flagged in both and explained or
  fixed before the commit.
- **P4.5b AOT anomaly.** The `aot` lane is 4x to 10x native on `sieve`, `matmul` and
  `fixed_mandel` while `jit` and `exe` sit at about 1x. Find the root cause: profile the
  AOT host, read the generated C++ for the three kernels, compare with the JIT over the same
  module (`perf/ARCHITECTURE.md` section 3 names the `das_copy` lambdas of struct-returning
  calls as the lead). A cause in the emitted shape, the tiers host or its compile flags is
  fixed here; a cause in daScript's AOT gets a minimal standalone repro and an issue in
  lookibed/daScript, the way #15 and #16 were filed. Either way a `docs/probe-findings.md`
  row records the finding and the capture is re-recorded. The row also owns the
  `fib_recursive` AOT cell at 0.01x native (the FX-6300 capture): the host's GCC 14 at `-O2`
  turns the second recursive call into a loop and unrolls levels, so the cell is a real time
  of a cheaper program than clang's `-O3` native build, not a kernel time; decide whether the
  AOT host compiles with the pinned clang at the native lane's flags so the two lanes
  compare, and record the decision in `perf/ARCHITECTURE.md`. The `exe` cell of
  `fib_recursive` (12.8 percent slower than the P2.3 tree on the same CPU with the converted
  kernel unchanged) is carried to P7.3.
- **P4.5c Readability metric.** `metrics/readability.das` (run by
  `scripts/run_readability.sh`) converts the suites' tests and the perf kernels and counts,
  per converted module and in total: `[c_function]` functions, `unsafe` blocks and
  `unsafe(...)` expressions, pointer-arithmetic sites, `reinterpret` casts, goto and label
  lowering sites, numeric literals where the C source has an enum or a named constant for
  the value, and raw `while` loops a `range` loop could spell. The totals are committed as
  `metrics/readability_linux.json` and ratchet like the suite pass lists: a count only goes
  down, and a commit that raises one says why in its message; `metrics/REVIEW.das` gates
  the file's shape. Every item's progress log entry prints the totals beside the test and
  perf numbers.
- **P4.6 Pointer constness: the uniform `var` policy.** A pointer parameter is `var` only where
  the body writes through it (F3), and das takes no `let` pointer for a `var` parameter, so a
  `let` pointer a caller holds - its own parameter that it never writes through, a field of a
  by-value record parameter, reached through `?:` or a cast - cannot flow into a callee's `var`
  parameter, by a direct call or through a function value whose type has a `var` position; the
  emitter fails closed there ("a pointer the callee writes through arrives through const
  parameter"). Making every pointer parameter `var` closes the gap but meets a const record
  lvalue: `var copy = s` of a by-value record parameter holding a pointer is "can't assign
  'S const.p: int? = int? const'", so the row is the redesign of F3, not a flag. c-testsuite
  00181 and gcc-torture 990128-1 wait for it, and csmith seeds 127 and 86922302 (a `let`
  parameter passed to a callee that returns its own pointer parameter). A pointer field of a
  by-value record parameter returned or copied out (`return s.p`) fails closed the same way.
  The redesign folds the emitter's three pointer walks - `mark_copied_pointer` (what a copy
  reads), `const_pointer_root` (what a call passes) and `mark_store_root` (what a store writes
  through) - into one.
  Landed: every data pointer parameter is `var`, and so is every by-value record parameter whose
  type holds a data pointer in a field or an array; a record holding no pointer stays `let`
  (`probes/test_param_constness.das`; F3, F46). A function type's positions follow the parameter
  rule, so every function of a C type fits it and `c_runtime`'s `CCompare` takes `var` pointers,
  a comparator arriving with no cast (F34, F33); a cast between two function pointer types that
  spell one das type is no cast. Every record parameter is copied on entry, `let` and `var`
  alike, which also fixes a by-value record reading the caller's object when the callee writes
  it through another pointer during the call (`f(a, &a)` returned 5 where C returns 1, F50); a
  scalar or pointer parameter the body writes is `var` and written in place, since das passes it
  by value. Every converted module spells `options stack = 8388608`, C's linux default, unless
  the sidecar sets `stack`, since das's 16 KiB default overflows on a record copy
  (gcc-torture pr20621-1's 64 KiB record, a recursion of 4000-byte ones). A hoisted temporary
  holding a pointer (an initializer list's item, an alloca's address) is `var`, and so is a
  marshal-only record writer's parameter holding one. The three walks fold into one pass over
  `each_expr` naming the scalar parameters the body writes; both refusals of a `let` pointer go,
  the shapes they refused now `converter/tests/fixtures/p4_pointer_policy.c`. c-testsuite 193
  to 194 (00181); gcc-torture 732 to 743 (990128-1, va-arg-9, va-arg-10, 20000314-3,
  20020406-1, pr99751, and 980223, a written record parameter holding a pointer; 920410-1,
  memcpy-1, multi-ix and nestfunc-4 under the 8 MiB stack); csmith seeds 127 and 86922302 leave
  `skip.txt` and join the ratchet.
- **P4.7 Layout leftovers.** Bitfield members of unions, named or padding (the P4.2 ledger), and
  records outside the layout law (F5, the P4.1 ledger). csmith generates both in about one seed
  in eight; their seeds are skipped under this row.
  Landed: a union's bitfield member is `[c_union(f0 = 8)]`, a property pair at bit 0 over the
  storage's leading elements, and an unnamed one is no member, its bits carried by `size =`/
  `align =`; where no naturally aligned unit reproduces clang, the layout law's relaxed search
  adds padding fields (`_pad<N> : uint8[n]`), units at the offset their size divides below the
  bits, and byte units (`_bits<N> = "uint8[k]"`), restoring clang's offsets and size with the
  das alignment at or below clang's (F5's last column); one bit arithmetic in `c_storage` serves
  both annotations. Lifted with it: a record no unit assignment reproduced, a record whose only
  bitfields are unnamed padding, a record holding an F5 record that clang's size refused
  (`converter/tests/fixtures/p4_layout_leftovers.c`). A record an attribute aligns past its
  members stays refused with a message naming the attribute. A record declared `packed` or under
  `#pragma pack(n)` that the relaxed search places converts like any other (F51). A bitfield's
  step and compound store spell the getter and the setter apart, `x = x + 1`, since a compound
  store to a property through a field of `deref(p + k)` crashes daslang before `main` (F52,
  lookibed/daScript#17). csmith 129 to 148: 19 of the 26 seeds pass and leave `skip.txt`; the
  other 7 now refuse a goto into a loop body and are ledgered under P3.3; gcc-torture 743 to 750
  (20181120-1, bitfld-6, bitfld-7 and pr58726, union bitfield members; pr58984 and pr60017,
  records the relaxed search places; pr58570, a `pack(1)` record whose two bitfields join into
  one 6-byte unit).
- **P4.7a Parameter write mode.** The first case of the "Speed vs idiomatic output" decision
  (very-detailed-plan.md section 1, ruling 2026-10-20): P4.6 writes a scalar or pointer
  parameter the body assigns, steps or takes the address of in place (a `var` parameter, no
  copy), the idiomatic form, which costs the interpreter 14% on `blit` (P4.6's FLAG: a write
  to an argument slot is slower than a write to a local). The converter flag `--param-writes
  in-place|copy` (default `in-place`), also the sidecar key `param_writes`, chooses between the
  in-place write and a local copy of every written scalar and pointer parameter (the callee
  copy under a free name, as before P4.6, the parameter itself `let`); nothing else about the
  output changes between the modes. Each mode: a native-compared fixture converted and run in
  both modes by test_lowerings (so preflight runs both); the perf lane `interp-copy`, the
  interpreter over the copy-mode conversion, beside `interp` in `results_linux.json`, the
  README table and the report; the readability capture's keys `perf/<kernel>@copy` for the
  kernels under both modes. The kernel `blit` covers the parameter write in both modes.
  Landed: `--param-writes in-place|copy` in `converter/main.das` and the sidecar key
  `param_writes`, the option over the key; under `copy` a written scalar or pointer parameter
  is `n_in` (the record copy's free-name rule) and the body opens with `var n = n_in`, the
  parameter keeping its own mode, a pointer `var`, since a `var` copy of a `let` pointer
  parameter keeps a const pointee (`probes/test_param_constness.das`, `test_param_copy`); a
  `va_list` parameter stays in place in both modes. Every fixture converts byte-identically
  under the default and under an explicit `in-place` (both targets), and every one runs as its
  native build under `copy`; `converter/tests/fixtures/p4_param_writes.c` runs in both modes in
  test_lowerings. A sidecar without `marshal` is no longer refused (json_boost's `?[]` of a
  missing key is a non-null sentinel, `probes/test_stdlib.das`). The `interp-copy` lane runs
  `blit` 10 percent faster than `interp`, the only kernel whose module the mode changes; the
  readability keys `perf/<kernel>@copy` count the same as their in-place keys.
- **P4.8 Scope fidelity.** A block flattened for a goto into it whose local hides a same-named
  global (`int g = 40; ... goto in; { int g = 3; in: ... } printf(g)`: the flattened local
  captures the later reads of the global, which the emitter refuses), and a local declared under one case label and
  used in later cases (`case 0:; int v = 1; ... case 1: v = 7;`), which the switch lowering
  scopes to its own case, so the compile check fails.
  Ledger: a value-producing step of an lvalue whose index has an effect evaluates the effect
  twice, `int v = arr[k++].a++;` lowering to `let _t1 = k; k++; let _t2 = k; k++; let _t0 =
  arr[_t1].a; arr[_t2].a++` (gcc prints `0 1 1 0`, the conversion `0 2 0 1`); the
  value-producing step reuses the index the read hoisted. The P2.4 ledger's `(*next())++` is the
  same family, and so is an assignment used as a value: the emitter stores, then reads the
  left-hand side again, so `if ((*p++ = *q++))` lowers to `var _t0 = p; p = p + 1; ...;
  deref(_t0) = deref(_t1); var _t2 = p; p = p + 1; if (deref(_t2) != 0)` (native prints `1 1`,
  the conversion `0 2`; `while ((*d++ = *s++))` copies nothing); the value read is the stored
  value, through the temporary the store used.
  Landed: a local of a block a goto enters, which loses its braces, and a local a lowered switch
  carries take a free name when a global or another local of the function spells theirs (`g1`);
  a declaration at a switch body's own level that a statement under a later label names is
  declared before the lowered switch as a bare `var v : T`, its initializer the assignment that
  stands where C declares it, and one filled by stores (a union's list, a sparse array) fails
  closed (F53). A step, a compound store and an assignment read as a value pin their target
  first: the pointer, index or record value in it that has an effect is evaluated once, into a
  temporary unless its text already is one (a variable's own name, `i` of `++i` or `p` of `p =
  q`, changes under a call later in the statement), and every spelling of the target reads it
  (`var _t0 = next()` then `deref(_t0)++`; `deref(p + _t0).bf = uint(int(deref(p + _t0).bf) +
  5)`, the F52 form with one call of the index); the value of an assignment is the target read
  after the store through the same temporaries (`converter/tests/fixtures/p4_scope_fidelity.c`).
  A declaration at a switch body's own level counts as named under a later label only where no
  declaration of that statement binds the name (a later case's block or `for` declaring its own
  `u` leaves the switch's `u` where it is). No other fixture and no kernel converts differently
  under either target.
  Ledger: the value of an assignment is its target read after the store, so a sibling later in
  the statement whose effect changes the target or its index gives the read a changed value:
  `reset() + (a[i] = 7)` with `reset()` zeroing `i` lowers to `a[i] = 7` then `reset() + a[i]`
  (native 107, the conversion 101), with or without a pinned target (`*next() = 7` reads
  `deref(_t0)` after the call too). The read belongs right after the store, into a temporary,
  when a later sibling has an effect; settled with the first suite program or Lua (P5.3) that
  hits it.
- **P4.9 Matrix and suite leftovers.** The `docs/c-feature-matrix.md` rows the P4 phase-end
  audit found without a green fixture, and the gcc-torture skip lines for string literals that
  named a bare phase (the 436 `__attribute__` and `__builtin_*` lines still name `P4`: the row
  that homes them is the owner's call). Each is the matrix line, then today's behaviour:
  a pointer to a struct the unit never defines (line 41, `struct opaque; static struct opaque
  *keep;`) emits no forward struct, so the compile check fails ("don't know what 'opaque' is",
  error 30817; a function returning one, 30814) - a bug; a VLA `int a[n]` (line 29) is refused
  with the zero-length-array message, since the dump gives the array count 0 (`converter/emit.das`,
  "a zero-length array (a GNU extension) is not lowered yet"), so the message names the wrong
  construct; a flexible array member (line 33) is refused ("flexible array member ... is not
  lowered yet") and the sidecar has no key for it; a compound literal outside a union
  initializer (line 52) is refused by the dumper (`CompoundLiteralExpr`; the union case is the
  P4.2 ledger); `_Alignof` (line 70) is refused by the dumper ("`alignof` is not dumped yet");
  `main(argc, argv)` (line 113) is refused by the emitter ("main with arguments is not lowered
  yet"; gcc-torture 20041113-1 waits for it); the general setjmp form `int r = setjmp(b)` (line
  101) is refused by the emitter ("the general trampoline form"); a wide string literal and a
  string literal in a 2-D char array initializer (`static const char s4_2[2][4] = {"1234",
  "5678"}`, "a string literal outside a pointer context is not lowered yet") are the
  gcc-torture skip lines naming this row (20010325-1, wchar_t-1, widechar-2, widechar-3; memchr-1,
  pr86714, strlen-2, strlen-6). Fixtures still owed for shapes that convert right today but only
  suite programs or a scratch conversion show: `_Alignas` (line 32), `exit()` from deep in the
  stack (line 114), `~` and binary `^` (line 63), `restrict` (line 39), K&R parameters (line 109),
  `inline` (line 111), `long double` (line 22), `volatile` on a plain field (line 38) and the comma
  operator as a value (line 69). The sidecar's platform defines for `#if` (section 6, "converter
  runs clang with fixed defines from sidecar") have no implementation. Duff's device (line 96)
  stays P3.3, which never landed: the 31 csmith skip lines name it.
  Upstream (daScript): the AOT lane of the kernel `switch_local` has no cell, since daslang's AOT
  writes a das `goto` past a `var` declaration as a C++ goto past an initialized local, which
  clang++ refuses ("jump bypasses variable initialization"; `perf/ARCHITECTURE.md` section 4);
  the issue with a standalone repro is owed. `perf/run.das` takes the failed AOT link for a
  built lane (`run_tier` returns the link's exit code, which passes its `>= 0` test) and reports
  the missing binary's exit 127 instead of the link error.
  Landed (phase A): a record the unit declares and never defines is an empty `struct Name {}`;
  a VLA fails closed in the dumper naming the declaration (`int a[n]`); `_Alignof` dumps as
  `alignof_v` and emits `typeinfo alignof`, clang's value where das aligns the type lower (F54);
  a string literal initializing a row of a `char` matrix or a record's `char[N]` field is
  `cstr_array`, which takes pr86714 and strlen-6 to passing (strlen-2 meets a `void`
  conditional; memchr-1's skip line moves to its wide literals); wide string literals are
  `never` on the skip ledger; a K&R parameter converts from its promoted type on entry
  (F55); the sidecar's `defines` reach clang as `-D`; `perf/run.das` reports a failed AOT host
  build as the lane's error; `converter/tests/fixtures/p4_matrix_shapes.c` carries these and
  the owed shapes (`_Alignas`, `exit()` from deep, `~` and `^`, `restrict`, K&R, `inline`,
  `long double`, `volatile`, the comma's value).
  Landed (phase B): a compound literal is its value where C reads one (`S(f = v, ...)`, a scalar's
  value) and otherwise an object `_clN` declared before the statement in the enclosing block (an
  array, a union, an address taken), a module global at file scope; `main(int argc, char **argv)`
  takes its arguments from `c_runtime/c_args`, `argv[0]` the source's stem (F56), and the
  converter's `--arg` passes them to a `--run`; the general setjmp form (`r = setjmp(buf)`, `int r
  = setjmp(buf)`, `setjmp(buf);`, `return setjmp(buf)`, a `switch` on it, an `if` testing it
  against a nonzero integer constant) opens the trampoline's tail with the value read as
  `_sj_val`, ISO C 7.13.1.1's shapes alone (F58); a flexible array member is read through the
  record's address plus its offset with no sidecar flag (F57), and a C89 trailing array the
  sidecar lists under `over_indexed` goes unchecked through its decay; a `void` conditional
  evaluated for its effects is an `if`/`else`, which takes strlen-2 to passing; `perf/run.das`
  reports a failed exe build as the lane's error; `perf/kernels/compound_lit.c` and
  `setjmp_general.c` carry the newly converted constructs; gcc-torture passes 39 more (27 that
  waited on `main(argc, argv)`, 11 on compound literals, strlen-2) and c-testsuite 00149 and
  00150.
  Ledger: still refused, each with its message - a setjmp whose statement reads anything before
  the call, holds another effect or a second setjmp, sits off a block's statement level (an
  unbraced branch, a loop condition) or whose branch or tail leaves an enclosing loop ("setjmp
  whose value is not tested against zero ... (the general trampoline form) is not lowered yet", "a
  setjmp site whose tail leaves an enclosing loop is not lowered yet"); `main` with `envp` ("main
  with an environment parameter (`char **envp`) is not lowered yet"); a flexible array member that
  pads its record or raises its alignment, one of a marshal-only record, and an initializer of
  one; a `void` conditional whose value is read; the `aot` tier's program arguments, since its
  host passes none; a `signed char` array initialized from a string literal, and a string literal
  in braces (`char s[3] = { "ab" }`); a `static` `main`; `_Alignof` of an `aligned` typedef as an
  array's element. A longjmp delivered after the setjmp site's block has ended (C keeps the buffer
  valid until the function returns) aborts the converted program with `EXCEPTION: longjmp`
  (`c_runtime/setjmp.das`) under both the `if` form and the general form, with no refusal at
  conversion. A goto into a trampoline's tail fails the compile check ("can't find label") instead
  of a refusal. A compound literal, or any hoisted temporary, in a do-while condition is refused
  "do-while with a side-effecting condition is not lowered yet" even when it has no effect (the
  fallback of `docs/lowering-examples.md` "Loops: if / while / do-while" is not implemented).
  `_Alignof(long double)` and `sizeof(long double)` on `--target linux` are double's 8, where
  clang gives 16 (F54). An `over_indexed` entry whose record name is both a typedef and another
  record's tag resolves to the last declaration (the other panics at its range check; the dumper
  refuses a true shared tag). memchr-1 converts and passes once its wide-literal skip line
  (`never`) is lifted. gcc-torture 920501-6, which `main(argc, argv)` let convert, fails at run
  time on a goto from an inner loop to a label at the end of the outer `for`'s body ("jump to
  label 1 failed"), a goto lowering defect no fixture covers yet. An enum constant read on a
  line where a macro expanded earlier (`int r = setjmp(buf) < FOUR;`) stops the dumper with
  "enum constant `FOUR`: libclang reports no reference at this location": the dumper's
  reference lookup takes the pre-expansion location.
- **Exit criterion:** csmith runs clean at 1000/night for a week; torture ≥ target with
  ledger; matrix has no row without a green fixture.
  Ledger: the nightly csmith N=1000 schedule is blocked on this box by the dumper's parse of
  clang's JSON dump (the P4.5 ledger line), and P4.9 holds the matrix rows without a green
  fixture.

## P5 — Lua 5.4

**Goal: first real program, and a semantic oracle bigger than all suites combined.**

- **P5.1 Whole-program conversion** of lua + luac (single module or SCC split — first
  real data point on das compile time at scale; measure and report).
- **P5.2 pcall** via the setjmp lowering (`LUAI_THROW/LUAI_TRY` → `c_longjmp`/contained
  pattern — the easy shape, per spec).
- **P5.3 Lua's own test suite** under interp. Expect a long tail of libc exactness bugs
  (strtod, number formatting, string.format) — each fix lands with a fixture.
- **P5.4 Perf snapshot:** fib/nbody/binary-trees, converted-interp vs native lua. Data
  point only; no bar.
- **Exit criterion:** Lua test suite passes under interp; JIT/AOT lanes at least compile
  and run the benchmarks.

## P6 — Doom

**Goal: the metric.**

- **P6.1 PureDOOM import.** Vendored, sidecar authored (defines, marshal types for WAD
  structs, alloca/stack sizing; `actionf_t` needs no entry, F32). Instrumentation patch: per-tic
  checksum (players[0].mo x/y/z/angle/health + P_Random index) — applied to the C
  source, so the native build and the converted build share it by construction.
- **P6.2 Native baseline build** (MSVC /O2) with instrumentation; record reference
  checksum logs for demo1/2/3 on freedoom2.wad and doom2.wad.
- **P6.3 Converts + compiles.** First real whole-program stress after Lua; expect
  module-size issues here if anywhere (SCC split is the tool).
- **P6.4 Boots headless.** `D_DoomMain` to attract screen; framebuffer CRC at fixed
  tics vs native.
- **P6.5 Demo sync.** The ladder: first desynced tic → bisect → fix → repeat until
  demo1/2/3 are 100% on both wads. This is the semantics endgame; every desync is a
  real bug with a tic number attached.
- **P6.6 Playable harness.** dasImgui window (framebuffer texture blit, key mapping),
  PCM SFX to the native audio path, MIDI music via dasAudio strudel_midi_player + GM
  soundfont.
- **P6.7 timedemo.** `-timedemo demo3` realtics for native / interp; publish table v1.
- **Exit criterion:** demo-sync 100%, playable with sound and music, perf table v1.

## P7 — Performance + tiers

**Goal: the 35 fps interp bar and the full table.**

- **P7.1 O1 range-loop rewrite** (unlocks automatic bound-check elision), **O2
  `[unsafe_deref]`**, **O3 `[hint(unsafe_range_check)]`** — sidecar-gated, enabled only
  after demo-sync green, re-verify sync after enabling.
- **P7.2 Profile** the renderer inner loops (R_DrawColumn/R_DrawSpan expected); apply
  O4/O5/O6 only where the profile demands.
- **P7.3 JIT + AOT lanes** green across suites, Lua, Doom; timedemo columns filled. Two
  perf cells carried here from P4.5b: the `exe` lane on `fib_recursive` runs the JIT's own
  LLVM code 5.7 percent slower than the JIT and 12.8 percent slower than the P2.3 tree's
  executable on the same CPU (the binary grew with `c_runtime/` and `dasCRuntime/`; layout is
  the candidate, the executable carries no symbols to check it); and the AOT cells of `sieve`
  and `matmul` (5.4x and 1.4x native) wait for daScript to address a module global by offset
  instead of a hash probe per access (lookibed/daScript#5, F49).
- **P7.4 The bar:** interp ≥ 35 fps at 320×200 (30 accepted floor). Then the writeup.
- **Exit criterion:** the §2 metric sentence of the plan is true, all four columns
  published.

---

## Standing dependencies

- P1 c_runtime items are converter-independent — they can proceed in parallel with P0.5.
- The suite runner (P1.5) blocks all ratchet claims — build it before deep lowering work.
- `[c_bitfields]`/`[c_union]` (P4) depend only on P1 macros, not on P2/P3 — they can be
  pulled earlier if the macro appetite is there.
- Nothing depends on any sidequest.md item; if one lands early (e.g. `[pack]`), swap the
  fallback out behind the sidecar flag.
