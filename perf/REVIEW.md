# perf Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`. Planned work: `docs/implementation_order.md`. A benchmark kernel,
wherever the diff puts it, also answers to the `kernels/` checklist.

**A diff whose `results_linux.json` names a different `cpu` than the committed file's pastes
into its commit message the text `--report <file>` writes on the `scripts/run_perf.sh` run that
records `results_linux.json`, run with `--baseline` and with no `--filter` and no `--samples`.**

**A diff whose `results_linux.json` names a different `cpu` than the committed file's gives
`--baseline` a json written on the diff's parent commit on the new CPU, and names that commit
and the command that wrote it in its commit message.**

**A diff whose `results_linux.json` names a different `cpu` than the committed file's gives in
its commit message the reason or the fix for every `FLAG` line its `--report` prints.**

**A diff that changes, beyond comments, what a timed lane runs or how its samples become a cell
- a file under `kernels/`, or, in `run.das`, `perf_measure.das`, `perf_lanes.das`,
`perf_compose.das` or `perf_tables.das`, the text around a kernel, a lane's argv or build, the
lane list, the sample count, or the sample arithmetic - re-records each capture whose lanes the
diff changes (`results_linux.json`, `results_method_linux.json`) from a `scripts/run_perf.sh` run
with no `--filter` and no `--samples` in the same change.** `ARCHITECTURE.md` section 7 lists the sites.

**A diff after which the text between the perf-table markers of `README.md` (repo root) differs
from the results table `scripts/run_perf.sh --table` prints refreshes it with
`scripts/run_perf.sh --table --readme` in the same change.**

**A table or report a diff adds never sets the numbers of two boxes side by side as a ratio.**
`ARCHITECTURE.md` section 5 states the box a capture records.

**A speedup a diff claims is the branch against main before it, measured on one box in one run.**
`ARCHITECTURE.md` section 5 states that a number carries its box.

**A diff that adds a table rendered from a capture labels its provenance line with
`boxes.das`'s `capture_label`.** `ARCHITECTURE.md` section 5 states the label.
