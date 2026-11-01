# compare Architecture - the report

Companion to `ARCHITECTURE.md` in this folder, its section 11.

## The rendering {#report}

`compare_render.das` turns the capture `results_linux.json` into markdown and reads nothing else:
each table and list is a pure function of the parsed capture, and a section the capture lacks
renders as one line saying so (`No suite is captured yet.`), never as an error. Three places print
the same text, `compare_report`:

- `run.das --readme` rewrites `README.md` (repository root) between `<!-- compare:begin -->` and
  `<!-- compare:end -->`, keeping the text around them, through `perf/perf_cli.das`'s
  `update_readme`; a README without both markers is refused and left as it was.
- `run.das --report <path>` writes the same text under a title, after the open lines of
  `docs/rulings-pending.md` when that file has any, since every report opens with them.
- `ports/publish.das` appends it to the ports repository's top-level README as the section
  `Head-to-head with the Rust translator` when the c2das-re tree it runs in holds the capture; a
  capture that does not read stops the publish.

The tables use `ports/ports_render.das`'s `table_of` (daslib's `md_boost` with the first columns
aligned left); `STATUSES` and `ALL_GROUPS`, which the suite and quality comparisons write with,
live in `compare_render.das` so that the writers and the renderer share one list.

## What each part reads

- Suites: per suite of `suites`, `ids`, `ours_pass` (the ratchet), the Rust `pass` and its
  breakdown by our tag, then the count of every status of `STATUSES` but `pass`; a total row when
  two or more suites are captured.
- Speed: the native column is the native cell's `time` in seconds, as the capture holds it;
  `perf.lanes` less `native` gives the other columns; a cell is the lane's `time` over the
  kernel's native `time`, two decimals, or the error in short form (`differs`, `timeout`,
  `compile` for a build that left no binary, `exit`, `convert`, else `error`; a refused Rust
  translation is `refused` in each Rust column); the geomean row is the capture's `perf.geomean`,
  not recomputed, with its kernel count, `n/a` when the count is 0. Every error cell is listed in
  full below the table, clipped at 160 characters.
- Readability and size: `quality.totals` per group, sorted, `all` last: the keys counted, both
  sides' files and lines, the Rust runtime lines and the Rust lines without them, `line_ratio` and
  `program_line_ratio`; the groups' `excluded` counts; then each counter of `metrics/`'s
  `METRICS` over `all`.
- Functions side by side: each entry of `quality.functions` as a heading naming the key and the C
  name, then both texts as fenced `das` blocks; a side whose text is "" is said to lack it.
- Lua and Doom: `lua.status`; a refusal shows the text after `cause=` of the error, then the gap
  (or `gap_error`), the pointer to the ports repository for our Lua numbers and to the pending
  ruling; `doom.status` and `doom.reason`.
- Where the Rust translator is ahead, one line a fact, by a margin `AHEAD_MARGIN` of 5%: a suite
  whose Rust `pass` exceeds our `ours_pass`; a kernel and lane whose ratio ours exceeds the Rust
  one by more than the margin and, relative to the Rust ratio, by more than either cell's
  `spread`, or where the Rust side has a cell and ours has none; a lane whose geomean ours exceeds
  by more than the margin over a non-zero kernel count; a counter whose `all` total ours exceeds
  the Rust one by more than the margin; the Rust lines without its runtime likewise below ours.
  A difference within the margin or within a cell's spread is not listed.
