# suites Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`. Planned work: `docs/implementation_order.md`.

**A diff that leaves an id's verdict inputs unchanged - the suite's pin in `VERSIONS.md` (repo
root) and, for csmith, what `csmith_program` (`csmith/generate.das`) writes for the seed,
`NATIVE_FLAGS` (`csmith/run.das`) and the `gcc:` line of `VERSIONS.md` - removes that id from
`expected_pass.txt` only by adding its `skip.txt` line in the same change; otherwise it fixes
the regression.**

**A diff adds or rewrites an id's `skip.txt` line naming a ledger row only for a test that uses
a C construct the converter refuses with an error naming it (the dumper, the emitter or the
compile check of the emitted module); the line names that construct and the id of the
`docs/implementation_order.md` row whose text names it, as the row's bold head spells it,
never a bare phase `P<n>`.**

**A diff adds or rewrites a `skip.txt` line marked `never` only when the converter's `--target`
dialect excludes the construct the line names, or clang (the converter's frontend) rejects the
program.**

**A diff that changes `gcc_torture/skip.txt` leaves it equal to what `gcc_torture/filter.das`
writes over the pinned tree and the diff's own `expected_pass.txt`, and gives every entry of
`RULES` (`gcc_torture/filter_rules.das`) a `phase` that is a ledger row id or `never`, the same as
the lines it writes.**

**A diff that adds or rewrites a `skip.txt` line names in its phase column `never` or a row of a
phase above the highest closed one (the highest `v0.<N>.0` tag, at least phase 4), never a
closed phase's row.**

**Never weaken a check in `REVIEW.das` - fix what it flags instead.**

**A diff that changes a suite's pin in `VERSIONS.md` (repo root; csmith's is its `csmith:`
line), what `csmith_program` (`csmith/generate.das`) writes for a seed, or the reference
compiler of the csmith differential - its flags (`NATIVE_FLAGS` in `csmith/run.das`) or its
version (the `gcc:` line of `VERSIONS.md`) - re-records that suite's `expected_pass.txt` with
`--update` from a run with no `--filter` (for csmith, with `--seeds 0` and no `--seed` or
`--from`, which judges every seed `expected_pass.txt` lists), and keeps a `skip.txt` line only
for an id that a run made with the line removed still refuses with an error naming the line's
construct, or one the line marks `never` (for csmith a `--seed` run naming the id or a `--from`
run naming it, for c-testsuite and gcc-torture a run with no `--filter`), in the same change.**

**A diff that changes a suite's `expected_pass.txt` puts in its commit message the summary line -
the runner's `<suite>: <status> <count>, ...` - of every `--update` run that wrote it, and names
each id it adds or removes by hand.**

**A diff that removes an id's line from `skip.txt` lists that id in `expected_pass.txt` exactly
when an `--update` run made after that removal judged it passing: for csmith a `--seed` run
naming the id or a `--from` file listing it, for c-testsuite and gcc-torture a run with no
`--filter`, which judges every id neither file lists.**
