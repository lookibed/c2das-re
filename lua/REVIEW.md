# lua Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`. Planned work: `docs/implementation_order.md` (repo root).

**A diff that changes the release or a hash on the `lua:` line of `VERSIONS.md` (repo root)
changes `SOURCES` in `sources.das` to the release's folder, in the same change.**

**A diff that adds or changes a key of `lua.c2das` states the key's value and its reason in
`ARCHITECTURE.md` section 3, in the same change.**

**A diff that changes which sources `sources.das` composes, their order or the macros before them
restates the composition in `ARCHITECTURE.md` section 2, in the same change.**

**Never weaken a check in `REVIEW.das` - fix what it flags instead.**
