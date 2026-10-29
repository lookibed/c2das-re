# ports Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`. Planned work: `docs/implementation_order.md`.

**A diff to `publish.das` or `ports_render.das` never makes any file a publish writes into the
clone, other than a `perf/capture_*.json`, depend on the time of the publish. Keep seconds in
`lua/work/publish_run.log` or the capture instead.** The clone is the c2das-ports checkout
`publish.das` writes (`--repo`, then `$C2DAS_PORTS`, then `../c2das-ports`). A publish without
`--perf` of an unchanged tree with the same flags then changes no file.

**A diff that adds or moves a refusal of `publish.das` makes it refuse before the first write into
the clone - never after it.**

**Never make `publish.das` delete a file in the clone - a file it no longer writes is removed by
hand in the ports repository instead.**

**A diff that changes how `publish.das` times a run under `--perf`, its warm-up runs, the median or
spread of a cell (one program and lane's samples), or the check of a run against the native
build's first run, restates the change in `ARCHITECTURE.md` section 4, in the same change.**
