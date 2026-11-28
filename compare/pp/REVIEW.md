# compare/pp Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`.

**A diff to the comparison maps only clang's spelling of a fact the lexer states another way (a
kind name, the `[LeadingSpace]` rule of section 2), never forgives a difference.** A mapping that
hides a lexer defect turns the oracle's zero into a claim nothing checked.

**A diff to the clang flags here takes them from Dumper A (`dumper_frontend_flags`,
`DUMPER_FLAGS`), never writes its own.** Two flag sets compare the lexer against a preprocessing
the converter never runs.

**A diff to the directive oracle's classes (`pp2_difference_class`, `pp2_class`) classes every
difference on its own, never a unit by its first difference or by a count, and puts a difference
in the PP.3 class only when a macro token or a place left to PP.3 lies in it (section 4), and
never adds a class that waits for an item already done.** A difference with no macro is the
preprocessor's own defect, wherever it stands, and a class that took it would hide it.

**A diff that changes the clang flags, the clang pin, or what `pp_features.das` asks regenerates
the feature tables with `das compare/pp/run.das -- --features` in the same change** (that no hand
edits them is `frontend/REVIEW.md`'s duty). The tables' test in `compare/tests/test_pp_oracle.das`
fails on a table the pinned clang does not answer.

**A diff to the record's oracle (`pp_macros.das`) normalizes only what Dumper A and the record
spell differently (`pp5_normalized`: splices, comments, blanks; `pp5_macro_text_agrees`: the blank
Dumper A writes at a `#define`'s line splice), and counts a disagreement for every site, copy or
`macros` entry of Dumper A the record does not hold and for every copy of the record outside the
argument it names - never drops one from the count - and lists apart, never forgives, a use, a
call or a copy only the record knows.** Dumper A's marks are the
only outside check of the record; an oracle that forgives a mismatch passes a wrong record into
the C-IR.

