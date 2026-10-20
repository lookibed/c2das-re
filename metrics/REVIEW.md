# metrics Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md` (beside this file). Planned work: `docs/implementation_order.md`.

**A diff that raises a total in `readability_linux.json` above its value at the commit the
change starts from (a total absent there counts as zero) says, in the message of the commit
that records the raise, which metric rose and why.**

**A diff that changes `readability_count.das`, or `c_file_of` or `measure_one` in
`readability.das`, beyond comments re-records `readability_linux.json` with
`scripts/run_readability.sh --update` in the same change and puts the run's totals table in
its commit message.**

**Never weaken a check `REVIEW.das` runs - in that file, or in `check_capture` or
`check_input_keys` of `readability_file.das` - fix what it flags instead.**
