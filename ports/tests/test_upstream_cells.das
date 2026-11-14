options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require ../upstream_cells.das

//! The cells a daslang defect slows: which program and lane a fork issue marks, the marked text,
//! and the footnote lines.

[test]
def test_upstream_issue(t : T?) {
    t |> run("an issue marks its program under its tier and the tier's variant lanes only") @(t : T?) {
        t |> equal(upstream_issue("sieve", "aot"), 48)
        t |> equal(upstream_issue("puredoom", "aot-fast"), 48)
        t |> equal(upstream_issue("sieve", "jit"), 0)
        t |> equal(upstream_issue("sieve", "aotx"), 0)
        t |> equal(upstream_issue("fib_loop", "aot"), 0)
    }
}

[test]
def test_upstream_marked(t : T?) {
    t |> run("a number gets the issue after it; a word, an empty cell or an unmarked cell stays") @(t : T?) {
        t |> equal(upstream_marked("8.07", "sieve", "aot"), "8.07 (#48)")
        t |> equal(upstream_marked("n/a", "sieve", "aot"), "n/a")
        t |> equal(upstream_marked("", "sieve", "aot"), "")
        t |> equal(upstream_marked("8.07", "sieve", "exe"), "8.07")
        t |> equal(upstream_marked("1.20", "binjgb", "aot"), "1.20")
    }
}

[test]
def test_upstream_footnotes(t : T?) {
    t |> run("one line per issue naming the shown programs it slows in table order, none without a marked lane") @(t : T?) {
        let lines <- upstream_footnotes(["fib_loop", "matmul", "sieve"], ["interp", "aot"])
        t |> equal(length(lines), 1)
        t |> success(lines[0] |> starts_with("- (#48) daslang's AOT generator reads every module global through a hash lookup"), lines[0])
        t |> success(lines[0] |> ends_with(" runs sieve 1.63, matmul 1.01 x native: [lookibed/daScript#48](https://github.com/lookibed/daScript/issues/48)."), lines[0])
        t |> equal(length(upstream_footnotes(["sieve"], ["interp", "jit"])), 0)
        t |> equal(length(upstream_footnotes(["fib_loop"], ["aot"])), 0)
    }
}
