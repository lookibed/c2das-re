# c_runtime Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`. Planned work: `docs/implementation_order.md`.

**A diff that changes a piece's public surface updates its fixture test in the same change.** A
piece is a `.das` file `c_runtime/c_runtime/<name>.das` (repo root) and its fixture test is
`tests/test_<name>.das`; its public surface is a public function's signature, a public struct's
fields, a public global's name or type, and the argument grammar of an annotation or call macro,
each added, removed or changed.

**A call or annotation that a diff adds to or changes in a fixture test, and that the test expects
to compile and return normally, matches the converter's spelling in its argument types, its casts
and where its side effects sit; literal values and their radix are free.** The spelling is that of
the first of these that calls the function: the converter's output for a C file under
`converter/tests/fixtures/` (repo root); a `docs/probe-findings.md` row naming the piece; an example
in `docs/lowering-examples.md` or `docs/stdlib-examples.md`.

**A diff that adds a public overload that the converter's output for no C file under
`converter/tests/fixtures/` (repo root), no `docs/probe-findings.md` row and no `docs/` example
calls tests it by a direct call in the piece's fixture test.**

**Never weaken `REVIEW.das` - fix what it flags instead.**

**A diff that makes a piece's function, or code a piece's macro generates, store on the das heap
bytes the converted program can take the address of, or bytes that outlive the call that made
them, is a defect - keep them in C-allocator memory, globals or the stack instead.** The das heap
is memory daslang's garbage collector owns: an `array`, a `table`, a `string`, a `new`
allocation, a lambda capture.
