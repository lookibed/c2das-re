# suites Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `suites/ARCHITECTURE.md`. Planned work: `docs/implementation_order.md` (sec. P1.5, P2.8,
P4.5).

**A diff that removes an id from a suite's `expected_pass.txt` is a defect unless the same
diff adds that id to `skip.txt` with its feature, reason and phase.** A pass count only goes up.

**A diff that adds a test to `skip.txt` names a feature the converter cannot carry, never a
test that merely fails today; weakening `REVIEW.das`, which checks the line shape, is a
defect.**

**A diff that changes a suite's pin updates `VERSIONS.md` and re-records
`expected_pass.txt` from a full run in the same change.**

**Never commit anything under `<suite>/fetch/` or `<suite>/work/`.**
