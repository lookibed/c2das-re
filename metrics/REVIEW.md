# metrics Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`. Planned work: `docs/implementation_order.md`.

**A diff that raises a metric on a `modules` key `readability_linux.json` held at the change's
base commit says, in the commit that records the raise, each raised metric, the keys it rose
in, and why.** One `inputs` group of `readability_linux.json` may stand for its keys when one
cause raised them all; a metric the base lacks counts as zero.

**A diff that adds keys under `modules` in `readability_linux.json` names them in the message of
the commit that adds them, or a whole `inputs` group when the diff adds every key of it, or names
the change to the suite's `suites/<suite>/expected_pass.txt` (repo root) that adds them.** The
`lua` and `perf` groups have no `expected_pass.txt`.

**A diff that changes, beyond comments, any code in `readability.das`, `readability_count.das`,
`readability_file.das` or `readability_inputs.das` that decides which counts `readability_linux.json` records re-records
it with `scripts/run_readability.sh --update` in the same change.**

**A diff that re-records `readability_linux.json` puts the totals table
`scripts/run_readability.sh --update` prints in its commit message.**

**A diff that changes, beyond comments, any code in `criteria.das`, `criteria_scan.das`,
`criteria_count.das`, `criteria_defines.das`, `criteria_file.das` or `readability_inputs.das`
that decides which counts `criteria_linux.json` records re-records it with
`scripts/run_criteria.sh` in the same change, and puts the table that run prints in the message
of the commit that records it.**

**Never weaken a check `REVIEW.das` runs - in that file, or in `check_capture` or
`check_input_keys` of `readability_file.das`, or `check_criteria` of `criteria_file.das` - fix what
it flags instead.**
