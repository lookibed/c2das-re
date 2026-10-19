# suites Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md` (beside this file). Planned work: `docs/implementation_order.md`.

**A diff that removes from a suite's `expected_pass.txt` an id the suite still contains at the
commit `VERSIONS.md` pins adds that id to `skip.txt` in the same change.**

**A diff adds an id to `skip.txt` only for a test that fails because it uses a C feature the
converter does not support - any other failing test stays unlisted, a count in the runner's
summary.**

**Never weaken a check in `REVIEW.das` - a `skip.txt` or `expected_pass.txt` line the gate
rejects is fixed in that line.**

**A diff that changes a suite's pin updates `VERSIONS.md` and re-records
`expected_pass.txt` from a full run in the same change.**

**Never commit anything under `<suite>/fetch/` or `<suite>/work/` - `fetch.sh` and the runner
regenerate them; they stay gitignored.**
