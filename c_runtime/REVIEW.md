# c_runtime Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `c_runtime/ARCHITECTURE.md`. Planned work: `docs/implementation_order.md` (sec. P1).

**A diff that adds a piece to `c_runtime/` adds its as-if-converted fixture test under
`tests/` in the same change, shaped as `docs/lowering-examples.md` or
`docs/stdlib-examples.md` shows the converter emitting it.**

**A diff that adds a `.das` file under `c_runtime/c_runtime/` names it in `.das_module`;
weakening `REVIEW.das`, which checks that, is a defect.**

**A diff that lets C data reach the das GC heap - `new`, an `array` or `table` holding C
objects, a `string` standing in for a C string - is a defect.** C data lives in raw memory,
globals and the stack (`docs/stdlib-examples.md`, the GC ruling).
