# perf Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
is the performance comparison of `docs/very-detailed-plan.md` section 2: C kernels, the
harness that times them under every lane, and the stored results.

## 1. File charters

- `kernels/<name>.c` - one kernel each: a `static void kernel_run(void)` and a
  `static int kernel_result(void)` over file-scope variables, nothing else; no kernel knows
  its expected result, the native lane measures it and every das lane must reproduce it or
  its cell is an error. The first three are
  dasProfile's scalar kernels with its parameters (`primes` 14000, `fib_loop` 6511134,
  `fib_recursive` 31), so a cell here compares with the same row of dasProfile's table.
  The other kernels each cover one ledger item's constructs: `fixed_mandel` is
  P2.1's, a 16.16 fixed-point Mandelbrot over struct vectors passed and returned by value;
  `sieve` and `matmul` are P2.2's, a sieve over a fixed byte array and a 96x96 product over
  two-dimensional arrays; `blit` is P2.3's, a byte copy through walking pointers over
  malloc'd buffers; `qsort_cmp` is P4.6's, an array of records sorted by `qsort` through a
  converted comparator, a function value with `var` pointer positions; `bit_pack` is P4.7's,
  read-modify-writes of bitfields under the `linux` dialect in a record of naturally aligned
  units, in a record whose bitfield takes a two-byte unit and that each round is built from an
  initializer folding that unit's word through `c_unit_bytes`, in a record holding an
  underaligned bitfield record that takes a padding field, and in a union whose bitfield member
  puns with a plain one beside an unnamed bitfield; `str_copy` is P4.8's, assignments read as
  values: a fill whose stored byte feeds a sum through an index the store steps (`sum +=
  (text[i++] = b)`) and a NUL-terminated copy whose loop tests the byte it stored (`while ((*d++
  = *s++))`); `va_forward` is P4.4's, a variadic sum called in a hot loop whose list `va_copy`
  copies, both copies forwarded to a consumer taking a `va_list`, and a format helper forwarding
  its list to `vsnprintf`; `switch_local` is P4.8's, a switch in a hot loop whose case-level
  local a later case assigns and reads, and a goto into a block whose local hides a global of
  external linkage, so the flattened local takes a free name (`g1`); `compound_lit` is P4.9's,
  compound literals as call arguments (a record by value, an array as a pointer, a record's
  address) and as assigned values in a hot loop, an `_Alignof` in the arithmetic, a pointer to a
  record the unit never defines passed through, a two-dimensional `char` table from string
  literals read through its rows, and a flexible array member filled and summed;
  `setjmp_general` is P4.9's too, `r = setjmp(buf)` re-entered by a longjmp on every pass of a
  hot loop and the value accumulated, glibc's `struct __jmp_buf_tag` declared in the kernel
  since a kernel includes no header. The kernel's parameter is a `volatile` static that `kernel_run` reads on every call: with a literal
  argument clang hoists the idempotent call out of the rep loop (the native lane reports
  zero), and daslang's optimizer evaluates a pure call with constant arguments at compile
  time whatever `infer_time_folding` says, so the interpreter lane measured a store. The
  converter drops `volatile`, which is what makes the das read a plain global read that no
  pass folds.
  A kernel holds no `main`, no `#include` and no `printf` or `clock` prototype, since the
  harness supplies `main` and those two prototypes (`perf_compose.das`), and no expected result,
  since the native lane's result is the value every das lane must match; it declares every
  other libc function it calls with a prototype of its own.
- `run.das` - the harness: composes each kernel (`perf_compose.das`), builds the native lane
  with the pinned clang at `-O3 -funsigned-char` (dasProfile's Release build gives its C++
  kernels `-O3`, and the lane follows its method), converts the same file through `converter/pipeline.das` (twice: the second under
  `--param-writes copy` for the `interp-copy` lane), and runs each
  lane as its own process `--samples` times (five by default). A cell is the median, with ±
  half the sample range as a share of it; startup never enters a cell because the program
  times itself; each das lane logs its argv at `info`. The `exe` and `aot` lanes each stand
  only on the binary their build leaves (an earlier run's removed first), since the tier
  returns the build's exit code when the build fails: a failed build is the lane's error,
  carrying the exe build's first line past its `info` lines (the linker's failure) or the AOT
  host build's last line. The run writes
  `results_linux.json`, or
  the `--out <file>` it is given (which `--table` then reads; the delta's default baseline stays
  the committed file at HEAD), and prints the results table,
  `--ratios` adds the ratio table, and the delta table follows whenever a baseline capture
  exists (section 5); `--table` renders the stored file instead of measuring, `--readme`
  rewrites the results table between the markers in `README.md`, and `--report <path>` writes
  the results, ratio and delta tables as one markdown block to `<path>` and prints it.
- `perf_compose.das` - the C program of a kernel: `composed_source` puts the kernel between
  the profile prologue (the `printf` and `clock` prototypes, the CRT's `CLOCKS_PER_SEC` as a
  constant) and epilogue (dastest's budget loop in C: a 0.5 s budget, reps regrown from the
  measured rate as `reps * budget / total * 1.2`, at most a hundredfold and at least one more
  per round, so a sub-tick kernel still converges, then one line `<seconds per run> <runs>
  <result>`), and `write_composed` writes it into a work folder. The harness builds and
  converts that program; the readability metric converts it. The kernels are listed by
  `c_file_ids` of `suites/suite_files.das`.
- `perf_tables.das` - the lanes and the tables over a capture read as JSON: the results
  table (the fastest lane of a row bold), the ratio table (each lane's median over native's,
  two decimals, native 1.00) with its `SUSPECT` lines, the delta table against a baseline
  capture with its `FLAG` lines, and the report holding the three. A missing cell is `n/a`
  in every table. All of them render through daslib's `md_boost` `render_md_table`. It
  measures nothing and reads no file.
