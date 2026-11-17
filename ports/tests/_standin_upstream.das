options gen2

module _standin_upstream public

require ../upstream_cells.das

//! `blk` run with a stand-in #48 in the fork-issue lists, the lists emptied again after it: the
//! marking the tables did while #48 slowed the AOT cells, which the pin `b7d8f6f52f` fixed.
def with_standin_marks(blk : block<() : void>) {
    UPSTREAM_ISSUES |> push((issue = 48, what = "daslang's AOT generator reads every module global through a hash lookup (`das_global<T, mnh>`), though the AOT context fixes each global's offset when it is generated"))
    UPSTREAM_CELLS |> push(UpstreamCell(program = "puredoom", tier = "aot", issue = 48, fixed = 1.14lf, fixed_over = "readable, demo1"))
    UPSTREAM_CELLS |> push(UpstreamCell(program = "doomgeneric", tier = "aot", issue = 48, fixed = 1.13lf, fixed_over = "readable"))
    UPSTREAM_CELLS |> push(UpstreamCell(program = "sieve", tier = "aot", issue = 48, fixed = 1.63lf))
    UPSTREAM_CELLS |> push(UpstreamCell(program = "matmul", tier = "aot", issue = 48, fixed = 1.01lf))
    invoke(blk)
    UPSTREAM_ISSUES |> clear()
    UPSTREAM_CELLS |> clear()
}
