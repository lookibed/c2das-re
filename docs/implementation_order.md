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
  address temporary.
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
  and written through `memcpy` of the unit); a record no unit assignment reproduces under the
  `linux` dialect (`struct { unsigned a : 3; char c; }`: clang's size 4 needs the declared
  type's alignment, F5), which the sidecar can mark marshal-only once the previous line lands;
  a record whose only bitfields are unnamed padding (`struct { char a; int : 20; }`: no das
  spelling fits both dialects, `uint8[N]` for `linux`, an empty `uint` unit for `msvc`); a
  record holding an F5 record that clang's size refuses with no escape (`struct { struct BF bf;
  short y; }` is size 8 under clang, 6 under the mirror's alignment 2); a flexible array member;
  `aligned(N)` on a record with bitfields; and a `_Bool` step, plain or bitfield (`b++`,
  `s.f++`).
- **P4.2 `[c_union]` macro.** One ref-returning operator per member (probed); storage
  alignment via max-align member type; anonymous-union flattening.
  Ledger (fail closed today, each a later row): a bitfield member of a union; a union the layout law finds unnatural - clang's alignment past
  8 (`aligned(16)`: no unsigned storage type aligns there) or below a member's (`packed`) - which
  waits for marshal to cover unions; a union holding a marshal-only record, and a marshal-only
  record holding a union; a union initializer outside a declaration (compound literals); an
  initializer of a union naming an anonymous member (`field` names `""`); an anonymous member
  that makes no field name visible (`struct { int : 4; }`), whose offset libclang gives only
  through `clang_Type_visitFields`, which dasClangBind does not bind yet; two anonymous records
  one macro expansion makes indistinguishable (`#define TWO REC(a); REC(b)`, one key or one
  `(anonymous at f:l:c)` spelling); a C tag spelled `anon_<N>` beside an untagged record whose
  slot is `N` (both spell `anon_<N>`, which predates unions); and the forwarding operators that
  would spell `s._anon1.i` as `s.i` (F29). Outside the dialect: a GNU zero-length array
  (`char z[0]`, gcc-torture zerolen-1) and GNU's cast to a union type (`ToUnion`, 960416-1).
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
  not the host's. Waiting on other rows: va-arg-9 and va-arg-10 (P4.6, a `let` pointer into a
  `var` parameter), va-arg-4 (a `char[N]` member initialized from a string literal), 20041113-1
  (`main` with arguments), multi-ix (forty `int[500]` locals overflow the default context
  stack, which only a sidecar's `stack` raises). Outside the dialect: GNU nested functions
  (nest-stdar-1) and GCC's `__builtin_va_arg_pack` and `__builtin_apply`, which clang does not
  know (va-arg-pack-1, pr47237; `filter.das` phase `never`).
- **P4.5 csmith differential.** Nightly N=1000 seeds vs `gcc -O0 -fwrapv`; any
  divergence is a converter bug by construction; creduce harness for minimization.
  Ledger: an address one past an array's end formed by indexing (`&a[N]`, gcc-torture
  strlen-5) trips das's range check; spell `&a[k]` as `addr(a[0]) + k` where `k` can reach `N`.
- **P4.6 Pointer constness: the uniform `var` policy.** A pointer parameter is `var` only where
  the body writes through it (F3), and das takes no `let` pointer for a `var` parameter, so a
  `let` pointer a caller holds - its own parameter that it never writes through, a field of a
  by-value record parameter, reached through `?:` or a cast - cannot flow into a callee's `var`
  parameter, by a direct call or through a function value whose type has a `var` position; the
  emitter fails closed there ("a pointer the callee writes through arrives through const
  parameter"). Making every pointer parameter `var` closes the gap but meets a const record
  lvalue: `var copy = s` of a by-value record parameter holding a pointer is "can't assign
  'S const.p: int? = int? const'", so the row is the redesign of F3, not a flag. c-testsuite
  00181 and gcc-torture 990128-1 wait for it.
- **Exit criterion:** csmith runs clean at 1000/night for a week; torture ≥ target with
  ledger; matrix has no row without a green fixture.

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
- **P7.3 JIT + AOT lanes** green across suites, Lua, Doom; timedemo columns filled.
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
