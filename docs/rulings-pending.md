# Rulings pending

Owner decisions not yet made, one line each: the item, the question, the options, the date asked.
A line leaves when its ruling lands in [implementation_order.md](implementation_order.md); the open
lines head every report (`AGENTS.md`).

- P5.3 (`lua/ARCHITECTURE.md`): the `run.das` charter is a 31-line flag list; cut it to one line plus a flags section, or keep it; 2026-10-31.
- P5.3 (`lua/ARCHITECTURE.md`): section 6 has no anchor; add `{#suite}` cited from `suite_check`, or leave it uncited; 2026-10-31.
- P5.3: a `LUA_USE_POSIX` build pair beside the ANSI port (`isatty`, `io.popen`, `mkstemp`, `%Ex`); run the Lua test suite against it too, or the ANSI build stays the port; 2026-10-30.
- P5 exit criterion: the Lua test suite under the JIT (lookibed/daScript#30, F75) and the AOT lane for Lua (the AOT host passes no program arguments) are `not yet`; accept them as the recorded halves of the P5 close, or ledger them before P6; 2026-10-31.
