# c_runtime Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`. Planned work: `docs/implementation_order.md`.

**A diff that adds a piece (a `.das` file in `c_runtime/c_runtime/`, repo root) or changes a
piece's signature writes or updates its fixture test under `tests/` in the same change. The test
calls the piece the way the converter emits the call: a `docs/probe-findings.md` row that names
the piece wins over an example in `docs/lowering-examples.md` or `docs/stdlib-examples.md`. A
piece no converted code calls directly - a support module for other pieces' macros - is tested
through its public functions.**

**Never weaken `REVIEW.das` - fix what it flags instead.**

**A diff that makes run-time code of a converted program (a `c_runtime/` function, or code a
`c_runtime/` macro generates) store a C object's bytes or a C string in GC-managed memory is a
defect - keep them in C-allocator memory, globals or the stack instead.**
