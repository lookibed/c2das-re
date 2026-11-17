# web Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`. Planned work: `docs/implementation_order.md`. A diff to
`scripts/build_web.sh` applies this checklist too.

**A diff never adds a game data file (a `.wad`, a release zip, an extract of one) to this folder,
to the site `scripts/build_web.sh` writes, or to the `gh-pages` checkout it fills.** The deploy
workflow downloads it into the Pages artifact only.

**A diff that changes which WAD the page or the workflow accepts keeps the check by the sha256 of
Freedoom 0.13.0 that the ports repository's `fetch_wad.sh` checks, in the page and in the
workflow both.**

**A diff to the timedemo in `puredoom/main_web.das` keeps its clock one tic per
`doom_force_update` and its checksum fold byte for byte the one `puredoom/shell.html` applies to
the native log; a change to either side changes the other in the same change.**

**A diff to `scripts/build_web.sh` keeps its refusals before its first write: a host at another
commit than `VERSIONS.md`'s pin, a host without libc++, an emscripten other than 5.0.7.**
