# compare/parse Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`.

**A diff to either side's reduction maps only clang's spelling of a fact the parser states
another way (a builtin type's canonical name, a node kind, the place of a first token), never
forgives a difference.** A mapping that hides a parser defect turns the oracle's `same` into a
claim nothing checked.

**A diff that makes the parser's side write a `?` adds its case, with the reason the tree alone
cannot spell clang's text there, to the list of section 3, and a fixture line that shows it.** A
`?` matches any text inside one type, so an unlisted one silently stops comparing a type.

**A diff that leaves a clang node or a field out of the comparison adds it, with its reason, to
the "Not compared" list of section 3.** An omission the document does not name reads as a
comparison that passed.

**A diff that leaves out a part of the parser's tree that clang's JSON does not show counts each
occurrence as a `note` line with its reason, so the run's totals print it under `not compared`.**
A part dropped in silence makes a unit `same` over a tree nothing compared.

**A diff to a named cause (`explained_by`, a cause the clang side writes on a line) lets it explain
only a difference of the type it names, in the shape section 7 lists, every other part of the line
compared as on any line.** A cause that accepts a whole line accepts any parser defect on it.

**A diff to the clang flags here takes them from Dumper A (`dumper_frontend_flags`,
`DUMPER_FLAGS`), never writes its own.** Two flag sets compare the parser against a
preprocessing the converter never runs.

**A diff to the stand-in for the unit entry (`parse_unit`) drops a clang declaration from the
comparison only when it starts in tokens the parser refused as a construct, and counts every
skip by its construct.** A wider drop hides a declaration the parser read differently.

**A diff that adds a fixture to `fixtures/` adds its expected verdict to the tests in the same
change.** A fixture with no verdict is compared by nothing.
