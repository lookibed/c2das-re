# perf Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `perf/ARCHITECTURE.md`. Planned work: `docs/implementation_order.md`.

**A diff that closes a ledger item of `docs/implementation_order.md` adds a kernel under
`kernels/` exercising what the item lowers, or names the kernel that already covers it, and
re-records `results_linux.json` from a full run in the same change.**

**A kernel is `kernel_run`, `kernel_check` and file-scope statics; a diff that adds a
`main`, a prototype or an include to a kernel is a defect.** The harness composes the rest.

**A kernel's parameter is a `volatile` static read inside `kernel_run`; a diff that passes a
literal to the kernel's function is a defect.** A literal lets clang hoist the call out of
the rep loop and lets daslang fold it at compile time, and the cell then measures nothing.

**A diff that changes the budget, the sample count or the lanes in `run.das` re-records
`results_linux.json` and refreshes the README table in the same change.**
