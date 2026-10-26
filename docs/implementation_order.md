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
  macro expansion (no main-file cursor; two constants of one expansion share a location;
  resolved by P5.1's location pass: `converter/ARCHITECTURE_DUMPER.md` section 3),
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
  Landed: the dumper takes a declaration as the program's when its file is the main file or
  under its directory, and lays out a libc record the program reaches a member, a variable or
  the size of (`struct tm`, `struct lconv`) from its system header; stdio, time.h and locale.h
  bind through crt with a record pointer as `void?` and `stdin`/`stdout`/`stderr` as crt
  accessors, a C `long` widened into and narrowed out of a crt call where the dialect's `long`
  is 32 bits, `fprintf` and `signal` in c_runtime (`signal` keeps the handler and returns the
  previous one, `SIG_DFL` the null function value, `SIG_IGN` the integer sentinel); a goto into
  another case re-dispatches its switch, and a label in a block other than a loop's body stands
  on `c_label_end()` (F62); a pointer difference keeps its
  subtrahend's parentheses; the sidecar's `defines` take a function-like macro. `lua/` fetches
  5.4.8 with its tests, composes `lua_all.c` and `luac_all.c` with the headers beside them, and
  converts, runs and compares both under `lua/lua.c2das` (`lua/run.das`, `--run --tier
  interp|jit`, a script as `--arg <path>`). On this host: `lua_all.c` dumps in 89.5 s over
  399,010,406 bytes of clang JSON, emits in 3.9 s a 24,610-line module with `[c_function]` on
  776 of 1,080 functions, compile check 8.3 s; `luac_all.c` 78.8 s over 361,265,529 bytes, 3.1
  s, 19,295 lines, 554 of 767, 6.5 s. daslang compiles the lua module in 9.9 s
  (`-compile-only`; `lua -e "print(1+1)"` runs in 9.3 s under the interpreter, 53.9 s under a
  fresh JIT and 9.7 s from its cache), the luac one in 7.8 s (`luac -v` 7.3 s, 37.7 s and
  7.7 s). The native oracles are 383,760 and 284,456 bytes. `lua -e "print(1+1)"` and a script
  over string, table and math print what the native build prints under the interpreter and
  the JIT, and `luac -o` writes the native build's bytecode byte for byte for every file of the
  5.4.8 test suite. One module type-checks and compiles in about ten seconds at this size; the
  single-module-or-SCC-split decision is the owner's.
  Ledger: Lua's error recovery is stubbed until P5.2 (`lua/lua.c2das`: `LUAI_THROW(L,c)=abort()`,
  `LUAI_TRY(L,c,a)={ a }`, `luai_jmpbuf=int`): a Lua error aborts the process. Host-delivered
  signals do arrive and `SIG_IGN`/`SIG_DFL` are honoured, but a converted handler never runs (das
  code cannot run from a host signal), so Lua's Ctrl-C hook (`lua.c`'s `laction`) never fires.
  `errno` after a `<math.h>` call the dialect maps to das `math::` (`log`, `pow`, `sqrt`, `exp`,
  ...) is not reliably set: daslang folds or drops a pure call, and the JIT's `sqrt` is an
  intrinsic (`dasCRuntime/ARCHITECTURE.md` section 7); the crt-bound libm entries set it. A case
  group of a re-dispatched switch holding a plain C label and a goto that leaves the group fails
  closed (F63); so do two `offsetof`s of different members in one macro expansion when one sits
  in an initializer list or where clang's dump keeps no expression (F20), and a C name das
  reserves whose `_c_` form the program also declares. `lua/run.das --run` and the converter's `--run` compare output through a das
  string capture that ends at the first NUL, so a script printing a NUL compares only its prefix.
  Two loud gaps the review's second prover pass found, both older than this item: a label that
  ends a C `for` body (`cont:;` before the brace) fails under the interpreter, since the
  for-lowering's leading `if (...) { break }` folds the rest of the body into an `else` and the
  label ends a block that is no loop (F62; `c_label_end()` after every label is the fix), and
  `in_program` reads clang's `-v` search list with `CPATH`/`C_INCLUDE_PATH` in it, so a program
  header directory named there counts as a system directory.
  Filed against daScript, each with its probe as the repro: F60's
  two defects (the optimizer moving a label into an `else`, lookibed/daScript#8; a loop taking
  a lower-numbered outer goto as its own, #19), F61's generic-instance error (#20), F62's
  unreachable label at a block's end, which `c_label_end()` works around (#22), and F63's
  labelled block that passes no goto outward under the interpreter (#21). The C-IR
  writes no record spelling, which the emitter's `va_list` test reads, so a module emitted
  from a re-read C-IR (rather than the dumper's tree) spells `va_list` and fails its compile
  check.
- **P5.1a Ports repository** (owner ruling 2026-10-22 (2), item A, with its perf addendum and
  the owner's correction of the native lane). `scripts/publish_ports.sh` runs `ports/publish.das`,
  which regenerates `lookibed/c2das-ports`: per program the converted modules, the sidecar, the
  upstream license, and a README naming the release and both tarball sha256s as the `VERSIONS.md`
  line pins them, the generating commit (`git describe` and the full sha; a dirty tree refused
  without `--allow-dirty`), how to run the modules, which upstream tests pass, the harness's report
  of the conversion, and the perf tables; `--commit` commits the program as `lookibed`, `--push`
  pushes. The perf tables time the same workloads (the startup row `-e "print(1)"`, fib,
  binary-trees, nbody and spectral-norm from `ports/lua/bench/`, and the release's test suite)
  as whole processes under the native build and the interpreter, JIT, exe and AOT lanes, built by
  `perf/perf_lanes.das`, the lane module `perf/run.das` now shares (native: the pinned clang at
  `-O3 -funsigned-char`); a lane or cell that does not work is `not yet` with its reason. Every
  sample of every lane lands in a capture file beside the tables; the top-level README carries the
  geometric mean of each lane's ratio to native per program. `ports/ARCHITECTURE.md` holds the
  method. The perf tables are off by default (`--perf` turns them on, owner ruling 3): until the
  perf method audit lands, the published README and projects section carry its `not yet` line,
  and the benchmark scripts stay in `ports/lua/bench/` as its inputs.
  Ledger: the perf tables wait for the perf method audit (ledger item C, `p-perf-method`).
  `doom/` joins at P6. The publisher runs by hand at each phase release; its CI
  invocation is a later pipeline item. The AOT lane is `not yet` for Lua: the AOT host passes the
  program no arguments (`converter/tiers.das`), and the test-suite row is `not yet` under every das
  lane until P5.2 (a Lua error aborts the process). daslang's `json_boost` fails type inference on
  `JV` of a struct holding an array of structs that holds an array of structs, so the capture keeps
  its cells flat (lookibed/daScript#23, `docs/probe-findings.md` F64); popen's timeout watchdog
  delays the return by up to 100 ms, so a sample's clock stops at the end of its output. A
  conversion leaves a stamp of its commit in `lua/work/`, which a `--no-convert` publish must
  match (`--allow-stale` otherwise). `perf/run.das`'s clang and daslang version lines now read
  past `info` lines (`first_reported_line`, the same text on this machine), and its exe and AOT
  builds take the 3600 s build timeout `converter/tiers.das` now passes to every build step.
- **P5.1b1 Multi-TU link** (owner rulings 2026-10-23, 4 and 5: the P5.1b split, the link on the
  dumper's in-memory trees with no C-IR spec change; branch `p5.1b1-multi-tu-link`). `c2das <a.c>
  <b.c> ...` and `c2das --program <p.json>` convert several C files as one program: each file is
  dumped as its own translation unit under the sidecar's `defines`, its `<stem>.cir.json` written
  and round-tripped as before, and `converter/link.das`'s `link_tus` merges the dumper's trees into
  one tree the emitter takes as one unit (one module, named by the unit holding `main`), with
  `program.cir.json` beside them in the spec's section 7 shape (`cir`, `target`, `tus` the units'
  C-IR files, `entry`). A manifest the converter takes names the C files in `tus` (relative to it),
  since the link never rereads C-IR; a C-IR file there, an empty `tus` or another target is
  refused. The link: the type tables merge by structural key (a record and an enum by spelling,
  location-based for anonymous ones), a record incomplete in one unit takes another's definition,
  two layouts or two enumerator lists of one spelling are refused with both locations; each
  external binds to its definition, else its first tentative definition, else its first
  declaration, and two definitions, a name both function and object, two dialects or two units of
  one stem are refused (two definitions at one header location named as such); internal linkage
  belongs to the name (the dumper makes a declaration without `static` after a `static` one
  static); a hoisted local static's `<function>_<name>` is numbered by the dumper past every
  file-scope name the unit declares and every parameter and local of the function (which also
  fixes a one-file program whose local spells that name: it read the local for the static); a
  static keeps its unit and its C name, two of one unit wanting one name refused, and is renamed `<stem>_<name>` when another owner takes the name: an external of the program, a name
  a converted module can resolve besides the program's own (the names mapped to libc, crt or
  c_runtime, every name the emitter spells bare, every public c_runtime definition, every crt
  binding: `reserved_das_names`), a name another unit's code references without a
  static of its own, or another unit's static; the new name is numbered past every file-scope name
  and every parameter, local and label of the units reaching it, and a parameter or local of the
  old name stays untouched; a header's static objects stay one copy per unit, its functions are
  kept once where every copy is byte-identical and every name they reference resolves alike in
  every unit of the copies (an external everywhere, or a static function kept once across them).
  A multi-file program's sidecar is the given one, else the entry file's `<stem>.c2das` (one
  beside another file, or two, refused), else the first file's folder `.c2das`; a file stemmed
  `program` is refused. One file is the one-unit conversion as before (no link, statics keep the
  dumper's `<stem>__<name>`). `lua/run.das` writes `work/lua.program.json` (the Makefile's
  `CORE_O`, `LIB_O`, `lua.c`) and `work/luac.program.json` (the core, `lauxlib.c`, `luac.c`) and
  converts both from the release's `src/` (no `lua_all.c`/`luac_all.c`, no header copy) into
  `work/lua/lua.das` and `work/luac/luac.das`; the native oracles build from the same files;
  `--filter` takes a stem. `ports/publish.das` publishes `lua.das` and `luac.das` and builds its
  native lane from the manifest's files; `perf/perf_lanes.das`'s `native_build_command` takes a
  program's files. On Lua the link refuses nothing and renames nothing, after the review fixes too
  (no Lua static is named like a mapped libc name or a name another file references, and no two
  files of either program share a static name; `writer` of `luac.c` and `lstrlib.c` never meet, since `luac` links
  no standard library), binds 5,829 declarations of `lua` and 4,185 of `luac` to another file's
  definition, and keeps no header function once (Lua's headers define none); the modules hold
  24,048 and 18,843 lines with `[c_function]` on 776 of 1,080 and 554 of 767 functions, the
  composition's counts, the text differing only in the statics' names (no `lua_all__` prefix) and
  in where an external object is defined. On this host, idle: the conversion of both programs
  takes 318.6 s against the composition's 220.0 s, the dumper 144.9 s over 33 files and
  498,177,489 bytes of clang JSON for `lua` (composed: 90.4 s, 399,010,406) and 120.1 s over 22
  files and 431,164,186 bytes for `luac` (81.3 s, 361,265,529), the link 0.2 s each; the compile
  check 8.9 s and 7.0 s (composed 9.0 and 6.9), `-compile-only` 9.75-10.21 s and 7.82-8.10 s
  over three runs (composed 9.81-10.23 and 7.85-7.89). `lua -e "print(1+1)"` and the
  string/table/math script print the native build's output under the interpreter and the JIT, and
  `luac -o` writes the native bytecode byte for byte for all 33 files of the 5.4.8 test suite.
  The review pass (grounding, prover, targeted, tdd-auditor) found three silent wrong outputs (a
  header copy kept once reading another unit's name, a renamed static captured by a local of its
  new name, a static named like a libc function taking another unit's libc call) and two loud
  failures (a static prototype before a definition without `static`, a hoisted local static and a
  file-scope static of one name); its second targeted pass two more silent ones (a numbered name
  taken by a local, a hoisted name equal to an external the unit references); its third pass one
  more (a renamed static taking a name the module spells bare: `end.c`'s `index` as `end_index`,
  the c_runtime helper an array pointer spells, read wild memory); all are fixed and tested
  (`tests/fixtures/p5_multi_names`, `p5_multi_hoisted`, `p5_multi_reserved`, and a test that fails
  when a public c_runtime definition is missing from the reserved list), with
  the sidecar rule above and the refusals of a field-order or dimension-only layout difference.
  Ledger: the ports repository still holds `lua_all.das` and `luac_all.das` until removed by hand
  at the next publish (the publisher deletes nothing). A header function kept once has one address
  where C gives each unit its own (`p_fp() == twice` across units is 1, natively 0). The reserved
  set holds the module's fixed names, not the pattern-named ones the emitter generates
  (`read_<record>`, `write_<record>`, `_cl<N>`, `anon_<N>`): a renamed static of a unit stemmed
  `read` or `write` could still meet one. `extern T a[];`
  in a shared header referenced in a unit not defining the array is refused per unit by the dumper
  ("a reference ... before a definition gives its array a length") where the link could size it.
  Two units with different anonymous `typedef struct {...} T` are refused as a layout clash of
  `struct T` though C allows them. One typedef name with two targets in two units is not refused
  (the lead's ruling asked for a refusal; it would refuse valid C the emitter handles, the
  typedefs being transparent: prover c10 prints the native output), so a sidecar key naming such a
  typedef (`marshal`, `over_indexed`) resolves to the last. A program whose headers sit outside its C
  files' folder needs them copied beside those files (the dumper's program-files rule holds per
  unit); a manifest naming the program's root is not implemented, Lua needing none. A non-static
  C99 `inline` function a header defines in several units is two definitions and refused, the
  message naming `inline` and both units. A
  one-file program keeps `<stem>__<name>` for its statics where `docs/lowering-examples.md` names
  them bare (renamed only on a cross-TU collision), as before this item. `lua/REVIEW.md`'s
  composition rule names `composes`; its wording joins the phase-end audit.
- **P5.1b2 Source module layout** (owner ruling 2026-10-23, ruling 4, after Boris 2026-10-08; the
  decisions row "Module layout" of `very-detailed-plan.md` section 1; after P5.1b1). Over P5.1b1's
  link, the output mirrors Lua's `src/`: `lapi.c` -> `lapi.das`, a set of mutually dependent files
  -> `<first_stem>_cluster.das` with a `<stem>.das.inc` fragment per member, an entry module with
  `main`. The partition is the Tarjan SCC of the unit reference graph (an edge from a unit to the
  owner of each function or object it references and to the owner of each type its declarations
  spell); a singleton is `<stem>.das`, a component `<lexically first stem>_cluster.das` with a
  `<stem>.das.inc` fragment per member sharing one module scope through a cluster renamer; a
  header's types go to `<header>_h.das`, never to the same-stem `.c`; the entry module holds
  `main`; the emitter splits into program and module state; `--layout source|single` with the
  sidecar field `layout`, default `source`; the single module stays an opt-in (a converter flag and a `.c2das` field). The mechanism is
  not Lua's: no Doom here (P6). Acceptance: everything P5.1 proves holds in both layouts (`lua -e
  "print(1+1)"` and the string/table/math script print the native build's output under the
  interpreter and the JIT; `luac -o` writes the native bytecode byte for byte for every file of the
  5.4.8 test suite), tested in the repository's style; `ports/publish.das` copies the module tree;
  preflight `--full` green, the suite counts held. Report: the modules and fragments, every cluster
  with its members, the largest cluster and why its files are linked, the count by Boris's include
  rule beside it, compile-check and `-compile-only` seconds and `lua -e` startup under the
  interpreter, a fresh JIT and the JIT cache for both layouts, readability and perf captures for
  both.
  Done (branch `p5.1b2-source-layout`), with owner ruling 2026-10-24 (6), the cycle cut: plain SCC
  is a monolith on real programs (Lua's core one cluster of 15 files; the Rust c2das put 51 of
  PureDOOM's 62 files in one), so the default `source` layout cuts the cycles where the cut is cheap,
  by late binding; `scc` keeps every cycle one module of fragments; `single` is P5.1b1's module.
  `converter/layout.das`'s `plan_layout` partitions the linked program inside `link_tus`'s scoping
  block (statics renamed and header copies kept per module); a record a header spells is the
  header's even where a unit defines it (`struct lua_longjmp` of `ldo.c` is `lstate_h`'s), so no
  header requires a unit; in each strongly connected component the edges a cut cannot late-bind (an
  object, a function whose address is taken or whose type spells a unit's record, a type edge, an
  edge whose source spells a record its target unit defines, `layout.keep_together`, an edge above
  `layout.threshold`) collapse into groups that stay one module, the entry module is highest (a
  group with a never-cut path to it joins it, every edge into it is cut, every module left without
  a require is required by it), and among the groups the cut is a minimum weight feedback arc set
  (exact over the subsets up to 16 groups, ties to fewer modules without a caller, else greedy),
  the `layout` options refused when they name what the program does not hold, each edge weighed by its symbols' dynamic call counts from the
  calling file in the profile `layout.profile` names, else by its call sites; `layout.cut` forces a
  cut. A cut symbol's slot and same-named wrapper (failing closed while unbound) live in the
  generated `<entry>_link.das`; the defining module binds it at `[init]` (a variadic one through a
  private function taking its `CVaList`, `c_runtime/variadic` taking a built list as it is) and
  spells its own calls `__::name`, a module requiring it and the link module `<module>::name`; the entry module requires every module it would not reach
  otherwise. `program.layout.txt` beside the C-IR lists the cut. `emit_program` spells the modules
  over one `EmitProgram` state with a fresh module `Emitter` each, a cluster's file holding the
  requires, the empty literal, the dialect `[init]`, its `include` lines, the fragments' digest
  (F72), the layout check, the module-init stores and the wrapper; one file is one module in each
  layout; `single` is P5.1b1's text byte for byte (107 single-file inputs and the four multi-file
  fixtures identical to f321bfc's, the fixtures' hashes in `converter/tests/test_layout.das`).
  `lua/profile.das` profiles the native interpreter (`-finstrument-functions`, the test suite and
  the four benchmarks) into `lua/lua.profile.json`, which `lua/lua.c2das` names; no threshold is set
  (below). On Lua 5.4.8 by the include rule (Boris): 61 files, 317 include edges, no include
  cycle, 33 modules, which daslang refuses (`circular dependency`); by the symbol graph alone
  (`nm`, the lead's probe reproduced): 19 modules, a cluster of 15. `scc`: 28 modules for `lua`
  (17 for `luac`), the cluster `lcode_cluster` of 15 (`lcode ldebug ldo lfunc lgc llex lmem lobject
  lparser lstate lstring ltable ltm lundump lvm`), and two header clusters, `lobject_h lstate_h
  lua_h` and `llex_h lparser_h`, whose records point at each other: 20 fragments. `source`: 43
  modules for `lua` (32 for `luac`) with `lua_link`, the largest cluster the three headers, 5
  fragments; 64 symbol-edge cuts of 51 functions on 34 edges, the same in both programs; the edges by profiled calls:
  `ltable -> lgc` 3,908,560 (`luaC_barrierback_`, `luaC_newobj`), `ldo -> lvm` 1,620,065
  (`luaV_execute` 1,618,204, `luaV_finishOp`), `lcode -> lparser` 1,359,860 (`luaY_nvarstack`),
  `lgc -> lstring` 482,158, `lobject -> lstring` 385,819, `ltable -> lvm` 332,876, `lgc -> lfunc`
  241,966, `ldo -> lparser` 228,646, `lgc -> ldo` 20,732, `ldo -> ldebug` 11,910 (`luaG_callerror`,
  `luaG_runerror`), and 24 more under 4,000, seven of them never called (`luaG_runerror` from
  `lmem`, `lobject`; `luaD_throw` from `lmem`, `lstring`, `ltable`; `luaC_fullgc`; `luaT_trybinTM`);
  the full list is `lua/work/lua/program.layout.txt`. Measured on this host, idle, three runs (min
  to max), source / scc / single: `lua` `-compile-only` 4.18-4.52 / 7.98-8.11 / 9.86-10.28 s, the
  compile check 2.81-3.00 / 6.58-6.82 / 8.61-9.02, `luac` 3.54-3.68 / 6.88-6.92 / 7.88-8.23 and
  2.25-2.36 / 5.71-5.97 / 6.66-7.00; `lua -e "print(1)"` under the interpreter 1.14-3.77 /
  5.80-8.31 / 8.93-9.29 (4.33-4.35 / 7.90-8.27 / 10.27-10.36 with `-no-module-cache`), a fresh JIT
  33.6-43.9 / 42.0-52.5 / 44.2-52.9, the JIT cache 1.84-1.93 / 6.76-6.99 / 9.91-10.23; the
  benchmarks as whole processes, interpreter: fib 27 13.8-14.8 / 19.1-19.4 / 22.1-22.8, binary_trees
  12 39.4-42.0 / 46.1-46.3 / 48.9-49.7, nbody 20000 33.4-35.5 / 39.6-40.0 / 43.4-43.7, spectral_norm
  100 19.8-21.1 / 25.6-26.0 / 28.7-29.1; JIT: 2.05-2.11 / 7.03-7.31 / 10.01-10.44, 2.56-2.64 /
  7.48-7.70 / 10.40-10.44, 2.39-2.43 / 7.31-7.63 / 10.19-10.72, 2.13-2.16 / 7.11-7.34 / 10.01-10.33
  (native 0.08-0.09, 0.39, 0.26-0.29, 0.11). With each layout's startup taken off, the late-bound
  calls cost nothing measurable under the interpreter (fib 12.6 / 13.3 / 13.1 s) and 2 to 3 percent
  under the JIT at a larger size (fib 32: 2.52 / 2.45 / 2.19 s, binary_trees 15: 6.95 / 6.77 / 6.1),
  where one module is 10 to 15 percent faster than either module-per-file layout; within "a few
  percent", so no threshold is set; the AOT lane stays `not yet` for Lua (its host passes no
  arguments). In all three layouts, under the interpreter and the JIT, `lua -e "print(1+1)"` and the
  string/table/math script print the native build's output and `luac -o` writes the native bytecode
  byte for byte for all 33 files of the test suite. Readability: keys `lua/<program>` (source),
  `@scc` and `@single`, no other key moved; every count agrees across the layouts but
  `literal_named` (71, 71, 1,947 for `lua`; 0, 0, 1,476 for `luac`), since a module counts only the
  names its own files declare and the enumerators live in the header modules. Perf: `perf/run.das`'s kernels are one file each, one
  module in every layout, and gain no lane; the ports publisher publishes the `source` trees as the
  primary, `scc/` and `single/` as opt-ins, and gains the `interp-scc`, `jit-scc`, `interp-single`
  and `jit-single` lanes; `perf/results_linux.json` and the README tables are not regenerated. das
  facts that failed their probe: daslang's module cache serves a module whose `include`d fragment
  changed (F72; the cluster's file carries the fragments' digest), and the optimizer folds a
  constant-argument call into mutually recursive functions reading a global before the global
  holds its value (F73, every layout; the fixtures pass their arguments through `argc`).
  Ledger: F72 is filed as lookibed/daScript#29 and F73 as #28. F73 touches no Lua call the three checks
  run (Lua's core calls take `L`, never all constants); no mitigation is applied: `[sideeffects]` on
  every function reading a global would stop the fold and cost the optimizer elsewhere,
  `-no-optimization` every program. The ports repository still holds `lua.das`, `luac.das`,
  `lua_all.das` and `luac_all.das` at its top until removed by hand. A type no single file defines
  and one two `.c` files define alike share `c_types`, whatever their headers. The scc and source
  layouts' JIT runs are slower than single's by a module-crossing cost the cut does not cause.
  Not captured: perf per layout and the `interp-scc`, `jit-scc`, `interp-single` and
  `jit-single` ports lanes (the perf method's runs wait for an idle host); AOT per layout is `not
  yet` (the AOT host passes a program no arguments); a real ports publish with the three trees is
  owed. A conversion lists what it writes in `program.modules.txt` and removes what the earlier
  list names, the publisher copying only the listed files. A C file whose module would take a
  name daslang or c2das-re loads (`math.c`, `strings.c`) is refused; renaming such a module
  (`math_c.das`) is a leftover. The full cut list is in the PR body and in `program.layout.txt` of
  every conversion (`lua/work/` is gitignored).
- **P5.1c Skip-list audit** (owner ruling 2026-10-22 (2), item B; branch `p5.1c-skip-audit`).
  `run_suite.sh <suite> --audit-skips` runs every ledgered id through the convert-and-run path,
  ratchet untouched (`--update` only adds the audited ids that pass), into `work/skip_audit.tsv`
  (id, feature, status by stage, `missing` for a ledgered id with no file, reason) with a
  per-feature tally; the audit of all 638 lines (gcc-torture 607, csmith 31) found 312 passing
  already. Skip lines before: 638, of them 436 naming the closed P4 (`__attribute__` 376,
  `__builtin_*` 60), 31 naming the closed P3.3 (csmith, goto into a nested body), 171 `never`
  (inline asm 73, GNU vectors 31, label addresses 21, `_Complex` 20, `__int128` 11, GNU keywords
  6, wide strings 5, argument forwarding 2, non-standard floats 1, case range 1). After: 352
  (gcc-torture 321, csmith 31), none naming a closed phase: `never` 64 (asm with template text or
  operands 44, a variable-length array in a block-scope struct, which clang refuses, 7, frame and
  return addresses 5, GCC builtins clang does not know 4, argument forwarding 2,
  `-finstrument-functions` 1, non-standard floats 1), P7.5 25, P7.6 125, P7.7 31, P7.8 107. By
  class: (a) 312 gcc-torture ids passed as they were and joined the ratchet (299 `__attribute__`,
  7 builtins, 3 asm, 1 label address, 1 GNU keyword, 1 wide string); (b) 43 more pass after this
  item's fixes - the dumper drops a deliberate list of attributes and refuses every other naming
  it, lowers an asm barrier (empty template, no operand, no `goto`, as libclang reads the
  statement) to the empty statement, writes `__builtin_constant_p` as clang's own -O0 answer
  (`clang_Cursor_Evaluate`), and the emitter maps `__builtin_ffs`, `ctz`, `clz`, `popcount`,
  `parity`, `clrsb` (with their `l`/`ll` forms), `bswap16/32/64`, `signbit`, `unreachable`,
  `prefetch` and `trap` (`c_runtime/c_builtins`); (c) the rows P7.5 to P7.9; (d) `never` only with
  the reasons above, none on standard C99. gcc-torture 824 -> 1179 passing (`pass 1179, skip 321,
  convert 141, exit 15`), c-testsuite 199 and csmith 151 held. `suites/gcc_torture/filter.das`
  writes `skip.txt` from `filter_rules.das` less the ratchet's ids (a passing test is never
  skipped); the audit's false positives are fixed: `&&[A-Za-z_]` matched a logical and
  (20000511-1), `\basm\b` matched `#include <asm/...>` (20001229-1), `__asm` without trailing
  underscores slipped through (pr81588), and the review's: `__asm __volatile__` and `asm ...
  goto` with GNU qualifiers (990413-2), `__complex`/`__real`/`__imag` without trailing
  underscores (20030910-1), a `-u` inside a string read as a wide literal (pr20601-1, which passes and the ratchet hid). `mode` is
  dropped too, since the pinned clang has already given the declaration the type the mode names
  (`typedef int DI __attribute__((mode(DI)))` dumps as `long`), so the five `mode` tests
  (20020108-1, 20050107-1, 20050119-1, 20050119-2, cbrt) pass, and pr87623 (`scalar_storage_order`,
  which clang ignores with a warning) passes as pr86659-1/2 do: the six joined through
  `--audit-skips --update`. `packed` and `aligned` stay read, not refused (the layout law places a
  packed record, F51), so the packed and aligned tests that pass (align-1, 20050215-1, bf-pack-1,
  pr52979-1/2, pr57344-1/2, pr70602, pr91597) are in the ratchet, and a test whose only kept
  attributes are those two is `packed or aligned layout`. A `weak` on a name the unit never defines is
  refused by the dumper, not the filter (no regex sees definedness). `suites/REVIEW.das` fails a
  skip line naming a phase at or below the highest `v0.<N>.0` tag (floor 4), and one whose phase
  column is neither `never` nor a row id. Upstream (daScript):
  a call to an empty function whose argument hides an effect inside `addr` (`h(addr(a[i++]))`) is
  removed with the effect, where `h(i++)` keeps it (`probes/test_functions.das`); `c_prefetch` is
  `[sideeffects]` for it; F70, filed as lookibed/daScript#26 (the optimizer also drops the effect in a
  dead `let` or assignment of `addr(a[i++])`; `-no-optimization` keeps every effect). daslib's
  regex misses a match when an alternative in a repeated group extends another
  (`x(aba|ab|b)*c` against `xabac`, F71); the filter spells such alternatives as optional
  suffixes; filed as lookibed/daScript#27.
  Leftover found by the review's prover, pre-existing on main: `offsetof` on a packed record the
  sidecar lists under `marshal` spells `typeinfo offsetof` over das's natural layout (8 where the
  pinned clang gives 5); the marshal path owes clang's offset.
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

- **P7.0 Perf method audit** (owner ruling 2026-10-22 (3), item C; branch `p7.0-perf-method`).
  Landed: the root cause of `fib_loop` interp 186x and `primes` 7.5x against dasProfile's
  hand-written 20x and 2.05x, measured construct by construct on the FX-6300 (five samples per cell,
  each change alone): the converted loop shapes and the wrap casts, nothing else - `[sideeffects]`,
  `options stack`, `[c_function]`, the global `count`/`result` per call, the clock, `bool` returns
  and `[hint(unsafe_division_check)]` each move nothing. Three converter changes, idiomatic and
  default (F66): a canonical counting `for` is a range loop (`primes` interp -63% alone), C's
  wrapping signed sum `(int)((unsigned)a + (unsigned)b)` is `a + b` (`fib_loop` -43% alone), `x = x
  op y` is `x op= y` (a further -23%), and a `for` body with no `continue` takes its increment last
  instead of `finally` or the flag (-29% against `finally`, -49% against the flag); with them
  `fib_loop` runs 0.060 s (31x native here, dasProfile's own hand-written das 32x on this machine)
  and `primes` 0.135 s (2.8x, dasProfile 2.9x). `--loops while` / the sidecar's `"loops": "while"`
  keeps the earlier `while` forms, both modes tested and captured (the `interp-while` lane, the
  `@while` readability keys). `volatile` is kept (F65): the dumper's `vol` mark, `c_volatile_load` /
  `c_volatile_store` over new `crt` forwarders, the fold probe on all four tiers; a whole volatile
  record copied at once keeps the plain copy (csmith's programs copy volatile records, so failing
  closed lost 40-odd csmith inputs), as do a bitfield and a `[c_union]` member, which have no
  address. The JIT's 2.3x on `fib_loop` is no converter cost: the JIT tunes for the host (`bdver2`),
  under which LLVM does not unroll a loop of unknown trip count (`clang -O3 -mtune=bdver2` on the C
  file runs the JIT's 0.00437 s), and dasProfile's das kernel passes a literal count where its C++
  reads a volatile one; the dasProfile-method lane gives the das side the volatile count its C++
  side has. The dasProfile method (`perf/run.das --method dasprofile`: `kernel_run` noinline, a
  volatile sink per run, the steady clock) over `fib_loop`, `fib_recursive` and `primes`, dasProfile
  436d58d run on the same machine (`perf/dasprofile.sh`, the SDK at `/root/daScript-sdk`), the
  comparison table generated into `README.md`; `scripts/run_perf.sh --from-scratch` and `--check`
  (10% either way), `.github/workflows/perf.yml` running `--check` on release tags. NEEDS RULING
  (owner): `very-detailed-plan.md` section 6 says the optimization tier is "Sidecar-gated, applied
  only after demo-sync is green", O1 among it, while `lowering-examples.md` "General for" says
  "Canonical counting loops take the O1 `for (i in range(n))` rewrite instead"; this item makes the
  range rewrite the default (the readable and the faster form at once) with `--loops while` as the
  opt-out - make the range rewrite default, or gate it on demo-sync per section 6. Same ruling for
  the trailing increment, which "General for" does not show (it gives the flag, with `finally` as
  the P1 alternative). Left undone, each measured: the range form of a `!=` counting test (`primes`'
  outer loop, -5% interp; `!=` equals `<` only when the start is at most the bound, which the
  converter cannot prove in general); `[hint(unsafe_division_check)]` on a function dividing by a
  range loop's variable (0% interp, within +-3% JIT: not worth a rule). Upstream (daScript, nothing
  filed but #24 and #25): (a) the interpreter runs `x = x + y` 1.3 to 1.7 times slower than `x +=
  y`, and bimodally per process (0.077 or 0.100 s on `fib_loop`), where a peephole to the fused
  op-assign node would close it; (b) a `while` body in a `{ } finally { }` block costs 29% over the
  same loop with a trailing increment; (c) the JIT tunes for the host CPU and on `bdver2` skips the
  runtime unrolling clang's generic tuning does, so the JIT and native lanes compare two code
  generator settings (a `-mtune`/target-cpu option for the JIT would align them); (d) every
  `uint(x)` conversion is an interpreter node of its own. F67 (an interpreter reinterpret of an
  extern's result, the class of lookibed/daScript#3) is lookibed/daScript#25; F68 is
  lookibed/daScript#24. Review fixes (grounding, prover, tdd-auditor, targeted reviewer): the
  op-assign and wrap folds spell a C truth value as its int and the folded operand once (`x = x + (a
  < b)` failed the compile check); a bound reading the counter keeps the `while` form; a volatile
  read in a store's or a step's target is made once into a temporary, a `x = x op y` with one keeps
  both of C's reads, and a used postfix step of a volatile stores from its one load; the dumper
  takes a type's own `volatile` from its innermost declarator group, so a volatile function pointer
  whose parameters hold a `*` (liolib's `volatile lua_CFunction`) is kept and a plain one with a
  volatile parameter is not; a `for` body ending in `break`, `return` or `goto` spells no dead
  increment; `crt::c_volatile_load_ptr`/`c_volatile_store_ptr` are gone (pointers move through
  `u64`); `"cir"` stays 0.1 as for F20 and F21. The dasProfile method runs dasProfile's own three
  kernels in C (`perf/kernels/dasprofile/`: `i != n` and `bool` in `isprime`, `noinline` on the
  kernel functions as its C++ has it, none on `kernel_run`; the default kernels, their emitted code
  and the default table unchanged), re-captured: converted `primes` interp is 4.45x native against
  the hand-written 2.92x, since both its loops test `!=`, the leftover above (+64% interp on
  dasProfile's program); `fib_loop` 31.5x against 31.6x, `fib_recursive` 8.76x against 8.60x. The
  README says the hand-written das passes literal counts, the comparison prints five significant
  digits, and `--check` holds a cell to 10% or twice its committed spread (the bimodal
  `fib_loop/interp-while`, 29%, upstream note (a)) and reruns this tree's lanes only. The
  readability record (main -> this item): every metric's rise is the 21 new keys (the three csmith
  seeds that now pass, `125079271`, `550566874`, `847133440`: `reinterpret` +918, `unsafe_expr`
  +1623, `while_rangeable` +234; the 16 perf `@while` keys: `while_rangeable` +40, `reinterpret`
  +39; the two torture tests: +3), and on the 1201 keys both captures hold `while_rangeable` is +101
  (csmith's loops whose counter outlives the loop, formerly in the flag form the metric does not
  count, now take the trailing increment and are counted: +183 before the review fixes, less the 55
  whose dead increment after `return`/`break`/`goto` is gone and the 32 perf default and `@copy`
  keys whose canonical loops became range loops), `reinterpret` -39
  (`reinterpret<T>(c_volatile_load(v))` of a volatile pointer global, a cast inference drops from
  the counted program where it kept `reinterpret<T>(v)`; `metrics/ARCHITECTURE.md`) and
  `literal_named` -22 (16 csmith keys with the review fixes). F69 (recorded, not fixed): in a
  `[c_function]` an assignment over a local array evaluates its value before its target's index
  under the interpreter, the JIT and the exe and the target first under AOT, so `arr[g()] = arr[g()]
  + 10` writes different elements per tier. Second review pass: clang's name of an anonymous record
  (`struct (unnamed at f.c:3:10)`) is no declarator group, so a plain pointer to a volatile
  anonymous record is no volatile object; a function whose return value is volatile carries no
  `vol`; a `for` body ending in an `if` whose both arms leave takes no increment. Leftover (P6.3,
  the whole-program compile stress): a volatile pointer to an anonymous record (`struct { int a; }
  *volatile p`, a typedef of such a pointer made volatile) is typed as the record `anon_N` itself,
  not `anon_N?`, so the module fails the compile check; older than P7.0, and the dumper's `vol` on
  such a pointer is tested on the spelling alone until it lands. Leftover (P6.3, same stress; older
  than P7.0, silent wrong output): a compound literal as a step's or an assignment's target
  (`((int[]){x, 2})[0]++`, `((struct P){x, 3}).a += 4`) is spelled twice, two objects, so the step
  lands on a copy (gcc 8, das 3 on the second pass's `v5.c`); with a volatile read inside the
  literal the store now fails closed instead.
- **P7.1 O1 range-loop rewrite** (unlocks automatic bound-check elision; the canonical form
  landed in P7.0 as the default, pending its ruling), **O2
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
- **P7.5 C99 completeness owed by the skip audit** (P5.1c). Skip lines name it: `_Complex` (20,
  `__complex`, `__real` and `__imag` included), `wide string literals` (4, with `wchar_t`) and
  `block-scope function declaration` (struct-cpy-1). Ordinary failures the rows' fixes unblock: `bool`
  as `#define bool _Bool`, which clang spells `bool` (20141107-1, 20230510-1); a file-scope empty
  declaration `;` (`EmptyDecl`: builtin-bitops-1, pr37573, and 20230630-2/4 behind P7.6); a pointer to `va_list` (pr64979,
  va-arg-21); a call through an unprototyped function pointer with arguments (pr67037), a pointer to
  a variadic function (pr68390), a libc function's value (pr54937), `main` with other parameters
  (alias-4, behind P7.6); `vfprintf` and `perror` mappings (fprintf-chk-1, user-printf,
  vfprintf-chk-1, printf-2).
- **P7.6 GNU emulations owed by the skip audit** (P5.1c). Skip lines name it under these features:
  `packed or aligned layout` (33: `packed` and `aligned` beyond what the layout law places or a
  typedef carries - a packed record outside the sidecar's `marshal`, an alignment on a variable, a
  record aligned past its members), `__attribute__` (5: `alias` in alias-2/3/4, and
  `scalar_storage_order`, which clang ignores, in 20230630-2/4, whose failure is P7.5's
  `EmptyDecl`), `GNU vector extension` (29), `address of a label and local labels` (17, labels as
  values through the switch re-dispatch), `__int128` (13, through c_runtime), `GNU keywords` (10:
  `typeof`, `__extension__`, `__alignof`), `GCC overflow builtins` (11), `__builtin_setjmp` (4,
  through the setjmp lowering), `__builtin_* calls` (2: `classify_type`, `choose_expr`/
  `types_compatible_p`), `GNU case range` (1). Ordinary failures: `__extension__` from a macro
  (pr58831), an alignment on a variable (pr68532), a record the law cannot place (pr41463).
- **P7.7 goto into a nested body** (P5.1c; P3.3's state-machine lowering, still owed, is owned
  here): the 31 csmith seeds `suites/csmith/skip.txt` lists, and gcc-torture pr38051 and pr43269
  (ordinary failures).
- **P7.8 Permissive inputs** (P5.1c): 107 gcc-torture skip lines `permissive input`, tests whose
  `dg-additional-options` ask gcc for `-std=gnu89` or `-fpermissive`, refused by clang 22's
  default-error diagnostics (implicit int, a parameter not declared, an undeclared library
  function, incompatible pointer types), and the three that call `__builtin_exit` (20001111-1,
  pr103052, pr115033), which clang declares only implicitly, where the emitter maps it to `exit`; and 20180921-1, a chained comparison `a < b <= c` clang
  refuses under `-Wparentheses` (an ordinary failure). The runner passing the test's own options,
  or the dumper `-Wno-error=` for these, unblocks them.
- **P7.9 Defects the skip audit found** (P5.1c), ordinary failures or behind a P7.6 line: wrong
  output or a run-time error - pr15296 (a null dereference at run time), builtin-prefetch-2 (`&p->f`
  through a null `p` dereferences, where C only computes the address), pr41395-1/2 (`failed to
  simulate`), 20101011-1 (integer division by zero must raise SIGFPE to the test's handler); a failed compile check of emitted code - pr39100 and pr47925 (can't locate
  a variable), pr48571-1 (`void? + uint64`), pure-1 (deref of `int[10]&`), 20090113-2/3 (a record
  clang lays out as size 16 align 8); the two bitfield layouts das cannot reproduce, standard C99
  (20040709-2 and pr79737-1, behind P7.6 lines): clang packs their bitfields across a unit the law
  does not join; 20030330-1, a link test whose `if (__builtin_constant_p(delay))` arm calls an
  undefined `link_error`: clang answers 0 and never emits the unused static function, where the
  converted module compiles every function and finds no `link_error`. Not a defect: bitfld-5
  exits 3 as the pinned clang's own build aborts (134); only gcc exits 0, since the test checks
  GCC's wrap of a 40-bit bitfield.
- **Exit criterion:** the §2 metric sentence of the plan is true, all four columns
  published.

## P8 — Comparison

- **P8.1 Head-to-head with lookibed/c2das (the Rust translator)** (owner ruling 2026-10-24 (8);
  added with P5.1b2, not executed before the stop ruling 5 orders). Build lookibed/c2das (master,
  the pinned commit recorded) as its README says and run it on exactly the inputs c2das-re uses:
  the three suites (gcc-torture execute, c-testsuite, csmith seeds), the perf kernels, Lua 5.4.8
  (`lua`, `luac`) and PureDOOM, with the same daScript pin where possible (any difference
  recorded). Correctness: pass counts per suite under the same runner and oracle; the Lua checks
  (`lua -e`, the string/table/math script, `luac -o` byte-identical, the Lua test suite once P5.3
  exists); Doom demo sync once P6 exists; a failure of either side classified (refused, compile
  error, runtime, wrong output). Code quality: `metrics/readability.das` on both outputs
  (`c_function`, `reinterpret`, `unsafe`, `while_rangeable` and the rest), size (lines, modules,
  fragments, largest cluster), and a short side-by-side of a few representative functions
  (`lvm.c`'s `luaV_execute` slice, a Doom renderer loop) in the report. Speed: the perf lanes
  (native clang -O3, interp, JIT, AOT, exe) and the dasProfile-method lane on the same machine with
  the same parameters for both translators, geometric means per lane. Output: a comparison table in
  c2das-re (`docs/` or `perf/`) and in the c2das-ports README, regenerated from scratch by the
  generator script, never hand-typed. Honest: where the Rust version is better, say so and open
  ledger rows to close the gap.

---

## Standing dependencies

- P1 c_runtime items are converter-independent — they can proceed in parallel with P0.5.
- The suite runner (P1.5) blocks all ratchet claims — build it before deep lowering work.
- `[c_bitfields]`/`[c_union]` (P4) depend only on P1 macros, not on P2/P3 — they can be
  pulled earlier if the macro appetite is there.
- Nothing depends on any sidequest.md item; if one lands early (e.g. `[pack]`), swap the
  fallback out behind the sidecar flag.
