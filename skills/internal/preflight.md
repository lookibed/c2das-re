# Preflight - the gates a change clears before it is pushed

`scripts/preflight.sh` runs the **fast tier** serially and stops at the first red:
`env`, `native`, `untracked`, `format`, `lint`, `compile`, `ast-verify`, `md-ascii`,
`review-md`, `criteria`. `--full` adds the **tests lane**: every dastest suite folder `suite_order` in the
script lists, which `--list-gates` prints (`probes/`, `dasCRuntime/tests`, `c_runtime/tests`,
`converter/tests`, `lua/tests`, `perf/tests`, `ports/tests`, `metrics/tests`, `compare/tests`,
`doom/tests`, `tests/`; a folder that does not exist is skipped); a diff to that list changes this
paragraph. The lane runs up to `--jobs N` suites at once (default 4) inside the preflight's own
process tree, so one `heavy` job covers it; each suite's output is buffered and printed in
`suite_order` once it and every suite before it have ended, and the lane is red when any suite
is. `--jobs 1` is the sequential lane: one suite after another, single-threaded, output
streamed. `PREFLIGHT_TEST_GROUPS="<a> <b>;<c>"` replaces the lane's suites (`;` between groups
that may run at once, a space between suites that run one after another, printed in the order
named): the way a pull request runs only the suites its diff touches (`AGENTS.md`), and the hook
`tests/test_preflight.das` drives with stand-in suites. `--only <gate>` runs one gate (`--only
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
| criteria | `metrics/criteria.das -- --report --delta-ref <base>`: prints the readability criteria table of the committed `metrics/criteria_linux.json`, its delta against the base's, and a `stale:` line per sample input that measures differently now | the capture is missing or unreadable; a stale sample or a fallen percentage is reported, never red: re-record with `scripts/run_criteria.sh` |
| tests | `dastest -- --test <suite> --failures-only` per suite, `--jobs` suites at once, the isolated suites under `--isolated-mode`; every suite runs before the lane fails | a suite is red: the failing test is fixed or its expectation corrected |

A red gate is fixed and re-run alone with `--only`; the full run happens once per PR. The
suites under `suites/` (c-testsuite, torture, csmith) are not preflight gates: their runners
keep their own ratchet state and run on their own schedule (`docs/very-detailed-plan.md`,
section 8).

## The tests lane's collision map

Which shared paths each suite writes, found by a full run under a write watcher (every 15 s, the
tree and `/tmp` against the suite then running) and by reading the tests. A suite that writes a
path another suite writes or reads runs in one `test_groups` entry with it; today no two suites
collide, so every group is one suite. A new suite, or a test that writes a fixed path outside a
`create_temp_directory` folder, updates this table and `test_groups` in the same change.

| Suite | Writes | Conflicts with |
|---|---|---|
| `probes` | temp folders | none |
| `dasCRuntime/tests` | temp folders | none |
| `c_runtime/tests` | temp folders (its JIT cache under one) | none |
| `converter/tests` | temp folders (stand-in roots for the suite runners) | none |
| `lua/tests` | a temp stand-in root (`lua/work`, `lua/fetch` inside it) | none |
| `perf/tests` | `perf/work/` (`audit`, `blit`, `fib_loop`, `fib_recursive`, `first_member`, `lanes_*`) | none; its own files share `perf/work/audit` |
| `ports/tests` | temp stand-in roots | none |
| `metrics/tests` | `metrics/work/` (`perf`, `c_testsuite`, `csmith`) | none; its two files share `metrics/work` |
| `compare/tests` | `compare/work/` (`perf`, `quality`, `gcc_torture`, `cmp_quality_*`), temp folders | none; `test_quality` and `test_rust_translator` share `compare/work/quality` |
| `doom/tests` | temp folders (`doom_demo_run_*`, `doom_convert_*`) | none |
| `tests` | temp stand-in suites | none |

Every suite also writes three shared caches, safe under concurrency: `.cache/daslang/` (the JIT's
objects, named by content hash, and the module cache), and `dasCRuntime/.das_module.manifest`
and `c_runtime/.das_module.manifest` (rewritten through a temp file and a rename, the same rows
from every writer). No suite binds a port.

`isolated_suites` run each test file in its own dastest worker (`--isolated-mode`, `iso_threads`
workers): `probes`, `converter/tests`, `c_runtime/tests` and `doom/tests`, whose files write only
their own temp folders. `perf/tests`, `metrics/tests` and `compare/tests` do not: their files share
a work folder, named above. `lua/tests`, `ports/tests` and `dasCRuntime/tests` are one long file
or one short one, where a worker buys nothing.
