# web Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`. Planned work: `docs/implementation_order.md`. A diff to
`scripts/build_web.sh` applies this checklist too.

**A diff never adds a game data file (a `.wad`, a `.pak`, a release zip, an extract of one) to this folder,
to the site `scripts/build_web.sh` writes, or to the `gh-pages` checkout it fills.** The deploy
workflow downloads it into the Pages artifact only.

**A diff that changes which WAD the page or the workflow accepts keeps the check by the sha256 of
Freedoom 0.13.0 that the ports repository's `fetch_wad.sh` checks, in the page and in the
workflow both.**

**A diff to the timedemo in `puredoom/main_web.das` keeps its clock one tic per
`doom_force_update`, and a diff to the fold in `puredoom/tic_digest.das`, `puredoom_c/tic_digest.h`
or `ticDigest` in `puredoom/shell.html` changes the other two in the same change, so
`tests/test_web_tic_digest.das` still pins all three to the native log's count and digest.**

**A diff to `scripts/build_web.sh` keeps its refusals before its first write: a sidecar without
defines, an emscripten other than 5.0.7, a host at another commit than `VERSIONS.md`'s pin, a host
without libc++ or the browser gate, a failed PureDOOM fetch.**

**A diff never streams sound during a timedemo: the timed updates stay the game's alone.**

**A diff to `puredoom/main_web.das` or `puredoom_c/main_web.c` that changes a clock, a frame budget,
the key table, the checksum fold, the uncapped mode or an output line changes the other host the
same way in the same change: the page compares the two builds under one harness.**
