# c_runtime Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`. Planned work: `docs/implementation_order.md`.

**A diff that changes a piece's public surface updates its fixture test `tests/test_<name>.das`
in the same change.** A piece is a `.das` file `c_runtime/c_runtime/<name>.das` (repo root); its
public surface is a public function's signature, a public struct's fields, a public global's
name or type, and the argument grammar of an annotation or call macro, each added, removed or
changed.

**A diff that adds or changes a call or annotation in a piece's fixture test (`tests/test_<name>.das`
for the piece `c_runtime/c_runtime/<name>.das`, repo root) that the test expects to compile and
return normally spells it exactly as the converter emits it.** The order of sources is: the
converter's output for a C file under `converter/tests/fixtures/` (repo root) that calls the
piece, then a `docs/probe-findings.md` row naming the piece, then an example in
`docs/lowering-examples.md` or `docs/stdlib-examples.md`. A public function that none of these
sources calls is tested by a direct call.

**Never weaken `REVIEW.das` - fix what it flags instead.**

**A diff that makes run-time code of a converted program (a piece's function, or code a
piece's macro generates) store bytes the converted program can take the address of, or that
outlive the piece's call that made them (a C object, a C string), on the das heap (an `array`,
`table`, `string`, `new` allocation, or a lambda capture) is a defect - keep them in
C-allocator memory, globals or the stack instead.**
