# perf/kernels Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `../ARCHITECTURE.md`. Planned work: `docs/implementation_order.md` (repo root).

**A diff that adds or edits a kernel so that it contains a `main`, an `#include`, a prototype of
`printf` or `clock`, or the kernel's expected result is a defect - declare each other libc
function the kernel calls with a prototype in the kernel file instead.** The harness supplies
`main` and those two prototypes, and the native lane's result is the value every das lane must
match.

**A diff that adds or edits a kernel makes `kernel_run` read a `volatile` file-scope static on
every call, pass the value it read to the functions it calls, and make the value
`kernel_result` returns depend on that static.** With a literal in its place, clang computes
the call once outside the harness's timing loop and daslang computes it at compile time, so
the run times nothing.
