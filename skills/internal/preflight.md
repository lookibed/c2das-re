# Preflight - the gates a change clears before it is pushed

`scripts/preflight.sh` runs the **fast tier** serially and stops at the first red:
`env`, `untracked`, `format`, `lint`, `compile`, `ast-verify`, `md-ascii`, `review-md`.
`--full` adds the **tests lane** (every dastest suite: `probes/`, `c_runtime/tests`,
`converter/tests`, `tests/`). `--only <gate>` runs one gate whatever changed, `--skip <gate>`
drops one, `--list-gates` prints the table. `PREFLIGHT_BASE` names the diff base
(default `origin/main`).

| Gate | What it runs | Red means |
|---|---|---|
| env | `scripts/verify_daslang.sh` | the toolchain lacks a part, or `DASLANG_ROOT` is behind the `VERSIONS.md` pin |
| untracked | `git ls-files --others --exclude-standard` | commit, ignore with a reason, or delete each file |
| format | `utils/das-fmt/dasfmt.das -- --verify` per `.das` folder | run the formatter (MCP `format_file` or the CLI) |
| lint | `utils/lint/main.das` over every `.das` folder | fix the finding; a `// nolint:CODE` needs its reason and is for a known false positive only |
| compile | `daslang -compile-only` per `.das` outside `fixtures/` | a file does not compile |
| ast-verify | `daslang -dry-run --ast-verify` per changed `.das` | an AST verify line or a crash: a bug in what built the node |
| md-ascii | added lines of rule documents | an em-dash, arrow or ellipsis in a rule document |
| review-md | `utils/internal/review-md/main.das -- --base <base>` | a `REVIEW.das` gate of a touched folder fired |
| tests | `dastest -- --test <suite>` per suite | a suite is red; the ratchet rule applies |

A red gate is fixed and re-run alone with `--only`; the full run happens once per PR. The
suites under `suites/` (c-testsuite, torture, csmith) are not preflight gates: their runners
keep their own ratchet state and run on their own schedule (`docs/very-detailed-plan.md`,
section 8).
