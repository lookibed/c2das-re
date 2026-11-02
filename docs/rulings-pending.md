# Rulings pending

Owner decisions not yet made, one line each: the item, the question, the options, the date asked.
A line leaves when its ruling lands in [implementation_order.md](implementation_order.md); the open
lines head every report (`AGENTS.md`).

- P5 close (archivists, PR #24), `lua/ARCHITECTURE.md`: the `run.das` charter is a 31-line flag list; cut it to one line plus a flags section, or keep it; 2026-10-30.
- P5 close (archivists, PR #24), `lua/ARCHITECTURE.md`: section 6 has no anchor; add `{#suite}` cited from `suite_check`, or leave it uncited; 2026-10-30.
- P5 close (archivists, PR #24), `lua/ARCHITECTURE.md`: sections 1 and 6 overlap on the stdin pipe and the launchers; merge into one, or keep both; 2026-10-30.
- P5 close (archivists, PR #24), `lua/REVIEW.md`: the proposed rule "A diff that changes which files `--suite-check` runs, the arguments it gives them, its memory caps, or its verdicts restates `ARCHITECTURE.md` section 6 in the same change"; add it, or not; 2026-10-30.
- P5 close (archivists, PR #24), `converter/ARCHITECTURE_EMITTER.md`: the JIT `return` inside a try/recover arm (F75, lookibed/daScript#30) is stated as a fact; an exception-ledger row, or a fix item; 2026-10-30.
- P5 close (archivists, PR #24), `converter/ARCHITECTURE_EMITTER.md`: merge the two `[c_function]` clauses, or keep them apart; 2026-10-30.
- P5.3: a `LUA_USE_POSIX` build pair beside the ANSI port (`isatty`, `io.popen`, `mkstemp`, `%Ex`); run the Lua test suite against it too, or the ANSI build stays the port; 2026-10-29.
- CI (the runner moved to the WSL box): `VERSIONS.md` pinned nm 2.44 (the FX-6300's) and the WSL box has Ubuntu's 2.38, so main's full tier went red at `lua/tests` test_profile_refusals; keep the two-version pin (PR #35), or install binutils 2.44 on the WSL box and return to one version; 2026-11-01.
- P8.1b: `require_lines` counts one `require` per C `#include`, so gcc-torture scores 7.2% and c-testsuite 39.9% (most tests include nothing); keep that denominator, or exclude inputs with no include; 2026-11-01.
- P8.1b: `long_lines` fails a module on any line over 160 bytes even where the C source has such lines (csmith 0%); keep, or count only the excess over the C source's long lines; 2026-11-01.
- P8.1b: noise criteria without a C counterpart (temporaries, stray braces, layout checks and the like) score the share of functions or modules with no site; keep, or a per-C-line rate (reads near 100% even where the worst functions are noisy); 2026-11-01.
- P8.1b: the `all` column and the total weigh the nine rows (six Lua program/layout rows, three suites) equally; keep, or weigh by input count or by C lines; 2026-11-01.
- P8.1b: `comments` counts a das comment as carried when it equals a C comment line or has two or more words found inside one, so one-word converter notes (`// retry`) do not count; keep, or count any das comment; 2026-11-01.
- P8.1b: the per-module criteria (`layout_checks`, `long_lines`, `late_binding`) are binary in the one-module `single` layout (0 or 100: lua/lua@single `layout_checks` 0.0 against 64.6 in source, `long_lines` 0.0 against 29.2); keep the per-module unit, or count these per function or per 1000 lines so a one-module layout is comparable; 2026-11-01.
- P8.2: project speed is timed per side wherever that side's lanes pass (the Rust and native cells stand without ours); keep, or time only lanes both sides ran; 2026-11-01.
- P8.2: the AOT host passes no program arguments, so AOT is skipped for programs reading argv (wasm3, both sides); fix it in `converter/tiers.das` as its own item, or leave AOT skipped for those programs; 2026-11-01.
- P8.2: `skipped` as a lane status (a lane the harness cannot run, reason recorded); keep it, or fold it into `refused` with the reason; 2026-11-01.
- P8.2: the bench's oracle is one native bench run held to the expected output except per-project free keys (own value, or extra lines by prefix) and omitted keys (binjgb: free `frames`, `frame[`; omitted `width`, `height`, `ticks`; wasm3 none, so exact); keep, or require the exact expected text for the bench too; 2026-11-01.
- P8.2: the native builds compile the canonical case's `c_reference.sources` (the bench: those with `corpus.bench_c_entry` in place of the last), falling back to the row's unit when the case names none (h264bsd-mp4: `all_reference.c` + its entry); keep as the rule, or always build the unit; 2026-11-02.
- P8.2: the case's `-w` reaches only the native build (h264bsd-mp4), not the Rust translator's clang arguments; keep, or pass it to the translator too; 2026-11-02.
- P8.2: plmpeg-stream's unit calls `c2da_rt_reset()`, a test-runtime hook the Rust runtime defines; give our side a body (a sidecar stub or no-op, as the Rust runtime does), or count the hook as a Rust-only input our converter refuses; 2026-11-02.
- P8.2: the JIT prints compile warnings (`[W] LLVM JIT: ...`) on stdout before the program runs; drop them before judging, as the `[I]` lines are (quakegeneric's Rust JIT would pass, Rust 6 of 6 on JIT), or keep them as output (quakegeneric's Rust JIT `output`); 2026-11-02.
- P7.0f (from P7.0b): the fast form of the address of a first member (`addr((p + i).val)`, `addr(reinterpret<GCUnion?>(o).h)`) is a `reinterpret`, which the readability criteria count as noise; make it the default, or an opt-in under the speed-vs-idiomatic rule; 2026-11-02.
