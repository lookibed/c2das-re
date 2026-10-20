# perf Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
is the performance comparison of `docs/very-detailed-plan.md` section 2: C kernels, the
harness that times them under every lane, and the stored results.

## 1. File charters

- `kernels/<name>.c` - one kernel each: a `static void kernel_run(void)` and a
  `static int kernel_result(void)` over file-scope statics, nothing else; no kernel knows
  its expected result, the native lane measures it and every das lane must reproduce it or
  its cell is an error. The first three are
  dasProfile's scalar kernels with its parameters (`primes` 14000, `fib_loop` 6511134,
  `fib_recursive` 31), so a cell here compares with the same row of dasProfile's table.
  The other kernels each cover one ledger item's constructs: `fixed_mandel` is
  P2.1's, a 16.16 fixed-point Mandelbrot over struct vectors passed and returned by value;
  `sieve` and `matmul` are P2.2's, a sieve over a fixed byte array and a 96x96 product over
  two-dimensional arrays; `blit` is P2.3's, a byte copy through walking pointers over
  malloc'd buffers. The kernel's
  parameter is a `volatile` static that `kernel_run` reads on every call: with a literal
  argument clang hoists the idempotent call out of the rep loop (the native lane reports
  zero), and daslang's optimizer evaluates a pure call with constant arguments at compile
  time whatever `infer_time_folding` says, so the interpreter lane measured a store. The
  converter drops `volatile`, which is what makes the das read a plain global read that no
  pass folds.
- `run.das` - the harness: composes each kernel with the profile prologue (the `printf` and
  `clock` prototypes, the CRT's `CLOCKS_PER_SEC` as a constant) and epilogue (dastest's budget
  loop in C: a 0.5 s budget, reps regrown from the measured rate as `reps * budget / total
  * 1.2`, at most a hundredfold and at least one more per round, so a sub-tick kernel still
  converges, then one line `<seconds per run> <runs> <result>`), builds the native lane with the pinned clang at `-O3
  -funsigned-char` (dasProfile's Release build gives its C++ kernels `-O3`, and the lane
  follows its method), converts the same file through `converter/pipeline.das`, and runs each
  lane as its own process `--samples` times (five by default). A cell is the median, with ±
  half the sample range as a share of it; startup never enters a cell because the program
  times itself. The run writes `results_linux.json` and prints the results table,
  `--ratios` adds the ratio table, and the delta table follows whenever a baseline capture
  exists (section 5); `--table` renders the stored file instead of measuring, `--readme`
  rewrites the results table between the markers in `README.md`, and `--report <path>` writes
  the results, ratio and delta tables as one markdown block to `<path>` and prints it.
- `perf_tables.das` - the lanes and the tables over a capture read as JSON: the results
  table (the fastest lane of a row bold), the ratio table (each lane's median over native's,
  two decimals, native 1.00) with its `SUSPECT` lines, the delta table against a baseline
  capture with its `FLAG` lines, and the report holding the three. A missing cell is `n/a`
  in every table. All of them render through daslib's `md_boost` `render_md_table`. It
  measures nothing and reads no file.
- `perf_cli.das` - the file side of the harness: whole-file text, the baseline capture
  (section 5), and the text a run prints and writes as its report.
- `tests/` - the dastest suite over `perf_tables.das` and `perf_cli.das`, driven by JSON
  fixtures; the preflight tests lane runs it.
- `results_linux.json` - the committed capture: CPU, platform, timestamp, the clang and
  daslang versions, the sample count, and per kernel and lane the median, spread, rep count,
  the result and raw samples.
- `scripts/run_perf.sh` - runs the harness from the repository root with both module folders
  loaded.

## 2. The lanes

`native` is the C program; `interp` and `jit` are `daslang` and `daslang -jit` over the
converted module with `-load_module` for `c_runtime` and `dasCRuntime`; `exe` is the
JIT-linked executable; `aot` is the `-ctx` context compiled with the seven-line host of
`converter/tiers.das`, which links `dasCRuntime/src/*.cpp` into the host because the
generated context declares `Module_CRT` and includes its header. The kernels reach the CRT
clock through the converter's libc map (`clock` is `crt::clock`), so every lane times itself
with the same clock.

## 3. What the table says

The ratio table reads across machines where the times do not. The JIT and exe lanes sit
within 8 percent of clang on `primes`, `fib_recursive` and `sieve`, and ahead of it on
`fixed_mandel` and `matmul`. The JIT, exe and AOT lanes run `fib_loop` at 2.2 to 2.3 times
native, and the JIT and exe lanes run `blit` at 9.4 and 10.7 times. Those rows are the
machine's, not the tree's: the P2.3 tree on the same FX-6300 gives `fib_loop` 2.29, 2.30
and 2.22 and `blit` 9.18 and 9.69.
The interpreter lane is the loop shape the emitter writes, not the optimizer: the das
profiler shows `primes` inlined into `c_main` with nothing else to charge, and the same
module with its two loops rewritten by hand as `for (i in range(...))` runs 4 times faster
under the interpreter, which is the gap to dasProfile's hand-written das on the same
kernel; the `range` rewrite of a canonical `for` is the O1 row of
`docs/implementation_order.md`. The AOT lane trails at 5 to 6.5 times native on
`fixed_mandel`, `matmul` and `sieve`, the anomaly the P4.5b row owns; the generated C++
spells every struct-returning call as a lambda building the value through `das_copy` into
memset locals. The AOT `fib_recursive` cell is ledgered in section 4.

## 4. Exception ledger

- `fib_recursive` / `aot`: the cell is a real time of a cheaper program, not of the kernel.
  The host's GCC 14 at `-O2` turns the second recursive call of the converted kernel into a
  loop and unrolls levels into a `.part.0` clone, so its work grows about 1.38 times per
  depth level where native's grows by phi: 13.96, 51.1 and 186.6 us at depth 27, 31 and 35
  against native's 1.23, 8.45 and 57.8 ms. `depth` is re-read on every call and nothing is
  hoisted. The row is not comparable with the native or JIT cells; the P4.5b row of
  `docs/implementation_order.md` owns it.

## 5. Tracking

A capture is compared with the one before it. The baseline is the `--baseline <json>` file
when given, else `results_linux.json` as committed at `HEAD`, read through `git show` before
the run overwrites the file; when `HEAD` has no such file there is no delta, and a file that
is not JSON is an error. A delta cell is `(new - old) / old` as a signed percent, kept in
hundredths of a percent so the comparison with the bar is exact. When both captures name the
same CPU, old and new are the two medians. When they name different CPUs, they are the two
lane/native ratios, the native column is `n/a`, and the delta heading names both CPUs: a
time measured on one machine says nothing about the tree against a time from another, while
a ratio carries across. A kernel or lane missing from either capture is `n/a`. A cell more
than 10 percent slower adds one `- FLAG <kernel>/<lane> +N.NN%` list item under the table,
else the line `no lane slower than 10%` follows it; a flag leaves the exit code alone,
because it is a review duty, not a gate. A lane under a tenth of native in the ratio table
adds one `- SUSPECT` list item: a lane that far ahead of clang measures a different program
than the kernel. The `--report` file holds the three tables and those list items as one
markdown block.
