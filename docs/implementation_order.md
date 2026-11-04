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

**Owner rulings 2026-11-01 to 2026-11-04, (12) to (29)** (after Boris Batkin's framing of 2026-08-22: generate the
text, make it all work, then the LLM-assisted port; his words on layout, start-up, speed and text
stand behind each)
12. Layout (P7.0a): the default layout keeps every cycle one module of `.das.inc` fragments, a file
    per member (today's `scc`); branches stay separate modules, header clusters as they are; late
    binding (the `<entry>_link.das` slots) stays an opt-in flag and sidecar field; the mode
    names follow the meaning, so the default
    is not called by another mode's old name; tests and captures in every mode; the ports publisher
    publishes the default mode as the primary one; the language's mutual-`require` limit becomes a
    probe, a `probe-findings.md` row and an issue in `lookibed/daScript` (fact and repro only).
13. Loops (P7.0, P7.1): the range form of a canonical counting loop and the trailing increment are
    the default, `--loops while` the option; `very-detailed-plan.md` section 6 and
    `lowering-examples.md` "General for" are corrected to the code (the B pull request); O2 and O3
    stay gated after demo sync.
14. Order: P8.1 finishes in its current scope, not expanded, its Lua speed part (interp and JIT of
    both translators on the same inputs) mandatory; then P7.0a, then P7.0b (the interpreter audit on
    Lua by P7.0's method); then P6.1 to P6.5, then the rest of P6; P7.5 to P7.10 wait for P6.5
    unless one blocks Doom.
15. Brevity: a new `Done` entry here is at most about ten lines (what, one to three numbers, a link
    to the report; older entries are not rewritten); a commit subject is at most about 72
    characters; a pull request closing an item carries a `Кратко` section (`AGENTS.md`).
16. Review: pending owner decisions live one line each in [rulings-pending.md](rulings-pending.md)
    and head every report; a pull request changing the default generated output shows before and
    after on a fixed sample; the readability metric counts structural noise (late-bound wrappers
    and slots, qualified calls, `require` lines per module); a perf lane worse than `main` by more
    than 5%, or a trade of speed against the output's shape, is an owner decision (`AGENTS.md`).
17. P8.2, the Rust c2das's real projects (ruling of 2026-11-01, later in the day): the six projects
    of its `tests/manual` (binjgb, doomgeneric, h264bsd-mp4, plmpeg-stream, quakegeneric, wasm3) go
    through c2das-re on the Rust side's own inputs, hosts, fixtures and reference outputs, the Rust
    result beside; right after P8.1 (its PR 5 closes it) and before P7.0a, so the order of (14) reads
    P8.1, P8.2, P7.0a, P7.0b, P6.
18. CI is off (2026-11-01, evening): the owner disabled both workflows (preflight, perf) and stopped
    the WSL runner, the box having no spare resources beside the agent; the agent re-enables neither
    workflow and touches neither runner (the WSL one nor the fx6300 one); #37 was merged on the gate.
    The merge gate until the owner says otherwise: the fast tier green locally on the pull request's
    branch rebased on `main`, plus the one quick review closed; the full tier runs locally at phase
    ends only (rule 10).
19. Lua on the Rust side (P8.1) is deferred to the owner; the report says refused, no host-import work.
20. The P8.1 report headlines the Rust line total without its emitted runtime (1.33x ours); the total
    as written (5.10x) stays as the second line.
21. P8.1b, the readability metric rebuilt on the critic's findings (`/root/notes/owner/
    2026-11-01_readability-critic.md`, the critic's text plus the agent's footnotes): next item,
    before P8.2; every finding and blind spot a criterion, a compliance percentage per criterion
    against a human port and one total, one command over the ports output (Lua, every layout) and the
    suites, wired into the fast tier as a report and into the item reports with the delta against
    `main`; `main` re-measured now, the numbers in the critic file's footnote area and the PR's
    `Кратко`; no translator fixes in the item.
22. P7.0a's start-up, 5.3 s against 1.0 s for `source-cut` (2026-11-02): accepted, no threshold.
23. P7.0c-h and the critic's readability items (2026-11-02, decided while the owner slept): where
    speed and readability pull apart, the readable form is the default and the fast form an opt-in
    flag (sidecar field and CLI), both tested and measured; where a form is both faster and more
    readable, it is the default. P7.0c: plain-case switch dispatch without the flag chain default,
    computed `goto <expr>` for dense switches opt-in; P7.0e: `x != 0` for `l_likely`/`l_unlikely`
    default; P7.0d: the wrap-cast fold default with its signed-wrap probe; P7.0g: the cheaper
    volatile load with F65's semantics default; P7.0f: the first-member `reinterpret` opt-in, the
    default stays `addr(...)`; P7.0h: flat `try` and inline enum cast default if the output reads
    simpler, low priority. Readability, readable-only so default, each its own small PR: character
    literals emitted as `'c'` where the C had one, then C comments carried over by source line, then
    `#define` constant names. Streams: one coder P7.0c, e, d, g, f, h; one coder the three readability
    items; first-ready-first-merged, the other rebases. Stop at 06:00 MSK (03:00Z) of 2026-11-02:
    no new coder or pull request after 05:40 MSK; merge what is green and reviewed; stop coders
    cleanly (WIP committed and pushed), write the handoff, end; no restart after the reset unless
    the owner says so.
24. Pace (2026-11-02): back to the pace before the night run; the night-run rulings (parallel
    streams, speed, tests-light) are lifted; the lead on Fable, Opus coders as (25) allows, no
    separate research session. Rule 11 holds: one open pull request at a time (a blocker fix may be
    the second); the night's three open ones (#60 P7.0k, #64 P7.0g, #65 P7.0d) are drained first,
    one by one, on targeted tests, the fast tier and the review of rule 10. CI stays off (18); the
    merge gate is targeted tests, the fast tier and a closed review; the full tier, the suites,
    criteria and perf re-records run at phase ends per rule 10, through `heavy`, once per commit; a
    coder queues a long run and reads only pass/fail, and a run silent for 20 minutes is hung.
    Order: the end run's three red full-tier tests on `main` (fix or ledger; the newly passing
    suite ids recorded; criteria rerun on the current `main`), the three pull requests, the ledger
    docs pull request, then P7.0f/h, the P8.4 projects table, P6.3a-f, P6.4, P6.5 demo sync, the
    rest of P6; P7.5-P7.10 wait for P6.5; speed against readability as (23).
25. Boxes and pools (2026-11-02): development stays on the owner's WSL box (build, compile, tests;
    every heavy job through `heavy`); the fx6300 is offline and not used. Perf measurements (perf
    captures, ports perf tables, compare's speed columns; criteria may run here) move to a local
    bench (Ryzen 3 1200, 32 GB; ready since 2026-11-03, `/root/notes/bench.md`): until it was
    ready no perf capture ran and each owed measurement (item, command, commit) went to
    `/root/notes/bench-queue.md`; numbers from the WSL box are not headline numbers. (24)
    holds otherwise, with one change to the model rules: the weekly limit is two pools, Fable (up
    to 50%) and all other models, both spent evenly by the reset; `/root/notes/budget-hint.txt`
    says which pool is behind: Fable behind, research, reviews, analysis and docs go to Fable
    subagents; the other behind, up to two Opus coders at once (never three) and reviews may run on
    Opus; the lead stays on Fable.
26. P7.0l (2026-11-02): a new analysis item, measured, no change to the default layout: for Lua
    and PureDOOM, split the edges inside each cycle cluster by kind (function call, global,
    function address, type) and recompute the clusters as if (a) only functions, (b) functions and
    globals could be forward-declared; report what remains of each cluster (count and sizes);
    `program.layout.txt` already holds the cut edge list, so the work is small. Placed after the
    three open pull requests drain and the ledger docs pull request, before P7.0f/h; it feeds the
    mutual-require question (F76, lookibed/daScript#32).
27. Boxes (2026-11-03): three measurement boxes, PC (the owner's WSL, Ryzen 7 7435HS), fx
    (FX-6300, when back) and bench (Ryzen 3 1200); use whichever is free and write the box name
    next to every number; what matters is the delta against the previous transpiler version on the
    same box, measured in one run; numbers from different boxes are never compared directly. Rows:
    (a) the ports publisher labels every table and capture with the box, (b) `perf/` and `compare/`
    captures carry a `box` field beside `cpu`, rendered into every "Captured on" line and table
    (both Done, PR #93, `perf/boxes.das` and `--box`), (c) a speed claim's PR carries main-before
    and the branch measured on one box in one run, the delta table from the two captures (open,
    under P7.0).
28. Startup is never inside a speed number (2026-11-04): every published or compared speed number
    is the work only, timed inside the process like dasProfile or at least the cell less the same
    lane's startup cell on the same box; startup (load, JIT compile, cache load) is its own row.
    The ports Lua tables had the program start inside every cell (JIT read 1.5-2x worse than on
    2026-10-31 while the work did not change): fixed first (PR #94, under P5.1a), then the
    startup study of the default layout against the cut one on one box, then every other harness
    audited (`perf/` and `compare/` clean, under P7.0). Addendum: c2das-ports holds everything
    measured, kernels and projects speed from the bench, the criteria table and the raw captures
    beside the tables; the bench is off for the night, measurements run on the PC, labelled.
29. The order after the two ruling-28 branches merge (2026-11-04): kernels are parity with Rust,
    not a win (interp geomean 36.08 / 35.92, JIT 1.61 / 1.55, AOT 1.37 / 1.92 the one win);
    projects 2 of 6 against 6 of 6 and ours slower; Lua interp 112-290x of C while kernels are
    7-30x. Nothing goes to Boris now; the one thing worth showing: Doom fps under interp and JIT
    next to Rust doomgeneric on the same machine (Rust 37x interp); if slower, find out why first.
    Order: (1) P6.7, with the P6.5 demo-sync rungs it needs; (2) the four P8.4 refusals
    (doomgeneric `m_config.c:109`, h264bsd `malloc`, quakegeneric `vfprintf`, wasm3 `vectorcall`),
    converter holes Rust passes; (3) the Lua gap between kernels and the program (P7.0b2); (4)
    compare re-captured, kernels and projects, on one box, labelled. Text: short tables, few
    columns, no walls. Publish: a SUSPECT cell (spread over 20%) is re-run or dropped, never
    published (the ports, perf and compare renderers). Done, all four: (1) P6.7 (PR #101); (2) the
    four refusals (PRs #96, #98, #99, #102; the next stops P8.4 (s), (t), (v), h264bsd-mp4 passes);
    (3) P7.0b2 as an investigation (its rows P7.0c2 first, P7.0c3, P7.0c4, P7.0b3); (4) the compare
    re-capture on box PC (PR #104). Open for the owner: the force-push reading for a PR branch; a
    replayed branch's original stays on origin for the owner to delete (`fix/ports-work-only`,
    `p6.7-doom-fps`, `p8.4q-malloc-shadow`, `fix/ports-in-process-timing`).
30. The open Doom questions (2026-11-04): (1) the per-tic frame checksum is the sync test's alone;
    the speed run has no checksum inside the timed window, and fps and the ratios against native
    and Rust doomgeneric come from the speed run (P6.7 re-timed that way); (2) doom2.wad is dropped
    entirely, no fetch script and no tests for it (PR #97 reverted by PR #100): freedoom2.wad is
    the one IWAD; (3) the native build questions (`-funsigned-char`, patch 0004 against a converter
    mechanism) answered from the research report `/root/notes/research/doom-native-questions.md`:
    keep the signed native build with patch 0003, keep patch 0004; the rows are under P6.5.

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
  Red on `main` (found by the ports coder, reproduced through `heavy`, 63 of 65):
  `metrics/tests/test_readability.das` `test_literal_counts` fails two checks (every integer width
  matches an enumerator or a let constant, got 0; a site names the first name of its value, 9
  expected, 8 got); older than the ruling-28 branches, unseen because the fast tier runs no tests
  lane. Row: bisect over the P6.3/P6.4 converter commits (`literal_named` counting), fix or
  re-expect; a fast-tier `tests` lane over `metrics/tests` would have caught it.
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
  the issue is lookibed/daScript#18 (open since 2026-10-21, repro and fix suggestion attached; binjgb's
  AOT lane, P8.4 (m), fails the same way). Row candidate, a converter-side workaround that gives
  `switch_local` its AOT cell and binjgb its AOT lane without waiting on daslang: declare a
  flattened block's locals uninitialized at the function top and assign at the original position
  (`var g1 : int` ... `g1 = k * 2`, the shape C++ lets a goto bypass), weighed against readability
  (ruling 23), so likely only for the locals a goto jumps past. `perf/run.das` takes the failed AOT link for a
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
  Ledger: Lua's error recovery was stubbed until P5.2 (`lua/lua.c2das`: `LUAI_THROW(L,c)=abort()`,
  `LUAI_TRY(L,c,a)={ a }`, `luai_jmpbuf=int`), which removed the stub (P5.2 row). Host-delivered
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
  lane until P5.3 runs Lua's own suite (P5.2 made a Lua error recoverable under the interpreter). daslang's `json_boost` fails type inference on
  `JV` of a struct holding an array of structs that holds an array of structs, so the capture keeps
  its cells flat (lookibed/daScript#23, `docs/probe-findings.md` F64); popen's timeout watchdog
  delays the return by up to 100 ms, so a sample's clock stops at the end of its output. A
  conversion leaves a stamp of its commit in `lua/work/`, which a `--no-convert` publish must
  match (`--allow-stale` otherwise). `perf/run.das`'s clang and daslang version lines now read
  past `info` lines (`first_reported_line`, the same text on this machine), and its exe and AOT
  builds take the 3600 s build timeout `converter/tiers.das` now passes to every build step.
  Regenerated from `main` (dc53a85: the `source` layout with `_cluster` modules and `.das.inc`
  fragments, `source-cut`, `single`, the head-to-head section) and the bench Lua tables published
  (46393ba, box bench): interp fib 190x, JIT 14x, exe 5.1x; the test suite interp 39.6x, JIT 2.6x;
  the exe test-suite and every AOT cell `not yet` (the Module_CRT load from the exe folder,
  lookibed/daScript#18). The Lua conversion dies in `heavy`'s 4G scope: a publish needs `--max 8G
  --mem 6500`.
  Ruling 28 Done (branch `fix/ports-work-only`, PR #94): a cell is the work, the whole-process
  time less the lane's startup cell; Startup and Work tables, ratios from work; a publish without
  `--perf` renders the directory's latest capture (it rendered PERF_NOT_YET while `lua/perf/` held
  two) and names its machine; the criteria table from `metrics/criteria_linux.json` and the raw
  captures beside the tables; a SUSPECT cell (spread over 20%) makes its lane's work suspect and
  is never published (ruling 29). Ruling 27 (a) Done with PR #93: `--box` in the capture, the
  machine column and the "Captured ... on" line.
  Startup study (ruling 28 item 3, box PC): v0.5.0 and `main` start equally fast per layout (warm
  interp monolith 4.9 s, cut 0.9 s, single 7.0 s; cold JIT compiles 28 / 14.5 / 36 s); the JIT
  startup rise between the two ports tables is P5.1b2's default-layout swap, not a regression.
  OWNER DECISION: the headline lane, the monolith (fastest JIT work, 1.6-1.9x over the cut) or the
  cut layout (5x faster start, interp work within 1.07x); the 8-lane capture renders both.
  Ruling 28 item 2 Done (c2das-ports fb88940, the 8-lane Lua capture on box PC, 3 samples): JIT
  work 4.1-8.9x native (the test suite 1.6x), interp 105-266x; the cut layout starts in 0.65/0.98 s
  against the monolith's 3.57/4.16 s with its work within 1.02x (interp) and 1.00-1.14x (JIT); the
  AOT lane not yet (`lua.das.cpp:22309` "cannot jump from this goto statement to its label": an
  AOT row). Finding: by subtraction the JIT work spreads run 10-20% and two single-module JIT cells
  are suspect, the 4-6 s startup dominating 1.4-2.5 s of work: in-process timing is the fix, not
  more samples.
  In-process timing Done (branch `fix/ports-in-process-timing-2`, PR #106; decision 2 of
  `/root/notes/plan-measure-setup.md`): `bench/timed.lua` times a benchmark inside the process, its
  `os.clock` seconds one stderr line, the test suite run under it too; the Work table, ratios and
  means render the work seconds, a capture without them by subtraction and marked. A one-sample
  publish on box PC gives converted JIT work at 4.0-9.5x native (fib 9.5, binary_trees 4.0, nbody
  5.6, spectral_norm 8.7) and 1.55x on the test suite, close to fb88940's subtraction tables: the
  published JIT column was not inflated.
  Rows: a progress/ETA line per cell here and in the compare projects (the plan, section 3); a
  perf kernels table in the top README if the owner wants ours-only kernels there;
  `ports/ARCHITECTURE.md` section 4 states the warm-start fact.
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
  A conversion removes only the files an earlier `program.modules.txt` lists: files from before any
  list existed, the `.cir.json` of renamed units and a previous layout's `program.layout.txt`
  survive in `--out`; the publisher copies only the listed files.
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
  pattern — the easy shape, per spec; branch `p5.2-pcall`). `lua/lua.c2das` drops the stub
  (`luai_jmpbuf=int`, `LUAI_THROW(L,c)=abort()`, `LUAI_TRY(L,c,a)={ a }`); with neither
  `LUA_USE_LINUX` nor `LUA_USE_POSIX` defined `ldo.c` takes its ISO `setjmp`/`longjmp` pair:
  `luaD_rawrunprotected` is the single-branch trampoline, `luaD_throw` a `c_longjmp` through the
  handler chain. The one converter change: the layout law's relaxed search takes a record with a
  `jmp_buf` field, padding after `CJmpBuf` to clang's offsets and size (`struct lua_longjmp`, 216
  bytes), where it failed closed; a packed one still refuses. Fixture
  `converter/tests/fixtures/p5_lua_protect.c` (ldo.c's struct, runner and throw, nested, rethrown
  and three-frames-deep errors) matches the native build. `lua/run.das --error-check` runs eight
  checks against the native oracle (now run under the name `lua`): `pcall(error, 'boom')`, an
  uncaught `error('x')` (exit 1, the message on stderr), nested `pcall`, `1 + {}`, a table error
  object, an error in a coroutine, `xpcall` with a handler, `string.rep`'s size error. Under the
  interpreter all eight agree in the source, scc and single layouts, with the standing checks (a
  string/table/math script, `luac -o` 33 of 33 byte for byte). Under the JIT the standing checks
  pass in every layout and the error checks agree 0 of 8: a `return` inside a `try` or `recover`
  arm leaves only the arm there (`docs/probe-findings.md` F75, lookibed/daScript#30), so
  `luaD_rawrunprotected`'s `return lj.status` falls through to the trailing 0 and every protected
  call reports success. Probes: a panic crosses `[no_jit]` and JIT frames both ways, and unwinds
  through a late-bound slot's `invoke` across modules under both tiers. Readability re-recorded:
  every metric's delta 0, the `lua/*` keys unchanged.
  Ledger: the JIT lane of Lua's error recovery waits for lookibed/daScript#30 (or a converter
  shape keeping returns out of the `try` arm, the owner's ruling); the ports README's Lua claim
  and its test-suite `not yet` text regenerate at the next publish; perf not re-captured; a field
  that is an array of `jmp_buf` (`jmp_buf bs[2]`) loses its array type in Dumper A (the C-IR field
  names the one `jmp_buf` record), so the relaxed search pads it as one buffer and the compile
  check fails where the record was refused before: refusing or lowering the array is open; the
  `--error-check` comparison merges stdout and stderr (a message on the wrong stream passes), and
  the `argv[0]` rename of the oracle and the `lua`-only gating of `--error-check` have no stand-in
  test (the real `error('x')` check is what catches them).
- **P5.3 Lua's own test suite** under interp. Expect a long tail of libc exactness bugs
  (strtod, number formatting, string.format) — each fix lands with a fixture.
  In progress (branch `p5.3-lua-suite`, PR 1 of n: the lane and the survey; owner rule
  2026-10-29 on memory: every suite run capped). `lua/run.das --suite-check` runs the files
  `all.lua` runs under `_port=true` (`_soft` false, `T` absent; `big.lua` as `all.lua`'s coroutine;
  `main.lua` returns at once under `_port`; `heavy.lua` is no file of the lane), then `all.lua`,
  each with the native oracle and the converted interpreter in the test folder, each in a systemd
  scope capped at `--suite-memory` (4G) and timed at `--suite-timeout` (1800 s), verdicts to
  `lua/work/<layout>/suite.txt`; outputs compare with every number masked (the suite prints seeds,
  timings, dates; `%g` picks its notation by the value) and without `all.lua`'s time warning.
  Survey 2026-10-29 under interp, the trees reconverted from main 04efd6a (the converter
  unchanged since P5.2): 30 of 30 files pass in each of the source, scc and single layouts, no
  fail, no timeout, no memory verdict at the 4G cap; wall time with the conversion 21.7, 24.3 and
  25.7 minutes, the suite runs 1131, 1291 and 1368 s. Native per file under the same cap: at most
  6.8 s (`errors.lua`), `all.lua` 13.8 to 14.1 s. The converted run's seconds (source / scc / single):
  `all.lua` 493 / 518 / 511, `constructs.lua` 234 / 238 / 236, `errors.lua` 173 / 177 / 180,
  `sort.lua` 59 / 61 / 63, `verybig.lua` 23 / 28 / 31, `big.lua` 19 / 23 / 27, `gc.lua`
  17 / 22 / 25, `calls.lua` 15 / 20 / 23, every other file under 17 s; a run's fixed cost is
  1.3 s in the source layout, 6 s in scc and 9 s in single (the larger modules' compile per
  process). No libc exactness bug, lowering bug or runtime panic surfaced: the first survey's one
  failure was the lane's (`all.lua`'s `time: %g` line, `2.7e-05` native beside `0.000643`
  converted), fixed by the number masking. Finding: before the cap, a run of the earlier session
  of this item reached 15 GB RSS in `lua_native` and the OOM killer took the session; which file
  is not recorded (`heavy.lua`, which `all.lua` never runs, is the suite's memory test); under the
  cap no run of the lane, native or converted, reaches 4G.
  PR 2 (branch `p5.3-port-survey`): `--run`, `--error-check` and `--suite-check` compare stdout
  and stderr apart (each run's stderr through `lua/work/run.stderr`; the JIT's `[I]` lines are on
  stdout), a difference naming its stream, and an `oracle` verdict quotes the first line of the
  native stderr; `--suite-port false` gives each file `_port=false`, running the tests `_port`
  skips. Survey 2026-10-29, `--suite-port false` under interp, the trees reconverted on the branch
  (the converter unchanged since 04efd6a): 27 pass, 3 oracle, no fail, timeout or memory verdict
  in each of the source, scc and single layouts; wall time with the conversion 13.1, 15.5 and 16.8
  minutes, the suite runs 613, 754 and 831 s (`all.lua` not run, an oracle). The `_port`-only
  blocks of `gc.lua`, `attrib.lua` (`package.loadlib`, which the ANSI build answers `not
  supported`, as the test accepts) and `math.lua` pass in every layout, each file's converted
  seconds within a few seconds of the `_port=true` run's (up to 6 s apart in scc and single). Verdicts that differ from the `_port=true` run (each a pass
  there): `main.lua` oracle, `sh: 1: lua: not found`: the lane's, the native run's `argv[0]` is
  `lua`, which the file runs through `os.execute`, and no `lua` is on `PATH`; `files.lua` oracle,
  `files.lua:84: assertion failed!`: the lane's, the invalid-seek check expects `io.stdin:seek` to
  fail and `run_and_capture` gives the child `/dev/null`, which seeks; past it, line 732's
  `io.popen` raises `'popen' not supported` in the ANSI build (class a: the file cannot pass
  natively without `LUA_USE_POSIX`); `all.lua` oracle, `main.lua`'s failure, which it runs first (the source layout's run predates
  the stderr quote: its three reasons are the ones the scc and single logs record, and the native
  runs repeat by hand). No libc exactness difference, lowering bug, runtime panic, timeout or memory
  verdict surfaced; the converted side of the three oracle files is not run, so `files.lua`'s later
  `_port` blocks (`io.popen` at 717, the date table at 805 exercising `os.time`/`os.date`,
  `%Ex`/`%Oy` at 841) stay uncovered on both sides until (4) below or a copy of the file without
  its popen block.
  PR 3 (branch `p5.3-main-lua`, follow-ups 2 and 3 of PR 2): each run of `--run`, `--error-check`
  and `--suite-check` reads a pipe at its end as stdin (`0< <(:)` in `run_split`'s bash wrapper,
  every `exec` keeping the program the direct child; `run_and_capture` alone gives `/dev/null`,
  which seeks), and each side's suite runs find a `lua` of their own build first on `PATH`
  (`lua/work/native_bin/lua`, a link named `lua` to the oracle;
  `lua/work/<layout>/bin/lua`, a script running the converted interpreter under the tier).
  Survey 2026-10-29, `--suite-port false` under interp, the trees reconverted on the branch (the
  converter unchanged since 04efd6a): 27 pass, 3 oracle, no fail, timeout or memory verdict in each
  of the source, scc and single layouts; wall time with the conversion 13.0, 15.5 and 16.8
  minutes, the suite runs 614, 748 and 834 s; the 27 passing files' converted seconds
  within 6 s of PR 2's. The three oracles are now each the ANSI build's own (class a),
  past the lane's two causes: `files.lua` passes its invalid-seek check (line 84) and stops at line
  732, `'popen' not supported`; `main.lua` runs `lua -v` through the launcher and stops at line 97
  (`main.lua:59: assertion failed!` in `checkout`): `echo ... | lua` with no script enters the
  interactive mode and its `> ` prompts reach the output, because the ANSI build's
  `lua_stdin_is_tty()` is the constant 1 (`lua.c:426`; `isatty(0)` only under `LUA_USE_POSIX`);
  past it, line 530's `io.popen` would stop it too; `all.lua` stops at the same line, `main.lua`
  being its first file. The converted side of an oracle does not run, so the three files have no
  converted seconds and the converted launcher runs under the stand-in test alone. No libc
  exactness difference, lowering bug, runtime panic, timeout or memory verdict surfaced.
  The memory cap (PR #20, the fix for the red main: the CI runner's user has no root and no
  manager of its own, so there the cap is `prlimit --as`, an address-space limit under which
  `malloc` fails instead of the kernel killing the run) leaves one gap: under `prlimit --as=512M`
  the converted interpreter dies with SIGSEGV where native lua says `not enough memory` (at 4G
  both run, the JIT too), and such a run reads as `fail` with exit code 11, not `memory`;
  whether the daslang heap or the converted allocation path dies is unprobed.
  Next, cheapest first: (1) the JIT survey, `--suite-check --tier jit`, after
  lookibed/daScript#30 (F75: every protected call reports success under the JIT, so the suite
  cannot pass there now); (2) the converted side of an `oracle` file run too, its verdict whether it
  fails the same way (exit code and stderr, masked as the comparison is): `main.lua` up to line 97
  (two runs of the converted launcher), `files.lua` up to line 732 (its `_port` blocks before the
  popen one), `all.lua` up to `main.lua`'s line, a lane change with a stand-in test; (3) whether
  the suite also runs against a `LUA_USE_POSIX` build pair (`isatty` for `lua_stdin_is_tty`,
  `io.popen`, `mkstemp` for `os.tmpname`, `%Ex` in `os.date`), an owner ruling, the port being the
  ANSI build: with it `main.lua`'s 66 nested runs (`RUN` and `NoRun`) each pay the converted
  interpreter's fixed cost, and `files.lua`'s later `_port` blocks (`io.popen` at 717, the date
  table at 805, `%Ex`/`%Oy` at 841) run on both sides; (4) the scc and single layouts'
  per-process compile, a perf row for P5.4 (answered there: the startup row per layout). Done
  (PRs #18, #19, #21, the cap tiers of #20 and #22; closed at the phase end, main 039f554): the
  suite passes under the interpreter file by file in the three layouts (30 of 30 under `_port=true`,
  27 pass and 3 `oracle` under `_port=false`, each `oracle` the ANSI build's own, no converter
  or runtime bug) and as one process (P5.4: `all.lua` 492 s, exit 0, `final OK !!!`); every run
  is capped (a system scope, a user scope or `prlimit`, whichever the host grants) and timed,
  stdin a pipe, each side's `lua` on `PATH`. Leftovers (1) to (3) above and the `prlimit` gap
  (the converted interpreter dies with SIGSEGV under `--as=512M` where native lua prints `not
  enough memory`, the dying path unprobed) stay ledgered; no libc exactness bug surfaced, so no
  fixture landed for one.
- **P5.4 Perf snapshot:** fib/nbody/binary-trees, converted-interp vs native lua. Data
  point only; no bar. Done (branch `p5.4-perf-snapshot`, main 81b5379): the ports publisher's
  capture of 2026-10-30 (`scripts/publish_ports.sh --program lua --perf --samples 5 --lanes
  interp,jit,exe,aot,interp-scc,jit-scc,interp-single,jit-single --timeout 1800` without
  `--commit`: the capture and the READMEs sit in the ports clone until the phase release
  publishes them; the FX-6300, clang 22.1.8, daslang 0.6.4, five whole-process samples, the spawn
  inside each), the converted `lua` over the native build: under the interpreter fib 400 (365 s over
  0.91), binary_trees 193, nbody 324, spectral_norm 436; under the JIT 9.2, 5.7, 7.2, 8.3; as the
  exe 6.1, 3.1, 4.3, 5.5; the startup row 1.15 s under the interpreter, 1.84 under the JIT, 0.052
  as the exe (native 0.006). Per layout (P5.3's follow-up 4): the startup row, each layout's
  per-process load from the module cache, is 1.15 / 6.01 / 8.93 s under the interpreter and 1.84 /
  6.99 / 9.79 under the JIT for source / scc / single, the difference the suite's per-file survey
  shows (30 processes: 614 / 748 / 834 s); with the startup taken off the benchmarks agree across
  the layouts within 6 percent under the interpreter (fib 364 / 386 / 375 s, nbody 331 / 335 / 328)
  and under the JIT one module runs 5 to 26 percent ahead of the source layout (fib 6.5 / 6.3 /
  5.7, spectral_norm 7.6 / 7.6 / 6.1), level with scc on binary_trees (3.5 / 3.4 / 3.4), as P5.1b2
  measured at smaller sizes. The test suite as one process (`-e
  "_port=true" all.lua`): native 8.50 s, the interpreter 492 s (58 times; scc 504, single 507),
  exit 0 with the suite's `final OK !!!`; the capture's JIT cells (2.43 s, 0.29 times native)
  measured no suite: under the JIT an uncaught Lua error exits 0 (F75), so `all.lua` stops in
  `db.lua`, the third file it runs, and exits 0, and the row compared the exit code alone; the publisher
  now requires the closing line (`ports/publish.das`, `closing`) and the phase-release publish
  re-captures under it; the exe suite cell is `not yet` (`Module_CRT` does not load through the
  relative module path from the test folder, the P5.1a leftover); the AOT lane stays `not yet`
  (its host passes no arguments). Against the capture of 2026-10-23 (one module, before P5.1b2,
  P5.2 and P5.3): the interpreter runs fib in 365 s against 386 and the JIT in 8.4 against 15.5, of
  which the startup row is 1.1 against 9.2 and 1.8 against 9.8 (the source layout's cached load
  against one module's), the work under the JIT 6.5 against 5.6 (one module ahead, as above) and
  the exe 5.59 against 5.49, absolute times on the same machine (the native fib cell moved from
  0.76 to 0.91 s between the captures under the same clang, so the ratios do not compare). `perf/results_linux.json` is re-recorded in the same change (the
  phase end's re-record, rule 10): no lane slower than 10 percent (switch_local under the exe lane
  runs 10.3 percent faster, within its 7 percent spread), no `SUSPECT` line.
- **Exit criterion:** Lua test suite passes under interp; JIT/AOT lanes at least compile
  and run the benchmarks.
  Ledger: the suite passes under the interpreter (P5.3) and the JIT lane compiles and runs the
  four benchmarks (P5.4); the suite under the JIT waits for lookibed/daScript#30 (F75: a
  protected call reports success), and the AOT lane neither builds nor runs: the tier refuses a
  program given arguments before any build (`converter/tiers.das`, `run_tier`; the P4.9 ledger
  line); both stay open past the phase tag, as P4's nightly csmith did.

## P8 — Comparison (runs before P6: owner ruling 2026-10-30 (11))

- **P8.1 Head-to-head with lookibed/c2das (the Rust translator)** (owner ruling 2026-10-24 (8);
  added with P5.1b2; owner ruling 2026-10-30 (11): it runs right after the P5 close (PR #25,
  v0.5.0, the ports publish), before any P6 or later item, under rule 10 in small PRs, the Lua
  tests under the memory cap; the Doom parts, which need P6, are marked pending, not blocking;
  the table is reported when done). Build lookibed/c2das (master,
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
  ledger rows to close the gap. Owner ruling 2026-11-01 (14): finished in its current scope, not
  expanded; its Lua speed part, interp and JIT of both translators on the same inputs, is mandatory.
  Done (branches `p8.1-*`, PRs #31, #32, #36 and `p8.1-report`): the Rust translator at
  `ce4647af` on the three suites, the 19 perf kernels, Lua and the output's readability, all in
  `compare/results_linux.json`, rendered by `compare/run.das --readme` into the report, the root
  [README](../README.md#head-to-head-with-the-rust-translator), and into the ports README. Suites
  pass ours 199 / 1179 / 151 against Rust 202 / 1197 / 47 (c-testsuite, gcc-torture, csmith); perf
  geomean over native, ours against Rust: interp 36.08 / 35.92, JIT 1.61 / 1.55, AOT 1.37 / 1.92;
  Rust lines 1.33x ours without its emitted runtime, 5.10x with it. Lua: the Rust side refuses it
  at `ldexp`, 20 libc names in the gap, so it has no Lua speed (deferred to the owner, ruling (19); the report says refused); Doom pending P6.
  The gaps where Rust is ahead: P8.3.
  Compare on the bench: the Rust binary b1d012eb5 (3 commits past the pin, `scripts/` and
  `tests/manual` only) translates all six projects there once its exporter and libclang were in
  place; its `protected_call` audit kernel fails there ("translation failed: operation=top-level
  declaration lowering") where the dev box translated it. Row: PR #93's tdd leftover: compare's
  `--box` wiring into `--suites`, `--suite` and `--perf` has no test (a `--filter` run writes no
  capture, and on a known box the CPU fallback masks the flag): a cpu-name env override for tests,
  low priority.
  Ruling 29 item 4 Done (branch `perf/compare-recapture-pc-2`, PR #104; box PC, Rust b1d012eb5, 5
  samples a kernel cell, 3 a project): geomean ours / Rust interp 30.52 / 30.40 (17 kernels), JIT
  1.13 / 0.96 (14), exe 1.46 / 1.40 (15), AOT 1.22 / 1.23 (15); two cells suspect (bit_pack ours
  interp, va_forward ours JIT). Projects: ours passes binjgb, plmpeg-stream and h264bsd-mp4 on
  every lane; decode over native ours / Rust interp binjgb 4.80 / 4.42, plmpeg-stream 1.63 / 1.38,
  h264bsd-mp4 6.63 / 4.24; wasm3 (v), doomgeneric (s) and quakegeneric (t) refused on our side. The
  first pass ran beside an investigation and had 10 suspect kernel cells: discarded, the kernels
  repeated on a quiet box. The suspect rule in the compare and perf renderers is Done (branch
  `fix/suspect-cells`, PR #103): a cell with a spread over 20% is suspect, never a number, out of
  the means and deltas; the rule lives in `perf/boxes.das` for ports, compare and perf alike.
  Rows from the capture: (1) compare's project runs take their address-space cap from a flag
  (default 6 GiB on a box with the memory; doomgeneric died with SIGSEGV under 4 GiB, an allocation
  failure under the cap, the second crash after (u)), and a crash is a recorded cell error, not an
  rc 139 of the whole run; (2) a filtered `--perf` run re-measures only the named kernels into the
  capture (today it writes nothing), so a suspect cell re-runs alone; (3) `perf/perf_measure.das`
  (compare and perf share it) records a signal death as "signal N (<name>)" with the first stderr
  line, never a bare exit code with an empty message, and spawns every sample under `prlimit
  --core=0` (the kernels runs left 25 GB of crash dumps); (4) the AOT host (`converter/tiers.das`)
  traps and dumps core on an unhandled daslang exception (bit_pack Rust AOT's "array resize ...
  grows past max_unreserved_size", a cell reading "exited 5: " with no message) where the exe lane
  exits 1 with the message: exit with the message, no trap; (5) va_forward AOT crashes
  intermittently on PC in both translations (fine alone, rc 0; fx ran it at 13.4x / 14.8x): watch
  the next capture, with (3) in place the cell says what.
- **P8.1b Readability metric by the critic's criteria** (owner ruling 2026-11-01 (21); after P8.1,
  before P8.2). `metrics/readability.das` gains a criterion for every finding and blind spot of the
  critic's review (`/root/notes/owner/2026-11-01_readability-critic.md`, the agent's footnotes
  included): comments lost, `#define` constant names lost to numbers, character literals turned into
  numbers, macro blow-up as das lines per C line per function, `switch` flag chains and manual
  `_goto`, machine temporaries `_tN` and `_first`, self-assignments, layout-check lines, stray braces,
  `_c_` renames, late-binding slots and wrappers, `__::` and `mod::` calls, `require` lines per module,
  `addr`/`deref` pairs around fields, lost parentheses, long lines and the rest the critic lists. Each
  criterion is a compliance percentage against what a human port would have (its definition stated
  per criterion in `metrics/ARCHITECTURE.md`), plus one total. One command measures the ports output
  (Lua, every layout) and the suites; it runs in the fast tier as a report line and in every item
  report, printing the percentages and their delta against `main`. `main` is re-measured in the item
  and the numbers land in the critic file's footnote area and the PR's `Кратко`. No translator fix in
  this item: the owner decides fixes from the critic file.
  Done (branch `p8.1b-metric`, PR #39): 22 criteria in `metrics/criteria*.das`, each a compliance
  percentage against a human port (`metrics/ARCHITECTURE_CRITERIA.md`), the total their unweighted
  mean; `scripts/run_criteria.sh` measures Lua (both programs, three layouts) and the three suites
  into `metrics/criteria_linux.json` (1535 inputs, 19 min); preflight's `criteria` report gate and
  the item-report line in `AGENTS.md`. Main 26e00eb: total 63.3% (Lua 61.8 source / 63.3 scc /
  58.8 single; c-testsuite 75.2, csmith 69.5, gcc-torture 67.5); comments, constant names,
  character literals, string literals and setjmp at 0%; long lines 35.7%. The numbers are the
  measurement block of the critic file; no translator change.
- **P8.2 Real projects of the Rust c2das** (owner ruling 2026-11-01 (17); after P8.1, before P7.0a).
  The six projects of the Rust repository's `tests/manual` (binjgb, doomgeneric, h264bsd-mp4,
  plmpeg-stream, quakegeneric, wasm3), each run through c2das-re on exactly the inputs, hosts,
  fixtures and reference outputs the Rust side uses there (its README, UPSTREAM and
  `fixtures/*.expected` are the oracle), the Rust result beside it. Per project: correctness (the
  Rust side's check passes or not, a failure classified refused, compile error, runtime, wrong
  output), speed on the same machine where the Rust side has a benchmark (interp, JIT, AOT or exe
  as available), code (`metrics/readability.das` on both outputs, size, a short side-by-side of one
  or two hot functions). Rules: the Rust checkout is read in place (`/root/c2das`, the owner's; no
  copy, worktree or rebuild; the binary through `C2DAS_RUST_BIN`); a host that needs SDL, Eden or a
  window runs headless or through the reference-output path, else one line says so and no GUI stack
  is built; one small PR per project (rule 9), the easiest first; a c2das-re failure becomes a ledger
  row, its fix a separate item; doomgeneric does not replace PureDOOM in P6 (overlaps noted); the
  memory cap and the two-heavy-tasks rule as for Lua. Output: one generated table in `compare/` and
  the ports README, never hand-typed; the `Done` row short (ruling 15).
  Done (branches `p8.2-*`, six PRs): `compare/run.das --project <name>` captures each project into
  `projects` of `compare/results_linux.json`, rendered under
  [Real projects](../README.md#real-projects). Ours is refused on 6 of 6 (five at an include folder
  or an external header, P8.4 (a); quakegeneric at a `///` comment); Rust passes 6 of 6 (interp and
  exe everywhere, JIT on 5: quakegeneric's prints LLVM JIT warnings before the right frames); Rust
  interp 31-71x native, JIT and exe 0.95-2.2x.
- **P8.3 Gaps against the Rust translator** (from P8.1's "where the Rust version is better"; the
  README's head-to-head block lists them: a suite on any excess, the rest past 5%). Candidates, each
  its own item later, none scheduled: the interpreter cells where Rust is ahead (`blit`,
  `compound_lit`, `do_while_effect`, `matmul`, `sieve`, `str_copy`, `switch_goto`, `switch_local`,
  `va_forward`); `switch_local` under the JIT (Rust 0.98x native, ours 5.96x) and AOT (our build
  fails); the suite ids Rust passes that our ratchet skips (gcc-torture 41, csmith 5, c-testsuite
  0). The rest of the list (`switch_goto` JIT and exe, `primes` AOT, the counter `pointer_arith`) is
  read from the block when an item is cut.
- **P8.4 Converter gaps found by P8.2** (from P8.2's six projects: wasm3, binjgb,
  h264bsd-mp4, plmpeg-stream, doomgeneric, quakegeneric). Candidates, each its own item later, none
  scheduled: (a) include folders, a sidecar key for both clang passes, and a program root wider than
  the main file's folder (wasm3 refused at `m3_bind.c`, binjgb at `common.c`, doomgeneric at
  `dummy.c`; further clang arguments such as quakegeneric's `-include engine_config.h` passed through
  too; `CPATH` or a symlinked root:
  an empty module; `../upstream` files are external: h264bsd-mp4 refused at `picParamSet_t`,
  plmpeg-stream at `plm_frame_t`); (b) braced scalar pointer initializers (`m3Err_none = { NULL }`,
  "not dumped yet"); (c) `__attribute__((musttail))` refused (the Rust side drops it with a
  warning); (d) the AOT host of `converter/tiers.das` passes no program arguments, so AOT is
  skipped for argv programs; (e) a C name that is a daslang type keyword (`Obj.byte3`) is emitted
  unrenamed, a compile failure; (f) `clock_gettime` has no c_runtime mapping (the Rust corpora's
  bench units refused on our side); (g) glibc `assert` without `NDEBUG` refused at `__extension__`;
  (h) `c2da_rt_reset()`, a test-runtime hook the Rust runtime defines and the native build takes
  from `shim.c`, is undefined for our converter once (a) is fixed (plmpeg-stream; not reached yet); (i) a `///`
  or `/** */` doc comment before a function is refused as a `FullComment` child (quakegeneric at
  `common.c` `memsearch`).
  Done for (a)-(h) (branch `p8.4-inputs`, PR #54, 2026-11-02): sidecar `include_dirs` and
  `program_root` (both clang passes; `CPATH` folders are user folders; an empty-module path is an
  error); braced scalar initializers; `musttail` as a plain returned call; the AOT host passes
  argv; das builtin type names take `_c_`; crt `clock_gettime`; glibc `assert`; `c2da_rt_reset` by
  a sidecar define. binjgb converts and passes interp/JIT/exe; gcc-torture +2 (`20001011-1`,
  `pr58831`, recorded with the phase-end readability re-record). Still open: (i) a calling-
  convention attribute inside a type spelling (`preserve_none` through wasm3's `vectorcall`); (j)
  a file-scope function-pointer table whose functions read the table back is a das global-
  initialization loop (emitter). Leftovers: the perf re-record for the AOT host change
  (`setCommandLineArguments` only), the readability re-record, compare's `aot` skip for argv
  programs and the ports Lua AOT lane can now run.
  Found after: (k) a block-scope `extern` without a file-scope declaration (quakegeneric
  `console.c:520`, doomgeneric `d_main.c:1336`; P6.3b); (l) an `extern` array used before the
  definition that sizes it (h264bsd-mp4 `h264bsd_deblocking.c:669`; P6.3a); plmpeg-stream needs an
  ours-only sidecar define (`c2da_rt_reset(...)=`) in the projects table. Projects rerun (branch
  `p8.4-projects`, PR #61): binjgb passes interp/JIT/exe through our converter (74.1x / 0.99x /
  1.25x native).
  Projects table (branch `p8.4-projects-table`, PR #76): compare's `aot` lane runs for a program
  with arguments (after `--`); ours-only per-project defines (plmpeg-stream `c2da_rt_reset(...)=`,
  recorded in the capture and the README); `--samples 0` leaves the speed cells "not measured"
  (owed to the bench, `bench-queue.md`); an AOT build failure is recorded by its heap line, else
  its first error; the capture records the address-space cap, 4 GiB (the Rust AOT generator's 1 GiB
  heap starves under 3 GiB). Table at 4 GiB (ours / Rust; interp, JIT, exe, AOT): binjgb pass pass
  pass COMPILE / all pass; plmpeg-stream all pass / all pass; wasm3 refused (i) / all pass;
  h264bsd-mp4 refused (l) / all pass; doomgeneric refused (k) / pass pass pass TIMEOUT (the 300 s
  build limit); quakegeneric refused (k) / pass OUTPUT pass pass. (k) and (l) are fixed on `main`
  since (P6.3b, P6.3a): quakegeneric, doomgeneric and h264bsd-mp4 pass the dumper; doomgeneric
  needs a sidecar marshal entry for the packed `mapvertex_t` (doomdata.h:57), h264bsd-mp4 stops at
  minimp4.h:2377, a `goto` into a loop body (P7.7): rerun the table after P7.7. New: (m) ours
  binjgb AOT: the generated C++ has a `goto` over a variable initialization
  (`binjgb_all.das.cpp:8637`, 10 errors) where the interpreter accepts the das, a daslang AOT gap
  beside `switch_local` (`perf/ARCHITECTURE.md`; lookibed/daScript#18); (n) doomgeneric's
  Rust AOT build against the 300 s build limit; (o) `test_projects`' stand-in wasm3 run shares the
  real wasm3 work folder (a concurrent run wiped it once): give the test its own folder. (o) Done
  (branch `fix/small-rows-p6.3g-h`, PR #80): compare `--work <folder>` (default
  `compare/work/projects`); the binjgb and h264bsd-mp4 stand-ins, which also wrote into the real
  folders, use the test's scratch too. Leftovers: `--work` unvalidated (an unwritable folder;
  ignored without `--project`; `rmdir_rec` on a user-named folder); the untouched check covers
  wasm3 only.
  Bench capture (PR #92, box bench; closes `bench-queue.md`'s projects-table line): Rust b1d012eb5
  translates and passes all six (quakegeneric JIT output differs, doomgeneric AOT times out); ours
  passes binjgb (AOT (m)) and plmpeg-stream. Speed over native `decode_us`, ours / Rust: binjgb
  interp 80.57 / 73.01, JIT 1.22 / 1.08, exe 1.29 / 1.05, AOT - / 1.10; plmpeg-stream 49.44 /
  39.15, 1.08 / 0.95, 1.18 / 1.01, 1.13 / 1.05. The entries carry no `cpu` or `box`: re-captured
  under ruling 29 item 4.
  Ours-side stops, ruling 29 item 2 (converter holes Rust passes; each its own row): (i) wasm3
  `vectorcall m3ret_t` in a type spelling (dumper); (p) doomgeneric `m_config.c:109` type spelling
  (dumper); (q) h264bsd-mp4 error[30341] too many matching functions or generics `malloc`, a
  project defining its own `malloc` beside crt's (compile check; a P6.3-class item); (r)
  quakegeneric `sys_null.c:160` `vfprintf` without a c_runtime map (emitter; a stdlib row, the
  vfprintf/vprintf family). (p) Done (branch `p8.4p-doomgeneric-type`, PR #96): the empty spelling was a
  doc comment (`//!`, a `FullComment` child) taken as a global's initializer; doomgeneric now
  passes the dumper and stops in the emitter at `doomdata.h:57:9`, "record `mapvertex_t` is not laid
  out naturally: a packed record is marshal-only, listed under `marshal` in the .c2das sidecar":
  (s) the projects table gives our side a per-project sidecar `marshal` list (the PureDOOM records,
  `doom/doom.c2das`, as the model), then the next stop is read. (r) Done (branch
  `p8.4r-vfprintf`, PR #98): `vfprintf` is c_runtime's `c_vfprintf`; quakegeneric now stops in the emitter
  at `host_cmd.c:63:10`, "a pointer to a variadic function is not lowered yet" (`void (*print)
  (char *fmt, ...)` in `Host_Status_f`): (t) a function pointer of variadic type, its `invoke`
  passing the trailing tuple; Rust passes interp, exe and AOT there (JIT output differs). One of
  two compare runs of the project crashed (SIGSEGV in `compare/run.das` after the Rust lanes'
  module list), the rerun did not: (u) watch for it in the ruling 29 item 4 re-capture.
  (q) Done (branch `p8.4q2-malloc-shadow`, PR #99): a function the program defines named like a
  libc function c_runtime maps takes the next free numbered name (`malloc1`, `strlen1`) and every
  call and `@@` reference binds to it (`rename_taken_names`, the `c_argc1` mechanism); h264bsd-mp4
  passes interp, JIT, exe and AOT, no next stop.
  (i) Done (branch `p8.4i-vectorcall`, PR #102): a calling convention in a type spelling drops, through
  the macro clang spells in its place too, and a `_Static_assert` at file or block scope is
  skipped (the next stop, `m3_compile.c:204`); wasm3 now stops in the dumper at `m3_parse.c:305:22`, "`m3type_t
  argTypes[numArgs + 1]`: a variable-length array is not lowered (out of scope in v1)": (v) a VLA
  local, out of scope in v1 (`docs/very-detailed-plan.md`); Rust passes all four lanes there.

## P6 — Doom

**Goal: the metric.**

- **P6.1 PureDOOM import.** Vendored, sidecar authored (defines, marshal types for WAD
  structs, alloca/stack sizing; `actionf_t` needs no entry, F32). Instrumentation patch: per-tic
  checksum (players[0].mo x/y/z/angle/health + P_Random index) — applied to the C
  source, so the native build and the converted build share it by construction.
  Done (branch `p6.1-puredoom`, PR #52, 2026-11-02): PureDOOM fetched at pin 355cfbd
  (`doom/fetch.sh`, never committed, GPL-2 kept in `doom/`), freedoom 0.13.0 pinned by sha256;
  `doom/patches/0001-per-tic-checksum.patch` (FNV-1a per tic over player 0's x/y/z/angle/health
  and `prndindex`, `-DDOOM_TIC_CHECKSUM`; fixes PureDOOM's `-timedemo` falling into the title
  loop); headless host with a virtual clock; `doom/sources.das` (62 units + host),
  `doom/doom.c2das` (6 defines, 11 marshal records, 3 over_indexed, no stack/alloca keys: no
  alloca, native stack under 16 KiB); `doom/run.das` `--fetch-check/--native/--demo`; 20 tests.
  Eight findings for P6.3 in the PR. Report: the PR.
- **P6.2 Native baseline build** (MSVC /O2) with instrumentation; record reference
  checksum logs for demo1/2/3 on freedoom2.wad and doom2.wad.
  Done (PR #52, 2026-11-02): native baseline with the pinned clang at -O2 (MSVC /O2 does not apply
  on this box); `doom/ref/freedoom2_demo{1,2,3}.log`, 2664 / 5444 / 2743 tics, demo2 a two-player
  demo; identical across runs and at -O0; no native desync or crash. doom2.wad: harness accepts
  `--wad`, its logs stay local (owner's file). Report: the PR.
- **P6.3 Converts + compiles.** First real whole-program stress after Lua; expect
  module-size issues here if anywhere (SCC split is the tool).
  Partial (branch `p6.3-convert`, PR #59): `doom/run.das --convert`/`--compile-check` and the
  blocker table; 10 of 63 units convert alone, the whole program stops at the dumper (DOOM.c
  `defaults[]`); 0 modules compile. Also hit: P7.7 (a `goto` into a block: F_CastTicker,
  P_SlideMove) and P6.1's finding 2 (`maptexture_t.patches`). The blockers are the rows below.
  After P6.3a-d (`doom/ARCHITECTURE.md` section 7): 11 of the 63 units pass alone, 51 stop at a
  function or an array another unit defines (link-bound), 1 at finding 2 (`r_data`); the whole
  program passes the dumper and the layout and stops in the emitter at `f_finale.c:408`, a `goto`
  into a loop body (P7.7), so no module is emitted and none compiles; the `source` layout holds 51
  units in one cluster (39 modules), `source-cut` 36 (56 modules). The whole-program conversion
  needs more than 3 GiB of address space (under `prlimit --as=3G` daslang dies with SIGSEGV on an
  allocation failure), so the harness runs it uncapped in a `heavy` scope of its own. P7.7 (PR
  #81) then ran before P6.4; the rows P6.3e-k took the whole program to 39 of 39 modules compiling.
- **P6.3a Dumper: `extern T a[]` sized by another unit** (5 units; DOOM.c:468 `extern int
  defaults[]`, where the whole-program dump stops; P8.4 (l)).
  Done (branch `p6.3a-extern-array`, PR #74): the dumper keeps clang's incomplete `int[]` on a
  reference before the definition (`c-ir-spec.md` section 7: dumpers never link); the emitter's
  `complete_extern_arrays` pass gives the reference the type of the global its name binds to (the
  tentative merge within a unit, the link across units), only a definition completes it (either
  unit order); refused: an array no unit defines (emitter), a declared length differing from the
  definition's (link). Doom units alone 10 -> 11, the program then stopped at DOOM.c:607 (P6.3b);
  the harness marks a unit alone stopping at another unit's array link-bound; h264bsd-mp4 passes
  `h264bsd_deblocking.c:669`. Found: the two rows P6.3g and P6.3h.
- **P6.3b Block-scope `extern` without a file-scope declaration** (3 units and DOOM.c; also
  quakegeneric and doomgeneric in P8.2: P8.4 (k)).
  Done with P6.3c (branch `p6.3b-block-extern`, PR #75): the first block-scope `extern` object or
  function prototype of a name is dumped as a unit-level declaration before the function (a later
  one binds by clang's previousDecl; a later definition in the unit completes it, the link binds
  another unit's; stdout-like names bind by file-scope name); a parameter or local named like one
  takes a free name; a hoisted static skips those names. Doom link-bound 44 -> 50, the block-scope
  rows 0, the program then stopped at `m_misc.c:193` (P6.3d); quakegeneric `console.c` and
  doomgeneric `d_main.c` pass the dumper (doomgeneric stops at doomdata.h:57, the packed
  `mapvertex_t`: a sidecar marshal entry, P8.4). Review leftover (no test): `dumper_a.das`'s
  `defines ? local_name(...) : raw` on a prototype's parameters changes nothing observable; a
  fixture case, or drop the condition.
- **P6.3c Block-scope function prototype** (2 units). Done with P6.3b (PR #75).
- **P6.3d File-scope `;;`**. Done (branch `p6.3d-empty-decl`, PR #77): clang reports a stray `;;`
  or the `;` after a function's `}` as an `EmptyDecl`, which the dumper skips; fixture
  `p6_empty_decl`; the doom stand-in's refused unit is a file-scope `asm` now.
- **P6.3e A marshal record's array field as an lvalue** (store, address, decay; fails closed since
  PR #59; PureDOOM's `mtexture->name` reads need the decay).
  Done (branch `p6.3e-marshal-array`, PR #82): every array field f of a marshal record T gets a
  generated `ptr_T_f(bytes, ofs)` = `reinterpret<E?>(bytes + (ofs + clang_offset))` (a 2-D field:
  E is a row), replacing the copying `read_T_f`/`write_T_f` pair; the decay is that pointer;
  element reads, stores, `op=` and steps go through `deref(ptr_T_f(p, 0) + i)`, in place, no range
  check, as C (a 2-D row index still checked); `&p->a[i]` is the pointer plus i, `&p->a` the
  pointer reinterpreted. A typed load at a packed offset relies on x86 (a strict target needs
  memcpy). Doom's whole program then stopped at `r_data.c:83`, finding 2 (P6.3i). Leftovers: an
  array-of-pointers field of a marshal record (`char *names[3]`) is refused with the finding-2
  message (the innermost-type check reads a pointer as a record) though `ptr_T_f` lowers it with
  no new case; `&p->first` of a scalar marshal field emits `addr(read_T_f(p, 0))`, which das
  refuses at compile time (pinned by `first_member_marshal_record`; the pointer form lowers it);
  `over_indexed` no longer affects a marshal array field (every element access is unchecked), to
  be said in the key's doc when the key is reworked.
- **P6.3f The `source` layout's 51-unit Doom cluster** (`source-cut`: 36): the cut's thresholds and
  profile for Doom before P6.4 (ruling 6).
  Done (branch `p6.3f-doom-cut`, PR #79, docs only): the census is P7.0l's Doom half. The cut
  (static call-site weights): `source` 39 modules, largest 51; `source-cut` 55 modules (54 plus
  the link module), largest 36, 132 cut lines on 72 edges, 65 symbols, weight 297 (`I_Error` 24,
  `Z_Malloc` 16, ...); threshold 10: 50 modules, largest 41. No hot call is late-bound (render,
  sound, video and the per-tic play core are all inside the 36). Judgment: the defaults stand, the
  sidecar options can only grow the cluster; re-judge with `layout.profile` after P6.4
  (candidates p_tick+p_user, p_tick+p_spec, p_mobj -> z_zone). Leftovers: an `--edge-census`
  passthrough in `doom/run.das`; a per-kind breakdown of the residual cluster in `edge_census`;
  section 7's "56 modules" re-measured as 55.
- **P6.3g A C file named like a daslang keyword** (found by P6.3a): `table.c` becomes `require
  table`, which breaks the `source` layouts; the module names are checked against `DAS_KEYWORDS`
  and such a unit's module renamed.
  Done (branch `fix/small-rows-p6.3g-h`, PR #80): a keyword-named C file's module is `_c_<stem>`
  in the source layouts (fragments, member lists and sidecar keys keep the stem; headers were
  `_h` already); `DAS_KEYWORDS` lives in `cir.das` and gained if/else/for/while/break/continue/
  default; the `single` layout never failed (the entry module is required by nothing). Leftovers:
  `ports/publish.das`'s `module_of` spells the plain entry stem (latent for a keyword-named main
  file); no test for `main` in a keyword-named file nor for `_c_table.c` beside `table.c` (refused
  cleanly).
- **P6.3h The declarator `int (*p)[] = &a;`** (found by P6.3a): `&a` of an `extern int a[]`
  already lowers (P6.3a's pass; tests added with P6.3g, PR #80); the pointer to an array of
  unknown length still fails closed, its message naming the wrong construct (daslang has no fixed
  array without a length); nothing converted so far needs it.
- **P6.3i A record or array-of-records field of a marshal record** (P6.1's finding 2;
  `maptexture_t.patches`, `r_data.c:83`, where the whole program stopped after P6.3e).
  Done (branch `p6.3i-marshal-record-fields-v2`, PR #83): the field gets `ptr_T_r(bytes, ofs) :
  uint8?` (the inner record's bytes), member access composes the accessors, an array-of-records
  index scales by the record size, a whole-record copy includes the inner records; a record array
  held by value is the das array indexed directly; `sizeof` of a record-array field is clang's.
  Refused: a union field, an unlisted record, a 2-D array of records, an array of pointers,
  `&o->arr` of a whole array-of-records field (by name). Doom: every module emitted for the first
  time; `--compile-check` 37 of 39 (the DOOM cluster fails at `d_net.c:103`, the null-pointer
  offsetof idiom, and `p_pspr.c:655`, an int-left pointer sum: P6.3j; `doom_main` requires the
  cluster); units 11 alone, 52 link-bound, 0 at finding 2. The marshal paragraph moved to
  `ARCHITECTURE_EMITTER_AGGREGATES.md` "Marshal-only records" (the 300-line limit). Leftovers: an
  over-indexed record array indexed on a local value; `for (k in range(1))` in a one-element
  reader.
- **P6.3j The null offsetof idiom and `n + p`** (found by P6.3i's compile check).
  Done (branch `p6.3j-doom-compile`, PR #84): `(integer)&((T *)0)->f...` is the byte offset as an
  integer (a plain record: `typeinfo offsetof` plus index times sizeof; a marshal record: clang's
  numbers folded; a union: member 0), every other member use through a null constant refused by
  name; `n + p` with the pointer on the right is `p + n`, scaled alike (`+` only). Fixed on the
  way, a latent bug: `offsetof(T, f)` on a marshal (packed) record used daslang's layout (8 where
  clang gives 7). Leftovers: `offsetof(T, a[i])` and `offsetof(T, a.b)` are refused by the dumper
  (a member path); the fold applies only with `&` directly under the integer cast, so
  `(size_t)(char *)&((T *)0)->f` is refused by name, not folded; `ARCHITECTURE_EMITTER.md`'s
  "never clang's constants" now reads against its marshal exception (phase-end wording audit).
  Doom then stopped at `m_menu.c`, daslang's 31104 "global variable initialization loop" (P6.3k).
- **P6.3k A global initializer that reaches its own global** (`m_menu.c`: menu tables holding
  functions whose bodies address other menu tables, MainMenu -> M_NewGame -> EpiDef -> ... ->
  MainMenu). Done (branch `p6.3k-global-init-loop-v2`, PR #85): daslang's rule, probed
  (`probes/test_globals.das` `test_global_init_loop`, F79: an initializer depends on every global
  and function it names, transitively through bodies; a path back is error 31104; no initializer,
  no dependencies), is applied to the C-IR in C order by `init_reaches_itself`; an initializer
  reaching its own global moves into `[init] def private c2das_init_globals` as an assignment
  (the existing address-of-a-later-global form), acyclic ones keep the plain `var`. Doom compiles
  39 of 39; units 11 alone, 52 link-bound. `lowering-examples.md`'s "no ordering constraint" for
  function-pointer tables holds only while no function in the table reaches the table back
  (rulings-pending). Leftovers: the C-IR records no binding, so a local named like a module
  global counts as it (a needless move, never wrong); a fixture menu whose function only calls a
  reader (the call-only path); a cross-unit cluster case (works, untested).
- **P6.3 harness fix: `doom/run.das` does not compile on `main`** (found by P7.0l):
  `doom/convert_check.das:109` passes `side.defines` to `dump_tu`, which takes a `DumpInputs`
  since P8.4, and the compile gate does not reach `doom/`; fix the call and add `doom/` to the
  gate. Done (PR #66, with the end run's fixes): `pipeline.das`'s `dump_inputs(side)` serves both
  callers, `doom/` is in the format, lint, compile and ast gates, `doom/tests` in the tests lane.
- **P6.4 Boots headless.** `D_DoomMain` to attract screen; framebuffer CRC at fixed
  tics vs native.
  The harness half Done (branch `p6.4-doom-run`, PR #86): `doom/run.das -- --run [--layout]
  [--tier interp|jit|exe|aot] [--demo N] [--tics N] [--wad] [--timeout S]` runs
  `doom/work/<layout>/doom_main.das` through `run_tier` with `-timedemo demoN` and `DOOMWADDIR`,
  holds its tic lines to `doom/ref/<stem>_demo<N>.log` and reports the first desynced tic or "N
  tics in sync", the exit code or timeout, the first error line (any-case error, exception or a
  daslang EXCEPTION) and the seconds per 35 tics; a whole-demo run passes only in sync to the end
  with the timedemo line; one tic-line reader (`harness.das`); per-layout exe and aot folders;
  `doom/ARCHITECTURE_RUN.md` section 8. The framebuffer half Done (branch `p6.4b-framebuffer-crc`, PR
  #88): the tic line is `tic=<gametic> cs=<8 hex> fb=<8 hex>`, fb FNV-1a over `screens[0]`'s
  64000 bytes, printed whole by `D_DoomLoop` after `D_Display`; the host takes `-tics N`
  (`--tics` passes it, a capped run ends clean); the harness names the differing fields; the
  three reference logs re-recorded (2664 / 5444 / 2743 tics, every `cs` unchanged). Found and
  fixed in the patch, by unconditional hunks both sides run: the native frame was not repeatable
  (`R_DrawColumn` reads up to 127 bytes past a column's start, freedoom2's 16-row CRATINY as a
  bottom texture and a sprite's first row rounding to -1, into the allocator's next block
  header), so cached lumps and composites get 128 zero bytes of slack and the screen is zeroed at
  start; the reference frames are the patched source's at those pixels (rulings-pending).
  Hashing 64000 bytes per tic costs the interp tier (watch at P6.7).
  State (`main` d00eeae): the converted Doom boots through the whole `D_DoomMain` init, renders,
  and runs demo1 in sync with the reference to tic 24 in `cs` and `fb`; tic 25 desyncs (`cs`
  expected ada955a8, got b66019e2; the first differing fields are player 0's x and y, momx and
  momy, `prndindex` equal), a panic followed at tic 137 (`finesine[angleb >> 19]`, index -4096,
  `r_main.c:413`, likely downstream): P6.5's first rung, branch `p6.5-tic25` in progress. The
  row is Done but for that desync, which P6.5 owns. Facts: `--compile-check` 39 of 39; the
  conversion takes 150 s at 2.9 GB peak on the dev box and dies with SIGSEGV under a 3 GiB
  address-space cap (the harness runs it uncapped in its own `heavy` scope); 1.18 s per 35 tics
  under the interpreter on the dev box (not a headline number, ruling 25).
- **P6.4a Padded array fields** (the first run's crash at `r_plane.c:442`, `pl->top[pl->minx - 1]
  = 0xff`, index -1 of 320: `visplane_t`'s `pad1; top[SCREENWIDTH]; pad2; bottom[SCREENWIDTH];
  pad3` absorb the -1 and N indexes, C UB Doom relies on). Done (branch `p6.4a-padded-fields`, PR
  #87): the sidecar key `padded` (`["Record.field"]`) names an integer array member with an
  integer neighbour of the element's width directly before and after (clang's offsets; a
  non-marshal record); it is indexed through its decay, unchecked, `deref(addr(pl.top[0]) +
  (pl.minx - 1))`, sound because the emitter's layout assertions make the das offsets clang's,
  so -1 and N land in the pads; refused without the key. `doom.c2das` lists `visplane_t.top` and
  `.bottom` (`openings`, `floorclip`, `ceilingclip`, `negonearray`, `screenheightarray` are
  reached through pointers only). Review leftovers: `pads_at`'s offset test lacks a reject case
  (an `aligned` member); a `_Bool` neighbour is accepted; the `+ -1` spelling;
  `doom/ARCHITECTURE.md` section 8's run paragraph states a dated result (the mood test: the
  tic numbers belong here); closed by P6.7: the paragraph, now `doom/ARCHITECTURE_RUN.md` section 8,
  names no result, and the tic counts are in P6.5 and P6.7.
- **P6.5 Demo sync.** The ladder: first desynced tic → bisect → fix → repeat until
  demo1/2/3 are 100% on both wads (doom2.wad dropped by the owner, ruling 30: freedoom2.wad alone). This is the semantics endgame; every desync is a
  real bug with a tic number attached.
  Rungs 1-2 Done (branch `p6.5-tic25`, PR #90): the tic-25 desync was no converter bug: ticcmd_t's
  plain `char` forwardmove/sidemove read demo1's strafe -40 as 216 under the converter's
  unsigned-char dialect (F17) against a signed-char native build; patch 0003 makes them `signed
  char` (Chocolate Doom's shape). Rung 2: vanilla's `finesine[negative]` (`r_main.c:413`) and
  `finetangent[>=4096]` (`r_segs.c`) read the neighbouring table, which das range-checks; patch
  0004 spells the neighbour read out (same bytes, native frames identical). Patch 0002
  (`-DDOOM_TIC_TRACE`): P_Ticker prints the six checksummed values per tic and `run.das --trace`
  holds the converted traces to the native ones apart from the reference path. Result: freedoom2
  demo1/2/3 under interp, `source` layout, in sync to the end (2664 / 5444 / 2743 tics, `cs` and
  `fb`), each ending in the timedemo line.
  RULINGS (owner, ruling 30 item 3, from `/root/notes/research/doom-native-questions.md`): (a) the
  native reference stays the signed-char build with patch 0003, not `-funsigned-char`; (b) rung 2
  stays patch 0004; rows: an alias sidecar key (two globals as one storage) when a second program
  needs it, and the emitter flags a constant out-of-range index with its C location instead of das
  failing at simulate time (error 50300); (c) "both wads": closed, dropped by the owner (ruling
  30): freedoom2.wad is the one IWAD.
  Next rung: jit, exe and aot and the `source-cut` and `single` layouts on freedoom2 demo1-3 (doom2.wad
  dropped by the owner, ruling 30); ruling 29 item 1 takes the rungs P6.7 needs with it. Leftovers: the native trace run's
  exit code is not checked (a partial `.native.log` passes); `native_path`, `layout_dir` and
  `sidecar_defines(true)` have no direct test; `doom/ARCHITECTURE.md` at 296 of 300 lines,
  closed by P6.7: sections 8 and 9 are `doom/ARCHITECTURE_RUN.md`.
- **P6.6 Playable harness.** dasImgui window (framebuffer texture blit, key mapping),
  PCM SFX to the native audio path, MIDI music via dasAudio strudel_midi_player + GM
  soundfont.
- **P6.7 timedemo.** `-timedemo demo3` realtics for native / interp; publish table v1.
  Ruling 29 item 1, first in the order: Doom fps under interp and JIT on one machine next to Rust
  doomgeneric on the same machine (Rust doomgeneric interp 32.0x its native, measured on box PC below); if slower than Rust, find out why
  first; the P6.5 rungs it needs come with it. Ruling 28: the speed number is realtics, in-process,
  never the process's wall time (startup is its own row); the per-tic framebuffer hash costs the
  interp tier (P6.4b), measured apart.
  Done (branch `p6.7-doom-fps-2`, PR #101; box PC, Ryzen 7 7435HS, WSL2): the host times the playback with
  `clock()` (`host: timed N gametics in S s`); `doom/run.das --run --fps` holds every run of demo1-3
  to the reference log under native, interp and JIT with the sync build, all in sync (JIT demo1/2/3
  2664/5444/2743 tics to the timedemo line), then times the speed build, `DOOM_TIC_CHECKSUM` left
  out (ruling 30), 3 runs a cell, every spread at or under 1% (`doom/results_linux.json`): native
  9029-10508 fps, interp 149-166 fps (59.2-63.3x native), JIT 2454-2855 fps (3.6-3.8x). With the
  checksum in the window (the first capture, 70eeb8f3da4f) the ratios read 47.3-47.7x and 2.4-2.8x:
  the checksum's cost hid part of the gap. The
  Rust doomgeneric on the same box (`compare/run.das --project doomgeneric --samples 3 --box PC`,
  `-timedemo demo1` on doom1.wad): interp 32.0x its native, JIT 1.04x. Engines, wads and demos
  differ; only the ratio to native compares.
  Why interp is slower, measured on PC with scratch kernels, one construct each (not committed; the
  method is this text): (1) the patch's per-tic `fb` checksum is inside every lane's window. Its
  loop alone over a 64000-byte buffer: 57 us per frame as C at the pinned clang `-O2` (20000 frames,
  one run, `clock()`) and 970 us as its converted body (the `while` of `d_main.das.inc`) under interp
  (500 frames, one run); set against the capture's per-tic times that is about 35% of a native tic
  and 12% of an interp one; the speed build measures the interp ratio without it at 59.2-63.3x.
  (2) `do { ... } while (count--)`, the inner loop of `R_DrawColumn` and `R_DrawSpan`, lowers to the
  `_first` flag loop with a temporary per pixel; a scratch kernel with `R_DrawColumn`'s body over
  module arrays, 200000 columns of 151 pixels, the converted loop against the same body in a
  counted `range` loop, 3 runs in one process: 1.33-1.36x slower under interp, 0.94-0.98x under
  JIT. Rust emits `for (urange64(0, count + 1))`. Row (a): a `do-while` whose condition is a
  post-decrement of a local counter lowered as a counted range (the converter; idiomatic default). (3) the frame checksum's own `for`,
  its counter declared outside, stays a `while` (not timed apart).
  Rows: (b) a per-function profile of a converted demo under interp, blocked: the daslang profiler
  prints no summary when the program exits through C `exit`, and a 700-tic trace exceeds 4 GiB: a
  host flag that returns from `main` instead of `exit` for profiling runs; (c) the JIT gap, 3.6-3.8x
  against Rust doomgeneric's 1.04x, unexplained: P7.0b2 did not reach it, P7.0b3 takes Doom beside
  Lua's residue.
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
  literal the store now fails closed instead. Owner ruling 2026-11-01 (13): the range form and the
  trailing increment are the default, `--loops while` the option; section 6 and "General for" are
  corrected by the B pull request. Bench captures (ruling (25), AMD Ryzen 3 1200): the default
  method re-recorded at `main` 551fba8 (branch `perf/bench-rerecord-551fba8`, PR #68; the first
  capture since the AOT host passes arguments, P7.0c's dispatch and the P7.0d/e/g kernels, so its
  deltas against the fx6300 baseline mix machine and code; `switch_local/aot` has no cell, the
  AOT gap lookibed/daScript#18) and at 504ca55 with the `interp-reinterpret` lane and the `first_member` kernel
  (PR #73). The dasProfile method's section and its column stay at the fx6300 capture until the
  bench has cmake >= 3.24 (dasProfile 436d58d's CMakeLists needs `DOWNLOAD_EXTRACT_TIMESTAMP`; the
  bench has 3.22; rulings-pending); the audit entries owed per item are in `bench-queue.md`.
  Ruling 27 (b) Done (branch `fix/box-labels`, PR #93): `perf/boxes.das` maps the CPU to a box
  name, `--box` overrides it; a `box` field beside `cpu` in the perf and compare captures, on every
  "Captured on" line and table; the rendered delta refuses two boxes in one line. Open: (c), the
  one-box before/after renderer `scripts/ab_measure.sh` (two worktrees measured interleaved in one
  run, the delta table from the two captures; `/root/notes/plan-measure-setup.md` section 4) and
  `scripts/bench_check.sh`, the dependency check before any timing (section 2). Leftover:
  `scripts/run_perf.sh --check` and the FLAG lines still compare a run against a committed capture
  of another box (print "no check: <label a> against <label b>" and pass, or refuse: owner's call)
  and the script names the box it expects. Lint opportunity: a gate flagging a `["cpu"]` read in a
  renderer outside `perf/boxes.das`.
  Ruling 28 audit: `perf/` is clean, the default method times the kernel's calls with the CRT clock
  in the process and the dasProfile method with the steady clock (`perf/ARCHITECTURE.md` sections 2
  and 6); `compare/` is clean, kernels by the dasProfile method, projects by the bench entry's
  in-process `setup_us`/`decode_us`; the compare `lua` section defers to ports.
- **P7.0a Default layout: cycles as one module** (owner ruling 2026-11-01 (12); after P8.1, before
  P6: ruling (14)). The default layout keeps every cycle one module of `.das.inc` fragments, a file
  per member (P5.1b2's `scc`), branches separate modules, header clusters as they are; the cycle cut
  by late binding stays an opt-in flag and sidecar field. The mode names follow the meaning (for
  example `source` = cycles as one module, `source-cut` = with the cut, `single`), the rename recorded
  in `converter/ARCHITECTURE_LAYOUT.md`; tests and captures in every mode as now; the ports publisher
  publishes the default mode as the primary one. The pull request shows before and after on the fixed
  sample of ruling (16) (`lvm.das`'s `luaV_execute` slice, `ldo.das`, a module header with its
  `require` lines) and adds the structural-noise counters to `metrics/readability.das` (late-bound
  wrappers and slots, `mod::name` and `__::name` calls, `require` lines per module). The language
  limit becomes a probe (two modules needing a mutual `require`, the minimal repro), a
  `probe-findings.md` row and an issue in `lookibed/daScript` asking whether daslang has or plans a
  way for two modules to call each other (a forward declaration of a function from a module below,
  a mutual `require` inside one package, or the like; fact and repro only, no implementation
  proposal; nothing filed in `GaijinEntertainment/daScript`). Report: compile, start-up, interp and JIT of the new
  default against `source-cut`, one line per mode.
  Done (branch `p7.0a-layout`, PR #47): `--layout`/sidecar `layout`: `source` (default, every
  cycle one module of `.das.inc` fragments, the former `scc`), `source-cut` (late binding through
  `<entry>_link.das`, the former default), `single`; `scc` refused. Lua `lua` default: 28 modules
  + 20 fragments, 0 slots, 0 qualified calls, 168 `require` lines (source-cut: 42 slots, 169
  qualified calls, 359); criteria `lua/lua` late_binding 79.2 -> 100, qualified_calls 93.8 -> 100.
  Interp benches 7% faster, compile 6.9 vs 4.1 s, start-up 5.3 vs 1.0 s (accepted, ruling (22)).
  Probe `test_mutual_require`, issue lookibed/daScript#32. Before/after and per-mode numbers in
  the PR; probe row F76. The next ports publish runs `--perf` (the old captures measured the
  former default).
- **P7.0b Interpreter audit on Lua** (owner ruling 2026-11-01 (14); after P7.0a, before P6). P7.0
  took `fib_loop` to 31x against 32x for hand-written das, while Lua runs 193x to 436x native under
  the interpreter (the P5.4 capture), so other constructs cost. One construct at a time, by P7.0's
  method, on `fib`, `binary_trees`, `nbody` and `spectral_norm`: find what costs. Candidates to
  check, not to assume: `TValue` and union access through `reinterpret`, pointer arithmetic, `setjmp`
  as try/recover, `[c_function]`, wrap casts on `uint`, calls through slots (gone in the default mode
  after P7.0a). The Rust c2das (P8.1) beside, on the same function. Output: a table construct ->
  interpreter effect and ledger rows for the fixes; the fixes are separate items, not this one. Lua
  tests under the memory cap.
  Done (branch `p7.0b-audit`, PR #48): Landed: `perf/audit_lua.das` over 12 kernels under
  `perf/kernels/audit/`, 14 constructs each timed as converted and as the spelling a fix would
  emit, the Rust translation beside, sites counted in lvm/ltable/lgc/ldo, the four benches whole
  with a startup row (`perf/audit_linux.json`, `perf/ARCHITECTURE_AUDIT.md`). Costly under the
  interpreter: the `_flag` switch chain 2.08x (Rust's computed `goto` 17x faster on the kernel),
  wrap casts 2.10x, the `__builtin_expect` round trip 1.58x, `addr((p + i).f)` 1.53x; the JIT
  within 16% (small call 1.16x) but `try` 5.43x, the `c_volatile_load` JIT cell SUSPECT and left
  out; slots 0.95-1.00x of scc net. No IR change needed; fixes are rows P7.0c-P7.0h. Report: the
  item's PR.
  Found by the bench audit (`perf/audit_lua.das`): (1) `--filter X` rewrites `perf/audit_linux.json`
  with X alone (a one-kernel capture replaced the 12-kernel file, so the bench audit is not
  committed); (2) `--benches-only` still runs a `lua/work/scc/` lane, "missing prerequisite" since
  P5.1b2 renamed the layout; (3) the Rust side fails `protected_call` on the bench (P8.1). Row:
  merge per-filter runs into the file or forbid `--filter` with a write, rename the lane, then the
  owed bench audit entries (P7.0f, P7.0h) again.
- **P7.0b2 The Lua gap between kernels and the program** (owner ruling 29, item 3): Lua runs
  112-290x of C under the interpreter while the kernels run 7-30x, and the P7.0b constructs (1.5-2x
  each) do not explain a 10x gap; profile the live program one construct at a time as P7.0b did,
  the Rust translation beside, and open rows for what costs. The main argument against the project
  today; runs after the P8.4 refusals, before the compare re-capture.
  Done as an investigation (report `/root/notes/research/p7.0b2-lua-gap.md`; no code): the gap is
  the opcode dispatch: the converted `luaV_execute` tests every opcode in turn, up to 83 tests per
  instruction, 64% of fib's interpreter time (10.1 ns a test, 249 tests per Lua call, 2.5 of 3.94
  us); the kernels have no such loop, which is why they sit at 7-30x and Lua at 105-266x;
  `[c_union]` accessor calls about 5%; das call overhead and `c_label_end` nothing measurable; 31%
  unexplained (about 220 ns per VM instruction). Computed-goto dispatch (P7.0c2) under the JIT on a
  quiet box: 1.82x fib, 1.43x binary_trees, 1.31x nbody, 1.54x spectral_norm (spreads at or under
  3%); under the interpreter it is blocked by a daslang bug (a computed `goto` to a label inside a
  `while` body followed by an `if` without `else` lands wrong, a larger body segfaults;
  lookibed/daScript#35). Rows: P7.0c2 first, P7.0c3, P7.0c4 and P7.0b3 below; a daScript issue
  for the inliner splicing `[c_union]` accessors (the 5%). The report's section on the ports
  tables (JIT work 1.3-2.6x native inside the process) is not reproduced by the in-process publish
  (4.0-9.5x, PR #106; other bench sizes or the variant modules): re-check it before it is cited.
  Doom's JIT gap (P6.7 (c)) not reached. Also a row: `lua/run.das` without `scripts/env.sh` dies
  with a raw array-index exception at `converter/emit.das:3057` instead of an error message.
- **P7.0b3 The Lua residue after the dispatch rows** (from P7.0b2): profile what remains after
  P7.0c2/P7.0c3 (the 31% unexplained, about 220 ns per VM instruction, and the `[c_union]`
  accessor calls) and Doom's JIT gap (P6.7 (c)) beside it, the Rust translation beside both.
- **P7.0c Switch dispatch without the flag chain** (ruling (23): the plain-case form default, computed `goto` opt-in). A case no `goto` and no fall-through enters
  tests `_goto == 0 && _cond == K` alone (2.08x interp on `dispatch_switch`, 83 flag cases in lvm,
  an upper bound of the plain ones, every VM instruction). Then, opt-in under the speed-vs-
  idiomatic rule, a dense switch as computed `goto <expr>` (the Rust translation's form: 23.9x
  native against our 419x on the same kernel). Both modes tested and measured.
  Done (branch `p7.0c-switch`, PR #56): a case of the matched-flag loop that only its own labels
  enter tests them directly (`if (_goto == 0 && _cond == K)`), the flag kept for fall-through and
  `goto` targets; `dispatch_switch` interp 419x -> 195x native (the former chain 2.33x slower, JIT
  1.06x); flag cases in lvm 83 -> 6 (plain-case sites 77). The computed `goto` opt-in is P7.0c2.
- **P7.0c2 Computed `goto` dispatch for a dense switch** (opt-in, ruling (23); split from P7.0c):
  `goto <expr>` over a jump table, the Rust translation's form (27.0x native on `dispatch_switch`
  against our 195x), behind a converter option (CLI flag and sidecar field, default off), both
  modes tested and measured. First after P7.0b2 (its finding: the dispatch is 64% of the
  interpreter time; 1.31-1.82x under the JIT on the four benches); under the interpreter it needs
  the daslang fix for lookibed/daScript#35 or a probe-guarded shape. OWNER DECISION: its place in
  the order now that ruling 29's four items are done.
- **P7.0c3 One `_goto` test per dispatch** (default; from P7.0b2): the matched-flag loop tests
  `_goto == 0` once per dispatch instead of once per case (about 1.28x fib, 1.13x binary_trees);
  for every build, the opt-in P7.0c2 above it.
  Done (branch `p7.0c3-one-goto-test`): a goto into another case stores a value no case holds into
  the condition (`var _condN`; one below the smallest case value, else one above the largest, an
  enum's through `enum_from_int`) before the re-dispatch, so every case test reads `_cond == K` alone
  and only `default` keeps `_goto == 0 &&`; cases spanning the condition's type keep the old form.
  The goto's own plain case cannot match on the restart (the `noconj` loop; a run test hangs without
  the store). The divergence from `docs/lowering-examples.md` (its Tier 2 tests carry no goto
  variable) is as P7.0c's. One sample each, box PC, in-process work, main vs branch (marked: one
  sample, two runs of `/root/notes/parallel/pc-p7.0c3-ab.sh` while another coder's jobs shared the
  box; the 3-sample run is owed): interpreter fib 30 1.19-1.30x, binary_trees 12 1.14-1.16x, nbody
  20000 1.11-1.15x, spectral_norm 100 1.18-1.22x; JIT fib 1.89-3.71x, binary_trees 1.27-1.81x, nbody
  2.70-2.81x, spectral_norm 3.05-3.30x (the JIT outputs equal main's on nbody and spectral_norm).
  `dispatch_switch` under the interpreter 197.9x -> 115.4x native (converted over the restored
  chain 0.45x -> 0.28x);
  perf's `flag-chain` rewrite now finds the new plain case. `lua/tests`' suite-check test failed once
  on this box with `sort.lua pass 4.9` where its spinning fixture wants a timeout past 5 s, a timing
  margin unrelated to the switch.
- **P7.0c4 A binary split of the case chain** (candidate; from P7.0b2): a dense switch's case found
  by a binary split of the chain (7 tests for 83 cases) for builds without the P7.0c2 opt-in;
  measured against P7.0c3 before it is scheduled.
- **P7.0d Wrap casts on 64-bit mixed operands** (ruling (23): default, with the signed-wrap probe). `int64(uint64(a) op uint64(b))` as `a op
  int64(b)`, extending P7.0's `int` fold to lvm's `intop` (OP_ADDI, OP_MUL, bitwise ops): 2.10x
  interp, sites 14/1/5/0. The kernel never overflows (values < 2^28): the fix depends on daslang's
  defined signed wrap, a probe to land with it.
  Done (branch `p7.0d-wrap`, PR #65): `int64(uint64(a) op uint64(b))` with `op` in `+ - * & | ^`
  and an operand of `T`'s width or narrower folds to `a op T(b)` (lua's `intop`: `acc +=
  int64(imm)`); division, modulo, shifts and comparisons never. The signed-wrap probe
  (`probes/test_scalars.das`, row F77) fixes `*` wrap for `int` and `int64` on the interpreter and
  the JIT (AOT unprobed). `wrap_cast` interp 31.2x native, the former casts 2.29x slower, JIT 0.99x
  (dev-box numbers; the bench re-record is owed, `bench-queue.md`). Leftovers: the `wrap-casts`
  site counts in `perf/audit_linux.json` (lvm 14, ltable 1, lgc 5, ...) were carried over from the
  `plain-op` key and may describe the output before the fold, recount at the next perf re-record;
  paths no test fails without: a narrower operand inside a 32-bit `T`, the `_Bool` operand path,
  `*=` `&=` `|=` through the wrap pair (only `+=` and `^=` are asserted).
- **P7.0e `__builtin_expect` truth tests** (ruling (23): default). `int64(x != 0 ? 1 : 0) != 0` as `x != 0`
  (`l_likely`/`l_unlikely`): 1.58x interp, sites 61/8/2/37.
  Done (branch `p7.0e-expect`, PR #62): a truth test looks past `__builtin_expect`, a widening
  integer cast and `!= 0` on a comparison, so `l_unlikely(trap)` is `trap != 0` and `l_likely(a <
  b)` is `a < b`; `trap_check` interp: the former round trip 1.75x slower (JIT 0.95x). Review
  leftover (no test): the hoisted-operand early stop in `truth_of` wants a fixture line like
  `if (__builtin_expect(f() != 0, 1))`.
- **P7.0f Address of a first member** (ruling (23): the `reinterpret` form opt-in; `addr(...)` stays the default). `addr((p + i).val)` and `addr(reinterpret<GCUnion?>(o).h)`
  where the member sits at offset 0: 1.53x and 1.17x interp, sites 106/2/0/11 and 81/10/62/10. The
  fast form is a `reinterpret`, which the readability criteria count as noise: NEEDS RULING
  (default or opt-in).
  Done (branch `p7.0f-first-member-v2`, PR #70; opt-in per ruling (23), the default output
  unchanged): `--first-member addr|reinterpret` and the sidecar's `first_member`; under
  `reinterpret` the emitter spells `&p->f`, a nested first member, `(*p).f`, `p[i].f` and an array
  member's decay as `reinterpret<F?>(pointer)` when clang's offsets put the member at 0, anything
  else keeps `addr(...)`; the `p7_first_member` fixture runs in both modes (a pointer, a function
  pointer, a union, a `char` first member, a stepped subscript, an anonymous union kept). The
  `interp-reinterpret` perf lane, the `first_member` kernel and the `@reinterpret` readability keys
  (converter/REVIEW.md); the lane's cells are in the bench capture at 504ca55 (PR #73), the
  `perf/audit_linux.json` entries (`union_access`, `stack_ptr`) are owed to the bench
  (`bench-queue.md`; the bench audit ran but is not committed, P7.0b's `--filter` finding).
- **P7.0g Cheaper volatile load** (ruling (23): default, F65's semantics kept). `c_volatile_load` (a C++ forwarder) costs 1.32x interp on the
  `trap` re-read, sites 50/0/0/7 (`updatetrap` per protected instruction); keep F65's semantics,
  find an interpreter-cheap form.
  Done (branch `p7.0g-volatile`, PR #64): `c_volatile_load` is a call macro expanding a number's
  read to its crt forwarder over the object's address in place; `bool`, pointers, function values
  and a by-value parameter go through `c_volatile::c_volatile_read` (module-qualified, so a
  program's own function of that name cannot take it; both names reserved); F65 kept; `trap_check`
  interp 28.7x -> 21.2x native (dev box; 1.31x over a plain load). Open for the owner: `require
  crt public` in `c_volatile` (rulings-pending).
- **P7.0h Flat setjmp and inline enum cast** (ruling (23): default if the output reads simpler; low priority). The `while (_sj_run)` trampoline as a
  flat `try` when the setjmp value is only tested against 0 (1.13x; `try` itself 1.25x interp,
  5.43x JIT; 1 site, per pcall); `enum_from_int` inline (1.12x, 5 sites, per instruction).
  Done (branch `p7.0h-flat-setjmp`, PR #72; default, it reads simpler): `if (setjmp(b) == 0) { A }`
  and `if (!setjmp(b))` with no `else` and no call in the tail lower to the contained `try`/`recover`
  of `lowering-examples.md`, the tail after it (a `longjmp` back from a tail that calls is valid C,
  so such a tail and every other shape keep the trampoline, and a `break`/`continue` leaving the
  loop is refused as the trampoline refuses it; negative-control fixture `again`); Lua's
  `luaD_rawrunprotected` 20 -> 9 lines. `enum_from_int` is
  a call macro expanding in place to its safe `reinterpret`, the text unchanged; a program's own
  call without a type witness is left to overload resolution. Dev-box ratios: the trampoline
  1.14x interp, `try` itself 1.20x interp / 4.91x JIT, the enum macro 0.99x. Leftovers: `r =
  setjmp(b); if (r == 0)` keeps the trampoline, as does a tail calling a function that never
  longjmps; the `perf/audit_linux.json` flat-try entry is stale until the bench re-records
  (`bench-queue.md`; the bench audit ran but is not committed, P7.0b's `--filter` finding); the
  fixture `p5_lua_protect` printed `out` in the printf of the call setting
  it (argument-order dependent), fixed to read it in its own statement.
- **P7.0i Character literals as `'c'`** (ruling (23), the critic's finding 3): a C character
  literal reaches the das text as `'c'` where the C had one (the C-IR carries the literal's kind;
  `probes`/P2.5's ledger line), readable-only, default; one small pull request.
  Done (branch `p7.0i-chars`, PR #57): Dumper A marks a character literal's `int_lit` and a
  character `case` label `"char": true` (an optional C-IR field; rulings-pending); the emitter
  spells a marked `int` as das `'c'` where das has the spelling (printable ASCII, `\n \t \r \b
  \f \\ \'`); char_literals 0 -> 89.6 (lua/lua 88.6). `'\0'`, `'\a'`, `'\v'`, octal and hex
  escapes stay numbers: a daslang lexer gap, lookibed/daScript#34.
- **P7.0j C comments carried over by source line** (ruling (23), finding 1): the C source's
  comments land as `//` lines above the statement of the same source line in the das output;
  readable-only, default; one small pull request after P7.0i.
  Done (branch `p7.0j-comments`, PR #58): the emitter reads the C source's comments by line and
  writes each as `//` above the statement of its line (an own-line comment above the next
  statement, a block comment line by line, a function's comment block above its `def`); comments
  0 -> 83.6 on lua/lua@single. Not carried: comments of globals, types, directives and a body's
  tail (a follow-up row if wanted).
- **P7.0k `#define` constant names kept** (ruling (23), finding 2): a numeric literal that a
  `#define` of the translation unit names is emitted as a `let` constant of that name (the macro's
  expansion location names it); readable-only, default; one small pull request after P7.0j.
  Done (branch `p7.0k-defines`, PR #60): a `#define` of a constant expression is a module-level
  `let` named after the macro and a use spells the name (Dumper A marks the macro-expanded
  literal, the emitter folds it back); an unparenthesized body is named only when it is one
  operand; a macro named like a das builtin's global keeps its value; constant_names 0 -> 59.8 on
  lua/lua@single. Pending: `builtin_global` sees only the modules the converter loads
  (rulings-pending). Candidates for a P7.0k2 row, the owner's call: `case` labels and global
  initializers as names.
- **P7.0l SCC edge kinds on Lua and PureDOOM** (owner ruling (26); analysis only, no change to the
  default layout; after the ledger docs pull request, before P7.0f/h). For each cycle cluster of
  `lua`, `luac` and PureDOOM, split the edges by kind (function call, global, function address,
  type) and recompute the clusters as if (a) only functions were forward-declared, (b) functions
  and globals; report cluster count and sizes per case beside today's. Input: the cut edge list
  `program.layout.txt` records. Output: a table in the pull request and `probe-findings.md`; it
  feeds the mutual-require question (F76, lookibed/daScript#32).
  Done (branch `p7.0l-scc-edges`, PR #69): `--edge-census` writes `program.edges.txt`
  beside `program.layout.txt` (the default output unchanged). Lua 5.4.8, `lua` and `luac` alike:
  the one `.c` cycle (15 units: lcode ldebug ldo lfunc lgc llex lmem lobject lparser lstate
  lstring ltable ltm lundump lvm) is 99 edges, all function calls (249 symbols), 0 address, 0
  global, 0 type, so forward-declaring functions alone dissolves it; what remains are two header
  cycles (llex_h+lparser_h: 2 type edges; lobject_h+lstate_h+lua_h: 4 type edges, 12 types) that
  no forward declaration of functions or objects touches. Found on the way: `doom/run.das`
  did not compile on `main` (the harness fix row under P6.3), and, by its review, the defect below.
  The Doom half Done with P6.3f (PR #79): the 51-unit `source` cluster is 438 edges, 326 call
  (698 symbols), 14 address (93), 218 global (600), 0 type, plus a 3-header type cycle
  (d_player_h, p_mobj_h, r_defs_h: 4 type edges). (a) leaves 36 units, the set `source-cut`
  leaves, held by shared objects (`players`, `consoleplayer`, `sectors`, DOOM.c's `doom_print` and
  `error_buf`: 29 units) and by address-taken functions (info.c's `states` -> the `A_*` of
  p_enemy/p_pspr, p_saveg -> the `T_*` thinkers: 7 units); (b) leaves only the header cycle. Unlike
  Lua's cluster, Doom's needs globals forward-declared too, so forward-declaring functions alone
  does not untie it.
- **P7.0l2 Layout: the cut late-binds an edge that carries a record type** (defect on `main`,
  reproduced by the P7.0l review; a small fix PR right after P7.0l). `find_edges` adds a unit-owned
  record's field types as edges but never to `plan.type_edges` (filled only from the unit's own
  uses; `spelled_types` does not walk fields), so `uncuttable` and `refused_forced` treat the edge as
  cuttable: x.c `struct S; struct T { struct S *p; int k; }; static struct T t;` calling `y_f`, y.c
  defining `struct S` and calling `x_g`, main.c calling `x_g`; `--layout source-cut` cuts `y_f` and
  x.das fails with "don't know what 'S' is". Fix: field-type reasons join `type_edges`; test: the
  repro. P7.0l test gaps to close with it: a unit that both calls and addresses a function, a
  header node inside a fixture cycle, the "today" clusters asserted against `program.layout.txt`.
  Done (branch `p7.0l2-type-edges`, PR #71): a record field's type reason joins `type_edges` in
  `find_edges`, so `uncuttable` and a forced cut refuse it; fixture `p7_type_edge` (the repro) and
  the three census test gaps closed.
- **P7.1 O1 range-loop rewrite** (unlocks automatic bound-check elision; the canonical form
  landed in P7.0 as the default, owner ruling 2026-11-01 (13)); **O2
  `[unsafe_deref]`** and **O3 `[hint(unsafe_range_check)]`** — these two sidecar-gated, enabled only
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
  Done (branch `p7.7-goto-into-body-v2`, PR #81): every if, loop or switch between a goto and its
  label is written out at its parent's level as das labels and gotos (very-detailed-plan section
  3 step 4; the Duff computed goto is an if/elif goto chain, no state variable); C `break` and
  `continue` of an opened construct become gotos; a braced block or loop the goto leaves that
  holds an opened construct is opened too (`open_left_blocks`; else a label left in a loop body
  jumps to slot -1, F60, daScript#19, or a braced if arm throws, F63). A second pass works around
  daScript#8 (`else { c_label_end() }` after an early-return if followed by a targeted label, a
  latent plain-goto bug too) as a C-IR shape check (an all-return switch with a default counts
  as closing); the guard goes when upstream fixes #8. The 31 csmith seeds and pr38051, pr43269
  pass and join the ratchets, judged with `--one` on gcc 11.4 (re-confirm on the pinned gcc at
  the phase end); readability re-recorded (1645 inputs); the cascade's cost (how many constructs
  a goto opens) is unreported, Lua's goto and label counts unchanged. The Duff spec lives in
  `converter/ARCHITECTURE_EMITTER_CONTROL.md#goto-into-body`, since `docs/` is authored elsewhere
  (rulings-pending). Doom then stopped at `f_finale.c:602`, P6.3e's decay case.
- **P7.7b The shapes P7.7 refuses**: a goto into a setjmp if's arm; an open switch re-dispatched
  from another case; a case label in a non-block switch body.
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
- **P7.10 Hygiene the P5.1 audit deferred** (owner ruling 9 step b, 2026-10-29; reports under
  `/root/notes/audit_p5.1/`). Folds the dupe audit found and the fix round left: the C-IR tree walks
  `layout.das` `expr_uses`/`stmt_uses` and `link.das` `remap_expr`/`remap_stmt`/`rename_expr` rewrite
  `emit.das`'s private `each_stmt`/`each_expr`/`each_subexpr(_mut)` (make the walkers public in
  `cir.das`, with a skip predicate for a direct call's callee); `emit.das` `relative_to`/`in_dir` and
  `layout.das` `relative_dir` against `fio::relative` (state the text-only reason or fold); the
  free-name search spelled three ways (`cir.das` `free_name`, `link.das` `fresh_name`, the
  `hoist_static` loop in `dumper_a.das`: one `free_name(taken, want, blocked)`); the per-layout output
  path spelled in `ports/publish.das` `module_of`/`single_of`/`scc_of`, `lua/run.das` `layout_dir`
  and the lane-suffix tests (one `layout_module_of` plus one lane-to-layout parse);
  `holds_constant_p`/`holds_comma` as one `holds_node`; the reachability walks `reached`,
  `live_nodes` and `join_entry`'s loop as one `reach(start, successors)`; the key-suffix strip in
  `metrics/readability.das` and `suite_files.das` `kernel_of_key`; the test helpers `written`,
  `converted_with`/`converted_in` and `test_cli.das` `run_layout`; the copied blocks: the `[init]`
  and late-signature lines in `emit.das` (5362-5371 vs 5664-5670, 5613-5626 vs 5654-5660), the
  `"{a}>{b}"` edge keys parsed in five places of `layout.das` (key by `int2`), the dedupe-and-sort
  of requires written three times, the three per-layout README loops in `publish.das`, the `[I]`
  line strip in `test_layout.das` (third copy of `program_output`). The cheap folds the hygiene PR left for
  size: `lua/profile.das` `holder` as `algorithm::upper_bound(...) - 1` (no test reaches it short of the full profile run);
  `pipeline.das` `read_program_input` over `sidecar.das` `read_json_file`; `lua/run.das`
  `write_manifest` over `cir.das` `write_program`; `occurs` shared by `test_layout.das` and
  `test_link.das`; the torture verdict in a module both `test_suite_audit.das` and
  `suites/gcc_torture/run.das` require; the constants and messages spelled twice (`lua/run.das`
  `layouts_of` vs `sidecar.das` `LAYOUTS`, `publish.das` `ALL_LANES` vs `DAS_LANES` with
  `LAYOUT_LANES`, the `program.modules.txt`/`program.layout.txt` literals vs `LAYOUT_REPORT`/
  `MODULE_LIST`, the module-list reader in `clear_owned` and `publish.das`, `main.das`'s third copy
  of the `--layout` `option_error`); `tiers.das` `bare_ident_of` beside `cir.das` `ident_of` (the
  AOT and exe output names keep a leading digit bare); `compare/projects.das` `exe_binary` beside
  `perf_lanes.das`'s private `built_binary` (fold: a `module_dirs` parameter on `built_binary`). Style items the audit rated
  suggestion or nitpick (`/root/notes/audit_p5.1/reports/style_*.md`): the `-1` sentinels and the
  `16` exact-order limit named, `NO_CUT` written as `(1l << 62l) - 1l`, `LayoutNode.kind` an enum,
  the forced edges in their own table, one `why_*` prefix for the refusal functions, the
  `PROGRAMS` tuple's named fields, `holder`/`counts`/`to`/`from` in `lua/profile.das`, the
  `output`/`mismatch` and `phase`/`ledger row` word pairs, the error message of `lua/run.das:164`
  naming its cause, the hand counts in `probes/test_toolchain.das`. Also: the daScript upstream
  report of the csmith worker kill missing children in their own process groups; whether the
  architecture companions number their sections (`ARCHITECTURE_COMMON.md` says sections are
  numbered); the vendored `skills/comment_style_hygiene.md` contradiction on a multi-line `//!`
  above a public `def` or global (fix upstream, re-sync). Metrics history: the commit messages of
  ce977d2, 97410f4 and 1e436ab lack the totals table and the added keys the checklist asks for
  (history is not rewritten).
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
