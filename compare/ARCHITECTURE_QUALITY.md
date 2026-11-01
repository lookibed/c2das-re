# compare Architecture - the quality comparison

Companion to `ARCHITECTURE.md` in this folder, its section 10.

## The corpus and the measures {#quality}

`run.das --quality` takes the inputs both sides translated into daslang that compiles: per suite of
the capture's `suites` section the ids whose Rust status is `pass`, `exit` or `output` and which the
suite's `expected_pass.txt` lists, and each kernel of its `perf` section the Rust side `ran`; a key
is `<suite>/<id>` or `perf/<kernel key>`. A key's C file is the one the earlier sections ran (a
csmith seed's by `csmith_source`, a kernel composed by the method and translated with
`-DC2DAS_NATIVE` as in `ARCHITECTURE.md` section 8). One worker process per key, `--jobs` at a time,
900 s each, converts it for `linux` and translates it with `translate_file`, no run, into
`work/quality/<key>/`.

Each side is measured by the readability metric's ten counters, `count_module` of
`metrics/readability_count.das`, over the module daslang runs (ours the one module the pipeline
writes, theirs the entry); one that does not compile as written is that side's `compile`. Size is
the count of `.das` and `.das.inc` files and their non-blank lines. The Rust translator writes its
runtime prelude (the `c2da_rt_` heap, the `c2da_std_` libc helpers) into every module, so its counts
and lines hold it; ours sits in `c_runtime` and `crt`.

The Rust side's `runtime_lines` are the non-blank lines of its emitted runtime: every top-level
declaration (`def`, `var`, `let`, `struct`, `enum`) whose name starts with `c2da_`, from its first
annotation line to the line before the next declaration's first line, the last to the end of the
file. The totals, per group and over `all`, sum each counter, the files, the lines and the runtime
lines over the keys both sides measured `ok`; `excluded` counts the rest by side and status
(`rust_compile`); `line_ratio` is the Rust lines over ours, `program_line_ratio` the Rust lines less
its runtime's over ours. The section `quality` is `{rust_commit, rust_commit_error, daslang, date,
keys, totals, functions}`, a key's entry `{ours, rust}`.

## The functions side by side {#side-by-side}

`SAMPLES` names the functions shown: four kernels' and `main` of the c-testsuite programs `00156` (a
counted loop) and `00205` (a struct array walked by two loops). A function is found by its C name: a
line opening `def `, `def private ` or `def public ` with the name, our `<stem>__<name>` of a
static, or C's `main` as each side renames it, `c_main` and `main_0` (`ARCHITECTURE.md` section 3).
Its text is the annotation lines right above, the `def` line and the lines up to the first `}` at
column 0, where both sides close a function; a `def` line not ending in `{` is the whole function,
and a side without it shows "". `functions` is `[{key, name, ours, rust}]` in `SAMPLES` order.
