# doom Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`. Planned work: `docs/implementation_order.md` (repo root).

**A diff that changes a patch under `patches/`, the `puredoom:` or `freedoom:` line of
`VERSIONS.md` (repo root), `host/doom_main.c`, the units `sources.das` lists or the sidecar's
`defines` reruns `run.das --native --demo N` for each of demo1, demo2 and demo3 and commits the
logs it writes under `work/ref/`, copied to `ref/`, in the same change.**

**Never commit a `.wad` file.**

**Never commit a file of PureDOOM: it is fetched by `fetch.sh` at the pin; a change to its source
is a patch under `patches/`.**

**Never move a file of this folder, which is GPL-2, into an MIT folder, and never copy PureDOOM's
code into one.**

**A new file of C this folder adds (a patch, a host) carries the GPL-2 notice the patch and the
host carry.**

**A diff that adds, changes, or removes a key of `doom.c2das` restates that key's entry in
`ARCHITECTURE.md` section 5 (its value and its reason), in the same change.**

**A diff that changes a `run.das` flag, default or output path restates it in `ARCHITECTURE.md`
section 1.**

**Never weaken a check in `REVIEW.das` - fix what it flags instead.**
