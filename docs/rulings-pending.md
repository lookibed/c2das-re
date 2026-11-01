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
- P8.1: Lua on the Rust side is refused at `ldexp` (`luaK_numberK`) and the libc gap is 20 names (`compare/results_linux.json` section `lua`); keep `refused` in the report, or write `--host-import` modules for the gap to get a Lua speed number; 2026-11-01.
- CI (the runner moved to the WSL box): `VERSIONS.md` pinned nm 2.44 (the FX-6300's) and the WSL box has Ubuntu's 2.38, so main's full tier went red at `lua/tests` test_profile_refusals; keep the two-version pin (PR #35), or install binutils 2.44 on the WSL box and return to one version; 2026-11-01.
