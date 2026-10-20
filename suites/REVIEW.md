# suites Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md` (beside this file). Planned work: `docs/implementation_order.md`.

**A diff that leaves the C program an id names unchanged - the suite's pin in `VERSIONS.md` and,
for csmith, what `csmith_program` (`csmith/generate.das`) writes for the seed - removes that id
from `expected_pass.txt` only by adding it to that suite's `skip.txt` in the same change; a test
that regresses any other way is fixed, never removed.**

**A diff adds an id to `skip.txt` only for a test that uses a C construct the converter refuses
with an error naming it (the dumper, the emitter or the compile check of the emitted module), or
that the converter's `--target` dialect excludes; the line names that construct and the id of
the `docs/implementation_order.md` row or phase that lifts it, or `never` for an excluded one.**

**Never weaken a check in `REVIEW.das` - fix what it flags instead.**

**A diff that changes a suite's pin in `VERSIONS.md`, or what `csmith_program`
(`csmith/generate.das`) writes for a seed, re-records that suite's `expected_pass.txt` with
`--update` from a run with no `--filter` (for csmith, with `--seeds 0` and no `--seed` or
`--from`, which judges every seed either file lists) and puts the run's summary in its commit
message, in the same change.**

**A diff that re-records a suite's `expected_pass.txt` after a pin change moves out of that
suite's `skip.txt` every id the run finds passing; for c-testsuite and gcc-torture, whose runner
skips ledgered ids, it re-judges them by hand until the runner can.**
