# ports Architecture: cells a daslang defect slows

Read `ARCHITECTURE.md` (this folder) first. This companion holds how a table cell that a daslang
defect slows says so: `upstream_cells.das`, the list of those cells and the text that marks them;
`tests/test_upstream_cells.das`, its functions over the committed list.

## 1. The list {#upstream-cells}

`UPSTREAM_CELLS` names each program or perf kernel whose cells under one tier a daslang defect
slows: the program (the ports directory's name, or the kernel's), the tier, the lookibed/daScript
fork issue, and the x native the same build gives with the defect worked around (by hand or by a
patched generator), with what that number is over. A cell is listed only when an A/B proves the cause.
On the pin `b7d8f6f52f` both lists are empty: #48 (the AOT generator read every module global
through a hash lookup) is fixed upstream (#4652), and PureDOOM's, doomgeneric's and the kernels
`sieve`, `str_copy`, `switch_local` and `matmul` AOT cells, the cells it slowed, run at the x
native its worked-around A/B gave (`perf/ARCHITECTURE_EXCEPTIONS.md`). `UPSTREAM_ISSUES` holds, per
issue, what it does to a cell, in the order the footnotes take. Both lists are `var`s, which
`tests/_standin_upstream.das` fills with the former #48 entries while a table test runs. The list lives in the code, not in
a capture or a variant file, since it is a fact of the daslang pin that every capture and variant of
the program shares, and the perf kernels have no variant file.

A tier's cells are the tier's lane and each of its variant lanes (`aot` and `aot-fast`).
`upstream_marked` writes the issue after a cell holding a number (`5.19 (#48)`) and leaves a word
(`n/a`, `not yet`, an error) as it is. `upstream_footnotes` gives one line per issue that marks a
shown program under a shown lane: what the issue does, each such program's worked-around x native
in the list's order, and the issue's link.

## 2. The tables that mark

- A program's variants table (`render_variants`, `ARCHITECTURE_VARIANTS.md` section 3): the
  `x native` cell per tier, the footnote among the lines under the table.
- PureDOOM's frame-rate table (`doom/fps.das`'s `render_fps`): each lane's `/ native` ratio, the
  footnote under the table.
- The head-to-head's speed table (`compare/compare_render.das`'s `perf_table`): our side's cell of
  each kernel, the footnote under the table after `Ours:`. The Rust side's cells are not marked:
  the A/B measured our generated C++ only.

A cell the defect no longer slows (the issue fixed upstream and the pin moved past it) leaves the
list in the change that re-captures it.
