# perf Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `perf/ARCHITECTURE.md`. Planned work: `docs/implementation_order.md`.

**A diff whose `results_linux.json` names a different `cpu` than the committed file's also puts
in its commit message the `--report` of a run against `--baseline <json>`, where `<json>` is a
capture of the parent commit's tree on the new CPU, with the reason or the fix for every `FLAG`
line it prints.**

**A diff that adds to a kernel under `kernels/` a `main`, an `#include`, a prototype of `printf`
or `clock`, or the kernel's expected result is a defect.** The harness supplies `main` and those
two prototypes, and the native lane's result is the oracle; a libc function the kernel calls is
declared by its own prototype.

**A kernel's input size lives in a `volatile` file-scope static that `kernel_run` reads on every
call; a diff that passes a literal to the function `kernel_run` times is a defect.** With a
literal argument, clang computes the call once outside the timing loop and daslang computes it
at compile time, so the cell times nothing.

**A diff that changes the budget, the sample count, or how a lane is built or run in `run.das`,
or the `LANES` list in `perf_tables.das`, re-records `results_linux.json` in the same change.**

**A diff that changes `results_linux.json` refreshes the perf table of `README.md` (repo root)
with `--readme` in the same change.**
