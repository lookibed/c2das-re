# c_runtime Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The
folder is the daslang module converted programs require: the semantic layer the bind-first
strategy leaves on the das side (`docs/stdlib-examples.md`), grown one piece at a time with an
as-if-converted fixture test landing first.

## 1. File charters

- `.das_module` - the descriptor: one `register_native_path("c_runtime", <name>, ...)` per
  file under `c_runtime/`, so a converted module writes `require c_runtime/<name>`. A file
  the descriptor does not name is unreachable; `REVIEW.das` keeps the two in step.
- `c_runtime/c_function.das` - the `[c_function]` function annotation: `apply` replaces the
  body with `unsafe { <body> }` before inference. The converter emits it only on a function
  whose body contains an unsafe operation, so its count across a converted program is the
  port-progress metric of the follow-up story; nothing else about the function changes.
  `unsafe` does not reach into a lambda or generator body, which C never produces.
- `c_runtime/enum_from_int.das` - `enum_from_int(type<E>, i)`, the C int-to-enum conversion:
  one generic over the type witness holding the one `unsafe(reinterpret)`, so an out-of-range
  value survives by value as C's does.
- `c_runtime/c_exit.das` - the process-exit protocol: `c_atexit` registers into a module
  list, `c_run_atexit` walks it once in LIFO order, the `[finalize]` walker runs it after a
  normal return from `main`, `c_exit(code)` runs it and ends the process with `exit_now`
  because daslang's `exit` reports 1 whatever its argument (`docs/probe-findings.md` F1),
  `c_abort` is `exit_now(3)` with no handler run, which is C's rule and the baseline's code.
- `c_runtime/cstr_array.das` - the `cstr_array("abc", N)` call macro: C's `char buf[N] = "abc"`
  as a `uint8[N]` literal built at compile time from the decoded string bytes, a NUL and zero
  padding; an exact fit carries no NUL, a longer string is a compile error. The das literal
  does the escape decoding, so the macro only spells bytes.
- `tests/` - one dastest file per piece, written as the converter will emit the code,
  including a control that the same code without the piece is rejected or wrong.

## 2. Loading

The module lives outside `DASLANG_ROOT/modules`; every daslang run that reaches it passes
`-load_module <repo>/c_runtime` before the script path (`scripts/preflight.sh`, `.mcp.json`),
the same way `dasCRuntime/` is loaded.

## 3. Exception ledger

Empty.
