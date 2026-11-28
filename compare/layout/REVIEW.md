# compare/layout Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`.

**A diff to the oracle takes the record's description from clang's AST and its answer from
clang's layout, never one from the other: no attribute value, size or alignment of the
description is read from an offset clang computed.** A description derived from the answer makes
the comparison agree by construction.

**A diff to the comparison counts every record as agreeing, differing, refused or undescribed with
its reason, and never drops one.** A dropped record turns the oracle's zero differences into a
claim nothing checked.

**A diff to the clang flags here takes them from Dumper A (`dumper_frontend_flags`), never writes
its own, a corpus's include folder and sidecar defines excepted.** Two flag sets compare the layout
against a parse the converter never runs.
