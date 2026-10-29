# lua Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`. Planned work: `docs/implementation_order.md` (repo root).

**A diff that adds, changes, or removes a key of `lua.c2das` restates that key's entry in
`ARCHITECTURE.md` section 3 (its value and its reason), in the same change.**

**A diff that changes which sources `sources.das` lists for a program, or their order, restates
section 2 of `ARCHITECTURE.md` in the same change.**

**A diff that changes `profile.das`, the sources `sources.das` lists for `lua`, or the release on
the `lua:` line of `VERSIONS.md` (repo root) reruns `profile.das` from the repository root and
commits the `lua.profile.json` it writes, in the same change.**

**Never edit `lua.profile.json` by hand - rerun `profile.das` instead.**

**A diff that changes a `run.das` flag, default or output path restates it in `ARCHITECTURE.md`
section 1.**

**Never weaken a check in `REVIEW.das` - fix what it flags instead.**
