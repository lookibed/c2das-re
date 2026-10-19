# suites Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md` (beside this file). Planned work: `docs/implementation_order.md`.

**A diff removes an id from a suite's `expected_pass.txt`, while the C program that id names is
unchanged (the suite's pin in `VERSIONS.md` and `CSMITH_OPTIONS` in `csmith/run.das` as they
were), only for a test the converter now refuses with an error naming its C construct, and it
adds that id to `skip.txt` in the same change - a test that regresses any other way is fixed,
never removed.**

**A diff adds an id to `skip.txt` only for a test that uses a C construct the converter refuses
with an error naming it (the dumper, the emitter or the compile check of the emitted module), or
that the dialect excludes; the line names that construct and the `docs/implementation_order.md`
row or phase that lifts it (`P4.7`, `P4`), or `never` for an excluded one.**

**Never weaken a check in `REVIEW.das` - fix what it flags instead.**

**A diff that changes a suite's pin in `VERSIONS.md`, or `CSMITH_OPTIONS` in `csmith/run.das`,
re-records that suite's `expected_pass.txt` and `skip.txt` in the same change, from a run over
every test the fetched suite holds - for csmith, every seed either file lists (`--from`).**
