# suites Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`. Planned work: `docs/implementation_order.md`.

**A diff that leaves the C program an id names unchanged - the suite's pin in `VERSIONS.md` and,
for csmith, what `csmith_program` (`csmith/generate.das`) writes for the seed - removes that id
from `expected_pass.txt` only by adding its `skip.txt` line in the same change; otherwise it fixes
the regression.**

**A diff adds an id to `skip.txt` only for a test that uses a C construct the converter refuses
with an error naming it (the dumper, the emitter or the compile check of the emitted module), or
that the converter's `--target` dialect excludes; the line names that construct and the id of
the `docs/implementation_order.md` row or phase that lifts it, or `never` for an excluded one.**

**Never weaken a check in `REVIEW.das` - fix what it flags instead.**

**A diff that changes a suite's pin in `VERSIONS.md`, or what `csmith_program`
(`csmith/generate.das`) writes for a seed, re-records that suite's `expected_pass.txt` with
`--update` from a run with no `--filter` (for csmith, with `--seeds 0` and no `--seed` or
`--from`, which judges every seed `expected_pass.txt` lists), in the same change.**

**A diff that changes a suite's `expected_pass.txt` puts in its commit message the summary line -
the runner's `<suite>: <status> <count>, ...` - of every `--update` run that wrote it, and names
each id it adds or removes by hand.**

**A diff that removes an id's `skip.txt` line lists that id in `expected_pass.txt` exactly when
an `--update` run made after the line goes judged it passing: for csmith a `--seed` run naming
the id or a `--from` file listing it, for c-testsuite and gcc-torture a run with no `--filter`,
which judges an id in neither file.**

**A diff that changes a suite's pin in `VERSIONS.md`, or what `csmith_program`
(`csmith/generate.das`) writes for a seed, keeps a `skip.txt` line only for an id that a run made
with the line removed still refuses with an error naming the line's construct, or one the line
marks `never`: for csmith a `--seed` or `--from` run naming the id, for c-testsuite and
gcc-torture a run with no `--filter` - no suite's re-record run judges an id its `skip.txt`
lists.**
