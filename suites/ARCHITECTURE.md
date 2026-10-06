# suites Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
holds the external C test suites that verify the backend: for each suite a fetch script, a
runner, the ratchet state and the skip ledger. Fetched inputs (`<suite>/fetch/`) and converted
output (`<suite>/work/`) are gitignored; only the runner and its two state files are tracked.

## 1. File charters

- `c_testsuite/fetch.sh` - clones c-testsuite at the commit `VERSIONS.md` pins into
  `c_testsuite/fetch/c-testsuite`; a checkout already at the pin is left alone.
- `c_testsuite/run.das` - the single-exec runner: converts every `tests/single-exec/<id>.c`
  into `work/<id>/` through `converter/pipeline.das` under the `linux` dialect (the baseline
  of a differential run is a native build on this host), runs the module under the
  interpreter with both module folders loaded, and compares the merged output with
  `<id>.c.expected` and the exit code with 0, the suite's contract. Each test ends in one
  status: `pass`, `convert` (the dumper, the emitter or the compile check refused it), `exit`,
  `output`, or `skip`.
- `c_testsuite/expected_pass.txt` - the ratchet: the sorted ids that pass. A listed id that
  stops passing fails the run; an id that starts passing is reported and `--update` writes it
  in. A failing test that is not listed is a count in the summary, not a skip.
- `c_testsuite/skip.txt` - the ledger of tests never run: one tab-separated line per id with
  the feature, the reason and the phase that unblocks it.
- `REVIEW.das` - the gate: `expected_pass.txt` sorted and unique, every `skip.txt` line in
  the four-field shape with a phase, no id in both files.
- `scripts/run_suite.sh <suite> [flags]` - fetches when needed and runs the runner from the
  repository root with `-load_module` for `dasCRuntime` and `c_runtime`.

## 2. Why the suites are not preflight gates

A full c-testsuite run converts 220 files and spawns clang and daslang for each, a minute on
this box; the preflight `tests` lane stays the sub-second dastest suites. The runners keep
their own ratchet and run on their own schedule, the way `docs/very-detailed-plan.md`
section 8 describes.

## 3. Exception ledger

Empty.
