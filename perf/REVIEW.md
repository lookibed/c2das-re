# perf Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `perf/ARCHITECTURE.md`. Planned work: `docs/implementation_order.md`.

**A diff whose `results_linux.json` names a different `cpu` than the committed file's also puts
in its commit message the `--report` of the `scripts/run_perf.sh` run that records the file, run
with no `--filter` and no `--samples` and with `--baseline <json>`, where `<json>` is a
`results_linux.json` written on the parent commit's tree on the new CPU, with the reason or the
fix for every `FLAG` line it prints.**

**A diff that adds or edits a benchmark kernel so that it contains a `main`, an `#include`, a
prototype of `printf` or `clock`, or the kernel's expected result is a defect - declare each
libc function the kernel calls with a prototype in the kernel file instead.** The harness
supplies `main` and those two prototypes, and the native lane's result is the value every das
lane must match.

**A diff that adds or edits a kernel makes `kernel_run` read, on every call, a `volatile`
file-scope static that its result depends on, and pass that value to the functions it calls.**
With a literal in its place, clang computes the call once outside the harness's timing loop and
daslang computes it at compile time, so the run times nothing.

**A diff that changes a file under `kernels/`, the prologue or epilogue `perf_compose.das` puts
around a kernel, a command `run.das` builds or runs a lane with, the default sample count, or
the `LANES` list in `perf_tables.das` re-records `results_linux.json` from a
`scripts/run_perf.sh` run with no `--filter` and no `--samples` in the same change.**

**A diff that changes `results_linux.json` refreshes the perf table of `README.md` (repo root)
with `scripts/run_perf.sh --readme` in the same change.**
