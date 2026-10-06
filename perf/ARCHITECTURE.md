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
  Each ledger item adds a kernel exercising the constructs it lowers: `fixed_mandel` is
  P2.1's, a 16.16 fixed-point Mandelbrot over struct vectors passed and returned by value;
  `sieve` and `matmul` are P2.2's, a sieve over a fixed byte array and a 96x96 product over
  two-dimensional arrays. The kernel's
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
  converges, then one line `<seconds per run> <runs> <result>`), builds the native lane with the pinned clang at `-O2
  -funsigned-char`, converts the same file through `converter/pipeline.das`, and runs each
  lane as its own process `--samples` times (five by default). A cell is the median, with ±
  half the sample range as a share of it; startup never enters a cell because the program
  times itself. The run writes `results_linux.json` and prints the table; `--table` renders
  the stored file, `--readme` rewrites the table between the markers in `README.md`.
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

The JIT, exe and AOT lanes sit at clang `-O2` on the scalar kernels, and AOT is ahead on
`primes` and `fib_recursive` (the host compiles the generated C++ with its own inliner).
The interpreter lane is the loop shape the emitter writes, not the optimizer: the das
profiler shows `primes` inlined into `c_main` with nothing else to charge, and the same
module with its two loops rewritten by hand as `for (i in range(...))` runs 4 times faster
under the interpreter (0.70 s against 2.84 s for twenty runs), which is the gap to
dasProfile's hand-written das on the same kernel; the `range` rewrite of a canonical `for`
is the O1 row of `docs/implementation_order.md`. AOT on `fixed_mandel` is the one row
where a das lane trails: 1.4 ms against the JIT's 0.23 ms. The host's `-O3` takes it to
0.95 ms, and the generated C++ spells every struct-returning call as a lambda building
the value through `das_copy` into memset locals, with `fmul` (6.6 million calls per run)
left to the C++ inliner; where the rest goes needs a sampling profiler this machine does
not have, and the row stays open for P7.

## 4. Exception ledger

Empty.
