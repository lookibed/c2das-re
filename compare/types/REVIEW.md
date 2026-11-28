# compare/types Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`.

**A diff to the comparison compares entries by their structural names and classes a unit by
section 2's classes only, never forgives a difference: a declaration-order difference is printed
and fails the run.** A forgiving rule turns the oracle's zero into a claim nothing checked.

**A diff to the clang flags here takes them from Dumper A (`dumper_frontend_flags`,
`default_clang`), never writes its own.** Another flag set compares the builder against a dump the
converter never makes.

**A diff to `declaration_order` reaches only what Dumper A's declarations and `decl` statements
name, never an expression's type, and keeps the hoisted declarations at their places (section
3).** An expression type there hides the interleave C.3 must reproduce, and a misplaced hoisted
declaration reports a builder defect that is the reconstruction's.
