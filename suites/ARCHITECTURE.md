# suites Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
holds the external C test suites that verify the backend: for each suite a fetch script, a
runner, the ratchet state and the skip ledger. Fetched inputs (`<suite>/fetch/`) and converted
output (`<suite>/work/`) are gitignored; only the runner and its two state files are tracked.

## 1. File charters

- `suite_runner.das` - the runner every suite shares: `run_suite_main(spec, verdict)` converts
  every `<id>.c` directly under the suite's tests folder into `work/<id>/` through
  `converter/pipeline.das` under the `linux` dialect (the baseline of a differential run is a
  native build on this host), runs the module under the interpreter with both module folders
  loaded and a per-suite timeout, and hands the exit code and merged output to the suite's
  verdict. Each test ends in one status: `pass`, `convert` (the dumper, the emitter or the
  compile check refused it), `exit`, `output`, or `skip`. The ratchet and the ledger live
  here too: a listed id that stops passing fails the run; an id that starts passing is
  reported and `--update` writes it in; a failing test that is not listed is a count in the
  summary, not a skip.
- `c_testsuite/fetch.sh` - clones c-testsuite at the commit `VERSIONS.md` pins into
  `c_testsuite/fetch/c-testsuite`; a checkout already at the pin is left alone.
- `c_testsuite/run.das` - the single-exec suite on the shared runner: a test passes when its
  module exits 0 with the merged output `<id>.c.expected` holds, the suite's contract.
- `gcc_torture/fetch.sh` - a blob-less sparse clone of gcc-mirror/gcc at the release tag and
  commit `VERSIONS.md` pins, holding only `gcc/testsuite/gcc.c-torture/execute`.
- `gcc_torture/filter.das` - the import's filter, run by hand after a fetch: every top-level
  `execute/*.c` whose text carries a GNU extension gets its `skip.txt` line, first matching
  rule wins - the dialect's exclusions (inline asm, `_Complex`, `__int128`, the non-standard
  floating types, vector types, atomics, GNU keywords) with the phase `never`, then the
  constructs a later row carries (`&&label` and `__label__` in P3, `__builtin_*` and
  `__attribute__` in P4). The `builtins/` and `ieee/` subfolders are not part of the suite.
- `gcc_torture/run.das` - the torture suite on the shared runner: a test passes when its module
  exits 0, the gcc harness's own contract (a failing test calls `abort`); output is not
  judged, as that harness does not judge it.
- `<suite>/expected_pass.txt` - the ratchet: the sorted ids that pass.
- `<suite>/skip.txt` - the ledger of tests never run: one tab-separated line per id with the
  feature, the reason and the phase that unblocks it, `never` for a feature the dialect
  excludes.
- `REVIEW.das` - the gate over both suites: `expected_pass.txt` sorted and unique, every
  `skip.txt` line in the four-field shape with a phase or `never`, no id in both files, and
  nothing tracked under a suite's `fetch/` or `work/`.
- `scripts/run_suite.sh <suite> [flags]` - fetches when needed and runs the runner from the
  repository root with `-load_module` for `dasCRuntime` and `c_runtime`.

## 2. Why the suites are not preflight gates

A full c-testsuite run converts 220 files and spawns clang and daslang for each, a minute on
this box, and the torture suite converts the 892 of its 1656 the ledger does not skip; the
preflight `tests` lane stays the sub-second
dastest suites. The runners keep
their own ratchet and run on their own schedule, the way `docs/very-detailed-plan.md`
section 8 describes.

## 3. Exception ledger

Empty.
