# metrics Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`. Planned work: `docs/implementation_order.md`.

**A diff that raises a metric of a `modules` key that `readability_linux.json` already holds at
the commit the change starts from - a metric the file lacks there counts as zero - says, in the
message of the commit that records the raise, each raised metric, the keys it rose in - by name,
or as a whole group of the `inputs` groups when one cause raised it there - and why.**

**A diff that adds keys under `modules` in `readability_linux.json` names them in the message of
the commit that adds them.**

**A diff that changes `readability_count.das`, or `c_file_of` or `measure_one` in
`readability.das`, beyond comments re-records `readability_linux.json` with
`scripts/run_readability.sh --update` in the same change and puts the run's totals table in
its commit message.**

**Never weaken a check `REVIEW.das` runs - in that file, or in `check_capture` or
`check_input_keys` of `readability_file.das` - fix what it flags instead.**
