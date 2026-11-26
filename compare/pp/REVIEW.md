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
in a PP.3 or PP.4 class only when a macro token or a place left to PP.3 or PP.4 lies in it (section
4).** A difference with no macro and no `#if` left to PP.4 is a PP.2 defect, wherever it stands,
and a class that took it would hide it.