- `perf_cli.das` - the file side of the harness: the baseline capture (section 5), and the
  text a run prints and writes as its report; whole files are read and written through daslib
  `fio`'s `fread(path)` and `fwrite(path, text)`.
- `tests/` - the dastest suite over `perf_tables.das` and `perf_cli.das`, driven by JSON
  fixtures, and `run.das` itself as a child process: `-?`, one sample of `blit` into an
  `--out` file, whose `interp-copy` cell must time the copy conversion and match the native result, and one sample of
  `fib_recursive` under a `PATH_TO_LIBCLANG` whose `clang++` (the AOT host's compiler) fails,
  whose `aot` error must carry that compiler's output, and one under a `PATH` whose `c++` (the
  linker daslang's `-exe` build calls) fails, whose `exe` error must carry the failed link; the
  preflight tests lane runs it.
- `results_linux.json` - the committed capture: CPU, platform, timestamp, the clang and
  daslang versions, the sample count, and per kernel and lane the median, spread, rep count,
  the result and raw samples.
- `scripts/run_perf.sh` - runs the harness from the repository root with both module folders
  loaded.

## 2. The lanes

`native` is the C program; `interp` and `jit` are `daslang` and `daslang -jit` over the
converted module with `-load_module` for `c_runtime` and `dasCRuntime`; `interp-copy` is
`daslang` over a second conversion of the kernel under `--param-writes copy`, into
`work/<kernel>/copy/`, the faster form of the "speed vs idiomatic" pair the converter offers
(`converter/ARCHITECTURE_EMITTER.md` section 4): every other lane runs the default `in-place`
conversion, and the copy lane's cells read beside `interp`'s, since the interpreter writes a
local faster than an argument slot (`blit` writes its three parameters in its loop); `exe` is the
JIT-linked executable; `aot` is the `-ctx` context compiled with the seven-line host of
`converter/tiers.das`, which links `dasCRuntime/src/*.cpp` into the host because the
generated context declares `Module_CRT` and includes its header. The host compiles with the
pinned clang's `clang++` at `-O3`, the native lane's compiler and level, so the two lanes
differ only in the program: under the system GCC 14 at `-O2` the inliner's struct temporaries
stay in memory, where a two-field store read back as one eight-byte load stalls on
store-to-load forwarding (`fixed_mandel` 5.1 times native, 0.9 under clang), and GCC turns
the second recursive call of `fib_recursive` into a loop, so the cell times a cheaper program
than the kernel (0.01 times native, 0.9 under clang). `-funsigned-char` stays native-only:
the C++ spells every byte type as `uint8_t` or `int8_t`, and the static runtime it links is
built with the platform's `char`. The kernels reach the CRT
clock through the converter's libc map (`clock` is `crt::clock`), so every lane times itself
with the same clock.

## 3. What the table says

The ratio table reads across machines where the times do not. The JIT and exe lanes sit
within 8 percent of clang on `primes`, `fib_recursive` and `sieve`, and ahead of it on
`fixed_mandel` and `matmul`; the AOT lane sits within 1 percent of clang on `blit` and
`fib_loop` and ahead of it on `fib_recursive`, `fixed_mandel` and `primes`. The JIT and
exe lanes run `fib_loop` at 2.3 times native and `blit` at 9.4 and 10.6 times. Those rows
are the machine's, not the tree's: the P2.3 tree on the same FX-6300 gives `fib_loop` 2.29
and 2.30 and `blit` 9.18 and 9.69.
The interpreter lane is the loop shape the emitter writes, not the optimizer: the das
profiler shows `primes` inlined into `c_main` with nothing else to charge, and the same
module with its two loops rewritten by hand as `for (i in range(...))` runs 4 times faster
under the interpreter, which is the gap to dasProfile's hand-written das on the same
kernel; the `range` rewrite of a canonical `for` is the O1 row of
`docs/implementation_order.md`. The AOT `sieve` and `matmul` cells are ledgered in
section 4.
Of the kernels only `blit` writes a parameter, so its module is the only one the copy mode
changes (its three parameters copied on entry); the `interp-copy` lane runs it about 10 percent
faster than `interp` (0.0376 against 0.0416 s), and every other row of the lane times the same
module as `interp`, the two cells apart by the samples' spread alone.

## 4. Exception ledger

- `sieve` and `matmul` / `aot`: 5.4 and 1.4 times native. The generated C++ finds a module
  global through the context's mangled-name lookup at every access (`das_global<T, mnh>`),
  and a C file-scope array is a module global. In `sieve` every iteration stores into the
  array, and the host compiles with `-fno-strict-aliasing`, so any store may alias the
  lookup table and clang keeps the probe inside the loop. `matmul`'s inner loop stores
  nothing, yet the probes stay in it too: hoisting the three lookups by hand in the generated
  C++ with the bounds checks kept takes the cell from 0.864 to 0.599 ms (native 0.600), while
  keeping the lookups and indexing raw without the bounds check leaves it at 0.84 ms; the
  lookup is the cost, the bounds check is not (`docs/probe-findings.md` F49,
  lookibed/daScript#5).
- `switch_local` / `aot`: no cell. daslang's AOT writes the flattened block's `var g1 : int =
  k * 2` as an initialized C++ local after the `goto` that jumps past it, and clang++ refuses
  the jump ("jump bypasses variable initialization"); the interpreter, the JIT and the exe
  take the same module. Every das `goto` past a `var` declaration under AOT meets it, a
  daScript issue (`docs/implementation_order.md` P4.9).

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
