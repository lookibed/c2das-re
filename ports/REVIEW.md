# ports Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`. Planned work: `docs/implementation_order.md`.

**A diff that changes a file a publish writes into the clone never makes its text depend on the
clock of the publish - keep seconds and timestamps in the conversion's log or a capture
instead.** A publish of an unchanged tree with the same flags then changes no file.

**A diff that adds or moves a refusal of the publisher makes it refuse before the first write into
the clone - never after it.**

**Never make the publisher delete a file in the clone - a file it no longer writes is removed by
hand in the ports repository instead.**

**A diff that changes how a measuring publish times a sample, warms a lane up, takes a cell's
median or spread, or judges a sample against the native oracle restates it in `ARCHITECTURE.md`
section 4, in the same change.**
