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

**Owner rulings 2026-11-01 to 2026-11-05, (12) to (31)** (after Boris Batkin's framing of 2026-08-22: generate the
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
31. The JIT profile (2026-11-05): P7.0c3 runs first (the coder); beside it, after Boris Batkin's
    words on the Lua numbers ("надо будет попрофайлить - чтобы понять где говно. может оказаться в
    паре мест - про алиасинг ... или ... выключи векторизацию"), P7.0b3's Doom half narrows to the
    JIT and his two hypotheses, by his method: a sampling profile (self time per function, native
    against JIT, one demo, the speed build), the hot loops' IR or asm against clang's, each cause
    confirmed by a hand edit of a temporary copy of the output with the whole demo re-timed, a
    minimal repro for every cause that sits in daslang, rows for the fixes (none in the item: the
    output forms do not change; profiling tools and the host flag of P6.7 (b) may land, with tests).
    Dispatch: lead Fable owns the item, the ledger row and the report's summary; one Opus researcher
    samples and reads the IR; the coder finishes P7.0c3, then takes the host flag and the hand-edit
    re-timings; Fable subagents write the probe-findings lines, the fork issues, the ledger and the
    report drafts. Full text: `/root/notes/owner/2026-11-05_jit-profile-aliasing.md`. Done as P7.0b4.

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
  Fix (branch `fix/lua-lane-time-warning`): the time warning goes with its newline, the dots
  around it joined, and a line of dots alone compares as one dot (all.lua's false `fail`).
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
  README (now [docs/rust-comparison.md](rust-comparison.md#head-to-head-with-the-rust-translator)), and into the ports README. Suites
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
  low priority. The override Done (branch `fix/compare-crash-rows`): `cpu_name` answers
  `$C2DAS_CPU_NAME` when set, and the filtered `--perf` run's test, on a CPU no box names, merges
  only because `--box fx` reached its stamps; `--suites` and `--suite` still lack a `--box` test
  (each needs a suite run that writes a capture).
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
  Rows (1)-(4) Done (branch `fix/compare-crash-rows`): (3) every sample runs `guarded`, `sh` around
  `prlimit --core=1` (a limit of 0 still feeds WSL's pipe handler), a signal death read as `signal N (<name>)` with the first reported line
  (`perf/ARCHITECTURE_SAMPLES.md`; daslib's `run_and_capture` reports signal N as exit code N, so
  the capture's "exited 5: " was SIGTRAP with the report's empty first line), `prlimit` checked
  by the `env` gate; (4) the AOT host runs `main` inside `runWithCatch` and exits 1 with
  `EXCEPTION: <text>` on stderr; (1) `--project --as <GiB>` (6 by default) caps every measured run
  through the same guard, the runner and the builds uncapped, a crash under the cap the lane's
  `exit` verdict with its signal; (2) `--perf --filter a,b` re-measures the named kernels into the
  capture (`merge_perf_rerun`, `reruns` recorded), refusing another box, Rust commit or sample
  count; the perf section moved into `compare/ARCHITECTURE_PERF.md`. Row (5) stays open: watch the
  next capture.
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
  [Real projects](rust-comparison.md#real-projects). Ours is refused on 6 of 6 (five at an include folder
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
- **P8.5 Strict aliasing under the JIT and exe** (ruling 37 phase 1, checklist item A; correctness
  before any timing). daScript `abf1d40e35` tags every typed load and store with `!tbaa` by class
  (`float`, `double`, one class for the wider integers and pointers) and leaves a function untagged
  when its body holds a punning `reinterpret` (F95). Inventory: `converter/ARCHITECTURE_TIERS.md`
  section 9. Decision per shape: unions (`[c_union]` accessors are punning reinterprets returning a
  reference), typed pointer casts, the `first_member` reinterpret, byte views, `memcpy` and the CRT,
  and integer-width or pointer views are right with the tags on (`p8_alias_safe.c`, JIT and exe
  as natively with the model on); a cast from `void *` (the model's hole, lookibed/daScript#44) and
  views loaded from a record (the escape daslang documents) are wrong with it on (`p8_alias_unsafe.c`
  prints `2 2` for `1 3` under JIT and exe). The model's switch is the root program's
  `options strict_aliasing` alone (a required module's line is ignored), so the converter writes
  `options strict_aliasing = false` into the module holding `main` by default, the status quo of
  every recorded JIT and exe number; the sidecar key `strict_aliasing: true` keeps the model for a
  program whose C is clean under `-fstrict-aliasing` (one line less, the tagged loops vectorize).
  Which kernels and projects take the key is a timing question for the phase-1 re-capture, measured
  both ways; per-function `[hint(no_strict_aliasing)]` is not emitted (one line per function, and the
  root option covers every module). Unblocks when lookibed/daScript#44 lands: re-probe F95, then
  the `void *` shape moves to the safe group and the default can be revisited.
- **P8.7 setjmp arms that return** (ruling 37 phase 1, the triage's correctness item; P8.5 is item A,
  P8.6 left for item B). daScript `21316206e9` (#4472) answers F75 by refusing a `return` inside
  a `try` or `recover` arm on every tier (error 30299, F96), and the setjmp lowering kept the C code
  after the site, its returns included, inside the `try`: every converted site whose tail or branch
  returns stopped compiling, `if (setjmp(b)) return -1;` first. Design: an arm holding a `return` is
  a block the arm invokes, `_sj_returned = invoke($() : bool { ... })`, a C `return v` in it
  `_sj_ret = v; return true`; the outermost such site declares `_sj_ret` (none in a void function)
  and `_sj_returned` before its `try`, the sites in its arms share them, and after the pair
  `if (_sj_returned)` returns `_sj_ret`, or `true` from the enclosing arm's block. A block returns
  from inside its loops, so no break-and-flag ladder is needed; a `goto` across the block's edge
  fails closed, and so does any arm, returning or not, whose `break` or `continue` leaves the site's
  loop: under the JIT and the exe such a `break` fails the cold compile and then leaves only the
  `try` (F97, lookibed/daScript#45; main converted it when the arm did not return). An arm without a return keeps its `try` as before (Lua's
  `luaD_rawrunprotected` is the flat site and does not change). Fixture
  `converter/tests/fixtures/p8_setjmp_return.c` (the idiom, a return in the longjmp arm and after it,
  a loop's return in the tail, the contained site with both arms returning, nested sites, a void
  function, a record result, the general form's `return setjmp(b)`, the flat site's returning
  branch) matches the native build under interp, JIT and exe. Unblocks the setjmp JIT lane parked on
  F75 (P5.2): the lowering puts no `return` in an arm, so the JIT runs what the interpreter runs.
- **P8.8 Exit codes of a death by signal** (ruling 37 phase 1, repin PR2). daScript `f386f92a35`
  (lookibed/daScript#37) makes `run_and_capture` report a child killed by signal N as exit code
  128 + N, as a shell does, where it reported N. The Lua suite check read a cgroup cap's kill as
  `SIGKILL` (9), so a native run killed at the memory cap read as a native failure (`oracle`, "native
  exited 137") instead of `memory`: `lua/run.das` now takes 137. The probes that pinned 11 for a
  SIGSEGV (`probes/test_unchecked.das`, F84) pin 139; `perf/perf_lanes.das` already read 128 + N
  through its `sh` wrapper. No other harness compares a run's code with a bare signal number.
- **P8.9 Workarounds of fixed daslang findings** (ruling 37 phase 1, repin PR3). Under daScript
  `abf1d40e35` the probes of F1, F37 (its cache half), F52 (lookibed/daScript#17), F61, F64, F67,
  F70, F71, F72 and F73 are re-pinned to the fixed behaviour, each row updated. Removed in the same
  PR: F67's local before the reinterpret in `c_volatile_read`. Removable, each its own change with
  its tests (readability phase first where the generated text changes): (a) F72, the cluster
  module's `// the fragments' digest:` line (`converter/ARCHITECTURE_LAYOUT.md`, its layout tests);
  (b) F61, the emitter's `uint8?` for a `void *` among a variadic call's arguments; (c) F52, the
  bitfield and compound-store spelling `x = x op v` through a pointer step, where `x op= v` now
  runs; (d) F73, `p5_layout_tree/main.c`'s depths through `argc`; (e) F70, `[sideeffects]` on
  `c_prefetch` and the no-op shims (harmless, keep unless a reader asks); (f) F71,
  `suites/gcc_torture/filter_rules.das`'s optional-suffix spellings; (g) F64, the ports capture's
  flat cells (no change needed). Stays: F1's `exit_now` in `c_exit` (`exit(N)` exits N now but
  still prints its call stack on stdout); F37's `f`va(…)` spelling (a call above the
  definition still binds before the macro exists).
- **P8.10 Goto workarounds of fixed daslang findings** (ruling 37 phase 1, repin PR4a). Under
  daScript `abf1d40e35` the seven goto probes of F60, F62 and F63 (lookibed/daScript#8, #19, #21,
  #22 and #35; upstream `41ee7d60b4`, the label-aware `if` fold, and `6394f6046a`, a block
  resolving only its own labels) are re-pinned to the fixed behaviour, the rows updated. PR4b
  probed the converter's own output shapes under the interpreter and the JIT (every goto fixture,
  the three refused shapes, Lua against its oracle) and removed: (a) `guard_label_folds`' `else {
  c_label_end() }` after a closing `if` before a label (#8, #35, `FOLD_MARK`); (b) the
  `c_label_end()` after a label outside a loop body, its module definition and the reserved-name
  refusal (F62); (c) the re-dispatch and jump-table labels numbered below every C label: they
  number after them (F60, #19); (d) `check_labelled_groups`' refusal of a labelled case group that
  a goto leaves (F63): the three shapes it refused are native-compared fixtures now.
- **P8.11 Blocks the goto-into-body lowering opens for F63 and #8** (after P8.10). `open_path`
  spells an `if` arm flat when it holds a label of its own (F63) or ends in a leaving statement
  (#8), and `open_left_blocks` opens every braced block an open construct's goto leaves (F60, F63),
  all for daslang behaviours `abf1d40e35` fixed. Each can keep its braces now, which gives the
  structured text back; the change touches `converter/tests/fixtures/p7_goto_into.c`'s expected
  texts and needs each shape run under the interpreter and the JIT against native. Not done in
  P8.10: the removal reshapes the goto-into-body output, which the readability forms price.

- **P8.12 The repin re-capture** (ruling 38 addendum 5, steps 4-7; after P8.5-P8.11 and repin PR5). Every
  timing number of the tables re-measured on daScript `abf1d40e35` (0.6.5) under `heavy --exclusive` on box PC,
  against the last pre-repin exclusive captures on 0.6.4 (perf `abbd5ad`, compare `4e63dc0`, Doom `5f84ae9`, the
  Lua ports 2026-11-07 at `9748560`). Step 4 (no timing, main `90abb14`): Lua suite 30/30 interp, error checks 8/8
  interp and JIT, luac 33/33 interp, JIT and exe, Doom demo1-3 in sync under interp, JIT and exe; compare binjgb,
  h264bsd-mp4 and plmpeg-stream pass every lane on both sides (ours binjgb AOT builds now); the Rust side's
  quakegeneric stops at error 30299 (a `return` inside a try arm, upstream #4472) on every lane. Predictions written
  before any timing run: `/root/notes/predictions/2026-11-09-repin.md`, sha256 `37cfee5fd02e405a3e6d2b75ddeb7b4a22ff1ed03dbaf4d46e87987ef0b2e853`: interp x0.97 everywhere;
  default JIT/exe flat but blit and Lua's call-heavy workloads (#38 `ptr_diff` inline); AOT sieve, str_copy and
  matmul down to the JIT's level (#5); the #43 solid/no-solid JIT A/B at 1.03 (close #43 when it holds); the
  `strict_aliasing: true` lane (A/S) at 0.85 on matmul, 0.95-1.00 elsewhere, Doom 0.98-1.00. Workarounds judged by
  the capture, none removed here: `options solid_context` (F80, the #43 lane), the root `strict_aliasing = false`
  (F95, the A lane); #38, #39 and #5 had no converter workaround.
  Measured (branch `perf/recapture-abf1d40e35`: perf 437bf3a, compare cceb401, Doom 0c5b5f4 (5 samples; the
  3-sample 98480bf had one disturbed sample in two cells), criteria 3259e3b; every group `heavy --exclusive`, machine
  quiet 1-2%): compare geomeans ours interp 31.30 -> 30.99, JIT 1.20 -> 1.03, exe 1.21 -> 1.12, AOT 1.18 -> 1.19 (16
  kernels now, switch_local builds); Rust interp 34.62 -> 35.39, JIT 1.32 -> 1.23, exe 1.41 -> 1.29. The JIT gain
  is blit (1.25 -> 0.17 ours, 1.48 -> 0.48 Rust: the pin's, both sides), va_forward and first_member. Doom interp
  58.6 / 59.7 / 58.4 -> 50.2 / 52.0 / 50.2 (P7.0s and the pin), JIT 1.09 / 1.13 / 1.11 -> 1.05 / 1.13 / 1.11.
  Interp kernels: flat to +7% under the pin (the 11-07 text and today's measure the same on abf1d40e35), primes
  2.65 -> 4.42 (lookibed/daScript#49: an inlined callee whose range loop returns early runs the caller 1.85x
  slower). AOT sieve 8.80 -> 8.17, str_copy 3.71 -> 3.61, matmul 1.57 -> 1.60: the AOT half of #5 is not fixed
  (lookibed/daScript#48: `aot_cpp.das` reads every global through the hash probe under solid_context). #43: sieve
  JIT solid/no-solid 1.063, the F93 repro 1.074 (spreads 1%): still reproduces, the issue stays open; solid pays on
  compound_lit 0.864, switch_local 0.853, setjmp_general 0.945 under the JIT and 0.62-0.64 under the interpreter.
  strict_aliasing:true: every kernel and Doom's demos right, JIT and exe A/S 0.99-1.02, Doom JIT fps 0.7-4% lower:
  no gain (the tags put every wider integer and pointer in one class), so no per-function
  `[hint(no_strict_aliasing)]` row. Lua ports perf not re-measured: /mnt/d fell under the 8 GB floor (7 GB) before
  that group; its 11-07 numbers stand, marked. Criteria +0.3 to +1.0 per program (label stubs, P8.10). Report:
  `/root/notes/parallel/repin/report.md`.
- **P8.13 The interpreter cost of an inlined early-return loop** (from P8.12, lookibed/daScript#49). Under
  abf1d40e35 a small callee whose range loop returns early, called directly, runs its caller 1.85x slower under the
  interpreter than with `[hint(noinline)]` on the callee (perf `primes` 2.65 -> 4.42x native; sieve, fib_loop and
  str_copy +4-7% are candidates of the same cause, unproven). Wait for the fork issue; if it stays, A/B a converter
  `[hint(noinline)]` on leaf functions holding a returning loop (interp gain against JIT cost), measured both ways.
- **P8.14 AOT global reads** (from P8.12, lookibed/daScript#48). P7.3's parked AOT cells (sieve, matmul, now
  str_copy) wait on `aot_cpp.das` emitting `das_global_solid` for reads under solid_context; no converter change.
  Correction (2026-11-14, `/root/notes/research/aot/aot25_root_cause.md`): the probe does not depend on
  solid_context. `aot_cpp.das` `visitExprVar` spells every global access in a function body `das_global<T, mnh>`
  with or without it (identical bodies; `probes/test_globals.das` `test_aot_globals`), and the standalone `-ctx`
  context fixes each offset at generation time, so the fix upstream is `visitExprVar` (or `StandaloneContextGen`)
  writing `das_global_solid<T, offset>` regardless; P8.12's "under solid_context" reads the same way. The same
  cause holds switch_local (1.67) and PureDOOM (5.2): with the reads rewritten to fixed offsets in the generated
  C++, sieve 8.21 -> 1.63, str_copy 3.60 -> 1.40, switch_local 1.65 -> 1.00, matmul 1.59 -> 1.01, PureDOOM demo1
  5.56 -> 1.14 x native (`TIMING-aot25`, exclusive, machine quiet). No option, flag or annotation reaches that
  path, so no converter change still holds; lookibed/daScript#48 is reopened with the repro.
  Closed (2026-11-17, ruling 38 repin 4): upstream #4652 (`960cae138a`, in the pin `b7d8f6f52f`) makes the
  `-ctx` body read `das_global_solid<T, offset>` under solid_context, so `test_aot_globals` flipped: the bodies
  are no longer identical (#256). The converted programs' AOT C++ holds no `das_global<` (PureDOOM 7779
  `das_global_solid<`, doomgeneric 7577). The exclusive check (TIMING-48-repin4, machine quiet, 7 rounds) gave
  sieve 1.62, str_copy 1.41, switch_local 1.01, matmul 1.04, PureDOOM demo1 (readable) 1.15 and doomgeneric
  (readable) 1.13 x native, each within its prediction (`/root/notes/predictions/2026-11-17-48-repin.md`). The
  `UPSTREAM_CELLS` entries and the #48 footnote are gone; the ports tables lose their (#48) marks at the next publish.
  Open: the Rust unit's doomgeneric AOT lane timed out in the check's non-exclusive prep run; its build and
  run time on `b7d8f6f52f` are looked at before the next compare capture.
- **P8.15 Harness gaps found by the repin** (from P8.12 step 4 and the capture): (a) `lua/run.das --luac-check`
  refuses `--tier exe` though `luac_check` goes through `run_tier` (exe checked by hand: 33/33); (b) `doom/run.das`
  `without_define` edits the sidecar as text and leaves a trailing comma when the removed define is the last of a
  multi-line array (the committed one-line sidecar is not affected); (c) blit's JIT at 0.17x native (Rust 0.48x):
  read the JIT's code before quoting it as a win (profile phase).
  (c) Done 2026-11-10 (branch `p8.15-blit-check`): no fold, the result is native's; the native build freed and
  allocated 2 x 256 KiB per rep and glibc's heap trim faulted the pages in again each rep (about 300 of its 360 us),
  while the 0.6.5 daslang process, its thresholds raised by its own earlier frees, kept them (JIT 397 us under
  glibc's static thresholds, 1.10x). The kernel allocates its buffers once; diagnostic, not exclusive: native 56 us,
  JIT 80 us (about 1.4x), the cell in the item 8 batch. Rust's arena allocator never trimmed: its 0.48 is its code
  (uint64 address walks, not vectorized). Corrections to P8.12: the JIT gain is blit's artifact, without blit ours
  1.196 -> 1.171 (15 kernels); the TBAA classes put every integer over 8 bits and every pointer in one class and the
  hot accesses are plain typed derefs; solid_context's JIT S/N geomean is 0.983 (3 of 17 gain), its interpreter
  0.62-0.64 is 2 of 4 cells. Report: `/root/notes/parallel/repin/report.md`, "The blit check".
- **P8.16 The Lua ports perf on abf1d40e35** (from P8.12): re-capture the ports' Lua tables under
  `heavy --exclusive` once /mnt/d has 8 GB free; the conversion at 1b3ea8d is in /root/wt-c2das-ports.
  Done 2026-11-10 on box PC at 2a7bab3 (`capture_2026-11-09T231608Z.json` in the ports clone, uncommitted until the
  next ports publish; 3 samples, `heavy --exclusive`, machine quiet 1%, Lua under a 3 GB address cap). Work x native
  against the 11-07 capture at 9748560: JIT fib 4.88 -> 1.95, binary_trees 2.57 -> 1.44, nbody 3.98 -> 1.19,
  spectral_norm 4.79 -> 1.62, test suite 1.44 -> 1.24 (P7.0x `jit_whole_program` plus the pin); jit-goto 1.58 / 1.29
  / 1.05 / 1.43 / 1.20; exe 1.77 / 1.34 / 1.22 / 1.62 (-5 to -17%); interp lanes -5 to +8% (fib 216, test suite
  26.6); startup from the module cache about halved on 0.6.5 (interp 3.42 -> 1.55 s, JIT 3.85 -> 1.96 s, single
  5.57 -> 2.57 s). The predictions hit 23 of 37 cells within 10%: the work misses are compiled cells 11-15% better
  than predicted and spectral_norm interp-single (+12%, inside the 8% run-to-run band of a second run), the startup
  misses the faster cache. The exe test-suite cell still fails (the exe loads `dasCRuntime/` relative to the test
  folder), as on 11-07.
- **P8.17 The addendum 6 A/B** (ruling 38 addendum 6 item 8; after P8.9 (c), P8.11 and P8.15 (c)). One
  `heavy --exclusive` job: bit_pack O/N (before and after P8.9 (c)) under interp, JIT and exe; Doom's speed build
  demo1-3 O/N under the JIT and demo1 under the interpreter (P8.9 (c) and P8.11 together); blit's new kernel (P8.15 (c))
  natively and under ours and Rust's interp, JIT and exe. Lua is not timed: neither item changes its text. Predictions
  written before any timing run: `/root/notes/predictions/2026-11-10-add6.md`, sha256
  `6ded4acf9c4bfe1f1254d61e392510aa0ea24162cb83000a2d42d03d7f3a7a53`: bit_pack interp N/O 0.97, compiled 1.00; Doom
  1.00; blit native 50-65 us, ours JIT 1.2-1.6x, interp 250-330x, Rust JIT 2.6-3.6x.
  Done 2026-11-10 (box PC, two `heavy --exclusive` jobs, machine quiet 1%, 5 samples interleaved; O = 055ab0c, N = O +
  P8.9 (c) + P8.11): bit_pack N/O interp 0.994, JIT 1.000, exe 1.001 (134x, 1.21x, 1.17x native). Doom dropped before
  timing: its text is identical O/N but for the `Z_CT` path strings. blit, the new kernel: native 56.3 us; ours JIT
  1.05x, exe 1.07x, interp 299x; Rust JIT 3.10x, exe 3.15x, interp 188x. Predictions: 7 of 8 hit; ours JIT 1.05 beats
  the predicted 1.2-1.6 (the 80 us diagnostic was not exclusive). Geomeans with this blit (15 kernels, the others
  from bba9010): ours JIT about 1.16, exe 1.14; Rust JIT 1.39, exe 1.46. The compare and perf captures keep the old
  blit row until their next exclusive capture. Raw: `/root/notes/parallel/add6_ab/` (ab.txt, summary.md).

## P9 — Readability forms (owner ruling 38, phase 2)

The emitter forms of `/root/notes/research/readability-architecture.md` step 1, each its own row and
small pull request, in this order. Each pull request shows before and after on real Doom or Lua output
and the form's count per 1000 lines of the Doom source-layout speed build (`doom/run.das --convert
--speed --layout source`) and of Lua's source layout (`lua/run.das --layout source`). The readable
form is the default; a form that slows the JIT or the interpreter on Doom or Lua beyond noise is a
`NEEDS RULING` with numbers (ruling 23).

- **P9.1 `p[i]` for `deref(p + i)`** (was P7.0v; reference diff rows 16-17). A pointer subscript and
  `*(p + i)` / `*(i + p)` of a data pointer are das's pointer index `p[i]`, the default; a marshal-only
  record's pointee (its reader at the scaled offset) and a difference `*(p - n)` keep their forms.
  Probe F100 (`probes/test_pointer_index.das`, 2026-11-08, re-run under daScript `abf1d40e35`): `p[i]`
  reaches the element `deref(p + i)` does for every index type and sign, one `PtrAt` node against an
  `i_das_ptr_add` call node under a null-checked `Ptr2Ref`; the JIT null-checks `p` once before a
  `p[i]` loop where the sum is checked per element; under the interpreter a null `p` at index 0 is
  SIGSEGV for `p[i]` where the sum panics, C's undefined behaviour either way. A scratch micro-kernel
  (`heavy --low`, indicative, not quoted): 8.5 against 11.4 ns per `int` read, 12.8 against 16.5 per
  byte copied by index. Measured on the output (2026-11-09, per 1000 lines): `deref` of a sum, Doom
  28.2 -> 0.1, lua 13.2 -> 0.3, luac 14.3 -> 0.4; every `deref`, Doom 37.1 -> 8.9, lua 28.8 -> 15.9,
  luac 27.9 -> 14.0; line counts unchanged. Expected before the A/B (box PC, x native; the lead's
  batched exclusive run, `/root/notes/parallel/pc-p7.0v-ab.sh`): blit and str_copy flat within noise
  on every lane (blit indexes only its checksum read, str_copy nothing); plmpeg interp a few percent
  faster (its `deref(_c_block + k)` sites), JIT and exe flat; Doom and Lua interp flat to a few
  percent faster, JIT flat. Leftover: `perf/audit_constructs.das`'s `node_index` row counts its Lua
  sites by `addr(deref(`, which the new spelling leaves to a plain `deref(p)`'s address; its site
  text becomes the `addr(<pointer>[` form.
- **P9.2 Plain blocks and `return null`**: a block that is a statement of its own, a case arm's
  trailing block or a `for`'s scope block loses its braces when its own level declares nothing and
  holds no label; a trailing zero `return` (`return null`, `return 0`) goes when the das text's last
  statement returns on every path by das's own rule (probe F101, `probes/test_return_paths.das`:
  an `if` chain with an `else`, a `while (true)` whose body returns; das's CLI accepts a `break` out
  of such a loop and falls off the end, lookibed/daScript#50, so a loop with a live `break` keeps the
  `return`). Measured on the output (2026-11-10, main e6c029b against this branch, Doom 39 of 39 modules
  compile): lines holding `{` alone per 1000 lines, Doom 10.0 -> 1.6, lua 29.1 -> 14.5, luac 33.4 -> 17.3 (the rest declare a local
  or are a `for`'s `finally` block); dead zero returns removed: lua 19, luac 17, Doom 0; lines Doom 31407 -> 30873,
  lua 29085 -> 28194, luac 22377 -> 21616. Expected speed effect: none to slightly faster under
  the interpreter (a dropped block is at most one block node fewer, the dropped `return` is
  unreachable); JIT flat; measured in the phase end's batched A/B (ruling 38 addendum 8).
- **P9.3 The C author's parentheses**: Dumper A marks the expression inside a `ParenExpr` (`"paren":
  true` in the C-IR), the source text's pairs all and a macro body's only around a shift or a bitwise
  operator; the emitter's `wrap` keeps a marked operand's parentheses where das's precedence needs none
  (`1 << (b - 1)` for C's `1 << (b - 1)`, printed `1 << b - 1` before; `(3 | (1 << 4))` for Lua's
  `makevariant`). No parentheses are added beyond those: a right-hand side, an argument or a condition
  stands bare, a lone name is never wrapped. Counts (2026-11-10, main f849a35 against this branch;
  Doom source layout, 39 of 39 modules compile; Lua source layout): a shift beside `+ - & | ^` with
  no parentheses between them per 1000 lines, Doom 4.7 -> 0.5, lua 48.7 -> 3.1, luac 63.7 -> 4.1;
  grouping parentheses per 1000 lines Doom 226.0 -> 235.7, lua 209.0 -> 292.9, luac 229.4 -> 336.6
  (most of Lua's are `makevariant`'s `(t | (v << 4))`); line counts unchanged. Density metric
  (`metrics/criteria_linux.json` re-recorded, 1610 inputs): `programs` 1395.8 -> 1342.4 (das-side
  917.9 -> 864.5), `lost_parens` 39.3 -> 5.5; Lua 1502.8 -> 1388.0, doomgeneric 1071.7 -> 987.5; old
  `all` 79.1 -> 79.9. Of the drop, `literal_arithmetic` 126.2 -> 106.6 is the counter's artifact (it
  counts a number, an operator and a number side by side, so `3 | (0 << 4)` is one site where
  `3 | 0 << 4` was two), not less literal arithmetic: the criterion should count across a
  parenthesis (left for the metric's next change). Expected speed effect
  (phase-end A/B): none on any lane, the parentheses are parse-only and leave the AST the same (interp,
  JIT and exe flat within noise on the kernels, Doom and Lua).
- **P9.4 Literal suffixes**: an `int` literal C converts to `int64`, `uint64`, `uint`, `uint8`,
  `double` or `float` is the das literal with its suffix (`0l`, `-1l`, `1ul`, `240u`, `7u8`, `10.0lf`,
  `3.0f`) in place of the conversion `int64(0)`; a type without a suffix (`int8`, `int16`, `uint16`), a
  negative value of an unsigned type, a value past `uint8` or a float's exact integers (2^24), a named
  constant and a character literal keep the conversion. Counts (2026-11-10, main 34b2beb against this
  branch; Doom source layout, 39 of 39 modules compile; Lua source layout), conversions of a plain
  literal per 1000 lines: Doom 264.0 -> 9.0 (the rest are `int16`, 243), lua 61.3 -> 0.7, luac 68.0 ->
  0.6; line counts unchanged. A few literal conversions come from other emitter paths and stay (a
  folded `sizeof`'s `uint64(4)`, the module's `fixed_array(uint8(0))`). Density metric
  (`metrics/criteria_linux.json`, 1610 inputs), with P9.3's leftover fixed in the same pull request:
  `literal_arithmetic` counts a parenthesized constant as a number (`3 | (0 << 4)` two sites); that
  counter alone, on main's output, raises `programs` 1342.4 -> 1361.7 (`literal_arithmetic` 106.6 ->
  125.9). This form against it: `programs` 1361.7 -> 1315.3 (das-side 883.8 -> 837.3), `literal_casts`
  54.7 -> 2.9, `literal_arithmetic` 125.9 -> 132.1 (sums of suffixed literals the conversions hid);
  Lua 1443.8 -> 1403.7, h264bsd 1360.7 -> 1256.5, plmpeg 1110.0 -> 1065.9, doomgeneric 987.5 -> 975.4.
  Expected speed effect (phase-end A/B): interpreter flat to slightly faster (a literal is a constant
  node where the conversion of a constant was a cast node over one, unless das folds it already), JIT
  and exe flat (LLVM folds the constant either way).
- **P9.5 Compound `#define`s as named constants**: an object macro whose body names other macros
  (`POS_B = (POS_A + SIZE_A)`) is a named constant, recursively. Dumper A names a node inside a macro
  expansion by its spelling, the whole body of an object-like `#define` of the program, so a constant
  inside another constant's body or a function-like macro's (`GETARG_A`'s `POS_A`) carries its name;
  the module's `let` of a compound constant spells the names, each declared first (`let private
  POS_A = POS_OP + SIZE_OP`), and a named shift count keeps its name in a conversion (`~0u <<
  uint(SIZE_A)`). Probe `test_compound_let_folds` (`probes/test_globals.das`, 2026-11-10): AOT and
  the JIT fold a `let` over other `let`s' names and a conversion of one to the literal, as P7.0zd's
  probe found for a single `let`. Counts (2026-11-10, main 32c1e41 against this branch; Doom source
  layout, 39 of 39 modules compile; Lua source layout), per 1000 lines: a literal, an operator and a
  literal side by side, Doom 11.2 -> 10.2, lua 27.7 -> 4.0, luac 34.3 -> 2.6; constant `let`s over
  another constant's name, Doom 0 -> 1.4, lua 0 -> 2.2, luac 0 -> 2.7; constant names in code, Doom
  49.0 -> 54.4, lua 21.2 -> 87.5, luac 19.0 -> 102.3; lines Doom 30873 -> 30885, lua 28194 -> 28334,
  luac 21616 -> 21711 (the new `let`s). Density metric (`metrics/criteria_linux.json`, 1610 inputs):
  `programs` 1315.3 -> 1270.4 (das-side 837.3 -> 797.5), `literal_arithmetic` 132.1 -> 88.7,
  `unnamed_constants` 11.5 -> 7.7, `casts` 287.6 -> 292.9 (a named shift count's conversion,
  `uint(SIZE_A)` where the literal took a suffix); Lua 1403.7 -> 1260.5, luac 1583.5 -> 1398.9,
  doomgeneric 975.4 -> 944.9, the others within 3; old `all` 79.9 -> 80.9. Expected speed effect (phase-end A/B):
  none on any lane; daslang folds each name to its literal before simulation (the probe), so the
  interpreter, the JIT and the exe run the same nodes as before.
- **P9.6 `static_assert` in a file of its own**: the layout checks leave the module body. A module of
  a source layout (source, source-cut) keeps its `[init] def private c2das_layout_check` in
  `<module>.layout.das.inc` beside it and includes it where the check stood, so the check still
  compiles with the module on every tier (a wrong layout in the file fails the module's compile, the
  test's control); the pipeline lists the file in `program.modules.txt`, which the ports publisher
  copies. The metrics read the module and its fragments, not its layout file (`is_layout_file`), as
  `layout_checks` defines the clean form ("in a test, not the module"). A unit converted alone and
  the single layout keep the check inline: their one `.das` is what the tiers, the suites and the
  publisher take, with no module list for a second file (left as is; a row if the owner wants it).
  Counts (2026-11-10, main 3b5aa7d against this branch; Doom source layout, 39 of 39 modules
  compile; Lua source layout): `static_assert` lines per 1000 lines of module text, Doom 19.7 -> 0,
  lua 17.7 -> 0, luac 20.8 -> 0; module text Doom 30885 -> 30240 lines, lua 28334 -> 27807, luac
  21711 -> 21243, the checks now in 19, 13 and 8 layout files (702, 566, 492 lines).
  Density metric (`metrics/criteria_linux.json`, 1610 inputs): `layout_checks` lua 29.4 -> 0, luac 34.5
  -> 0 (compliance 72.9 -> 100, 78.4 -> 100), `programs` 145.1 -> 137.6 (no compare project changes:
  each converts as a unit alone and keeps its checks inline); the totals rise, `programs` 1270.4 -> 1273.9, Lua 1260.5 ->
  1269.4, luac 1398.9 -> 1414.3, das-side 797.5 -> 795.7: a check line holds one site against the
  average 1.26 per line, so the other densities grow as the denominator loses lua's 514 code lines,
  a property of a per-line density and not more noise (every other site count is unchanged); old
  `all` 80.9 -> 81.6.
  Expected speed effect (phase-end A/B): none on any lane; the same `[init]` function of `static_assert`s
  compiles into the same module, and a `static_assert` costs nothing at run time.
- **P9.7 A named `c_runtime` helper for repeated cast chains** (`uint8(*unsafe(reinterpret<uint8?>(...)))`
  and its like), decided by their count in Doom and Lua output: only where the helper is shorter and
  no slower. Counts on main 4c57c7b (Doom source layout, Lua source layout, per 1000 lines): the named
  chain, a conversion of a dereferenced reinterpret, is Doom 0.26 (8), lua 0.11 (3), luac 0 after
  P9.1's `p[i]` and P9.4's suffixes: no helper for it. The chain that repeats is a C string literal,
  `unsafe(reinterpret<uint8?>("..."))` in an initializer and `reinterpret<uint8?>("...")` in a body,
  Doom 45.3 (1369), lua 32.3 (897), luac 30.5 (647), so the helper is that one: `c_runtime/cstr`'s
  call macro `cstr("...")`, which expands in place to the literal's `reinterpret<uint8?>` flagged safe,
  as `enum_from_int` does, so it is no function and no call node under any tier (the c_runtime test
  walks the compiled program for a call), never `[inline]` (1.69x slower under the interpreter, the
  2026-11-02 measurement). Measured on the output (2026-11-11, main 4c57c7b against this branch): every
  literal is `cstr("...")`; `unsafe(` per 1000 lines Doom 38.1 -> 17.9, lua 10.0 -> 0.1, luac 7.6
  -> 0.1; `[c_function]` Doom 635 -> 612, lua 775 -> 683, luac 553 -> 519 (a body whose only unsafe
  operation was a literal); bytes per line Doom 48.8 -> 47.9, lua 36.4 -> 35.9; lines over 160 bytes
  Doom 161 -> 157, lua 194 -> 173, luac 156 -> 144; lines Doom 30240 -> 30221, lua 27807 -> 27731
  (the formatter rejoins shortened lines). The metrics count `cstr("...")` as the reinterpreted
  literal it expands to (`string_literals`, `string_casts`), a C string still bytes and not a das
  string. Density metric (`metrics/criteria_linux.json`, 1610 inputs): flat by design, the sites
  the same; `long_lines` `programs` 16.7 -> 16.2 (lua 11.8 -> 10.5); `programs` 1273.9 -> 1275.5, Lua
  1269.4 -> 1275.0 (fewer lines under the same sites); old `all` 81.6 -> 81.6. Expected speed effect (phase-end A/B): none on any lane, the expansion
  is the node the literal was; a function that loses `[c_function]` loses its body's `unsafe` scope,
  a compile-time mark (flat; if anything a block node fewer under the interpreter).
- **P9.8 The phase 2 A/B** (ruling 38 addendum 8 item 4; after P9.1-P9.7). One `heavy --exclusive` job, A = c25fca7
  (main before the forms, the repin end) against B = 37a7e0c (forms P9.1-P9.7): the 17 perf kernels (every one's text
  changed, the harness at least) under interp, JIT and exe; Doom's speed build demos 1-3 under the interpreter and the
  JIT; Lua's source layout, fib, nbody, spectral_norm and binary_trees through `ports/lua/bench/timed.lua`, under the
  interpreter and the JIT; binjgb and h264bsd-mp4 under the JIT; a micro-kernel of C string literals for P9.7's `cstr`
  expansion under the interpreter and the JIT. Predictions written before any timing run:
  `/root/notes/predictions/2026-11-11-phase2.md`, sha256
  `1f221e7234fb09f5a8e5cd02a74ed9055f6f2c8620304fbf6c91318d9f422b86`: B/A 1.00 on every compiled cell and on the
  kernels' interpreter cells but compound_lit's 0.95 (P9.1's five `p[i]`); Doom and Lua interp 0.98 (P9.1), JIT 1.00;
  binjgb, h264bsd-mp4 and the `cstr` kernel 1.00. A hit is within 0.03 of the predicted ratio.
  Done 2026-11-11 (box PC, one `heavy --exclusive` job, machine quiet 1%, 5 samples with the arm order alternating per
  sample, Lua's interpreter 3; the composed kernels are perf/work's of 2026-11-07, so blit is the kernel before P8.15
  (c), the same C in both arms). B/A medians: the kernels 0.98-1.01 on every lane but compound_lit (interp 0.920, JIT
  0.940, exe 0.918) and two noise cells; Doom interp 0.909 / 0.907 / 0.922 (50.4 -> 45.8x native on demo1), JIT 1.006
  / 0.992 / 0.996; Lua interp fib 0.987, nbody 0.985, spectral_norm 0.994, binary_trees 0.999, JIT 1.003-1.019; binjgb
  JIT 0.959, h264bsd-mp4 JIT 0.886 (1.16 -> 1.03x native); the `cstr` kernel interp 0.926, JIT 1.009, exe 0.998.
  Predictions: 59 of 70 hit. The misses: Doom interp x3, compound_lit x3, binjgb, h264bsd-mp4 are faster than
  predicted, from P9.1's `p[i]`. Under the interpreter it is one `PtrAt` node where the sum was a call under a
  null-checked `Ptr2Ref`, and Doom's column and span drawers index two pointers per pixel. Under the JIT the null
  check happens once before the loop, not per element (probe F100). The prediction priced only the interpreter.
  The `cstr` kernel's interpreter gain is not the expansion, which is the same node (JIT and exe flat).
  Its `pick` loses `[c_function]`'s extra `unsafe` block (P9.7) and its dead `return null` (P9.2), on a call made
  20000 times a run. primes interp 1.060 is no form: its timed functions are the same text in both arms, only `main`'s
  harness differs, and B's samples are bimodal (0.065 / 0.069). va_forward JIT 0.884 is an order effect: both arms are
  bimodal by position (the first arm of a sample 4.9-5.0 ms, the second 4.2-4.3 ms in each), so position-matched it is
  1.01. No form slows any lane: no NEEDS RULING. Raw: `/root/notes/parallel/p9_ab/` (ab.txt, raw/, summary.md, the
  scripts).
- **P9.9 Form 10: `p++`, `p += n` and `*p`** (ruling 38 addendum 10, phase 2b item 1;
  `/root/notes/research/r38/forms_8_11_estimate.md` section 10). A step of a pointer lvalue is das's
  `p++`/`p--` and a pointer's compound store `p += n`/`p -= n` (a marshal-only pointee's by its C size,
  `p += 24`), on every lvalue kind; a C dereference is `*p`, parenthesized under a postfix (`(*p)++`,
  `(*row)[2]`). Probe F102 (`probes/test_pointer_steps.das`, 2026-11-11): `*p` and `deref(p)` compile
  to the same nodes in the same order; the steps hold for an `int`, `uint`, `int64` and `uint64` count
  on a variable, field, field through a pointer, element, pointee and `[c_union]` member under the
  interpreter and the JIT; das reads `*q++` as `(*q)++`. The metrics count a unary `*` as the `deref`
  site it is. Decay `addr(a[0])` and `addr(local)` stay (no `&` in das). Counts (main c3070b2 against
  this branch, per 1000 lines; Doom source-layout speed build, 39 of 39 modules compile; Lua source
  layout): `deref(` Doom 10.9 -> 0, lua 21.3 -> 0, luac 18.7 -> 0 (the same sites as `*`); `x = x +/-
  n` Doom 11.2 -> 0.04, lua 13.9 -> 0, luac 14.8 -> 0; lines unchanged. Density metric
  (`metrics/criteria_linux.json`, 1610 inputs, 0 failed): flat by design, `*p` the same `deref` site;
  `programs` 1275.5 -> 1275.4, Lua 1275.0 -> 1274.5, luac 1417.5 -> 1417.0, old `all` 81.6 -> 81.6. The
  first criteria run caught `addr(*(...)[0])` (gcc-torture strlen-4, strlen-6), fixed with a fixture
  line. Expected speed effect
  (phase-end A/B, B/A): Doom interp 0.98 (`dest += SCREENWIDTH` in the column drawers is one
  `i_das_ptr_set_add` node where the sum was an add and a copy), JIT 1.00; Lua interp 0.99 (the fetch's
  `pc++`), JIT 1.00; the kernels 1.00 on every lane but blit interp 0.98; exe 1.00 everywhere (the JIT
  and AOT spell `p += n` as the load, GEP and store `p = p + n` was; `*p` is the same node).
- **P9.10 Form 8: C truth values as int** (ruling 38 addendum 10, phase 2b item 2;
  `forms_8_11_estimate.md` section 8). C's `!x` of a value that is no das bool is the inverse zero
  test, `x == 0`, `p == null`, `f == 0.0f`, `int(e) == 0` (exact for every value, NaN included:
  `!NaN` is 0, `NaN == 0.0f` false), where `!` over the bool view spelled `!(x != 0)`; `!!x` is
  `x != 0`, `!(x != 0)` the C text spelled is `x == 0`, and a loop's exit or a flattened branch tests
  a zero test's inverse (`if (_t0 == 0) break` for `while (n--)`) through `Em.inverse`. A truth C
  reads as an int is `int_of(c)`, `c_runtime/int_of`'s call macro that expands in place to `c ? 1 :
  0` once `c` is inferred (the same nodes, no call; `c_runtime/tests/test_int_of.das` compares the
  node kinds with the spelled ternary's); an argument that is no `bool` is a compile error, and the
  name is reserved for the converter. A macro named `int` would see every `int(` of a module (the
  research's probe), so the name is `int_of`. A `doom_boolean`/`Bool` enum as a das `bool` stays out
  (its own ruling: Doom stores 0..3 into one). The metrics count `int_of(` as the `bool_roundtrip` it
  expands to. Counts (main 09154dc against this branch, per 1000 lines; Doom source-layout speed
  build, 39 of 39 modules compile; Lua source layout): `!(x != 0)` Doom 20.2 -> 0.2, lua 6.9 -> 0.8,
  luac 5.9 -> 0.8 (the rest are `!` over a compound the C text wrote, `!(xmove != 0 || ymove != 0)`);
  `? 1 : 0` Doom 2.9 -> 0.1, lua 6.4 -> 0.1, luac 6.4 -> 0.1, now `int_of(` 2.8, 6.3, 6.3; lines Doom
  25697 -> 25698, lua 21700 -> 21710 (the `require c_runtime/int_of` lines). Density metric (`metrics/criteria_linux.json`, 1610 inputs,
  0 failed): flat by design, `int_of(c)` the same `bool_roundtrip` site; `programs` 1275.4 -> 1275.2,
  Lua 1274.5 -> 1274.1, luac 1417.0 -> 1416.7, old `all` 81.6 -> 81.5. Expected speed effect (phase-end A/B,
  B/A): 1.00 on every lane (the `int_of` expansion is the ternary's nodes; `x == 0` is one compare
  node where `!(x != 0)` was a compare and a not, so the interpreter at most 0.99 on Doom, whose
  `!` sites are 20 per 1000 lines, and on the kernels 1.00).
- **P9.11 Shape macro `do_while`** (ruling 38 addendum 10, phase 2b item 3;
  `/root/notes/research/r38/shapes_and_macros.md` section 4.1). A `do` whose test hoists no
  statement is `do_while (c) { body }`, the call macro of `c_runtime/do_while.das`: it expands in
  place before its arguments are inferred to `while (true) { body; if (!(c)) { break } }`, or to
  the first-pass flag `var first = true; while (first || c) { first = false; body }` under a fresh
  name when the body holds a `continue` of its own loop (outside every nested loop and inner
  `do_while`, a `match` arm's counted), the body's statements in the loop's own block;
  `c_runtime/tests/test_do_while.das` compares the expansion's nodes with the spelled loops'. A
  `while (0)` whose body continues is `do_while (false)`; a test that hoists (`while (j++ < n)`)
  keeps the spelled bottom test or flag; the count-down range, the `while (0)` block and a body
  that always leaves are unchanged. Counts (main 8c74d21 against this branch, per 1000 lines; Doom
  source-layout speed build, Lua source layout): `do_while(` Doom 0 -> 0.48 (15), lua 0 -> 0.78
  (22), luac 0 -> 0.60 (13); `while (true) {` Doom 2.42 -> 1.94, lua 3.56 -> 2.79, luac 2.80 ->
  2.21; lines Doom 31036 -> 30993, lua 28368 -> 28309, luac 21754 -> 21718. Density metric
  (`metrics/criteria_linux.json`, 1610 inputs, 0 failed): flat by design, no counted site goes
  (the lines do); `programs` 1275.2 -> 1276.0, Lua 1274.1 -> 1275.0, old `all` 81.5 -> 81.5. Expected speed effect
  (phase-end A/B, B/A): 1.00 on every lane, interp, JIT and exe (the expansion is the bottom test's
  own nodes; no program has a `do` with a `continue`), compile time unchanged within noise.
  Renamed `c_do_while` (module `c_runtime/c_do_while`, macro `c_do_while`) by ruling 38 addendum 12:
  the shape macros carry the `c_` prefix and C's meaning; `c_do_while (false)` is C's `do { } while (0)`.
- **P9.12 Shape macro `c_switch`** (ruling 38 addenda 10-12, phase 2b item 4;
  `/root/notes/research/r38/shapes_and_macros.md` sections 4.2, 5, 8.1). A C switch no goto
  re-dispatches, under no jump table, whose enum values all have an enumerator and whose
  `continue` reaches a real loop body prints as `c_switch (c) { case (A, B) { ... } case (_) { ... } }`,
  the call macro of `c_runtime/c_switch.das` with C's meaning (Boris's answer, addendum 12): the
  arms as C wrote them, `break`s included, an arm not ending in a jump falling into the next, `_`
  the `default` anywhere, `continue` reaching the enclosing loop through nested switches. It
  expands before inference, inner switches first, to the converter's two tiers under the same
  choice (the if-chain with the tail breaks dropped, else the matched-flag loop with its plain arms
  and `_cont` epilogue); `c_runtime/tests/test_c_switch.das` compares the nodes with the spelled
  tiers'. The value is read in place when it is a variable (one `let` fewer), else through a
  `let`. Rejected: daslib `match` with the converter unrolling fallthrough (copies 1-5 lines at
  10-15 sites per program), and Swift-style arms with an explicit `fallthrough` (the first
  prototype). Kept spelled: goto re-dispatch (Lua 3), the `goto` jump table, an enum value with
  no enumerator, Duff's device (spelled open). A function ending in such a switch with a default
  and every arm ending in `return` drops its zero `return`. `_` joins das's keywords (`_c__`).
  Probe F105 (`probes/test_switch.das`): `default {` is a syntax error, `switch` no module name,
  `case (_) {` an expression with `_` a variable. Counts (main 5696d2f against this branch, per
  1000 lines; Doom source-layout speed build, Lua source layout): `c_switch(` Doom 0 -> 3.09 (98),
  lua 0 -> 3.08 (89), luac 0 -> 3.35 (75); `_flag ||=` Doom 1.10 -> 0, lua 3.43 -> 0.69, luac 3.32
  -> 0.40; `let _cond` Doom 3.19 -> 0.03, lua 3.25 -> 0.10, luac 3.50 -> 0.04; `while (true) {`
  Doom 1.94 -> 1.45, lua 2.79 -> 2.15; lines Doom 30993 -> 31756, lua 28309 -> 28874, luac 21718
  -> 22403 (C's `break` lines and the arm braces). Density metric (`metrics/criteria_linux.json`,
  1610 inputs, 0 failed, re-recorded for the gcc-torture compile sweep): `switch_flags` 84.9 ->
  98.0, old `all` 81.5 -> 82.0; `programs` total 1276.0 -> 1277.9 (`blowup_lines` +3.3, the longer
  text) with its das side 796.4 -> 794.5 (`switch_machinery` 3.0 -> 0.8), lua 1275.0 -> 1279.7 (das
  side 748.1 -> 743.2), luac 1416.8 -> 1419.4 (824.1 -> 818.7), doomgeneric 944.2 -> 943.6. Expected speed effect (phase-end A/B, B/A):
  1.00 on every lane, interp, JIT and exe (the expansion is the tiers' own nodes; a variable value
  saves one `let` per switch run, at most 0.99 on the interpreter where a switch on a local is
  hot), compile time within noise (one macro expansion per switch).
- **P9.13 Form 11: same-type conversions** (ruling 38 addendum 10, phase 2b item 5, step (a)+(d);
  `/root/notes/research/r38/forms_8_11_estimate.md` section 11). A C numeric conversion whose
  operand das already spells as the target type is the operand (C's `char` and `unsigned char`,
  both `uint8`: `(lu_byte)str[i]` is `str[i]`, `(unsigned)(lu_byte)s[1]` is `uint(s[1])`, so the
  value-keeping chain (b) folds through it), an enum and a truth value keeping their routes; a
  `sizeof` C reads as an `int` is `typeinfo sizeof(type<T>)`, an `int` already (a marshal-only
  record's size its literal). A conversion that changes the das type stays (`uint64(uint(i))`).
  Fixture `p9_conversions` (bytes past 0x7f, a sizeof in an int and a size_t context, a negative
  int zero-extended, narrow fields), native-compared under interp and the JIT. Counts (main
  5696d2f against this branch, per 1000 lines; Doom source-layout speed build, Lua source layout):
  `int(uint64(typeinfo sizeof` Doom 2.94 -> 0.42, lua 2.30 -> 0.64, luac 1.29 -> 0.23 (the rest
  convert a product, `sizeof(T) * n`); `uint8(` Doom 16.26 -> 15.91, lua 19.11 -> 16.25, luac
  21.73 -> 19.34; numeric conversions in all Doom 203.7 -> 198.3, lua 155.2 -> 148.0, luac 174.7
  -> 170.1; lines unchanged. Density metric (`metrics/criteria_linux.json`, 1610 inputs, 0 failed,
  re-recorded as the compile sweep): `programs` 1277.9 -> 1271.2 (`casts` 296.2 -> 289.5), lua
  1279.7 -> 1267.1, luac 1419.4 -> 1411.2, doomgeneric 943.6 = (its row reads no `char` cast or
  int `sizeof`), old `all` 82.0 -> 82.0. Steps (c) (narrow `==` against a literal) and (e) (`uint(int(e))`)
  are the next PR. Expected speed effect (phase-end A/B, B/A): interp 0.99-1.00 on Doom and Lua
  (fewer conversion nodes: `uint8(uint8)` is a cast node das keeps under the interpreter), JIT and
  exe 1.00 (LLVM folds them).
- **P9.14 Form 11: narrow equality, direct enum conversions** (ruling 38 addendum 10, phase 2b
  item 5, steps (c) and (e); `forms_8_11_estimate.md` section 11). C's `==`/`!=` of a promoted
  `uint8`, `int8`, `uint16` or `int16` value against an integer literal in its range, or of two
  values of one such das type, compares narrow (`ts.extra == 0`, `*s == 'a'`, `a.extra ==
  b.extra`), decided by das types below the conversions that keep every value; a literal outside
  the range, a `#define`'s name (`int(L.status) == LUA_OK`: das reads the name as an `int`, and the
  name is the readable part), mixed types and an ordering keep the promoted compare. An enum, an
  enumerator and an enumerator shift count convert straight to the integer target (`uint(e)`,
  `int64(e)`, `1u << uint(TMS.TM_EQ)`), through `uint` first for a 64-bit target of an
  unsigned-underlying enum and through the promoted integer for a floating one. Probe F106
  (`probes/test_conversions.das`): storage integers take a bare literal in range on either side
  (character and `u` literals included), one past the range is a compile error, an enum converts to
  every integer type directly with `int(e)`'s bits, under the interpreter and the JIT. Fixture
  `p9_narrow`, native-compared under interp and the JIT. Counts (main 7f65da3 against this branch,
  per 1000 lines; Doom source-layout speed build, Lua source layout): `uint(int(` Doom 4.28 ->
  0.06, lua 1.77 -> 0.42, luac 2.28 -> 0.54 (the rest convert a computed `int`, `uint(int((i >> uint(POS_B)) & ...))`); `int(x) ==/!= literal` Doom 12.69 -> 10.71 (the
  rest are `doom_boolean` truth tests, `int(e) == 0`, which stay), lua 3.05 -> 0, luac 1.92 -> 0;
  numeric conversions Doom 193.5 -> 185.0, lua 145.1 -> 140.2, luac 164.9 -> 160.5; lines
  unchanged. Expected speed effect (phase-end A/B, B/A): interp 0.99-1.00 on Doom and Lua (one
  conversion node fewer per site; a narrow `==` is one compare of the storage value), JIT and exe
  1.00 (LLVM folds the conversions).
- **P9.15 Long lines** (ruling 38 addendum 13 part 3; the `long_lines` criterion,
  `metrics/ARCHITECTURE_CRITERIA.md`). A line past 160 bytes breaks where the emitter marked the
  expression as it spelled each node: after a list's `,` (call arguments, `fixed_array` elements,
  record initializers, function parameters), after `&&`/`||` and `?`/`:`, and after any other
  binary operator; `converter/line_wrap.das`'s `laid_out` picks the lowest-ranked marks first
  (the shallowest parentheses, a list before `&&`/`||` before the other operators), fills each line,
  indents a continuation 8 spaces past its statement, and breaks only directly inside a `(`, where
  das reads the next line as the same expression (das's continuation-line rule: a line opening with
  `+`/`-` outside parentheses is a new statement), never in a literal, a comment, a `[ ]` or a
  `{ }`. No pass parses printed text to find a break; a written file holding a mark is a converter
  error. Rejected: daslib's `wrap_long_lines` (a token pass over the printed text, against the
  AST rule). Lines over 160 per 1000 (main 116e1c1 against this branch; Doom source-layout speed
  build, Lua source layout): Doom 4.77 -> 0.80, lua 5.38 -> 0.75, luac 5.77 -> 0.88; modules with
  one Doom 43 of 112 -> 7, lua 34 of 61 -> 7, luac 22 of 45 -> 5 (the rest hold a long string
  literal, a field-name list, or an operator chain outside every parenthesis); lines Doom 31644 ->
  35019 (data tables and initializers, 2771 of the 3375 in `DOOM_cluster`, `tables`, `info`), lua
  28813 -> 29176, luac 22358 -> 22631. The metrics read a line at a time in two places the
  layout broke: a `def` whose parameters wrap is found at its brace (`scan_das`), and a literal
  cast counts once per statement across its continuation lines. Density metric
  (`metrics/criteria_linux.json`, 1610 inputs, 0 failed, re-recorded for P9.14 and P9.15 together):
  `long_lines` clean share lua 33.3 -> 85.4, luac 45.9 -> 86.5, doomgeneric 46.7 -> 86.7, `all` 38.6 ->
  62.0; old `all` 82.0 -> 83.0; raw long lines lua 154 -> 22, luac 128 -> 20, doomgeneric 20 -> 2;
  `blowup_lines` raw lua 2546 -> 2603 (the wrapped lines inside functions), `macro_blowup` lua
  88.7 -> 88.1. Leftover: the
  densities count sites per 1000 das code lines, so a layout change moves every density without a
  site changing (P9.15's added lines dilute them: doomgeneric's total mostly by its wrapped data
  tables); the basis should not depend on line wrapping (per 1000 statements, or per KB of
  non-blank text), and P9.15's raw counts in its PR are the comparison across this change.
  Expected speed effect (phase-end A/B, B/A): 1.00 on every lane (whitespace only), compile time
  within noise.
- **P9.16 `let` for never-reassigned locals** (ruling 38 addendum 14 item 2, fn-macros part 2 step 1;
  `/root/notes/research/r38/fn_macros_part1.md` section 6). A local declared with an initializer that
  nothing in its scope assigns, steps or takes the address of prints as `let` when das spells it as an
  integer, a floating value or an enum (`let i1 : int64 = v1.value_.i`); the scope is the rest of the
  declaring block, so sibling blocks' locals of one name are planned apart. Pointers, records and arrays
  stay `var` (F3: a `let` pointer reads its pointee as const). The `[inline]` splice of part 2's folded
  macros substitutes a `let` argument in place where it binds a copy for a `var` one (F104, the probe
  now checks a `let` local too). Fixture `p9_let_locals`, native-compared under interp and the JIT.
  Counts (main ce19ef3 against this branch; Doom source-layout speed build, Lua source layout): typed
  initialized locals that are `let`, of all typed initialized locals, Doom 0 -> 32 of 109, lua 0 -> 497
  of 1733 (`luaV_execute` 0 -> 87 of 349), luac 0 -> 355 of 1366; the rest are pointers, records and
  locals their scope writes; lines unchanged. Expected speed effect (phase-end A/B, B/A): 1.00 on every
  lane, interp, JIT and exe (a `let` scalar local is the same stack slot as a `var` one under the
  interpreter, and no folded macro exists yet whose splice could skip a copy); compile time unchanged
  within noise.
- **P9.17 C-IR 0.2: function-like macro fields** (ruling 38 addendum 14, fn-macros part 2 step 2,
  first of two PRs; `/root/notes/research/r38/fn_macros_part1.md` section 7). `docs/c-ir-spec.md`
  section 6.3: the unit's `macros` (name, parameters, file, line, the `#define` on one line, and per
  parameter how many times the full expansion holds the argument, -1 unknown), `fn_macro` on a node
  that is a whole expansion (outermost first where one node is several, with each argument's text as
  the call writes it) and `macro_args` on each copy of an argument, each absent when empty;
  `CIR_VERSION` 0.2. `cir.das` writes and reads them; `tests/test_cir_macros.das` round-trips a unit
  holding each. No dumper writes them yet (P9.18) and no output changes. Expected speed effect
  (phase-end A/B, B/A): 1.00 on every lane; the C-IR of every unit gains only its version string.
- **P9.18 Dumper A marks function-like macro expansions** (ruling 38 addendum 14, fn-macros part 2
  step 2, second PR). Dumper A writes P9.17's fields: definitions and expansions from libclang's
  preprocessing record on its layout pass, the nodes found by their spellings against the `#define`
  text (`converter/macro_sites.das`, `converter/ARCHITECTURE_DUMPER_MACROS.md`), nested expansions,
  the calls an argument writes, chains and a macro of itself included. No output change: the emitter
  reads none of it yet (step 3). A node is taken as an expansion only when its leaves are the full
  expansion's and its argument copies follow the parameters' order, and a system header's
  function-like macro is never marked (#183 review: a node of two side-by-side calls, a body calling
  one macro twice with the arguments swapped, `offsetof` and `va_start` were marked). Fixture
  `p9_fn_macros` (classes A-D, nested, side by side, swapped arguments, bodies differing in a
  constant, a called parameter, effectful and faulting arguments, a split argument, system macros).
  Counts (main 42573be against this branch, Lua source layout): marked expansions lua 11392 of 490
  macros (`lvm`: `ttisinteger` 88, `tonumberns` 29, `op_arith_aux` 10), luac 10989 of 450, Doom 217 of
  9; of lua's, 9860 hold each argument as often as the macro uses it (the rest mostly `cast(t, e)`,
  whose type argument has no node); das text byte-identical (Lua, luac, Doom); lua's C-IR 21.6
  MB -> 25.8 MB. Expected speed effect (phase-end A/B, B/A): 1.00 on every lane (no das text change);
  dump time within noise (the preprocessing record and one walk over the dump's macro nodes).
- **P9.19 Link merge and fold verdicts of function-like macros** (ruling 38 addendum 14, fn-macros
  part 2 step 3, first of two PRs; lead's rulings of 11-12). `link_tus` merges the units' `macros`
  tables first (a `#define` of one name, file, line and text once), remaps every `fn_macro.m` and
  renumbers each unit's expansion ids past the earlier units', and compares header function copies
  with their ids numbered by first appearance (`write_cir_decl(d, true)`), so a header function
  using a macro stays kept once (`ARCHITECTURE_LINK.md#link-macros`). `converter/macro_fold.das`
  gives each whole expansion its verdict from the node alone (`ARCHITECTURE_EMITTER_MACROS.md`
  `#fold-verdict`): class A folds; class B (a parameter read twice, never or on some paths) only
  without effectful arguments and with every such argument a constant, a local, a field of one
  through `.`, its address or arithmetic without `/` or `%` (else `faulting`, counted apart); D
  (a block or `do { } while (0)`) without outward flow; a caller's local the body writes is a
  reference parameter; never-fold shapes (no-op, identity, single cast, one operator with an unread
  argument, the sidecar's `no_fold`); `incomplete`, `capture`, `lvalue`, `shape`, `flow`, `order`
  (an argument C reads after a store of the body, an effectful argument after a body action or
  beside an argument reading what it writes, effectful arguments das may reorder; #184 review:
  a declaration's initializer is a body action, a faulting argument after a body call stays
  expanded, a body name a parameter takes is a capture, a volatile copy is effectful). No
  output change: the emitter reads no verdict yet (P9.20). Fixture `p9_fn_fold` (the verdict of
  each outermost site: every class, nested, swapped, typed, a written local, a loop, and a
  negative control per guard); a hand-built two-unit link test. Expected speed effect (phase-end A/B, B/A): 1.00 on
  every lane (no das text change); link time within noise.
- **P9.23 Form 9 step A: `<=` and global or member bounds as range loops** (ruling 38 addenda
  10-14, phase 2b item 7; `/root/notes/research/r38/forms_8_11_estimate.md` section 9, step A).
  Local analysis inside `counted_for` (`ARCHITECTURE_EMITTER_LOOPS.md`, the range loop). (1) `i <=
  n` is `range(a, n + 1)` (a literal's successor as one literal) for a constant `n` below its
  type's maximum (a constant at the maximum stays `while`), or for a signed counter whose body
  holds no `break` of the loop, `return`, `goto`, call, volatile access or nested loop whose test
  loads no object (none, `while (!0)`, an enumerator, `sizeof`: C lets a constant-test loop run
  forever, while one testing an object with no call or volatile access may be assumed to end, C11
  6.8.5p6; the #187 review's `while (!0)` case): such a run
  reaching `n == INT_MAX` steps the counter past it, which C leaves undefined, so no defined run
  meets the wrapped end; an unsigned `<=` over any other bound stays `while` (a defined endless
  loop at the maximum). The research note's rule (`leaves_loop` false) also excludes a call here,
  since `exit` or `longjmp` ends the run early as a `break` does. (2) A bound over globals and
  members (`.` and `->`) is invariant when the body makes no call and every store misses every
  load of the bound: two variables' storage is apart; a variable no pointer reaches (a local with
  no `&` or array decay of it in the function, a global the program defines and points at in no
  function and no initializer: the program's C-IR holds every unit) is apart from every access
  through a pointer; two pointer accesses are apart only by C's type-based aliasing. Aliasing mode:
  C11 6.5p7 binds valid ISO C programs, but the converter's default (`strict_aliasing` off, the
  root `options strict_aliasing = false`, P8.5) declares the program one built with
  `-fno-strict-aliasing` (Doom, Quake), whose punned stores (an `int` written through a `float *`)
  are the program's meaning, so the type rule proves nothing there: by default two pointer
  accesses are never apart, and only the sidecar's `strict_aliasing: true` (C clean under
  `-fstrict-aliasing`) applies the classes (an integer by width with its twin, `_Bool`, an enum
  with every integer, a floating type by width, every pointer one class; a character type, a
  record, an array and any member of a union alias everything). The variable rules hold in both
  modes, since a pun needs a pointer to the object. Fixture `p9_counted_for` (the ranged loops,
  and the ones that stay `while`: a callee writing the global bound, a `char *` store into the
  bound's object, `<=` with a `break` against `INT_MAX`, `<=` with a call, a C89 counter read
  after, a float store into a member bound by default, a union's other member under strict
  aliasing; and from the review: a call writing a member bound, a pointer to the global bound from a
  global's initializer and from a record initializer's, a union member's array decay, a volatile
  member bound, `<=` over inner loops tested by `!0` and by an enumerator and with a volatile store,
  `i <= 2147483647`, `<=` with a call that exits, an enum store into an int bound under strict
  aliasing), native-compared under interp and the JIT, and again under the sidecar's
  `strict_aliasing: true`. The guard for a global the program declares but does not define has no
  fixture: such a program fails das's compile (`can't locate variable`), and the defined-elsewhere
  objects the converter maps (`stdin`, `stdout`, `stderr`) are pointers to an opaque record, never
  an integer bound. No probe: the das side (`range` from a start past the end runs no pass,
  `n + 1` wraps) is `probes/test_loops.das` and F-rows already recorded. Counts (main cf8d361 against this branch; Doom source-layout speed build, Lua
  source layout; range loops, then `while (c)` loops, per 1000 lines): Doom 166 (4.73) -> 185
  (5.27), 289 (8.23) -> 270 (7.70); lua 55 (1.88) -> 59 (2.02), 162 (5.54) -> 158 (5.41); luac 53
  (2.34) -> 57 (2.52), 120 (5.29) -> 116 (5.12); programs (the criteria's ratchet suites
  and projects but doomgeneric) 7939 (8.94) -> 8062 (9.08), 11312 (12.74) -> 11192 (12.61); the
  criteria capture re-recorded (densities within +0.2 per 1000, the text being shorter). The research note's estimate
  (Doom about 29 + 9-20, Lua about 14 + 4) assumed the type rule: under the default aliasing mode
  the pointer-store bounds stay `while`, and most of what remains has a call in the body (step B).
  Expected speed
  effect (phase-end A/B, B/A): interpreter 0.99-1.00 on Doom and Lua (a range loop drops the test
  node and the step of a `while`, on a few dozen loops, none in `luaV_execute`'s hot path), JIT and
  exe 1.00 (the JIT compiles both forms to the same code, `benchmarks/bench_for_shapes.das`);
  compile time unchanged within noise.
- **P9.24 Form 9 step B: program summaries for range-loop bounds past calls** (ruling 38 addenda
  10-14, phase 2b item 8; `/root/notes/research/r38/forms_8_11_estimate.md` section 9, step B). Two
  PRs: `converter/summaries.das` (`ARCHITECTURE_EMITTER_LOOPS.md#summaries`), analysis only, read
  once from the program's C-IR: per function the globals it stores to by name, stores through a
  pointer (their types under strict aliasing), output, surely-returns (no exit/longjmp/abort, no
  recursion, no goto, loops C11 6.8.5p6 lets end), callees merged over the call graph's components;
  a call through a pointer does what every address-taken function does; libc by table, any other
  callee stores everything; noescape per parameter (greatest fixpoint). Then `invariant_bound` takes
  calls whose summaries miss every load of the bound, a local whose `&` reaches only noescape
  parameters counts as unpointed (str_reverse's `l`), and `<=` takes calls that return and print
  nothing. Step A's aliasing ruling holds: callee stores through pointers are apart from a load
  only by type and only under `strict_aliasing: true`. Fixture `p9_summaries` (each kept-`while`
  case beside its range control: a two-level store, a function pointer, an out-parameter,
  strcpy/memset/memcpy into the bound, a recursive cycle, a reader, str_reverse's noescape length,
  a callee keeping the pointer in a global, exit two levels down in `<=`, getenv as a callee no
  table lists) and a two-file program, native-compared under interp and JIT in both aliasing
  modes. Counts (main d5bf5d0 against this branch; range loops, then `while (c)`, per 1000 lines):
  Doom 185 (5.27) -> 199 (5.68), 270 (7.70) -> 256 (7.31); lua 59 (2.02) -> 63 (2.16), 158 (5.41)
  -> 154 (5.27); luac unchanged 57 (2.52), 116 (5.12); programs (the criteria's ratchet suites and projects but doomgeneric) 8062 (9.08) -> 8066 (9.09),
  11192 (12.61) -> 11188 (12.61) against P9.23's recorded count; the criteria capture re-recorded
  (densities within 0.2 per 1000). Doom's 14 are init and setup loops (`numdefaults`, `numlines`,
  `sector->linecount`, `numtextures`, R_InitBuffer's `viewheight`); Lua's 4 are str_reverse,
  str_lower, str_upper and a `<=` in liolib. Doom demos 1-3 in sync, Lua 8/8 error checks and
  luac -o 33/33 under interp and JIT. The estimate (Doom about
  57, Lua about 14) assumed the type rule; under the default aliasing mode a callee that stores
  through any pointer reaches every pointer or pointed-global bound, and Doom's callees mostly do.
  Expected speed effect (phase-end A/B, B/A): interpreter 0.99-1.00 on Doom and Lua (a few dozen
  more range loops, none in `luaV_execute` or the renderer's column loops), JIT and exe 1.00;
  conversion time: the summaries add one pass over the program, predicted within noise.
- **P9.20 Function-like macros fold into `[inline] def`s** (ruling 38 addendum 14, fn-macros part 2
  step 3, second PR; `converter/ARCHITECTURE_EMITTER_MACROS.md#fold-emission`). Every expansion
  whose P9.19 verdict folds prints as a call of a private `[inline]` def in the module using it
  (generic, or typed overloads per signature; `var` pointers, `var x : auto&` for a written local;
  `[c_function]` when the body needs unsafe), the def under a comment with the `#define`; the
  chain's next level and nested expansions fold inside a def; a def whose text reads more than its
  parameters stays expanded (`spelling`), as do the arms of a null-armed pointer `?:` (das inlines
  no call there). Sidecar `no_fold: [names]`, unknown names refused. Folded is the default (ruling
  23); the global switch is 3b. Counts (main 651d262 against this branch, source layout): lua
  29237 -> 30182 lines (506 defs, 1951 def lines), `luaV_execute` 2611 -> 1954, luac 22676 ->
  23093 (400 defs), Doom 35196 -> 35227 (7 defs); lua sites folded 2604, faulting 224, capture
  352, never 1217. Lua and luac against native (8 error checks, luac -o 33 files) and Doom demo1-3
  in sync under interp and the JIT. Expected speed effect (phase-end A/B, B/A; F104 prediction):
  JIT and exe 1.00 within 2% (the splice folds the copies); interp 0.97-1.00 (a `var` argument
  binds a copy per call, `let` locals of P9.16 do not).
- **P9.25 `[c_macro]`, the carrier of the folded function-like macros** (ruling 38 addendum 18,
  after the P9.20 speed gate failed: Lua interp B/A nbody 1.51, spectral 1.34, binary_trees 1.22,
  fib 1.09, root cause the `[inline]` splice's per-level argument copies, `_res` blocks and `_low`
  flags). Three PRs, landing with P9.20's fold code: (1) `c_runtime/ARCHITECTURE.md` split, the
  compile-time pieces into `ARCHITECTURE_MACROS.md` (LINT027); (2) `c_runtime/c_macro.das`, a
  function annotation replacing each inferred call by the def's written body with the parameters
  substituted by the argument expressions as written (C's expansion), a statement body's locals
  renamed apart, `[c_function]`'s `unsafe` kept with the body, any other shape a compile error;
  fixture test under interp, JIT, exe and AOT; (3) the emitter prints `[c_macro]` on a folded def
  whose text is one expression or a void statement body, the value-returning statement bodies
  (Lua's `tonumberns` class, 8 defs) stay expanded at their sites, and a pointer parameter of a
  folded def is `var` only when its value is written through, passed to a `var` parameter
  (innermost defs first), escapes as a pointer, or the parameter is assigned, casts looked
  through (classification row 9). Predictions (the lead's exclusive re-gate, A = main without the
  fold, B = P9.20 with this item): Lua interp B/A 1.00-1.03 on fib, nbody, spectral_norm and
  binary_trees (prototype M on the real Lua: 1.003 / 1.018 / 1.035 / 1.028, of which the
  `tonumberns` sites stay expanded here, so spectral and binary_trees should fall to about 1.01);
  JIT 1.00 within noise; Doom interp and JIT 1.00 (7 folded defs); Lua compile time (`-dry-run`)
  about A's plus a third (prototype: A 3.3 s, `[inline]` 5.8 s, `[c_macro]` 4.4 s); converted text
  unchanged against P9.20 but the annotation word, the dropped `var` of read-only pointer
  parameters and the `tonumberns`-class sites spelled expanded; criteria 1610 inputs, 0 failed.
  The fold's `ternary` and `labels` guards (das's inliner hosts no call in a null-armed `?:` arm or
  declared in a labelled block) are `[inline]`'s and stay for now; lifting them, and folding the
  class B refusals the textual substitution evaluates as C does, is a follow-up row.
- **P9.26 Bench method audit** (ruling 38 addendum 12 item 3, Boris's lesson from upstream #4529:
  a das-vs-clang kernel or repro keeps its C data on the heap or behind an external function and
  consumes the result, and the loop is shown to run by asm or `-Rpass` before an "Nx of clang" is
  quoted). Done as an audit, no timing (report `/root/notes/research/r38/bench_method_audit.md`):
  the 17 `perf/kernels`, the 12 `perf/kernels/audit` and the 3 `perf/kernels/dasprofile`
  programs composed as the harness composes them and built with the native lane's flags
  (clang-22 `-O3 -w -funsigned-char`): every timed loop nest is in `main`'s rep loop at the
  source's depth (scalar, unrolled or vectorized, nothing deleted; the `volatile` parameter and
  the printed result keep each rep's work), so the perf and audit tables stand. The repros:
  F80 `global_in_branch.c`, F81 `byte_read_memcpy.c`, F87 `volatile_load.c` and F89's TBAA
  kernels (malloc arrays, clang's remarks recorded) run their loops and stand; the compare
  projects' benches hash every decoded frame and stand. One number is void: **F86's "33x, 1.6 ns
  per difference"** (JIT 0.313 s against C 0.0094 s): `ptr_diff.c` keeps the array on the stack,
  so clang -O3 folds `&arr[i & 63] - &arr[0]` to `i & 63` and vectorizes the sum, a loop with no
  pointer difference in it. The ratio is void until the next exclusive capture times the heap
  form `ptr_diff_heap.c` + `ptr_diff_heap_ext.c` (array and pointer table from another
  translation unit, the sum consumed; asm: load, `sub`, `shr $4` per difference) against
  `ptr_diff_heap.das`, all in `/root/notes/research/p7.0p/repro/`. The finding itself (the JIT
  calls `i_das_ptr_diff` per difference and divides by the stride) is unchanged.
- **P9.21 The `fn_macros` switch** (ruling 38 addendum 14, fn-macros part 2 step 3b, first PR;
  `converter/ARCHITECTURE_EMITTER_MACROS.md#fold-emission`). `--fn-macros fold|expand` and the
  sidecar's `fn_macros`: `fold` (the default, ruling 23) prints the calls of P9.25's `[c_macro]`
  defs, `expand` folds no site and the module holds no def; any other value refused, a test per value (CLI, sidecar, a
  fixture run against native under `expand`). Its option duties: the perf lane
  `interp-fn-macros-expand` (cells at the lead's next capture; no kernel expands a macro of its
  own, so the lane's text is the default's), the readability keys `<input>@fn-macros-expand` for
  every kernel and Lua program, the criteria rows `lua/lua@fn-macros-expand` and `luac`'s, kept
  out of `all`. #181's minors: a `for` whose first clause is one bare declaration (Dumper A always
  writes a block; another C-IR producer may not) is planned for `let` too; `let_local`'s dead
  `dims` test dropped. Predictions: no default text change on any input (the bare clause never
  reaches the emitter from Dumper A), so every default readability key and criteria row stays as
  recorded; `@fn-macros-expand` keys spell main's text without the fold (Lua lua 30757 lines
  folded against 29152 expanded, luac 23689 against 22619, `luaV_execute` 2568 against 2611).
  Expected speed effect (phase-end A/B, B/A): 1.00 on every default lane;
  `interp-fn-macros-expand` equals `interp` on each kernel within noise.
- **P9.22 Header macros share one def** (ruling 38 addendum 14, fn-macros part 2 step 3b, second
  PR; the lead's placement ruling of 2026-11-12; `converter/ARCHITECTURE_EMITTER_MACROS.md#fold-emission`).
  A macro a header `#define`s whose node is a layout module (a header owning a record or an enum),
  whose expansions name no function, global or string literal outside their arguments, whose
  records and enums that module sees, and whose using modules all see that module, one of them
  another module, has one public `[c_macro] def` there (`plan_shared_macros`): the module is
  assembled after every other, with the `#define` constants the defs name (and those their values
  name) as its own private `let`s; a def it holds folds only macros it sees. `[c_macro]` spells the
  body at the call, so a calling module keeps the constants and requires the body names (a
  probe: a private `let` of the def's module is refused at the call, error 30283, and a function of
  a module only the def's module requires is not found); a header def's `var` parameters are
  decided for the whole program first (`hosted_var_parameters`), so a def passing its parameter on
  in any module sees the final def. Every other macro stays private per using module; the single
  layout and a cluster using its own header's macros are unchanged. Names program-wide (a private
  def takes no public def's name). Fixture `p9_fn_headers` (shared, private, a constant, a nested
  shared macro, a written pointer passed on by a private def) under interp and the JIT, and the
  single layout. Counts (source layout, against P9.21): lua 30757 -> 30542 lines, its 498 private
  defs (def lines, overloads counted) -> 131 public over 124 header macros plus 305 private; luac
  23689 -> 23414, 393 -> 126 public over 120 plus 189 private; folded sites lua 2739 -> 2739, luac
  2506 -> 2505, the expanded sites' reasons shifting (`overload` 184 -> 191 and 184 -> 198: a
  header def holds one text for the whole program); Doom unchanged (7 private defs, no header
  macro qualifies). Lua and luac against native (8 error checks, luac -o 33 files) and Doom
  demo1-3 in sync under interp and the JIT.
  Expected speed effect (phase-end A/B, B/A): 1.00 within noise on every lane (the call is
  substituted at its site wherever the def lives); compile time within noise.
- **P9.27 The fold verdicts beside `macro_blowup`** (ruling 38 addendum 14 item 1 and the part 2
  brief's step 4; `metrics/ARCHITECTURE_CRITERIA.md#criteria`). The criteria worker records the
  conversion's fold verdicts (`ConvertResult.fold_counts`) as three raw keys: `macro_sites` (every
  outermost function-like macro expansion, once per module), `macro_folded` (printed as a call of
  its `[c_macro] def`) and `macro_faulting` (left expanded because an argument the body evaluates
  zero times or in one branch only may fault: a dereference, an index or a division), each a line
  of the length table beside `macro_blowup`'s das/C ratios; a compare project's are 0 (its
  conversion keeps no verdicts), a capture before them reads them as 0 (`LATER_RAW_KEYS`). Under
  `fn_macros` `expand` every site counts as `expand`, so either value's counts total the
  program's sites; no das text changes, no criterion or density moves. Counts (criteria
  re-record, 1612 inputs, 0 failed): lua 6000 sites, 2739 folded, 224 faulting (luac 5624, 2505,
  221; under `expand` 6504 and 6165 sites, the expansions a folded def holds counted too);
  c_testsuite 11 / 10 / 0, gcc_torture 93 / 35 / 1, csmith 10192 / 0 / 0; no other raw count of
  any row moves. Expected speed effect: none (no output change);
  the criteria run's time within noise.
- **P9.28 The phase 2b end A/B** (ruling 38 addendum 10: batched exclusive A/B at the phase end, the forms and
  the macros, plus the fold switched on and off; after P9.9-P9.27). One `heavy --exclusive` job, 5 samples with
  the arm order rotating per sample, Lua's interpreter 3, over three arms:
  - A = c3070b2, the phase 2 end.
  - B = 408d198, main after P9.27.
  - C = B with the sidecar's `fn_macros: expand` in Lua's and Doom's, so the fold is off.

  The lanes:
  - The 17 perf kernels and P9.8's `cstr` kernel under interp, JIT and exe for A and B. No kernel folds a macro,
    so C's kernel text is B's.
  - Doom's speed build, demos 1-3, under the interpreter and the JIT.
  - Lua's source layout, fib, nbody, spectral_norm and binary_trees, under the interpreter and the JIT.
  - binjgb and h264bsd-mp4 under the JIT, for A and B.
  - F86's heap `ptr_diff` repro (P9.26): native clang -O3 and -O2 against das JIT.

  Predictions were written before any timing run: `/root/notes/predictions/2026-11-13-phase2b.md`, sha256
  `4bdda806c9cffd1b07a3eaa7b641a2ee1d92be7a8a3274403470d58bc2404214`. Each one prices the P9.9-P9.27 rows'
  expected speed effects per cell, multiplied, with P9.25's re-gate as the fold's measured value. The B/A
  predictions:
  - Kernels: 1.00 on every lane, but blit interp 0.98 (P9.9).
  - Doom: interp 0.95 (range 0.92-0.98: P9.9, P9.10, P9.13, P9.14, P9.23, P9.24), JIT 1.00.
  - Lua interp: fib 0.95 and nbody 0.95 (range 0.92-0.98); spectral_norm 0.98 and binary_trees 0.98 (range
    0.95-1.00).
  - Lua JIT 1.00; binjgb and h264bsd-mp4 JIT 1.00.

  The fold, C/B: Lua interp fib 1.02, nbody 1.02, spectral_norm 0.99, binary_trees 0.99 (the re-gate inverted),
  JIT 1.00; Doom 1.00 on both lanes. `ptr_diff` JIT/native about 2.5 (range 1.5-4), replacing F86's void 33x.

  A hit is within 0.03 of the point, or inside the stated range. A lane where B is slower than A by more than 3%
  is a NEEDS RULING.

  Done 2026-11-13, box PC: one `heavy --exclusive` job, machine quiet (1%), 06:14-07:14Z, 903 runs, none failed.
  The B/A medians:
  - Doom interp: 0.948 / 0.945 / 0.944 (demo1 45.8x -> 43.4x native). Doom JIT: 0.983 / 0.990 / 0.997.
  - Lua interp: fib 0.987, nbody 1.005, spectral_norm 0.984, binary_trees 1.005.
  - Lua JIT: 1.011 / 1.028 / 1.042 / 1.032.
  - Kernels interp: sieve 0.782 (`<=` range loops), blit 0.863, str_copy 0.910, compound_lit 0.946,
    first_member 0.965, switch_local 1.050. Every other kernel cell is 0.99-1.01, but the slower cells
    listed below and two noise cells (va_forward JIT 0.856, setjmp_general JIT 1.171).
  - Kernels exe: compound_lit 1.114 and sieve 1.066, steady in every sample.
  - binjgb JIT 1.033; h264bsd-mp4 JIT 0.995.

  The fold, C/B:
  - Lua interp: fib 1.009, nbody 0.992, spectral_norm 0.988, binary_trees 0.981. This is the re-gate's band.
  - Lua JIT: 0.995 / 0.981 / 0.957 / 0.997. The fold carries the JIT cost: C/A is 1.006 / 1.009 / 0.997 / 1.030,
    and the re-gate measured JIT 1.007-1.041.
  - Doom: 0.986-1.002 on both lanes.

  `ptr_diff`, heap form: native -O3 0.0477 s and -O2 0.0478 s, das JIT 0.128 s (2.69x), interp 1.995 s (41.8x).
  This replaces F86's void 33x. The finding stands at 2.7x: a call to `i_das_ptr_diff` and a division per
  difference.

  Predictions: 68 of 84 hit, plus the `ptr_diff` ratio.
  - Faster than predicted: five kernels' interp cells, from P9.9's steps and P9.23's ranges under the
    interpreter.
  - Slower than predicted: Lua interp fib and nbody (0.95 predicted; the forms barely touch `luaV_execute`), Lua JIT
    binary_trees and spectral_norm (the fold), and the cells below.

  Two cells are noise:
  - va_forward JIT has P9.8's position effect: whichever arm runs first takes 4.9-5.1 ms, the second 4.0-4.3 ms.
  - setjmp_general JIT is bimodal in both arms (1.76-1.79 / 2.08-2.11 ms), and mode-matched it is 1.00.

  NEEDS RULING (B slower than A by more than 3%, steady in every sample and position):
  - Lua JIT spectral_norm 1.042 and nbody 1.028 from the fold. P9.25 predicted 1.00.
  - compound_lit exe 1.114 (`row++`, `range(s.n)`) and sieve exe 1.066 (`range(2, n + 1)`): AOT only, with
    the JIT flat or faster.
  - switch_local interp 1.050: `c_switch(op & 3)` against the spelled `let _cond` if-chain.
  - binjgb JIT 1.033, form not isolated.

  Raw: `/root/notes/parallel/ph2b_ab/` (ab.txt, raw/, summary.md, prep.sh, ab.sh, summarize.py).
- **P9.29 Two variants per port, `readable` and `fast`** (ruling 38 addendum 19; plan
  `/root/notes/parallel/r38_add19_plan.md`). Every program of c2das-ports (Lua with luac, the six compare
  projects, PureDOOM) is published twice, each variant under its own converter flag set chosen per program:
  `readable` the set with the highest criteria total, `fast` the set with the best exclusive time on the
  program's own workload (the JIT set the default, a tier that differs named). Infrastructure, in small PRs:
  (1) the publisher runs each program in a process of its own (`ports/ARCHITECTURE_RUN.md`; one process
  publishing every program grew past 10 GB of resident memory on the bench and was OOM-killed at PureDOOM);
  (2) the variant files `ports/variants/<program>.{readable,fast}.json` (knob -> value, a one-line reason,
  the numbers that chose it), every knob at the current default, reason "default, search pending";
  (3) the harnesses convert under a variant; (4) the publisher converts and publishes both side by side, the
  tables with both columns. Then the missing off-switches for the forms the phase 2b end A/B traced
  regressions to (P9.28's compound_lit and sieve exe, switch_local interp). The searches (criteria per
  candidate as normal heavy jobs, timing in exclusive batches) and the publish are the lead's.
  Step 2 done in PR 4: the sidecar's `forms_off` and `--forms-off` (`pointer_steps`, `ranged_loops`,
  `c_switch`; `converter/ARCHITECTURE_EMITTER_TEXT.md#forms-off`), each restoring the spelling before
  P9.9, P9.23/P9.24 and P9.12 alone, the default unchanged; the perf lanes `interp-<form>-off` (cells
  at the lead's next capture), the metrics keys `@<form>-off` and the criteria rows
  `lua/<program>@<form>-off`, and the variant knob `forms_off` (`[]` in every file).
  Step 1's publisher, PR 5: the variant files' `results` (`criteria` total, `speed` x native per tier
  from an exclusive quiet run, `lines`, `notes`, each with its commit and date;
  `ports/ARCHITECTURE_VARIANTS.md#variant-results`), which the searches fill, and the variants table
  (`render_variants`: both variants side by side, a number the search left out falling back to a
  labelled capture). PR 6: Lua's publish converts each variant (`lua/run.das --variant <file>
  --layout <its layout>`) into `lua/readable/` and `lua/fast/`, each with its sidecar and
  `variant.json`, and renders the table; the perf lanes are each tier over `readable` and over
  `fast` (`-fast`), the goto and layout lanes leave new captures (old captures still render them).
  PR 7: the same for the compare projects and PureDOOM (a sync table per variant).
- **P9.30 Follow-ups of the repin to daScript `6401904cf9`** (ruling 38 addendum 20 item A; PRs #208 and
  #209). The pin fixed fork issues the converter still works around. Each line is
  a later row, resumed from here, none started: (a) the setjmp lowering's invoked-block form for an arm that
  returns (F96) and the fail-closed refusal of an arm that breaks or continues out of a loop (F97). A `return`,
  `break` and `continue` inside a try or recover arm now run alike under the interpreter and the JIT (daScript
  `7bb5b8dcf8`), so both could be written plainly. That needs a probe of the exe and AOT tiers and Lua's
  `luaD_rawrunprotected` under every tier first. (b) gcc-torture 960116-1, 20001101 (#46) and pr17252 (#47) pass
  under `-jit` now (checked one by one on the pin), so the `--tier jit` ratchet can take them. (c) F101: a `while (true)` that no `break` leaves
  ends the function wherever its return stands, so the trailing zero `return` after it can go (P9.2's rule
  widened, a criteria gain). (d) F93/#43: the solid LSR spill is gone at the IR level. The sieve JIT cell and the
  `solid_context` S/N need one exclusive run before #43 closes. (e) F95: the fixture's record views no longer
  miscompile under `strict_aliasing: true`, so whether the root `options strict_aliasing = false` is still worth
  its line is an exclusive A/B. (f) #49 (primes interp) is not re-measured on this pin.
- **P9.31 Working AOT** (ruling 38 addenda 17 and 20 item 3; AOT as a full tier for every port, on daScript
  `6401904cf9`). Step 1, the audit (2026-11-14, `/root/notes/research/aot/audit.md`): AOT output equals native
  on every port that converts (PureDOOM demo1-3, Lua suite, benches, error checks and luac `-o`, plmpeg-stream,
  binjgb, h264bsd-mp4, the 20 perf kernels; both variants). No daslang defect: fork #18 is fixed on the pin
  (probe PR #214), and fork #48 (global reads as `das_global<T, mnh>` probes) is by design, since `solid_context`
  "prohibits AOT". Everything still missing is ours. Step 2, the harness (2026-11-14):
  PR #215 `run_tier`'s exe and aot build once and reuse the binary while its build key stands
  (`converter/ARCHITECTURE_TIERS.md#build-reuse`; `lane_binary` too); PR #216 `lua/run.das --tier exe|aot` for
  `--run`, `--error-check`, `--suite-check` and `--luac-check`, one binary per layout and variant in the layout's
  folder (this closes P8.15 (a)); this row's PR: `perf/ARCHITECTURE_EXCEPTIONS.md` drops `switch_local` / aot
  (it has a cell now; result equals native) and records #48 as the contract. Verified on the PC through `heavy`,
  no timing: Lua under `--tier aot` in source, source-cut and single and both variants (readable, fast with
  checks off): error checks 8/8, suite 30/30, luac `-o` 33/33 byte for byte, each; a second run says `aot binary
  reused`; luac-check went from about 17.5 min (33 host builds, audit) to about 1.6 min wall (one build), which is a
  wall-clock indication from the logs, not a measurement. PureDOOM (source layout) under
  `doom/run.das --run --tier aot`: demo1-3 in sync, 2664 / 5444 / 2743 tics. The host is built once at demo1, and
  demo2 and demo3 reuse it (the binary's mtime does not change). The three demos took about 3.5 min wall in all,
  about 10 min in the audit (a build per demo).
  Logs: `/root/notes/parallel/aot2_logs/`.
  This row closes, by reference, these dated notes; their lines stay as written: the Lua AOT lane "not yet" /
  "neither builds nor runs" in P5.1a, P5.1b2, P5.4 and P5's exit criterion, which is now met for AOT (the lanes compile and
  run the benchmarks, and the suite passes under AOT); the AOT "goto past an initialized local" gap as open
  (lookibed/daScript#18) in P4.9, P5.1a, P8.4 (m) and P7.0. Step 3 is not done here and is the lead's: the AOT lanes on in
  the ports publish (`ports/publish.das` leaves them off by default; `ports_render.das` already has the columns)
  and in the A/B, both variants. Timing only under `heavy --exclusive`, each binary built before the exclusive
  job as a normal job (the key makes the timed run reuse it, so no build lands inside the exclusive window).
  Doom's `run_converted` times the whole `run_tier` call, so its first run includes the build: build first.
  `sieve`, `matmul` and `str_copy` stay exception cells (#48).
  Step 3 (2026-11-14): PR #219 turns the AOT lanes on by default in the ports publisher and in doom `--fps`,
  interleaves samples across lanes (native first, then the das lanes forward and backward in turn) and reuses the
  native build by a key. PR #218 adds `compare --project --bench-only`, which times the bench over the kept work
  folder. Capture on box PC, daScript `6401904cf9`, conversion as `accac6c`; every binary was built first as a
  normal heavy job. Timed in two `heavy --exclusive` jobs, both `machine quiet (cpu busy 1%)`:
  `TIMING-aot-all` 08:46-09:13Z (kernels, projects, PureDOOM) and `TIMING-aot-lua` 09:17-09:58Z; 3 samples each.
  x native, readable / fast:

  | program | interp | JIT | exe | AOT |
  |---|---|---|---|---|
  | Lua (4 benches + suite) | 110.9 / 111.4 | 1.54 / 1.49 | 1.54 / 1.57 | 1.36 / 1.30 |
  | PureDOOM demo1-3 | 44.2 / 43.1 | 1.07 / 1.02 | 1.04 / 0.98 | 5.19 / 5.17 |
  | binjgb | 73.4 / 77.4 | 1.15 / 1.08 | 1.19 / 1.07 | 1.15 / 1.10 |
  | h264bsd-mp4 | 59.6 / 60.9 | 1.05 / 1.00 | 1.05 / 1.00 | 1.13 / 1.15 |
  | plmpeg-stream | 29.4 / 29.9 | 0.98 / 0.98 | 1.02 / 1.03 | 1.08 / 1.09 |

  Lua's exe column covers the four benches only: the exe binary does not load the crt module from the
  test-suite folder (a relative module path). The numbers are in the variant files' `results.speed`,
  `compare/results_linux.json` and `doom/results_linux.json`. The predictions,
  `/root/notes/predictions/2026-11-14-aot-capture.md`, scored 18 of 20 readable cells; the misses are
  PureDOOM AOT (5.2, predicted 1.3-4.0) and Lua AOT (faster than predicted).
  Open from this capture:
  - (a) PureDOOM AOT at 5.2x native, against JIT and exe at 1.0-1.1. The suspect is #48 (Doom's globals read
    through `das_global` probes); it is not yet profiled.
  - (b) checks off is slower than safe in places: binjgb interp 1.05; the Lua exe lane on nbody 1.05 and on
    spectral_norm 1.03; h264bsd-mp4 and plmpeg-stream interp 1.02. Every one is outside its spread.
  - (c) Lua's exe test-suite cell, the module path.
  - (d) The perf kernels' AOT lane was timed by the capture script over `perf/work` (17 kernels; aot/exe
    geomean 1.01 over the 14 non-exception kernels; sieve 8.1, str_copy 3.6, matmul 1.6, switch_local 1.67 x
    native). `perf/results_linux.json` is not re-recorded, since `perf/run.das` converts inside its run.
  Correction to step 1 (2026-11-14, ruling 38 addendum 25, `/root/notes/research/aot/aot25_root_cause.md`):
  fork #48 is not by design. The probe does not come from `solid_context`: `aot_cpp.das` `visitExprVar` spells
  every global access in a function body `das_global<T, mnh>` with or without it (the bodies are identical), and
  `options.rst`'s "prohibits AOT" speaks of classic AOT, where a function links into other programs' contexts;
  the standalone `-ctx` context of the AOT tier is one fixed program whose constructor asserts every global's
  offset. It is a daslang emitter gap (addendum 16 class: daslang issue), and #48 is reopened with a das-only
  repro. Open item (a) is answered by it, and so are the sieve, str_copy, switch_local and matmul cells of (d):
  the same generated C++ with the reads rewritten to `das_global_solid` runs PureDOOM demo1 5.56 -> 1.14, sieve
  8.21 -> 1.63, str_copy 3.60 -> 1.40, switch_local 1.65 -> 1.00, matmul 1.59 -> 1.01 x native (`TIMING-aot25`,
  exclusive, machine quiet, 5 samples). No clean workaround exists on our side (no option or annotation reaches
  the path; hoisting global addresses into locals would put pointers into the shared output for one tier), so
  those AOT cells carry #48 in the ports tables. `perf/ARCHITECTURE_EXCEPTIONS.md` restates the cause.
  Step 4 (2026-11-14, addendum 22): the three programs P9.32 made convert whole, captured. A normal `heavy` prebuild
  (`/root/notes/parallel/aotfinal_capture/prep.sh`, `compare --project` per variant, cb35b34) passed native,
  interp, JIT, exe and AOT for wasm3, doomgeneric and quakegeneric, both variants, our side and Rust's. Then one
  `heavy --exclusive --label TIMING-aot-final` job, `machine quiet (cpu busy 1%)`, ran `--bench-only`, 3 samples,
  with the variants alternating. Predictions were written first (`/root/notes/predictions/2026-11-14-aot-final.md`)
  and every range held; the hedge that a wasm3 cell might be suspect did not happen (spreads 0.2-10.5%).
  x native, readable / fast:

  | program | interp | JIT | exe | AOT |
  |---|---|---|---|---|
  | wasm3 | 56.9 / 52.2 | 2.79 / 2.63 | 2.61 / 2.57 | 1.59 / 1.62 |
  | doomgeneric | 43.3 / 42.3 | 1.08 / 1.03 | 1.08 / 1.03 | 3.69 / 3.64 |
  | quakegeneric | no bench | no bench | no bench | no bench |

  quakegeneric's compare row has no bench unit, so it has correctness only, which passes on every tier. The
  numbers are in the variant files' `results.speed` and in `compare/results_linux.json`'s three entries.
  Rust on the same runs: wasm3 64.4 / 2.63 / 2.59 / 1.49; doomgeneric 33.5 / 1.06 / 1.08 / 3.69. Its AOT now
  builds within the limit.
  doomgeneric's AOT at 3.7x, against JIT and exe at 1.0-1.1, is #48: the exclusive A/B of 2026-11-16 (7
  samples, medians, c32c329 on the pin, readable) gives native 117.1 ms, AOT 428.4 (3.66x) and, with
  `aot_cpp.das` patched to read each global at its fixed offset, 132.2 (1.13x); its cell is in
  `ports/upstream_cells.das` (#243).
- **P9.32 The whole-program blockers of wasm3, doomgeneric and quakegeneric** (ruling 38 addendum 22 item C;
  the audit `/root/notes/research/aot/blockers.md`, its rows W1-W4, D1-D8, Q1-Q6). Our side fixed in the audit's
  order, a PR each, until each program converts whole and runs under interp, JIT, exe and AOT with the native
  output, in both variants. D1 (doomgeneric's alignment-only packed records, F51) took the owner's ruling (a), addendum 23.
  Step 1 (W4, D7, Q4): a compare project row carries the program keys of our side's sidecar (`marshal`,
  `over_indexed`, `padded`) into the whole conversion, so the committed capture, the criteria and the ports
  publisher convert with them; a file converted alone leaves them out (the converter refuses a key naming a
  record the file does not declare).
  Step 2 (W1): the converter predefines `__STDC_NO_VLA__` as 1 (C11 6.10.8.3, an implementation without VLAs;
  `CONVERTER_DEFINES` of the dumper, the criteria's preprocessing too), so wasm3's `M3_HAS_VLA` takes its
  fixed-size `argTypes`; VLAs stay out of scope.
  Step 3 (D5, Q3's `fgetc`): the crt module binds `strcasecmp`, `strncasecmp`, `strdup`, `fputc`, `fgetc` and
  POSIX `mkdir`, and the emitter maps them (`CRT_CALLS`, their effects in `summaries.das`). `fscanf` follows
  as its own step.
  Step 4 (W2): a flexible array member may start in the record's tail padding (wasm3's `M3FuncType`, at 14 of
  16): the check is now that its offset rounded up to the other fields' alignment is clang's size, so
  `{ int n; char c; char d[]; }` converts too; its decay keeps clang's offset.
  Step 5 (W3): a fold site passing a `void *` where another expansion of the macro passes a typed pointer stays
  expanded (`overload`), decided program-wide (`flag_typed_pointer_arguments`), since das finds a `T?` call
  ambiguous between a `T?` and a `void?` overload (lookibed/daScript#57); wasm3's `m3_Free` sites then fold.
  Step 6 (D6, Q2, Q1): a reference to a function whose type at the site is not its definition's (declared
  without a prototype) is reinterpreted to the site's type; a call with arguments through `T (*)()` calls the
  function the promoted argument types spell; a pointer to a variadic function is
  `function<(fixed...; CVaList) : R>`, its value the function's list-taking adapter `f__va_list`.
  Step 7 (D8, Q3's `fscanf`): crt's `malloc` gives a block of 128 KiB and up zeroed (`calloc`), as a fresh native
  process's fresh pages give it, so a program reading memory it has not written (Doom's zone) reads what native
  does; the audit's process-wide `mallopt(M_MMAP_THRESHOLD)` made the converter itself crash on quakegeneric's
  whole conversion (a latent host memory bug, not root-caused). `fscanf`/`vfscanf` are c_runtime's, each piece of
  the format the CRT's own `fscanf` over the stream.
  Step 8 (D1, owner ruling 38 addendum 23 choice (a), and D4): an alignment-only packed record (every field at its das offset,
  das's size; `mapthing_t`, `wadinfo_t`, `filelump_t` and Doom's other map records) is a plain das struct aligned
  above clang's 1; a record holding one where das would move it, and a union holding one, fail closed; `pcx_t`
  stays marshal-only. The owner's condition, a probe of arrays of such records at odd addresses copied and read
  in loops on all four tiers, passes (`probes/test_misaligned_records.das`, F110). A scalar field's address in a marshal-only record
  is the record's bytes plus the field's offset, no longer `addr` of its reader (D4).
  Step 9 (Q5): the sidecar key `flat_indexed` (a program key, in the compare row of quakegeneric:
  `texinfo_t.vecs`, `mtexinfo_t.vecs`) lists array-of-arrays members whose inner index the program runs past a
  row into the next (C11 6.5.6's undefined behaviour); that index goes through the row's decay, unchecked, the
  row index still checked. `checks: off` is no substitute, since the AOT host keeps its range checks.
  Step 10 (Q6): a setjmp site's `recover` rethrows through `c_jmp_rethrow()`: a longjmp to another buffer as
  "longjmp", any other panic with its own message (the context's `last_exception`), where it said "longjmp".
- **P9.33 `switch_dispatch` `table`: the dense switch flat** (ruling 38 addenda 29 and 30; the research
  `/root/notes/research/goto_table/report.md`). A third value of the option and the sidecar key, off by
  default; `chain` and `goto` output byte-identical to main's (Lua's source tree and six switch fixtures).
  Done, first PR (branch `p9.33-switch-table`): a dense switch (8 or more values in int's range filling half
  of [lo, hi], fallthrough allowed) is one jump and das labels at its parent's level, with no loop, flag or
  case test: `goto _cond + base` past a bounds guard when every value of the range is a case, else
  `goto _<function>_cases?[_cond - lo] ?? D` through a module-level `let private` table of label numbers;
  Duff's device is recognized by its shape (`converter/ARCHITECTURE_EMITTER_CONTROL.md`, The flat dense
  switch, Duff's device). Flat switches: Lua 14 (5 by value, 9 by table; `luaV_execute` 2568 -> 2461 lines),
  PureDOOM 8, binjgb 11. Under `table`: Lua's suite 30 of 30 and luac 33 of 33 (interp, JIT), PureDOOM demos
  1-3 in sync (interp, JIT), binjgb as native (interp, JIT, exe, AOT), c-testsuite 204 and gcc-torture 1205
  expected passes held. Found: the interpreter lands a label of a block with a `finally` section and a local
  one statement early (lookibed/daScript#63; binjgb never ended), so a `for` body with a das label at its
  level steps by the increment-first flag.
  After the review (`/root/notes/research/goto_table/review242.md`): the `finally` rule covers a label in any
  plain block under the body, in every mode, so chain and goto change for one shape that never ended under
  the interpreter on main (fixture `p9_for_labels.c`); the 17 `perf/<kernel>@table` readability keys are
  recorded (each equal to its default key: no kernel has a dense switch).
  That re-record also lowered `c_function` of the ten `lua/lua` readability keys by one (697 -> 696, single
  692 -> 691, source-cut 710 -> 709): a drift from main, not from PR #242. The capture was last recorded on
  11-13, and main's converter at 0b328d4 and the branch's give the same Lua text under chain and goto.
  Second PR (branch `p9.33b-switch-table-ab`; the owner waived `converter/REVIEW.md`'s "in the same change"
  for these): the `interp-table` perf lane (its cells come with the next perf re-record, a timing run; no
  kernel has a dense switch), the Lua `@table` readability keys with the criteria rows `lua/lua@table` and
  `lua/luac@table`, a function of `p9_for_labels.c` holding that a das label in an `if` arm or a nested loop
  under a `finally` block runs as native in every mode, and the exclusive A/B below.
  The captures: readability 1834 inputs, the two new keys alone (no existing key changed; every raised total
  is their sum: `lua/lua@table` 205 gotos and 248 labels against the default's 39 and 14 and `@goto`'s 93
  and 266); criteria 1621 inputs, the two new rows alone, totals `lua/lua@table` 88.9 and `lua/luac@table`
  88.5 against the defaults' 88.9 and 88.5 and `@goto`'s 88.9 and 88.3.
  Predictions for that A/B (2026-11-16, written before any conversion or run of the arms; box PC, one
  exclusive job, 3 samples, every arm the readable knobs with `switch_dispatch` alone differing; arm time
  over chain's, below 1 faster; `/root/notes/predictions/2026-11-16-switch-ab.md`): Lua interp goto/chain
  fib 0.50-0.62, binary_trees 0.68-0.80, nbody 0.62-0.74, spectral_norm 0.56-0.68 (P7.0c2's ratios hold)
  and table/goto 0.90-1.00 on all four (one case test and the loop's restart fewer an opcode); Lua JIT
  goto/chain 0.72-0.82, 0.88-0.96, 0.76-0.86, 0.74-0.84 and table/goto 0.97-1.03; PureDOOM demos 1-3 fps,
  both tiers, both arms over chain 0.98-1.02 (no flat switch in the drawers); binjgb decode interp
  table/chain 0.50-0.80 (the 256-opcode chain becomes one table jump), goto/chain 0.55-0.90 if the goto arm
  takes the opcode switch, else 0.98-1.02; binjgb JIT table/chain 0.97-1.10, goto/chain 0.97-1.05; every
  arm's output native's.
  Done (one exclusive job, `machine quiet (cpu busy 2%)`, box PC, main fe269f2, pin 6401904cf9, 3 samples a
  cell, the arms' order rotating with the sample; `/root/notes/research/goto_table/ab/`: `prep.sh` as normal
  jobs, then `heavy --exclusive --label TIMING-swab --max 8G -- bash cap.sh 3`, `summarize.py` over `run/`).
  Arms: the readable knobs with `switch_dispatch` chain, goto or table. Medians, arm time over chain's (for
  PureDOOM chain's fps over the arm's), below 1 faster; spreads at most 3.7%:

  | workload | tier | chain | goto | table | goto/chain | table/chain | table/goto |
  |---|---|---:|---:|---:|---:|---:|---:|
  | Lua fib | interp | 53.73 s | 26.97 s | 24.74 s | 0.502 | 0.460 | 0.917 |
  | Lua binary_trees | interp | 28.70 s | 18.19 s | 16.95 s | 0.634 | 0.590 | 0.931 |
  | Lua nbody | interp | 55.66 s | 38.86 s | 36.44 s | 0.698 | 0.655 | 0.938 |
  | Lua spectral_norm | interp | 72.06 s | 44.28 s | 40.36 s | 0.615 | 0.560 | 0.911 |
  | Lua fib | JIT | 0.506 s | 0.395 s | 0.387 s | 0.780 | 0.764 | 0.980 |
  | Lua binary_trees | JIT | 0.515 s | 0.468 s | 0.449 s | 0.909 | 0.872 | 0.959 |
  | Lua nbody | JIT | 0.440 s | 0.363 s | 0.357 s | 0.825 | 0.812 | 0.983 |
  | Lua spectral_norm | JIT | 0.613 s | 0.496 s | 0.495 s | 0.808 | 0.806 | 0.998 |
  | PureDOOM demo1 | interp | 225.2 fps | 224.5 fps | 224.6 fps | 1.003 | 1.003 | 1.000 |
  | PureDOOM demo2 | interp | 254.2 fps | 254.8 fps | 253.8 fps | 0.998 | 1.002 | 1.004 |
  | PureDOOM demo3 | interp | 220.2 fps | 220.5 fps | 220.0 fps | 0.999 | 1.001 | 1.002 |
  | PureDOOM demo1 | JIT | 9352 fps | 9365 fps | 9391 fps | 0.999 | 0.996 | 0.997 |
  | PureDOOM demo2 | JIT | 10073 fps | 10067 fps | 10189 fps | 1.001 | 0.989 | 0.988 |
  | PureDOOM demo3 | JIT | 8974 fps | 8998 fps | 9049 fps | 0.997 | 0.992 | 0.994 |
  | binjgb decode | interp | 4.374 s | 4.323 s | 4.312 s | 0.988 | 0.986 | 0.998 |
  | binjgb decode | JIT | 0.0715 s | 0.0724 s | 0.0731 s | 1.014 | 1.023 | 1.009 |

  x native: PureDOOM interp 43.5-44.2 and JIT 1.05-1.10 in every arm; binjgb interp 71.1 / 70.3 / 70.1, JIT
  1.16 / 1.18 / 1.19 (Lua's oracle is an `-O0` build, so no ratio to it is given). Every arm's output is
  native's: the four Lua benches' text, demos 1-3 in sync, binjgb's four lanes pass.
  Against the predictions: Lua interp goto/chain 3 of 4 (binary_trees 0.634, predicted 0.68-0.80: faster);
  Lua interp table/goto 4 of 4 (0.91-0.94: table is 6-9% faster than goto, 1.5-2.2x faster than chain); Lua
  interp table/chain 2 of 4 (fib 0.460 against 0.47-0.62 and binary_trees 0.590 against 0.63-0.80: both
  faster); Lua JIT goto/chain 4 of 4; Lua JIT table/goto 3 of 4 (binary_trees 0.959, predicted 0.97-1.03, its spread 2.9%);
  PureDOOM 12 of 12 (no arm moves a demo by more than 1.2%); binjgb JIT 2 of 2; binjgb interp a miss on both
  arms (0.99 against 0.50-0.80 and 0.55-0.90): both arms take `execute_instruction`'s opcode switch (9 and 11
  computed jumps in the tree) and the decode time does not move, so the chain arm's `c_switch` dispatch is
  not where binjgb's interpreter time goes; not profiled. This table is the "before" for the fused goto node.
  Left (review of #244): the `interp-table` lane times the default's text until a kernel has a dense
  switch, so a perf kernel with one is owed; the `p9_for_labels` `in_arm_and_loop` case falls into its
  below-level label but never jumps to it (n < 10 never dispatches i = 9); PureDOOM's ratio here is chain's
  fps over the arm's, the predictions file's the inverse (every cell hits either way).
- **P9.34 Interpreter profiles and pointer comparisons without `intptr`** (ruling 38 addendum 32; branch
  `p9.34b-intptr`). Fresh `--das-profiler` profiles on main ef5b135, normal `heavy` jobs at 4G (no timing):
  `perf/profiles/doom_demo1_interp.txt` (600 tics; `builtin intptr` 17.3% of self time, 19.0M calls, 12.97M
  of them `W_CheckNumForName`'s `lump_p-- != lumpinfo`) and binjgb's first, `perf/profiles/binjgb_interp.txt`.
  doomgeneric is not profiled: its bench prints a fixed 1000 frames, past the profiler's per-call event
  store under the cap. Why `intptr` costs: it is a daslib generic, and the interpreter's auto-inliner takes no
  generic instance (`ast_inline.cpp`, `fn->fromGeneric`; by design, F114), so each site is a das call; the
  JIT inlines it. The probe `probes/test_pointer_compare.das` holds das's `==`/`!=` between two data pointers
  and a relation over `reinterpret<uint64>` to C's answers on all four tiers. The emitter now writes
  `p == q` and `reinterpret<uint64>(p) < reinterpret<uint64>(q)`; `(intptr_t)p` keeps `intptr` (PureDOOM 14
  sites left, Lua 7). Predictions (`/root/notes/predictions/2026-11-16-intptr.md`, before any timing; after
  over before, fps for PureDOOM, seconds otherwise): PureDOOM interp demo1 1.05-1.12, demos 2 and 3
  1.04-1.12, JIT 0.98-1.02; binjgb interp and JIT 0.98-1.02; Lua interp fib 0.96-1.00, binary_trees
  0.93-0.99, nbody and spectral_norm 0.98-1.01, JIT 0.98-1.02.
  The exclusive A/B ran on daScript `2decba91d5`, both sides rebuilt there: before = main a936fe6, after =
  this branch, one `heavy --exclusive` job (`machine quiet (cpu busy 2%)`), before and after interleaved,
  3 interp and 5 JIT samples a cell, medians, after over before (fps for PureDOOM, above 1 is faster;
  seconds otherwise, below 1 is faster). The run's first try on `6401904cf9` was stopped for the repin and
  is not quoted. Correctness on the pin first: test_lowerings 202/202, the probe 7/7, Doom demo1 2664 tics
  in sync on interp and JIT, Lua error checks 8/8 on interp and JIT.

  | cell | interp | JIT | predicted interp | predicted JIT |
  |---|---:|---:|---|---|
  | PureDOOM demo1 | 1.016 | 1.000 | 1.05-1.12 miss | 0.98-1.02 hit |
  | PureDOOM demo2 | 1.016 | 0.985 | 1.04-1.12 miss | 0.98-1.02 hit |
  | PureDOOM demo3 | 1.023 | 0.989 | 1.04-1.12 miss | 0.98-1.02 hit |
  | binjgb decode | 1.000 | 0.996 | 0.98-1.02 hit | 0.98-1.02 hit |
  | Lua fib | 0.998 | 0.987 | 0.96-1.00 hit | 0.98-1.02 hit |
  | Lua binary_trees | 0.989 | 0.995 | 0.93-0.99 hit | 0.98-1.02 hit |
  | Lua nbody | 0.956 | 0.958 | 0.98-1.01 miss | 0.98-1.02 miss |
  | Lua spectral_norm | 0.988 | 0.957 | 0.98-1.01 hit | 0.98-1.02 miss |

  10 of 16 hit. The PureDOOM interp misses go the predicted way but gain about a tenth of the 17.3% the
  profile charged to `intptr`: the profiler inflates a small leaf call's cost, as the predictions warned,
  and the 30-40 ns per call estimate was high. The Lua nbody and spectral_norm misses are gains the
  predictions did not expect (no pointer compare was thought to be on their path); not profiled here, so
  the cause is open. Readability (`scripts/run_criteria.sh --filter`, both sides on the pin): PureDOOM
  `casts` 242.5 -> 235.3, `reinterpret` 71.1 -> 72.2, total 874.2 -> 868.2; binjgb `casts` 565.8 -> 564.5,
  total 1138.9 -> 1137.5. Prediction 6 holds for the casts and the reinterprets; the `[c_function]` half was
  not counted.
  binjgb's HALT path, a proposal (no code): 96.9% of `execute_instruction`'s 5.40M calls are the
  `CPU_STATE_HALT` case (counted by a copy of the module with counters), one `tick` and a return before the
  opcode switch, reached through `emulator_run_until` -> `emulator_step_internal` -> `execute_instruction`
  once per 4 cycles; P9.33's table arm did not move binjgb (0.986) because the switch is not on that path.
  The interpreter pays per HALT step two das calls (it declines to inline `execute_instruction` into
  `emulator_step_internal`: "caller frame growth budget exhausted"), the six local declarations C leaves
  uninitialized (`opcode`, `s`, `u`, `c`, `u16`, `new_pc`, each zeroed by das on entry), the `c_switch` over
  `INTR.state` with HALT its fifth case, and `should_dispatch`'s `enum_from_int(type<Bool>, int_of(...))`
  round trip. Candidates, cheapest first, each its own A/B: (a) sink a function-level declaration below
  every early `return` that precedes its first use (all six here: the HALT path returns before any of them
  is read or written, so it then declares none); (b) a
  `c_switch` whose cases are few and sparse tests the hot case first only with profile data, so not without
  a sidecar knob, left; (c) an opt-in form that outlines a large function's tail (here the opcode switch after the state
  dispatch) into a second def, so the head left is small enough for the auto-inliner to take into its caller (the
  frame budget then falls on the cold tail alone): the HALT step becomes zero das calls inside
  `emulator_run_until`'s loop. (c) is the one that removes the calls, and it is an output change (a new
  def per split function), so it is an opt-in flag first, measured on binjgb, Lua and PureDOOM.
- **P9.35 `crt` as a wasm64 package; PureDOOM compiled to wasm** (ruling 38 addendum 31 item 3; plan
  `/root/notes/parallel/r38_add31_wasm_plan.md` steps 2 and 3, toolchain `/root/notes/research/wasm/toolchain.md`).
  Done (branch `p9.35-wasm-crt`; the item converts no C construct, so no perf or readability
  re-record applies): `dasCRuntime/CMakeLists.txt` builds `liblibDasModuleCRuntime.a` under
  `emcmake` (memory64, threaded, wasm exceptions, no RTTI), `.das_package` declares it for
  `daspkg release wasm`, and `scripts/build_crt.sh --libcxx-host` builds the `crt` a libc++ cross-compile
  host loads (`dasCRuntime/ARCHITECTURE.md` section 8). Off the gates: `tests/test_crt_wasm.das` skips
  where emscripten, cmake or ninja is not on PATH (a toolchain no gate installs, so no phase lifts the skip; its arm runs
  wherever emsdk 5.0.7 is active, and refuses another emscripten than `VERSIONS.md`'s); `tests/test_build_crt.das`
  covers `build_crt.sh`'s refusals and the libc++-host configure without emscripten. First verified
  before the repin (superseded below: the pin then 6401904cf9, a libc++ host at 6f83af0855):
  a `crt` app through `daspkg release wasm` (the archive built by the hook) prints the CRT's answers under
  node; PureDOOM processed cross-compiled, linked with `-sMEMORY64=2`, plays demo1 under node 24 with all
  2664 tic hashes equal to `ref/freedoom2_demo1.log` (game loop about 0.9 s, indicative, a busy box).
  On the pin 2decba91d5, with the wasm host and its wasm64 archives rebuilt at that commit: daScript's
  wasm64 regression `web/test/fileinfo_constructor.cjs` passes, `dasCRuntime/tests` (with emsdk, so
  `test_crt_wasm` runs), `c_runtime/tests` and `ports/tests` pass 178 of 178, and the processed
  PureDOOM released through `daspkg release wasm` plays demo1 in Edge with all 2664 tic checksums equal.
  Browser host (branch `p9.35-wasm-web-2`): `web/puredoom/main_web.das` runs the processed port
  under daslang's web lifecycle (WebGL texture, GLFW keys, play and timedemo), `scripts/build_web.sh`
  builds the site for the ports repository's Pages (`web/ARCHITECTURE.md`; the WAD only in the deploy's
  artifact). Edge on box PC, demo1 timedemo: every tic checksum equal to the native log; its time is
  indicative only, not a result (a browser run, not exclusive); the same box, exclusive and quiet:
  native C 0.276 s, daslang JIT 0.448 s. The host reads daslang's clock, not `crt`'s `clock()`.
  The page's fps line and uncapped rendering (renders between tics; PureDOOM has no interpolation;
  checked in the browser only, no suite test: a timedemo with a render after every tic keeps all
  2664 checksums in both builds), and the C baseline
  (`web/puredoom_c/`, PureDOOM's own C by emscripten -O3 with the same flags and host): its demo1
  matches all 2664 checksums; headless Edge, alternating, indicative: C 0.521-0.525 s, daslang
  0.614-0.658 s (about 1.2x).
  Sound: Doom's sfx mix and music through dasAudio; Freedoom's music lumps are MIDI files, which
  PureDOOM's MUS player cannot read, so the host plays them with `web/puredoom/doom_midi.das` into a
  small General MIDI synthesizer (`doom_synth.das`); headless Edge, a temporary diagnostic line
  reading dasAudio's playback counters: music and sfx stream, 0 underruns.
  quakegeneric page (`web/quake/`): the converted engine under a host beside its generated entry,
  keys through `Key_Event`, the demo1 timedemo's first 100 frames held to the Rust repository's
  reference; the wasm `crt` archive carries glibc's `rand` (`dasCRuntime/src/glibc_rand.cpp`, held to
  the host's glibc by `tests/test_crt_rand.das`), as the frames depend on its sequence. Headless Edge:
  969 frames, the first 100 in sync with the native run (indicative). The Quake host gets no lint:
  lint compiles the engine under policies the generated code does not meet (a dead write in
  `pr_cmds`), so it never reaches the host; its formatting is checked.
  Left: emscripten's `clock()` under `-pthread` can return a
  negative value (`-75812969` in a three-line C test), which the Doom host's `work_started >= 0` check
  reads as "not started", so its `host: timed` line was missing in 2 of the 6 full wasm runs whose
  output was kept.
- **P9.36 Follow-ups of the repin to daScript `2decba91d5`** (ruling 38, repin 3; PRs #246, #247 and #249;
  notes `/root/notes/parallel/repin3/notes.md`). The pin fixed fork issues the converter still works around,
  and the repin's reviews left small items. Each line is a later row, resumed from here, none started:
  (a) the increment-first flag for a `for` body with a das label at its level
  (`converter/ARCHITECTURE_EMITTER_LOOPS.md`, `emit.das` `labels_at_level`, `test_switch_table.das`,
  `p9_for_labels.c`). The interpreter lands such a label right now (daScript `2d4b23b491`,
  lookibed/daScript#63, F113), so the `finally` form could take the labelled body again. That needs the suites
  and Lua, PureDOOM and binjgb under every tier and dispatch mode first.
  (b) the `void *` site of a typed-pointer macro that stays expanded (`flag_typed_pointer_arguments`,
  `converter/ARCHITECTURE_EMITTER_MACROS.md`): a `T?` argument picks the `T?` overload now (daScript
  `c5491d404d`, lookibed/daScript#57, F111), so wasm3's `m3_Free` sites could fold.
  (c) F59 and F111: `ptr - n` on a computed pointer compiles, and a `null` first arm of `?:` takes the other
  arm's type, so the negated-count spelling and the `default<T?>` first arm could go (a readability gain).
  (d) F107 and F108: the splice of an expression-body `[inline] def` is the expression as written and a call
  under `addr(...)` is spliced, so whether the `[c_macro]` function-macro fold (P9.20) is still faster than
  `[inline]` under the interpreter is one exclusive A/B; F107's timings are those of `abf1d40e35`.
  (e) `docs/probe-findings.md`: the probe-cell titles of F59, F107, F108 and F109 name runs that were renamed;
  F112's probe compiles both walks in one child and should use one child per walk.
  (f) the default-stack fix (#249): `STACK_SPARE` 4096 is not derived from what
  `compare/tests/test_perf_compare.das` needs (1 to 3 KiB of its slack is unpinned); `dump_tu` and `emit_tu`
  rely on a fresh struct and reset nothing; `doom/convert_check.das` and `metrics/switch_census_count.das`
  still hold a `Dumper` or an `Emitter` in a frame (their entries run under a 1 MiB stack).
  (g) the ratchets on the pin: c-testsuite passes 204 with 00187 newly passing (it writes `fred.txt` into the
  working folder, so the run leaves an untracked file), gcc-torture passes 1210 with 921019-1, 980605-1,
  pr15296, pr67037, pr68390 and pure-1 newly passing: one `--update` each records them. csmith does not run on
  the WSL box (gcc 11.4.0 against the pinned 14.2.0); its 182 seeds are owed to a box with the pinned gcc.
  Closed (2026-11-17, owner ruling 38 addendum 36 item 3): the box has gcc-14 14.3.0 (ppa:ubuntu-toolchain-r/test;
  jammy ships no 14.2.0) beside the system gcc 11.4.0; `VERSIONS.md` pins 14.3.0 and `suites/csmith/run.das` takes
  the reference compiler from `CC` (default `gcc`). The full run (`CC=gcc-14 --seeds 0 --update`, daScript
  `b7d8f6f52f`) passed all 182 seeds; `expected_pass.txt` re-recorded byte for byte the same, no seed newly failing.
  (h) an unbounded `dastest --isolated-mode` probes run is OOM-killed under `heavy --max 4G` (32 JIT children
  at once, exit 137 each: 50 reds, about 39 of them false); the preflight's two workers run clean. A suite `--timeout`
  ends dastest but leaves the compare suite's never-ending lane child running.
  (i) Lua's exe test-suite cell is still P9.31 (c): the exe names the crt module by a relative path, so it
  loads from the repository root (error checks 8 of 8, luac 33 of 33) and not from the test-suite folder
  (0 of 30). (j) `docs/performance.md` and the ports tables carry the numbers of the `6401904cf9` capture
  until the re-capture on this pin (step 6, a timing run, not started without a ruling).
- **P9.39 The real `fast` variant per published program** (ruling 38 addendum 38 item 1; resumes the
  addendum-19 search of P9.29 on daScript `b7d8f6f52f`, its numbers on `6401904cf9` void; work folder
  `/root/notes/parallel/add38/`). Per program (Lua with luac, binjgb, h264bsd-mp4, plmpeg-stream, wasm3,
  doomgeneric, PureDOOM) the knobs of `VARIANT_KNOBS` are searched one at a time from the `readable` knobs on
  the JIT lane (the `fast` default), the winners combined, and the combined set timed on all four tiers;
  quakegeneric has no bench unit, so its `fast` is `readable` with checks off and the reason. An arm whose
  converted text equals the readable one is pruned untimed; every timed arm's output is native's.
  Predictions for batch 1 (2026-11-17, before any timing; `/root/notes/predictions/2026-11-17-add38-b1.md`;
  arm time over the readable arm's on the JIT, below 1 faster): Lua `switch_dispatch` table fib 0.72-0.82,
  binary_trees 0.84-0.92, nbody and spectral_norm 0.76-0.86 (P9.33's ratios); checks off 0.88-0.98 on every
  program (PureDOOM 0.92-0.98); `jit_whole_program` off for Lua 1.05-1.60, on for PureDOOM 0.85-1.00 and for a
  one-module project 0.95-1.02; PureDOOM single layout 0.85-1.00; `strict_aliasing` 0.94-1.01 where the program
  is clean; inline helpers, while loops, macros expanded, the forms off, source-cut and first-member
  reinterpret (over checks off) each within 0.97-1.05. Combined `fast` over readable: Lua 0.68-0.82, PureDOOM
  0.82-0.96, the projects 0.90-0.99.
  Batch 1 (2026-11-18, `heavy --exclusive --label TIMING-add38-b1`, `machine quiet (cpu busy 1%)`, box PC,
  branch at a77160d, pin `b7d8f6f52f` (the pin guard green before and after), 7 samples a cell, the arms' order
  rotating; `/root/notes/parallel/add38/`: `prep.sh` as normal jobs, `cap1.sh`, `summarize.py b1`). Every run's
  output was native's. JIT only; arm time over the readable arm's, geometric mean over the program's workloads
  (Lua's four benches, PureDOOM's demos 1-3, a project's bench), below 1 faster; `f` (first-member reinterpret
  with checks off) over checks off alone; `-` not an arm (its text equal to readable's, or the knob not
  applicable: one translation unit takes no layout, `strict_aliasing` only for a program clean under it):

  | program | checks off | table | jwp flip | inline | while | expand | forms off | strict al. | source-cut | single | f/k |
  |---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
  | Lua | 0.992 | 0.782 | 2.372 (off) | 0.969 | 1.017 | 0.970 | 0.974 | 0.973 | 0.930 | 1.071 | - |
  | PureDOOM | 0.946 | 0.993 | 0.955 (on) | - | 0.981 | 0.999 | 0.981 | - | 1.031 | 0.937 | 1.002 |
  | binjgb | 0.956 | 0.992 | 1.023 | - | 1.026 | 0.998 | 1.020 | 0.998 | - | - | 1.002 |
  | h264bsd-mp4 | 0.957 | 1.003 | 1.005 | 1.002 | 0.998 | 0.995 | 1.001 | 0.996 | - | - | 1.005 |
  | plmpeg-stream | 0.997 | 1.006 | 1.005 | 0.997 | 1.004 | 1.007 | 1.006 | 1.005 | - | - | 0.999 |
  | wasm3 | 0.967 | 0.995 | 0.997 | 0.990 | 0.995 | 0.999 | 0.993 | 1.001 | - | - | 1.007 |
  | doomgeneric | 0.960 | 0.994 | 0.994 | 0.990 | 0.996 | 0.999 | 0.986 | - | - | - | 0.999 |

  Found: first-member reinterpret does not compile on Lua even with checks off (error[31004] "cast requires
  unsafe" at `[c_macro]` fold sites such as `obj2gco(...)` in `lparser`), so Lua has no `f` arm; on every
  other program it changes nothing measurable over checks off. Predictions for batch 2
  (`/root/notes/predictions/2026-11-18-add38-b2.md`, before its timing; arm over readable on the same tier):
  Lua L1 (table, source-cut, inline helpers, macros expanded, strict aliasing, the three forms off) interp
  0.40-0.60, JIT 0.64-0.80, exe 0.66-0.82, AOT 0.75-0.97, and L2 (L1 with checks off) 0.36-0.57, 0.62-0.80,
  0.64-0.82, 0.75-0.97; PureDOOM D1 (single layout, jwp, checks off, while loops, forms off) interp 0.90-1.02,
  JIT 0.86-0.94, exe 0.86-0.95, AOT 0.95-1.03, and D2 (D1 in the source layout) 0.90-1.02, 0.88-0.96,
  0.88-0.96, 0.95-1.03; checks off on binjgb, h264bsd-mp4, wasm3 and doomgeneric interp 0.88-0.97, JIT
  0.94-0.98, exe 0.94-0.99, AOT 0.97-1.02, on plmpeg-stream 0.90-1.00 interp and 0.98-1.02 elsewhere.

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
  host flag that returns from `main` instead of `exit` for profiling runs (done in P7.0b4: the
  host's `-return-from-main`); (c) the JIT gap, 3.6-3.8x
  against Rust doomgeneric's 1.04x, unexplained: P7.0b2 did not reach it; P7.0b4 took it (Done: the
  JIT's per-access lookup of module globals, then the marshal `crt::memcpy` calls), P7.0b3 keeps Lua's
  interpreter residue.
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
  comparison table generated into `README.md` (now `docs/performance.md`); `scripts/run_perf.sh --from-scratch` and `--check`
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
  accessor calls) under the interpreter, the Rust translation beside. Doom's JIT gap (P6.7 (c)) and
  Lua's JIT residue went to P7.0b4 (ruling 31): this row keeps the interpreter residue.
- **P7.0b4 JIT profile: aliasing and vectorization** (ruling 31; the JIT half of P7.0b3): where
  Doom's and Lua's JIT code loses 2-4x against native while Rust doomgeneric loses 4%; a sampling
  profile, the hot loops' IR against clang's, Boris's two hypotheses tested, a hand edit per cause
  in a temporary copy of the output with the whole demo re-timed, a repro per daslang cause.
  Done as an investigation (branch `p7.0b4-jit-profile`; report
  `/root/notes/research/p7.0b4-jit-profile.md`, data `/root/notes/research/p7.0b4/`; box PC, speed
  build, demo1, every cell the median of an interleaved A/B run through `heavy`, spreads at or under
  6.1% but the last row's 12.4%). Method: `perf/sampler/`, an `LD_PRELOAD` timer sampler (100 us,
  RIP and the stack-top word, gated on the host's two `clock()` calls) symbolized offline against
  the JIT's cached `.dll`, self time per function on native and JIT. Doom demo1 JIT 4.18x native as
  converted (47.5% of all JIT samples in `jit_get_global_mnh`, the hash lookup of a module global
  per access, 67 calls in `R_RenderSegLoop`'s loop) -> 1.30x with `options solid_context` in all 39
  modules -> 1.10x with the builtin `memcpy` in the constant-size marshal accessors
  (`crt::memcpy(..., uint64(1))` is an indirect call per byte, 14% of the solid build) -> 1.02x
  with `unsafe_deref` + `hint(unsafe_range_check)` (per-pixel null and range checks, about 8%).
  Aliasing: no (clang reloads the same globals in `R_DrawColumn`'s loop, the JIT emits no TBAA at
  all and it costs nothing measurable, F83). Vectorization: no (native with `-fno-vectorize
  -fno-slp-vectorize` 0.2783 s against 0.2782 s; the JIT vectorizes none of the hot Doom loops,
  `--jit-opt-level 2` equals 3). Lua fib 30 10.8x and nbody 5.5x under JIT: 62-69% of the samples
  on the dispatch chain's compare lines (P7.0c3/P7.0c2), no global lookups. Unexplained:
  `R_RenderSegLoop` + `R_StoreWallRange` 1.3x and the `W_CheckNumForName` scan 1.7x after the
  edits, Lua's residue (about 3.4x of fib's 10.8x if the chain cost went to zero). The coder's
  part, done: `perf/tests/test_sampler.das`; the host's `-return-from-main` (P6.7 (b),
  `doom/tests/test_host.das`; real Doom under the profiler segfaults after the summary, 2.7 GB
  trace for 3 tics); the solid_context probe (P7.0m: default). Per demo (box PC, 3 interleaved
  rounds, report "Step 3"): demo1/2/3 JIT 3.90/3.47/3.44x -> solid 1.35/1.43/1.33x -> +memcpy
  1.10/1.14/1.27x (demo3 noisy, ±11.2%) -> +checks off 1.02/1.04/1.04x; the new host 3.97/3.28/3.39x.
  Facts F80-F83; upstream lookibed/daScript#36 (the lookup), #37 (`run_and_capture` reads a signal
  death as an exit code, found by the compare runner), #31 (das-fmt and `def f : T? =>`, re-confirmed).
  Rows: P7.0m, P7.0n, P7.0o, P7.0p.
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
  Done (branch `p7.0c2-goto-dispatch`): `switch_dispatch` `goto` (sidecar key, `--switch-dispatch`,
  `lua/run.das --switch-dispatch`; `chain` the default, `lua.c2das` unchanged) gives a dense switch
  (8 or more values in `int`'s range filling half of [lo, hi], no group falling into the next, not
  spelled open) a bounds guard and `goto _cond + (base - lo)`, a label per value, holes and the
  out-of-range target at `default` or the loop's end; a goto into another case jumps to its label's
  own das label (no re-dispatch, no sentinel). The interpreter runs it as the JIT does: the probe
  (`probes/test_goto.das` `test_goto_dispatch`) showed daScript#35 to be #8's fold, which an `else`
  on every case branch avoids, and lvm's segfault the loop's label claim (F60), which numbering the
  table below every C label avoids. Default vs opt-in on the same commit, in-process work: JIT, 7
  samples on a quiet box PC (`/root/notes/parallel/p7.0c2_ab3jit/table.md`): goto faster by fib 30
  1.32x, binary_trees 12 1.09x, nbody 20000 1.25x, spectral_norm 100 1.28x (spreads 1-7%);
  interpreter, 3 samples: 1.98x, 1.38x, 1.48x, 1.66x (spreads 1-5%). `dispatch_switch`'s
  composed program under the interpreter 22.3 -> 6.4 ms a run (3.5x; 121x -> 35x native), under
  the JIT 0.151 -> 0.177 ms (0.85x, one sample). Not a perf lane yet: perf's lanes carry the
  `--param-writes`, `--loops` and `--first-member` options only.
  The ports Lua tables carry the goto lane as the JIT, goto dispatch column in place of AOT
  (ruling 32; branch `fix/ports-goto-lane`): the publisher converts `lua` with
  `--switch-dispatch goto` into `lua/work/goto/`, the lane `jit-goto` runs it, `aot` is asked for
  by name only; the re-capture measures it.
- **P7.0c3 One `_goto` test per dispatch** (default; from P7.0b2): the matched-flag loop tests
  `_goto == 0` once per dispatch instead of once per case (about 1.28x fib, 1.13x binary_trees);
  for every build, the opt-in P7.0c2 above it.
  Done (branch `p7.0c3-one-goto-test`): a goto into another case stores a value no case holds into
  the condition (`var _condN`; one below the smallest case value, else one above the largest, an
  enum's through `enum_from_int`) before the re-dispatch, so every case test reads `_cond == K` alone
  and only `default` keeps `_goto == 0 &&`; cases spanning the condition's type keep the old form.
  The goto's own plain case cannot match on the restart (the `noconj` loop; a run test hangs without
  the store). The divergence from `docs/lowering-examples.md` (its Tier 2 tests carry no goto
  variable) is as P7.0c's. Measured on box PC (3 samples, interleaved A/B, in-process work, the
  converter at 2444a73 against main 9c6248f, every spread at or under 9%; table
  `/root/notes/parallel/p7.0c3_ab3/table.md`): interpreter fib 30 1.21x, binary_trees 12 1.16x, nbody
  20000 1.22x, spectral_norm 100 1.24x faster; JIT fib 3.52x (0.307 -> 0.087 s work), binary_trees
  1.58x, nbody 2.45x, spectral_norm 3.07x faster, outputs equal.
  `dispatch_switch` under the interpreter 197.9x -> 115.4x native (converted over the plain
  cases restored to the chain 0.45x -> 0.28x); perf's `flag-chain` rewrite now finds the new
  plain case, restores plain cases only (the flag cases keep `_flag ||= _cond == K`). `lua/tests`' `spin`
  stand-in returns at once natively and counts forever converted, so the suite-check test's timeout
  verdict no longer depends on the box's speed (it passed in 4.9 s on this box).
- **P7.0b5 TBAA and vectorization under the JIT** (ruling 33 items 1-2; the compiler's own answers in place
  of P7.0b4's timing argument). Done as research (branch `research/r33-tbaa`, report
  `/root/notes/research/r33-tbaa-vectorize.md`, box PC, 3 interleaved rounds through `heavy --low`): the JIT
  emits no `!tbaa` (F89, lookibed/daScript#39), so a float loop bounded through an `int*` runs 8.55x native
  where clang with strict aliasing vectorizes and without it is "uncountable" (the JIT is 1.21x that no-TBAA
  native); where TBAA is not the gate the JIT vectorizes on its own at AVX2 width (sum 0.72-0.80x perf's
  generic native, 1.01x `-march=native`). Clang's remarks refuse every hot Doom renderer loop (gathers
  without bounds, calls, a global counter) and the JIT's dump holds no vector type there: the renderer's
  1.07-1.31x is not a vectorization gap. dasLLVM exposes no remarks (F90, lookibed/daScript#40). Probe
  `probes/test_jit_tbaa.das`. No converter change follows; `blit`'s 1.23x is a loop-form residual (P7.0v2).
- **P7.0c4 Goto as the JIT default, or a chain order fix** (candidate; from P7.0b2, measured by
  P7.0p place 4): under the JIT LLVM recovers a jump table from P7.0c3's chain for the opcodes up
  to 0x44 only (`cmp $0x44,%eax; jbe; jmp *%rax`, F88): its switch recovery stops at the first
  flag-merged case (`_flag ||= _cond == OP_RETURN1`), so the cases above 0x44 (RETURN1 72 and
  FORLOOP 73 among them, up to EXTRAARG 82) fall through `cmp $0x45; je; cmp $0x46; je; cmp $0x47;
  jne` and the compare chain. Goto mode (P7.0c2) removes it: fib 30 2.50x -> 2.02x native, nbody
  20000 1.34x -> 1.05x (box PC, in-process work, 3 interleaved samples). The candidate is one of
  two, measured against P7.0c3: goto as the default under the JIT (ruling 23 keeps the plain-case
  form the idiomatic default, so a per-tier default needs a ruling), or the flag cases emitted after
  the plain ones so every plain `_cond == K` test sits first and the recovery covers all 83 cases.
  The old candidate, a binary split of the chain (7 tests for 83 cases), stays the interpreter's
  option for builds without the P7.0c2 opt-in.
  Closed by owner ruling 36 section 1 (2026-11-08): goto stays an opt-in (`--switch-dispatch goto`),
  no per-tier default, by the rule "readable by default, fast as an option". Its readability price on
  Lua (the 11-06 trees, source layout): 225 more `label N:` and 22 more `goto` across the program (14
  -> 239 labels, 55 -> 77 gotos, 29 355 -> 30 089 lines), `luaV_execute` 2731 -> 2984 lines with 89
  labels. The ports' `jit-goto` column stays a column; the criteria rows `lua/lua@goto` and
  `lua/luac@goto` carry the price in `metrics/criteria_linux.json`: totals 79.7 and 79.2 against the
  defaults' 79.7 and 79.3.
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
  Over-count (found 2026-11-07, `metrics/tests` `test_literal_counts` red on main): the
  readability counter walked the macro's expansion, a `reinterpret` at the call the text does not
  spell, so every converted `enum_from_int` call counted as a reinterpret site in the captures
  since this item. Fix (branch `fix/readability-macro-sites`): a `reinterpret`, `unsafe_block`,
  `goto` or `label` site counts only where the text at its column spells its keyword (daslang
  marks no call-macro expansion: `probes/test_ast_facts.das`, lookibed/daScript#42); a bare
  literal argument (`enum_from_int(type<E>, 7)`) is no `literal_named` site: the walk visits the cast, not the literal.
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
- **P7.0m `options solid_context` in generated modules** (from P7.0b4, place 1): a non-solid
  module's global costs the JIT a `jit_get_global_mnh` call per access, a perfect-hash probe LLVM
  cannot hoist out of a conditional path in a loop (F80: the repro 5.4x native, 11.7x of the solid
  build; Doom demo1 JIT 4.18x -> 1.30x, box PC, 7 interleaved rounds). The emitter writes
  `options solid_context` in every generated module, the default: `probes/test_solid_context.das`
  builds and runs a solid two-module program requiring `c_runtime`, globals and cross-module `@@`
  callbacks stored in a global included, under interp, JIT, exe and the AOT host alike (daslang's
  doc says it prohibits AOT and patches; the AOT context is the generated C++, F80, F49; nothing
  in `c_runtime` reloads code or runs in another context, so the patch caveat does not apply). Tested on the fixtures, measured per demo (P7.0b4 step 3). Upstream beside it:
  lookibed/daScript#36.
  Done (branch `p7.0m-solid-context`): `assemble_module` writes `options solid_context` after
  `options indenting = 4` in every module of every layout, the `<entry>_link.das` slot module
  included, a `.das.inc` fragment none (included text); opt-out `--no-solid-context` and the
  sidecar's `solid_context: false` (default true), for a module another context runs or a patch
  reloads. Tests: the header in the source, source-cut and single layouts and the slot module, both
  opt-outs, the sidecar key, the fragments; the tree and cut fixtures (a global of one module written
  and read in another, the slots written at `[init]`) run under interp, jit, exe and aot. Doom's 39
  speed modules carry it; the sync build holds demos 1-3 under the JIT. A/B, A main c36ba64, B the
  branch, box PC, 3 interleaved samples (`/root/notes/parallel/pc-p7.0m-ab.sh`, `p7.0m_ab/`):
  Doom JIT demo1/2/3 3.86/3.28/3.18x -> 1.30/1.38/1.29x native (spreads under 6%); interp 62.7/63.4/
  60.3x -> 59.0/59.5/57.6x (1.05-1.06x faster). Lua interp unchanged (0.97-1.03); Lua JIT 0.91-0.99
  (fib 30 and nbody 20000 6% and 9% slower in a 5-sample re-run, spreads 7-8%; binary_trees 1.09x
  at 13%). Kernels, B over A: switch_local JIT 5.59x -> 1.02x native, exe 6.34x -> 1.14x; matmul
  interp 84.4x -> 56.9x; fib_loop flat; blit exe 7% slower (2.05x -> 2.24x, spreads 1-2%, re-run
  2.17x); va_forward JIT 8-20% slower at 15-21% spread; dispatch_switch interp 1.00, JIT 1.06x;
  switch_local's aot lane fails to build on both sides (`goto` across an initialization, pre-existing).
  The JIT and exe slowdowns are unexplained: row P7.0q. The published READMEs (perf, compare, ports) keep
  their captures: the re-capture is a phase-end item.
- **P7.0n Constant-size marshal reads through the builtin `memcpy`** (from P7.0b4, place 2): a
  marshal accessor (`read_post_t_topdelta`, `read_patch_t_width`) spells a one-byte read
  `crt::memcpy(addr(r), bytes + ofs, uint64(1))`, an indirect call into dasCRuntime per byte under
  the JIT, 14% of the solid build's samples; the builtin `memcpy` is an LLVM intrinsic that folds
  to a load (F81: 0.22 s against 0.011 s on 1e8 reads, C 0.018 s). The emitter writes
  `memcpy(dst, src, N)` with an `int` size (the builtin, not crt's `uint64` overload) or a typed
  load for a constant size; Doom demo1 JIT 1.30x -> 1.10x (box PC). Shorter and faster, so the
  default; tested on the marshal fixtures, measured on the kernel and the demo.
  Done (branch `p7.0n-builtin-memcpy`): every marshal reader and writer copies through the builtin `memcpy` with an `int` size (62 Doom sites, 0 left; no `require crt` for it); probe `test_stdlib.das`; JIT/exe/AOT runs of three marshal fixtures. A/B on the solid build (main 784b0a3 against the rebased branch), box PC, 3 samples interleaved, median and spread: Doom JIT demo1 0.358 s ±19% -> 0.313 s ±5% (1.15x; 1.27x -> 1.11x native), demo2 0.738 ±8% -> 0.577 ±14% (1.28x; 1.44x -> 1.12x), demo3 0.389 ±13% -> 0.324 ±13% (1.20x; 1.31x -> 1.09x); the interpreter 0.98-1.04x, inside its spreads. Before P7.0m (no solid context) the JIT gain was 1.05x, 1.09x and 0.95x (inside the spread): the call is a larger share once the context is solid. perf/kernels has no marshal-read kernel.
- **P7.0o Speed opt-in: `unsafe_deref` and `hint(unsafe_range_check)` on every converted function** (from
  P7.0b4, place 3; P7.1's O2 and O3, now measured): per-pixel `null_check` on `dest`,
  `dc_source + x`, `dc_colormap + x` (a GEP result is never provably non-null) and fixed-array
  range checks in `R_DrawColumn`, `R_DrawSpan` and `R_RenderSegLoop`, about 8% of the solid+memcpy
  build; Doom demo1 JIT 1.10x -> 1.02x (box PC, spread 12.4%: re-measure). A converter option (CLI
  flag and sidecar field, default off) adds both annotations to every converted function, with or
  without `[c_function]`; the checked form stays the default (ruling 23), both modes tested and
  measured, demo sync re-verified with the flag on (P7.1). Measured on Lua by P7.0p (box PC, in-process work, 3 interleaved samples;
  both annotations hand-added to all 776 functions of the single-layout build): fib 30 -3% chain /
  -10% goto, nbody 20000 -2% / -5%. `luaV_execute` carries 400 `test/je` null-check pairs in 9642
  instructions against native's 48 in 4770, and the unsafe copy grows to 62.8 KB (the annotations
  change inlining too, so the number is the net of both); nbody's inlined `luaH_getshortstr` (1.5x
  native, 3 of its 7 `jit_exception` sites on the node walk) is covered by the same flag.
  Done (branch `p7.0o-unsafe-checks`): `--checks safe|off` and the sidecar's `checks`, default `safe`; under `off` both annotations
  on every converted function (Lua 1080, Doom 762) and a banner line; probe `test_unchecked.das` (F84), tests `test_checks.das`. Risk: a
  wrong C program reads its neighbor or dies by SIGSEGV instead of panicking; the AOT host keeps its range checks. Doom's sync demos
  replay with it on. A/B, box PC, same converter, 3 interleaved samples, B (`off`) against A (`safe`), data `/root/notes/parallel/p7.0o_ab/`:
  Doom JIT demo1-3 -6.5% / -6.7% / -2.6%, interpreter -4.6% / -2.9% / -3.8%.
  Lua JIT fib 30 -10.8%, nbody -5.0%, binary_trees -3.0%, spectral_norm -5.0% (7-sample re-run); interpreter -3.4%, -7.5%, -2.3%, +1.6%.
  Kernels: blit interpreter -5.0%, JIT +3.1%; matmul interpreter +0.7%, JIT +7.7% (spread 5.5%). Why the kernels gain nothing under the
  JIT is not analysed; a candidate cause: the elision pass already proves matmul's indices and LLVM keeps blit's null tests out of its loop.
  Timestamped predictions hit 6 of 18 cells; Lua's JIT cells ran at P7.0p's goto-mode share, not its chain-mode one.
- **P7.0p The Lua JIT residue after the dispatch rows** (from P7.0b4, place 4): the dispatch chain
  is 62-69% of fib's and nbody's JIT samples (P7.0c3 default, P7.0c2 opt-in); fib 30 stays about
  3.4x native if the chain cost went to zero. The remaining JIT symbols: `[c_union]` and field
  accessor calls (`.val`, `.p`, `.i`: 3-5%), `das::i_das_ptr_diff` and `crt::c_volatile_load_i32`
  as runtime calls (about 1%). After P7.0c3 and P7.0c2 land: re-sample fib and nbody with
  `perf/sampler/` (`--lines` over a `--jit-debug` dll) and open a row per cause, P7.0b3's
  interpreter residue beside it.
  Done as research (branch `p7.0p-lua-jit-residue`, no converter change; report
  `/root/notes/research/p7.0p-lua-jit-residue.md`, data `/root/notes/research/p7.0p/`; box PC,
  in-process work, 3 interleaved samples through `heavy`, spreads at or under 8.2%, clang -O3 the
  oracle): fib 30 native 0.0367 s, chain 2.50x, goto 2.02x; nbody 20000 chain 1.34x, goto 1.05x.
  P7.0b4's 10.8x and 5.5x are gone: P7.0c3's one test per dispatch lets LLVM recover a jump table
  for the opcodes up to 0x44 (F88). Five places (fib chain unless said): (1) `luaV_execute`'s head
  (startfunc/returning, run twice per Lua call, 3.2M times), 37-40% of its samples, 29 ms of 92
  against native's 2-4, about half of the excess: `trap = c_volatile_load(L.hookmask)` is an
  indirect call bound `modifyExternal` after which every live value reloads from the stack (F87;
  copies without the call: fib -10% chain / -16% goto, nbody -2% / -4%), a null check per link of
  `cl = ci.func.p.val.gc.cl.l; k = cl.p.k; pc = ci.u.l.savedpc`, and 10 extern slots reloaded per
  loop entry (42 samples) -> P7.0r; (2) `luaD_precall` 1.8x native plus `das::i_das_ptr_diff` as a
  leaf call per Lua call (F86, lookibed/daScript#38); (3) 400 `test/je` null-check pairs in
  `luaV_execute` against native's 48: `unsafe_deref` + range check fib -3% / -10%, nbody -2% / -5%
  -> P7.0o, no new row; (4) chain mode's fall-through compares for the opcodes above 0x44 (RETURN1
  72, FORLOOP 73): goto mode fib 2.50x -> 2.02x, nbody 1.34x -> 1.05x -> P7.0c4; (5)
  `luaH_getshortstr` inlined into nbody's GETFIELD/SETFIELD, 1.5x native on its node-walk null
  checks -> P7.0o. The opcode bodies run at native speed (1.1x). Explained, of fib chain's 55 ms
  excess per run: the head 25-27 ms, `luaD_precall` 4.5, the two leaf calls 6.4, fetch + dispatch
  9-21, RETURN1 3, the bodies 1-2; by edits in copies: the volatile call 9.4 ms, the null checks 3,
  the goto table 17, all three together about 1.6x native (goto + no volatile call measured 1.67x).
  Unexplained: how native's 122 unattributed samples (lvm.c:0, hoisted code) split between the head
  and dispatch, so the head is 2-14x and fetch + dispatch 1.0-1.7x; why the solid build's identical
  head block runs slower (P7.0q). Not done: binary_trees, spectral_norm, the interpreter residue
  (P7.0b3). Leftover, the sampler: `symbolize.sh --lines` under-attributes, since binutils
  `addr2line` fails on the dll's DWARF 5 (form 0x23) and `llvm-addr2line` gives line 0 for merged
  instructions; `addr_lines.sh` in the data folder reads objdump's line table instead (the candidate
  fix); and `--jit-debug` cannot be passed to a converted program (lua.c refuses the flag; the debug
  dll comes from a refused run, cached before argv is parsed, and is copied under the release
  build's hash name: `dbg_build.sh`).
- **P7.0q Where `options solid_context` costs the JIT and the exe** (from P7.0m): the solid build
  of Lua runs fib 30 6% and nbody 20000 9% slower under the JIT (5 interleaved samples, spreads
  7-8%, box PC), the blit kernel 7% slower under the exe (spreads 1-2%) and va_forward 8-20% slower
  under the JIT (spreads 15-21%), while Doom, switch_local and matmul gain. The P7.0m A/B ran from
  outside the tree (`/root/notes/parallel/pc-p7.0m-ab.sh`), so the measuring tool comes first: a
  `--no-solid-context` variant lane in `perf/run.das` (interp and JIT beside the default lanes, as
  `interp-copy` runs `--param-writes copy`) that re-runs the cost on every kernel from the tree. Then
  profile the solid and the non-solid build of each with `perf/sampler` (P7.0b4's method) and read
  the IR of the hot function under `-jit-no-cache --jit-dump-to` (F82); a daslang cause goes
  upstream to lookibed/daScript. P7.0p's finding on Lua (box PC, in-process work, 3 interleaved
  samples, spreads under 8.2%): solid +6.3% on fib 30 (0.0916 against 0.0862 s) and +5.6% on nbody
  20000, visible in the profile as `luaV_execute` +11% self samples and `luaD_precall` -27%, the
  leaf calls equal. The solid build folds the 7 module globals `luaV_execute` touches
  (`absentkey` 34 sites, `strupval` 21, `c2das_empty` 14, `LUAI_MAXSTACK` 12, `LUA_HOOKTAILCALL`
  4, `dummynode_` 3, `luaO_ceillog2_log_2` 2: 90 `jit_get_global_mnh` calls in the no-solid IR)
  into constants, the F80 gain and real here too (`luaD_precall`, RETURN1 faster), yet LLVM
  compiles the 45 KB function differently throughout: 6673 of 13531 normalized IR lines differ,
  9642 against 9787 instructions, 789 against 976 stack reloads, 537 against 549 null checks, and
  the loss sits in blocks whose instructions are identical in both builds (the head's
  call-reload chain). No construct, call or check of the output form: no converter row; a
  dasLLVM-side item with `/root/notes/research/p7.0p/ir/chain.ll` against `ir/nosolid.ll` as its
  inputs (`llc -print-after` and `llvm-mca` on the head block, `--jit-split-modules 0` to see
  whether inlining moved). The variant lane above stays this row's tool for the kernels (blit under
  the exe, va_forward).
  Re-capture profile (2026-11-06, `perf/profiles/sieve_*`): sieve JIT 0.99x -> 1.17x (perf table, 5
  samples, spread 13%) and 1.23x (compare table) native; the no-solid IR hoists two `jit_get_global_mnh`
  calls before the loop, the solid one loads the context once, and the loop bodies are identical, so
  the 10% (0.00179 against 0.00197 s, single ungated runs) sits outside the loop body: the next step
  reads the prologue and the exit path, not the loop.
  Mechanism (2026-11-08, F93, `probes/test_jit_solid_lsr.das`): not the prologue. The hot code is
  `kernel_run` inlined into `main` (solid) or `c_main implementation` (not), and the two IRs are the
  same instruction for instruction but for the base of `flags`: `gep %globals, 16` against the opaque
  `jit_get_global_mnh` result. LLVM's loop strength reduction in the code generator rebases the solid
  build's inner store to a pointer induction variable per unrolled copy of the outer loop: one more
  `add` per inner step (7 instructions against 6, the samples on the `add` after the store) and 16
  start pointers spilled, 55 stack references in the hot function against 20 (`.dll`, objdump); `llc
  -O3 -disable-lsr` on the solid dump gives back `movb $0, 16(%base,%k)` and 4 stack references
  against 67. The array at offset 0 of the block, or no `solid_context`, and LSR changes nothing. No
  converter form avoids it (a local `&` reference compiles to the same code; a pointer drops the
  range check): a dasLLVM item, lookibed/daScript#43 (a candidate there: the solid base through
  `llvm.launder.invariant.group`, which on the dump gives back the folded store). `str_copy` is a
  different case: its copy loop is one instruction shorter solid and `-disable-lsr` leaves it, so its
  1.15-1.31x stays open. Lua's diffuse difference (above) is not checked against F93.
  Predictions for the A/B (`/root/notes/parallel/pc-p7.0q-ab.sh`, solid against the same conversion
  without the option, interleaved, not run): sieve JIT solid/no-solid 1.08-1.12 and the F93 repro the
  same; interp solid at or under no-solid on every kernel; matmul and fib_loop JIT solid at or under;
  str_copy JIT unexplained by F93 whatever it shows.
  Measured (the 2026-11-08 batch, `heavy --exclusive`, machine quiet 1%, 5 interleaved samples, solid against the same
  conversion without the option, S/N of the medians): JIT sieve 1.084 (predicted 1.08-1.12, hit: the F93 LSR cost),
  str_copy 1.079 (unexplained, not F93), matmul 1.003, fib_loop 1.000; interpreter sieve 0.615, matmul 0.621, str_copy
  0.927, fib_loop 0.985 (solid much faster, as predicted); Lua JIT fib 30 0.926, nbody 20000 0.990: the 6-9% Lua loss
  P7.0m measured is gone on today's main (after P7.0r and P7.0x). Kept as the default (ruling 32); the remaining JIT
  cost is dasLLVM's (lookibed/daScript#43). Raw: `/root/notes/parallel/p7.0q_ab/`.
- **P7.0r A JIT-visible volatile load and store** (from P7.0p, place 1): `c_volatile_load(x)` and
  `c_volatile_store(x, v)` expand to the `crt::c_volatile_load_*`/`c_volatile_store_*` externs
  (`c_runtime/c_volatile.das`, `dasCRuntime/src/dasCRuntime.cpp`), an indirect call the JIT knows
  nothing of, bound `modifyExternal`, so after each one every live value reloads from the stack;
  clang emits one `mov`. Sites: the head of `luaV_execute` (`trap = c_volatile_load(L.hookmask)`,
  twice per Lua call, 3.2M times in fib 30) and the 47 `updatetrap` sites, 63 in Lua; every C
  `volatile` access. Measured in situ by copies with the call replaced by the plain read (valid for
  the benches: no hook is set): fib 30 -10% chain / -16% goto (1.67x native), nbody 20000 -2% /
  -4% (box PC, in-process work, 3 interleaved samples); repro 2.1x in a tight loop (F87); the
  call's own samples are half the cost, the reloads after it the other half. The row decides the
  mechanism: a daslang-side intrinsic the JIT lowers to LLVM `load volatile`/`store volatile`
  (upstream lookibed/daScript; the extern slot loads hoisted once per function beside it), or an
  `unsafe` typed `deref` through the object's address on the das side that every tier is proven
  not to fold or drop (the interpreter folds nothing, the JIT and AOT need the volatile marking),
  and proves it with `c_runtime/tests/test_c_volatile.das` under interp, jit, exe and aot plus a
  read-after-store check each tier's optimizer would merge. Default once the semantics hold on
  every tier (ruling 23: it is the shorter form too); the extern call stays for a width the
  intrinsic lacks.
  Done (branch `p7.0r-volatile`, converter output unchanged): dasLLVM's `[llvm_code]` rail is the
  mechanism, no upstream change (F91: `accessExternal` is `modifyExternal`'s bit; a das `deref`
  folds on the JIT and AOT). Under the JIT `c_volatile_load` and `c_volatile_store` are generics
  whose generated body is one inlined `load volatile`/`store volatile`, generic so the split build
  of the cached DLL inlines them too; the interpreter and AOT keep the forwarders; `bool` keeps them
  everywhere (lookibed/daScript#41); both `[llvm_code]` sites carry a `version` the cache key sees.
  A/B against main 642f366 and 41b152c (c_runtime and crt as b4e2ccd), box PC, in-process work,
  medians: Lua JIT fib 30 goto 0.86x (spreads 1.4% / 2.1%), chain 0.91x suspect (+-29%: one B
  sample of 7; every run's chain cell passed 20%), nbody 20000 chain 1.00x, goto 0.96x; interpreter
  0.98-1.01x; the F87 repro 0.193 -> 0.045 s; Doom demo1 JIT 1.01x (PureDOOM has no volatile site).
- **P7.0s Fused loops for C89 shapes** (ruling 33 item 3, the Rust reference diff rows 13-15; report
  `/root/notes/research/r33-rust-reference-diff.md`): a counted `for` whose counter is declared before
  the loop and dead after it takes the range loop (Rust's liveness walk; same C: h264bsd 0 range loops
  against Rust's 46, Doom 4 against 164), `do { } while (c)` is tested at the bottom instead of the
  `_first` flag on every pass (the flag stays only with a `continue`), `do { } while (count--)` with
  `count` dead after becomes a range over `count + 1`. Expected before measuring (box PC, interp, x
  native): matmul 57 -> about 40, sieve 31 -> about 20, do_while_effect 19.2 -> about 15 (the Rust
  cells), Doom interp fps up; JIT, exe and AOT flat (LLVM rotates the loop either way). Readable: the
  C names stay. Default (ruling 23).
  Done (branch `p7.0s-fused-loops`): `dead_after` walks the statements after the loop (a `for` whose
  init assigns the counter kills it, so nested C89 loops fuse, which Rust's walk misses); a counter
  whose every reference sits in such loops loses its declaration, any other counts in a free name;
  `do {} while (0)` is a block. Box PC, exclusive and quiet, x native, A main / B: matmul interp 55.4
  -> 40.5, do_while_effect 19.3 -> 13.6, sieve, blit, str_copy flat (no shape: `<=`, step 7, read
  after); JIT/exe/AOT flat; Doom interp fps +10 to +12% (demo1 172 -> 190, re-run after the review
  fixes), JIT within the run-order drift. Range loops: h264bsd 0 -> 73 (Rust 46), binjgb 22 (22),
  Doom 4 -> 169 (164), Lua 0 -> 55; `_first` left only with a `continue`. The liveness walk counts any
  `break`/`continue` it cannot follow as a read; 20 negative controls guard its branches.
- **P7.0t Flat label CFG for a function with `goto` into case groups** (reference diff row 21): the
  `while (true)` re-dispatch loop with `_goto` and `_flag ||=` tests walked on every jump (switch_goto's
  `run_code`) becomes native `label N:` / `goto label N` with a computed `goto` for the case dispatch, as
  P7.7 did for a goto into a loop body. Expected before measuring (box PC, x native): switch_goto interp
  72 -> about 45, JIT 1.07 -> about 0.55 (the Rust cells: the re-dispatch loop defeats LLVM's switch
  recovery); binjgb interp and JIT as the program check (its opcode switch has gotos). Depends on
  lookibed/daScript#35 the way P7.0c2 does for the interpreter.
  Predictions (2026-11-08, ruling 36 section 5, written before any code or run; box PC, exclusive, x
  native). Form: an opt-in, the `switch_dispatch` `goto` value widened (ruling 36 section 1 keeps goto
  forms opt-in): under it a switch that a goto from another case group re-dispatches and that P7.0c2's
  jump table refuses is spelled open (P7.7's form) with a computed `goto` dispatch when its values fill
  half of [lo, hi], an `if`/`elif` goto chain otherwise; `chain` output is unchanged. Arms: M = main's
  converter, T = the branch's, both under `goto`. Sites, from main's output (chain and goto trees):
  switch_goto `run_code` 1; Lua 2 (lstrlib `match`, `str_format`, goto tree only); Doom (PureDOOM
  source-speed, 159 files) 0, binjgb 0 (its opcode switch has no goto: emulator.c's only goto outside
  `CHECK` is `get_cart_infos`'s `goto done`, no switch around it; the row's claim above is wrong), the
  other compare projects 0; no open switch in Doom or binjgb either. The row's base cells are stale: the
  11-07 perf record has switch_goto interp 45.7x, JIT 0.44x (Rust 43.5x / 0.53x). Expected: switch_goto
  interp 45.7 -> about 28 (T/M 0.62: about 14 dispatch nodes an opcode, the chain tests, `_flag ||=`,
  the `_goto`/`_cond` stores and the restart of op 1 and 2's gotos, become a bounds test, the jump and
  a goto to the end, about 4, against about 10 of body and loop), JIT 0.44 -> 0.44 (T/M 1.00 +-5%: LLVM
  already threads the restart into direct branches at 0.44x); binjgb JIT 1.14x -> 1.14x and Doom demos
  1-3 JIT (about 1.05-1.15x native, fps unchanged) T/M 1.00 +-2%: the converted text is byte-identical,
  the run a noise control. Readability price: `run_code` 69 -> about 45 lines (ratio 0.65), labels 3 ->
  9 (a label per case value and the end), gotos 4 -> 9 (one computed), `while (true)` 1 -> 0, `_flag ||=`
  6 -> 0; Lua's goto tree about +25 labels and +45 gotos in the two functions, line ratio about 1.0
  (`match` 180) to 1.1 (`str_format` 176, 17 sparse values as an `elif` chain); Doom, binjgb none.
  Implemented (branch `p7.0t-flat-label-cfg`, timing is the lead's exclusive batch,
  `/root/notes/parallel/pc-p7.0t-ab.sh`): `open_redispatched` and `open_table`
  (`converter/ARCHITECTURE_EMITTER_CONTROL.md#flat-cases`); under `goto` an open switch (Duff's device,
  one a goto enters) takes its own table too, and P7.7b's "open switch re-dispatched from another case"
  converts; `chain` output unchanged. The interpreter needs no daScript#35 fix: `guard_label_folds`
  reads the computed goto as naming its table's labels (probe `test_goto.das`, the flat label CFG).
  `run_code` measured 67 -> 47 lines (0.70), labels 3 -> 9, gotos 4 -> 9 (one computed); readability
  `@goto` keys for every kernel and Lua program and the criteria rows `lua/lua@goto`, `lua/luac@goto`
  recorded. Review fixes: an unsigned subject's `case -1` read as its held value (no table; was every
  value to no-case), tables from `INT_MIN` jump by the distance from `lo`, the `_contN` epilogue
  guarded above a flat label, the unshadow pre-pass under goto mode; the `interp-goto` perf lane
  (its cells come with the next re-record, a timing run).
  Done (batch 5, `/root/notes/parallel/p7.0t_ab/ab.txt`; one exclusive job, quiet at 1% busy, box PC,
  M=dd60478 T=466b657, both under `goto`, 5 samples, every result native's; medians T/M): switch_goto
  interp 0.555 (predicted 0.62, hit; 44.6x -> 24.7x native), JIT 0.919 (predicted 1.00 +-5%, a miss:
  0.45x -> 0.41x, the flat CFG drops the restart's stores, which LLVM had not removed); binjgb JIT
  1.003 (1.00, hit; text identical); Doom demos 1-3 JIT 1.002 / 1.003 / 1.007 (1.00, hit). The
  prep's "Doom text differs in 9 files" is a miss of the check, not of the code: the 82 lines are
  `__FILE__` paths naming each arm's own worktree in `Z_CT` error strings and the cluster's
  fragments' digest; with the path set aside the trees are identical (0 sites, as predicted);
  demos 1-3 sync under T's JIT. Hit rate 5 of 5 within 25% (the JIT cell outside its own +-5% band).
  Readability: `run_code` 67 -> 47 lines (0.70), labels 3 -> 9, gotos 4 -> 9 (one computed);
  criteria `lua@goto` 79.6 and `luac@goto` 79.2 against the defaults' 79.7 and 79.3 (switch_flags
  +2.2 on lua, label_stubs -1.0 and -1.3, macro_blowup -0.7 and -1.0). Decision: stays inside the
  `goto` opt-in (ruling 36 section 1); the default `chain` output is byte-identical.
- **P7.0u Builtin `memcpy`, `memmove` and `memset8` for the program's own calls** (reference diff
  rows 5-6; extends P7.0n, which moved the constant-size marshal reads): a C `memcpy`/`memmove` of a
  program size calls daslang's builtin with the size guarded against zero, a C `memset` calls `memset8`
  (the Rust translator's `c2da_rt_memset`), in place of the `crt::` externs, whose `modifyExternal`
  bind is an indirect call plus the F87 reload barrier under the JIT and the exe. Expected before
  measuring: h264bsd (56 memset sites, block clears per macroblock) and plmpeg JIT and exe a few
  percent faster, interp flat (libc does the copy either way); the kernels have no such site, so a
  kernel with a `memset` per block is the measurement. The crt binds stay for the AOT host's widths.
- **P7.0v** `p[i]` for `deref(p + i)` moved to the readability phase as P9.1 (owner ruling 38); its
  `uint64` mirror half stays here as P7.0v2.
- **P7.0v2 The `uint64` mirror of a stepped pointer, opt-in, and the `p++` step spelling** (split from P7.0v, whose
  probe measured the step): a local or parameter pointer that is only dereferenced, indexed, compared and stepped by
  a constant (never addressed, passed or stored, not volatile) is mirrored in a `uint64` local under an opt-in
  (`--pointer-steps=mirror`, sidecar key), the default staying the pointer; the default's step `p = p + 1` becomes
  `p++` / `p += n` where the readability re-record agrees. Expected before measuring (box PC, interp, x native): blit
  45 -> about 30 and str_copy down by a like share under the mirror, about a third of that from `p++` alone; JIT flat
  or worse under the mirror (the `inttoptr` hides the pointer from alias analysis: check the IR first).
- **P7.0w Expression inlining of pure `static` helpers** (reference diff row 28): a `static` function
  whose body is `return <expr>` or the clamp shape over scalar parameters is substituted as one
  expression at every direct call site (Rust's inline.rs, on in every mode); daslang's `[inline]` is
  no substitute (1.69x slower under the interpreter, memory note). Expected before measuring (box PC,
  interp, x native): plmpeg 37.5 -> about 33 (77 `plm_clamp` sites, 19M calls per 7 frames),
  fixed_mandel 51 flat or better; JIT lanes flat (LLVM inlines them). The helper's name vanishes at the
  site, so the default is decided after the measurement (ruling 23).
  Reference pass (2026-11-08): Rust's `inline.rs` takes a `static`, non-variadic function of at most 4
  arithmetic parameters and result whose body is `return <expr>` or the clamp chain, every expression
  pure (parameters, literals, enumerators, value casts, operators, `?:`, calls of other candidates),
  not self-recursive (mutual recursion stopped by an expansion stack); arguments cross at the parameter
  types, a non-leaf argument binds a `var` temp and then every argument does; a site in an unused, a
  constant or a conditional-arm context that would need statements keeps the call; the definition
  stays; on in every mode (15% of pl_mpeg's interpreter time, compiled lanes within noise). daslang's
  `[inline]` rejects `goto` bodies and measured no faster on statement bodies (Rust's probe, the memory
  note's 1.69x); daslang has no expression-level substitution. Ours (the opt-in `inline_helpers`,
  `--inline-helpers`, the call the default): the same candidates without enums, `_Bool` or K&R
  definitions, and none whose value is taken; a temporary only for an argument with an effect (or a
  volatile read) and for a non-plain one the body reads twice, the others spelled in place; the clamp
  calls nothing. Predictions for the A/B (`/root/notes/parallel/pc-p7.0w-ab.sh`, arms D default and I
  inline, box PC, `heavy --exclusive`): plmpeg interp I/D 0.90 (0.86-0.94: the 77 sites trade a call
  node for a `?:` chain plus, for a sum argument, one `let`; Rust saved 15%), JIT I/D 1.00 (+-3%);
  fixed_mandel interp I/D 0.85 (5 `fmul` calls of about 30 nodes per iteration gone), JIT 1.00.
  Ruling 36 (2026-11-08), program-level under the JIT, box PC, exclusive, before any run: binjgb JIT I/D 1.00
  (+-3%) and Doom demos 1-3 JIT I/D 1.00 (+-3%), since LLVM inlines a direct call of a small static function
  either way and the expression only reaches the interpreter; Doom's hot `FixedMul` is external, no candidate.
  The opt-in's readability price is the `@inline` rows (`perf/<kernel>@inline`, `lua/<program>@inline`) of
  `metrics/readability_linux.json` and `metrics/criteria_linux.json` against their default rows; its perf lane
  is `interp-inline`.
  Measured (2026-11-08 batch 4, one `heavy --exclusive` job, machine quiet 1%, box PC, tree a7f569d, 5 samples,
  every result equal to native; raw `/root/notes/parallel/p7.0w_ab/ab.txt`), inlined/default: plmpeg-stream interp
  0.941 (predicted 0.90, 0.86-0.94: at the range's edge, the temporaries of sum arguments eat part of the saved call),
  JIT 1.002; fixed_mandel interp 0.872 (predicted 0.85, hit), JIT 1.006; binjgb JIT 1.002 and Doom demos 1-3 JIT
  1.004 / 1.007 / 1.000 (predicted 1.00 +-3%, hits). Every number within 25% of its prediction (8/8). Readability
  price (criteria capture): lua 79.7 -> 79.6 (bool_roundtrip 92.3 -> 91.9, literal_arithmetic 70.5 -> 70.3,
  temporaries and macro_blowup -0.1, constant_names +0.2), luac 79.3 unchanged, the per-function line ratio's median
  and worst unchanged; the readability counters equal on every `@inline` row. gcc-torture 1204 and c-testsuite 203,
  equal to main. Decision: the JIT is flat on every program and the gain is interpreter-only, so the form stays the
  opt-in `inline_helpers` and the default stays the call (ruling 23; ruling 36 section 1, readable by default).
  Follow-up (review 2026-11-08, minor): a static helper of a header several files include is defined in each and
  never inlined; `--inline-helpers` cannot switch a sidecar's `inline_helpers: true` off; two guards of
  `inline_helper` are unreachable from valid C.
- **P7.0x The source layout's split JIT build loses cross-module inlining** (found by the re-capture's
  profiles, 2026-11-06): the ports `jit` lane runs the source layout (30 modules, the cached JIT a
  partition per module) at Lua fib 4.9x (the ports size, fib 34) and nbody 4.1x (200000) native, where
  the single layout runs 2.24x (fib 30) and 1.37x (nbody 20000) on the same box and runtime (P7.0p
  measured the single layout; the 11-04 ports module reproduces its 9.46x, the runtime and priority
  ruled out; the sizes differ, so the first step is one like-for-like pair). The loss is inlining
  across module boundaries in the per-module build (the `lobject_h_cluster` accessors stand as
  separate JIT symbols in the source layout's profile). Candidates: a whole-program JIT build for the published lanes
  (`--jit-split-modules` off or a link-time inline pass, dasLLVM side: a fork issue with the number),
  or the hot cluster kept in one module by the layout (P5.1b2's cluster rules). The ports tables carry
  both layouts, so the gap is visible there; the predictions file scores the `jit` column against it.
  Ports publish 2026-11-07 (c2das-ports, exclusive, in-process work): source layout JIT fib 4.87x, binary_trees
  2.57x, nbody 3.98x, spectral_norm 4.79x native against the single module's 2.24x / 2.28x / 1.38x / 2.00x and the exe's
  2.14x / 1.40x / 1.36x / 1.91x (one linked program): the gap is the layout's, not the runtime's. The `jit-goto` column
  (source layout) reads 4.84x / 2.55x / 3.77x / 4.52x: the goto dispatch's single-layout gain (P7.0c2) does not show
  through the split build, which P7.0c4 weighs before any JIT default.
  Reference pass (2026-11-08): the Rust translator's output is one file per program (`compare/work/projects/*/rust/*_all.das`), so
  it never meets the split; dasLLVM's `--jit-split-modules` takes 0 for monolithic emission (one LLVM context, full cross-module
  inlining) beside its default -1 (a partition per das module), with the script pin `options jit_split_modules`; `--jit-lto` is an
  exe-only flag and `DAS_JIT_PROBE_LTO` a dev probe for the DLL rail; `-jit-no-cache` runs in memory, one unit; the `exe` lane is
  one unit by default (an exe splits only when its build command asks), which is why it tracks the single layout. Profile cited:
  perf/profiles/lua_fib_jit.txt (source layout) spends 8.6% in six `lobject_h_cluster` accessors standing as JIT symbols
  (`val` 3.4%, `p` 1.8%, `l` 1.5%, `gc` 1.0%, `cl` 0.9%, `i` 0.7%) that lua_fib_native.txt and the single layout inline away.
  Predictions (2026-11-08 00:15 MSK, before any timing run; fib 30 and nbody 20000, in-process work, 7 interleaved samples, box PC):
  the default split JIT runs the source layout 2.2x slower than the single layout on fib and 2.9x on nbody; under
  `--jit-split-modules=0` (and `-jit-no-cache`) the source layout runs at the single layout's speed, 2.24x / 1.38x native (within
  10%), the single layout unchanged (it is one module either way); the goto source layout under the monolithic build then shows
  its single-layout gain, about 1.3x on fib over chain; the cached `-e "print(1)"` startup moves less than 10% (one DLL loaded
  either way), the no-cache startup pays the whole compile on every run.
  Mechanism (2026-11-08, before any timing of it; F92): daslang takes no partitioning flag before the script, the JIT reads
  `--jit-split-modules` only after `--`, where the converted program reads it as its own argument (Lua's `-e "print(1)"`
  refuses it), no environment variable sets it, and the script pin `options jit_split_modules` is an invalid option unless
  the program requires `llvm/llvm_jit`. `c_runtime/c_jit_build` declares the option, so the sidecar's `jit_whole_program`
  (set in `lua/lua.c2das`) has the converter write `options jit_split_modules = 0` and the require into the module holding
  `main`: every tier runs it, and the cached JIT builds the very DLL (the same cache key) `--jit-split-modules=0` builds, so
  the predictions above stand for B. Added before any run: binary_trees 14 and spectral_norm 500 under B at the single
  layout's 2.28x / 2.00x native within 10% (A as published, 2.57x / 4.79x); the startup row runs under B unchanged.
  Review (2026-11-08, before any run of B): the single layout is split too by default (a partition per c_runtime
  module, 9), so "one module either way" is wrong as a reason; the predicted single-layout numbers stand as written.
  The A/B (`/root/notes/parallel/pc-p7.0x-ab.sh`, the lead's batch): A the split default, B the pin, source, single and goto
  layouts, fib 30, nbody 20000, binary_trees 14, spectral_norm 500 and the startup row, 7 interleaved samples.
  Done (branch `p7.0x-split-jit`, the 2026-11-08 batch, `heavy --exclusive` machine quiet 1%, 7 interleaved samples,
  x native in-process work): fib 30 source layout A 4.96x -> B 2.22x (predicted 2.24x, hit), nbody 20000 3.92x -> 1.38x
  (1.38x, hit), binary_trees 14 2.63x -> 1.75x (predicted 2.28x: better than the single layout's 2.44x, which still splits
  per runtime module: a miss in the good direction), spectral_norm 500 4.86x -> 1.91x (2.00x, hit); the goto layout under B
  fib 1.72x, nbody 1.04x, binary_trees 1.52x, spectral_norm 1.49x (the predicted ~1.3x goto gain over chain: 1.29x on
  fib, hit); the single layout A/B within 3%; the cached `-e "print(1)"` startup within 2% (hit). Raw:
  `/root/notes/parallel/p7.0x_ab/ab.txt`. Hit rate 6 of 7.
- **P7.0zd A numeric `#define` as the literal at its use** (ruling 36 section 5, item 3): where P7.0k
  spells a `#define` constant by name over a module `let private NAME = <value>`, emit the value at
  every use, the Rust translator's form (its `macros.rs` lowers the expanded AST and never names a
  macro: binjgb's `ADDR_MASK_8K` is `8191` at its six uses there). The readable default stays the name
  if the criteria say the name matters; the literal is then an opt-in (`converter/REVIEW.md`'s option
  duties). Sites: binjgb's bench module holds 123 such `let`s spelled at 272 uses (190 macro names over
  1308 marked nodes in its C-IR); doomgeneric's C-IR marks 2226 nodes under 529 names (FRACBITS,
  FRACUNIT, SCREENWIDTH in the column and span drawers among them, the hot paths).
  Expected before measuring (box PC, program-level, x native, the A/B the literal arm against main):
  flat on every lane, interp, JIT and exe, within 2%, binjgb and Doom demos 1-3 alike. Reason: the
  output declares each constant `let` (const) with a literal or a literal expression (`456 * 154`,
  `~0ul`, `uint64(a) * uint64(b)`), and daslang's constant folding (`ast_const_folding.cpp`,
  `visit(ExprVar)`) replaces every read of a const foldable global whose initializer folds to a
  constant with that constant before simulation, so the interpreter, the JIT and AOT already see the
  literal; the probe of the next commit pins it. Readability price of the literal form: criteria
  `constant_names` to about 0 (lua/lua 61.8, lua/luac 53.5), so the criteria total of lua/lua 79.7 ->
  about 76.9 and lua/luac 79.3 -> about 76.9 (one of 22 criteria), nothing else moved; `literal_named`
  falls, since the counter matches literals against the module's own names and the `#define` lets
  leave, an artifact of the counter and not a gain. If the probe holds, nothing is implemented: the
  name costs nothing at run time.
  Closed without the literal form (coordinator's decision 2026-11-08, the owner may overrule): the
  probe `test_constant_let_folds` (`probes/test_globals.das`) pins the fold on all seven `let` shapes
  above: AOT spells each literal with no `das_global` read, the JIT IR holds the immediate (`and i32
  %arg_value_0, 8191`) with no `jit_get_global`, and the `var` control reads the global on both (a
  mutation making the function read the `var` fails both cases). The literal form buys no speed and
  costs the predicted readability (`constant_names` to about 0, lua/lua 79.7 -> about 76.9); the name
  stays the default and no opt-in is added. No timing run: nothing differs to time. Caveat: the Doom
  site count is doomgeneric's C-IR (the compare project), not the PureDOOM tree `doom/run.das` converts.
- **P7.0y Hand-written daslang references beside the Rust translator's output** (owner note
  2026-11-06, the reference pass of ruling 33 item 3 widened): the owner's plmpeg port
  (lookibed/plmpeg-stream, checkout `/root/plmpeg-stream`, bench `/root/plmpeg_bench`) against our
  and Rust's plmpeg, the owner's wasm3das (lookibed/wasm3das, `/root/wasm3das`) against wasm3's
  translation (ours refused: VLA, P8.4 row i), and spiiin/dasSDL3 (cloned under `perf/work/` or
  `compare/work/`, read-only) as an idiom and speed reference. From each: how a human writes the
  same hot path (loops, pointers and arrays, structs, globals, options), the speed per lane where
  a like-for-like run exists, and every construct our output could adopt, one ledger row each with
  its expected effect written before measuring. After the current P7.0 speed rows.
- **P7.0za The Lua conversion's memory** (owner ruling 35, second item) - Done: `lua/run.das --native
  --run` (both programs, three layouts, one process) peaked at 7.7 GB RSS and the 11-07 ports publish
  was OOM-killed. Cause: a daslang context frees no string it is not told to and its heaps never
  shrink, so the six conversions of one run added up, about 1.9 GB each, and within one conversion
  clang's JSON text (500 MB over `lua`'s 33 files) stayed on the string heap after its parse. Fix:
  a run of more than one conversion makes each in a process of its own (`lua/ARCHITECTURE.md`
  section 7, the oracle built once by the parent, `--oracle-built` in the child), and the dumper
  frees the JSON text once parsed. Peak RSS (bench, `/usr/bin/time -v` with a 1 s sampler summing the
  process tree), before / after: `--filter lua --layout source` 1.87 / 1.40 GB, `single` 1.91 /
  1.43 GB, `source-cut` 1.84 / 1.35 GB, the whole run (`--native`, both programs, three layouts)
  7.96 / 1.61 GB (the parent and one child; the largest process 1.43 GB); the publish's `--native --run`
  1.89 GB (the parent, a child and the converted interpreter it runs; the largest process 1.43 GB).
  The tree peaks come from a 1 s sampler and are lower bounds; `time -v` gives the largest process. The six output trees hash
  the same before and after and the run's log is the same line for line, its seconds aside. Under
  heavy's default 4G cap now. Left: the per-conversion floor is the dump phase (each unit's CirTu
  kept until the link, the JSON tree at the parse), not the emitter or the compile check. The harness
  test pins the arguments, the one oracle build and the order, not the separate processes, which the
  bench peak shows.
- **P7.0zb `&a[k]` without the `end_index` call** (binjgb profile, `/root/notes/research/binjgb-profile.md`
  candidate 1): binjgb's interpreter spends 12.6% of its das-profiled time in `c_bounds::end_index`, 1.43 M
  calls per 60 frames (1.04 M from mode3's sprite loop `addr(e.state.ppu.line_obj[0]) + end_index(n, 10)`),
  because `&a[k]` lowers to the decayed array plus `end_index(k, N)` (F45). Rust's form is unchecked:
  `addr(reinterpret<Obj?>(p)[n])`. The change: an index that is an integer constant under integer casts
  (an enumerator, `int(E.X)`) folds at emit time as a literal does (below the length `addr(a[k])`, the
  length `addr(a[0]) + N`); an index that is a plain load (a variable or a field, under casts) of an array
  without effects is `k == N ? addr(a[0]) + N : addr(a[k])`, das's own range check on every index but
  the length, no call; any other index keeps `end_index`. Expected before measuring (box PC, x native):
  binjgb interp -4 to -5% (7.2 M calls x ~35 ns of 4.9 s, three quarters of them on plain-load
  indexes), JIT and exe flat (LLVM inlines the call already). Readable: the fold is shorter, the
  plain-load conditional spells C's one-past-the-end rule in das's own index; a compound index stays
  the call, since the conditional would spell it twice. Default (ruling 23).
  After review: the readability capture counts the conditional's repeated length (`literal_named` +59), so
  the fold is the default and the conditional the opt-in `past_end` `inline` (`--past-end inline`, the
  sidecar key); the A/B times A (base), B (default) and C (inline). The predictions above are C's; B is
  expected within noise of A.
- **P7.0zc A case whose body does nothing joins the next case's labels** (binjgb profile,
  `/root/notes/research/binjgb-profile.md` candidate 2): binjgb's CpuState switch in
  `execute_instruction` (the HALT path, 5.2 M steps per bench, 97% of the calls) takes the matched-flag
  loop (`while (true)`, `var _flag`, `_flag ||= _cond == K`) only because `case CPU_STATE_NORMAL:
  assert(0);` is `((void)0)` under NDEBUG and falls into `case CPU_STATE_STOP`. Rust's form: a bounds
  guard and `goto int(state) + 6`, the NORMAL label adjacent to STOP's (its assert dropped), one jump.
  The change: a group with no default label whose statements do nothing (a `;`, an expression
  statement with no effect and no volatile read, a block of those) joins the next group's label set
  when that group has no default label; a group that holds a label, a declaration, a case label in
  a nested block or anything that acts keeps the flag form. Once no group falls through, the switch is
  the if-chain (`_cond == A || _cond == B`). Expected before measuring (box PC, x native): binjgb
  interp -2 to -4%, JIT and exe flat (LLVM folds the flag loop already). Readable: fewer constructs,
  the empty `if (_flag) {}` gone. Default (ruling 23).
- Owner ruling 34 (2026-11-06): the dasProfile-method hand-written column stays the bench's
  capture; no daScript SDK on box PC; re-run only on the bench at a phase end, never a PR blocker.
  Measured (the 2026-11-08 batch 2, `heavy --exclusive` machine quiet 2%, binjgb's built bench, 5 samples alternating
  arm order): the default (constant fold, the call kept) interp 0.993 of main (predicted within noise, hit), JIT 0.996;
  the `--past-end inline` opt-in interp 0.973 (predicted -4 to -5%: a miss, half the predicted gain: the profiled
  per-call cost overstated what the conditional saves), JIT 1.026 (inside main's 7% spread). Raw:
  `/root/notes/parallel/endidx_ab/ab.txt`.
  Measured (the 2026-11-08 batch 2, `heavy --exclusive` machine quiet 2%, binjgb's built bench, 5 samples alternating
  arm order): interp 0.987 of main (predicted -2 to -4%: half the gain, a miss: the HALT path's flag loop costs less
  than the profile's share suggested), JIT 1.002 and native 0.995 (predicted flat, hits). Raw:
  `/root/notes/parallel/emptycase_ab/`.
- **P7.0ze The density metric** (owner ruling 38 part 3, 2026-11-09; the readability note
  `/root/notes/research/readability-architecture.md` step 0) - Done (branch `r38-metric-density`):
  beside the 22 compliance percentages, `metrics/criteria_linux.json` records 24 densities, sites per
  1000 das code lines (casts, literal casts, `addr`, `deref`, `reinterpret`, `_tN` names, expanded
  function-like macros, blow-up lines, the rest of the criteria's sites), pooled over `lua/lua` and the
  six compare projects by their lines (`programs`), with the function-length distribution and the
  hand-written plmpeg port (`hand/plmpeg-stream`) beside as the base; `label_stubs` counts `label N:`
  and `goto label N` since `c_label_end` is gone (P8.10). The "before" for the forms pack: `programs`
  1465.7 per 1000 lines (das-side 980.6, the hand port 79.8); Lua 1571.0, Doom 1080.1, binjgb 1386.8,
  quake 1584.8; the old `all` on the same output 78.3 (77.9 was recorded before P8.10).
  Re-recorded 2026-11-10 on main 0dded85 (the repin, P9.1 and P9.2 in; 1610 inputs, 0 failed): the
  pre-form output (main c25fca7, same tool) measures the same "before" (the repin moved no density);
  P9.1 and P9.2 together: `programs` 1465.7 -> 1395.8 (das-side 980.5 -> 917.9), `deref` 89.4 -> 39.4,
  stray braces 22.9 -> 10.3, blow-up lines 56.1 -> 48.6; Lua 1570.8 -> 1502.8, luac 1771.6 -> 1694.5,
  Doom (doomgeneric) 1080.1 -> 1071.7, h264bsd 1533.4 -> 1386.1, plmpeg 1276.0 -> 1135.8, binjgb
  1386.8 -> 1376.7, quake unchanged; old `all` 78.3 -> 79.1; the hand plmpeg port 79.8.
- **P7.0zf The switch census** (owner task 2026-11-15, for the daslang author's decision on a
  `switch` node; research, the converter and its output unchanged, no perf or readability
  capture involved; branch `switch-census`, report `docs/switch-census.md`):
  `metrics/switch_census.das` reads every `switch` of the converted programs from the C-IR and
  sorts it by what a daslang form must carry (`metrics/ARCHITECTURE_SWITCH.md`). 428 switches in
  the eight programs (334 without doomgeneric, the same game as PureDOOM): 394 (92%) constants
  with no real fall-through, 29 (7%) with one, 5 (1%) with a goto between cases (Lua 3, Quake 2),
  none on a non-integer; of the 9 in functions of the committed profiles' top ten rows 7 are the
  first kind, `luaV_execute` is the third.
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
