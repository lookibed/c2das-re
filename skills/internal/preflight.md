# Preflight - the gates a change clears before it is pushed

`scripts/preflight.sh` runs the **fast tier** serially and stops at the first red:
`env`, `native`, `untracked`, `format`, `lint`, `compile`, `ast-verify`, `md-ascii`,
`review-md`. `--full` adds the **tests lane**: every dastest suite folder `gate_tests` in the
script lists, which `--list-gates` prints (`probes/`, `dasCRuntime/tests`, `c_runtime/tests`,
`converter/tests`, `lua/tests`, `perf/tests`, `metrics/tests`, `tests/`; a folder that does not exist is
skipped); a diff to that list changes this paragraph. `--only <gate>` runs one gate (`--only
tests` runs the lane alone), `--skip <gate>` drops one. `PREFLIGHT_BASE` names the diff base
(default `origin/main`; the root commit when that ref is absent). The format, lint and compile
gates cover the `.das` files under the folders `das_dirs` in the script lists, outside `fetch/`
and `work/`; a folder of house `.das` code outside that list is a defect of the script.

| Gate | What it runs | Red means |
|---|---|---|
| env | `scripts/verify_daslang.sh` | the toolchain lacks a part, or `DASLANG_ROOT` is behind the `VERSIONS.md` pin |
| native | `scripts/build_crt.sh` | `dasCRuntime/` (the `crt` module) does not build against `DASLANG_ROOT` |
| untracked | `git ls-files --others --exclude-standard` | an untracked file exists: commit it, ignore it with a reason, or delete it |
| format | `utils/das-fmt/dasfmt.das -- --verify` per `.das` file of every `.das` folder outside `fetch/` and `work/`; the first unformatted file is named | a file is not formatted: run the formatter (MCP `format_file` or the CLI) |
| lint | `utils/lint/main.das` over every `.das` folder outside `fetch/` and `work/`, LINT019 off | a finding: fix it; a `// nolint:CODE` needs its reason and is for a known false positive only |
| compile | `daslang -compile-only` per `.das` outside `fixtures/`, `fetch/` and `work/` | a file does not compile |
| ast-verify | `daslang -dry-run --ast-verify` per changed `.das` outside `fixtures/` | an AST verify line or a crash: a bug in what built the node |
| md-ascii | added lines of every `REVIEW*.md`, `ARCHITECTURE*.md`, `CLAUDE.md` and `AGENTS.md` in the tree and of `skills/internal/*.md` (`docs/` is never checked) | an em-dash, arrow or ellipsis in one of them |
| review-md | `utils/internal/review-md/main.das -- --base <base>` | a `REVIEW.das` gate of a touched folder fired |
| tests | `dastest -- --test <suite>` per suite; every suite runs before the lane fails | a suite is red: the failing test is fixed or its expectation corrected |

A red gate is fixed and re-run alone with `--only`; the full run happens once per PR. The
suites under `suites/` (c-testsuite, torture, csmith) are not preflight gates: their runners
keep their own ratchet state and run on their own schedule (`docs/very-detailed-plan.md`,
section 8).
