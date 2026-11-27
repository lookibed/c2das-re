# compare/types Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`.

**A diff to the comparison compares entries by their structural names and classes a unit by
section 2's classes only, never forgives a difference: a declaration-order difference is printed
and fails the run.** A forgiving rule turns the oracle's zero into a claim nothing checked.

**A diff to the clang flags here takes them from Dumper A (`dumper_frontend_flags`,
`default_clang`), never writes its own.** Another flag set compares the builder against a dump the
converter never makes.

**A diff to the C-IR comparison (`cir_difference`, `stmt_difference`, `expr_difference`) sets
aside only the fields section 2 names - places, the macro fields and the source parentheses - never a type, a cast or a value.** Each field set aside is a difference the C-IR
byte diff of C.6 will still see, and only those have an owner outside this item.
