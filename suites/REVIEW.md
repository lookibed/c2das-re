# suites Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`. Planned work: `docs/implementation_order.md`.

**A run that judges an id is, for csmith, a `--seed` run naming it or a `--from` file listing it;
for c-testsuite and gcc-torture, a run with no `--filter`.** A run that judges every listed id is,
for csmith, `--seeds 0` with no `--seed` or `--from`, and for c-testsuite and gcc-torture a run
with no `--filter`.

**A diff that changes an id's verdict inputs - a suite's pin in `VERSIONS.md` (repo root;
csmith's is its `csmith:` line), what `csmith_program` (`csmith/generate.das`) writes for a seed,
or the csmith reference compiler's flags (`NATIVE_FLAGS` in `csmith/run.das`) or version (the
`gcc:` line of `VERSIONS.md`) - re-records that suite's `expected_pass.txt` with `--update` from a
run that judges every listed id, in the same change.**

**A diff that leaves every id's verdict inputs alone removes an id from `expected_pass.txt` only by
adding its `skip.txt` line in the same change, and otherwise fixes the regression.**

**A diff that changes an id's verdict inputs keeps a `skip.txt` line only for an id the line
marks `never`, or one that a run that judges the id, made with the line removed, still refuses
with an error naming the line's construct.**

**A diff adds or rewrites an id's `skip.txt` line naming a ledger row only for a test that uses
a C construct refused with an error naming it by the dumper, the emitter, the compile check of
the emitted module, or clang's diagnostics.**

**A `skip.txt` line a diff adds or rewrites names its construct and the id of the
`docs/implementation_order.md` row whose text names it, as the row's bold head spells it; a
line may name the class of clang diagnostics that refuses the test as its construct when the row
names that class.**

**A diff adds or rewrites a `skip.txt` line marked `never` only for a construct standard C99 does
not define, and the line's reason states why: no das emulation can exist, the converter's
`--target` dialect excludes it, or clang (the converter's frontend) rejects the program.**

**A diff that changes `gcc_torture/skip.txt` leaves it equal to what `gcc_torture/filter.das`
writes over the pinned tree and the diff's own `expected_pass.txt`.**

**A diff to `csmith/run.das` keeps `WORKER_BUDGET` below `WORKER_TIMEOUT` and caps every timed
child at what is left of the worker's budget, so the driver never kills a worker while a timed
child is alive.**

**Never weaken a check in `REVIEW.das` - fix what it flags instead.**

**A diff that changes a suite's `expected_pass.txt` puts in its commit message the summary line
of every `--update` run that wrote it - the runner's `<suite>: <status> <count>, ...`, or an
`--audit-skips --update` run's `<suite> skip audit: <n> passing ids joined ...` - and names each
id it adds or removes by hand.**

**A diff that removes an id's line from `skip.txt` lists that id in `expected_pass.txt` exactly
when an `--update` run judged it passing: an `--audit-skips --update` run made before the
removal, which joins the ids it passes, or a run that judges the id made after the removal.**
