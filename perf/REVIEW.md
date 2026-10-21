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

**A diff that changes a file under `kernels/`, the prologue or epilogue `perf_compose.das` puts
around a kernel, an argument `run.das` passes to the native `clang` command, to `convert`, to
the `interp` or `jit` lane's `daslang` argv, or to a `run_tier` call, the `samples` default in
`run.das`'s `Args`, the `LANES` list in `perf_tables.das`, or `measure`, `cell_of`,
`median_of`, `last_line` or `accept_lane` in `run.das` beyond comments, re-records
`results_linux.json` from a `scripts/run_perf.sh` run with no `--filter` and no `--samples` in
the same change.**

**A diff after which the text between the perf-table markers of `README.md` (repo root) differs
from the results table `scripts/run_perf.sh --table` prints refreshes it with
`scripts/run_perf.sh --readme` in the same change.**
