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
- `tests/` - one dastest file per piece, written as the converter will emit the code,
  including a control that the same code without the piece is rejected or wrong.

## 2. Loading

The module lives outside `DASLANG_ROOT/modules`; every daslang run that reaches it passes
`-load_module <repo>/c_runtime` before the script path (`scripts/preflight.sh`, `.mcp.json`),
the same way `dasCRuntime/` is loaded.

## 3. Exception ledger

Empty.
