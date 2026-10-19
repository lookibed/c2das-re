# c_runtime Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md` (beside this file). Planned work: `docs/implementation_order.md`.

**A diff that adds a piece to `c_runtime/` adds its as-if-converted fixture test under
`tests/` in the same change, shaped as the converter emits it: the `docs/probe-findings.md` row
on that piece's example when one exists, else the example in `docs/lowering-examples.md` or
`docs/stdlib-examples.md`; weakening `REVIEW.das`, which checks that the test file exists, is a
defect.**

**A diff that adds a `.das` file under `c_runtime/` (the module folder, beside this file) names
it in `.das_module`; weakening `REVIEW.das`, which checks that, is a defect.**

**A diff that makes run-time code of a converted program (a `c_runtime/` function, or code a
`c_runtime/` macro generates) store a C object's bytes or a C string in GC-managed memory is a
defect - keep them in C-allocator memory, globals or the stack instead.**
