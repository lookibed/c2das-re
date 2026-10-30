# perf Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
is the performance comparison of `docs/very-detailed-plan.md` section 2: C kernels, the
harness that times them under every lane, and the stored results.

## 1. File charters

- `kernels/<name>.c` - one kernel each: a `static void kernel_run(void)` and a
  `static int kernel_result(void)` over file-scope variables, nothing else; no kernel knows
  its expected result, the native lane measures it and every das lane must reproduce it or
  its cell is an error. The first three are this tree's versions of dasProfile's scalar kernels
  with its parameters (`primes` 14000, `fib_loop` 6511134, `fib_recursive` 31): `primes` tests
  `i < n` in `isprime` and returns `int` where dasProfile's tests `i != n` and returns `bool`, and
  no kernel function is `noinline`, so a cell here reads beside dasProfile's row without being its
  program; `kernels/dasprofile/` holds its programs.
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
  since a kernel includes no header; `switch_goto` is P5.1's, lua's VM dispatch: a loop over an
  opcode array whose switch cases jump into another case's block and into the middle of one, so
  every such goto re-dispatches the switch's matched-flag loop; `do_while_effect` is P5.1's too,
  `do { ... } while (--n > 0)` nested in another, the decrement in the condition. The kernel's parameter is a `volatile` static that `kernel_run` reads on every call: with a literal
  argument clang hoists the idempotent call out of the rep loop (the native lane reports
  zero), and daslang's optimizer evaluates a pure call with constant arguments at compile
  time whatever `infer_time_folding` says, so the interpreter lane measured a store. The
  converter keeps `volatile` (`converter/ARCHITECTURE_EMITTER_LOOPS.md`): the das read is a
  `c_volatile_load` no tier folds, one per call, so the das program has the unknown trip count
  the native one has.
  A kernel holds no `main`, no `#include` and no `printf` or `clock` prototype, since the
  harness supplies `main` and those two prototypes (`perf_compose.das`), and no expected result,
  since the native lane's result is the value every das lane must match; it declares every
  other libc function it calls with a prototype of its own.
- `kernels/dasprofile/<name>.c` - the dasProfile method's kernels: dasProfile 436d58d's
  `tests/cpp/<name>.cpp` in C, file for file, for `fib_loop`, `fib_recursive` and `primes`: the
  same functions with external linkage, the same loops and parameter, `PROFILE_NOINLINE` as
  `__attribute__((noinline))` and `bool` as `_Bool`, in the kernel shape above.
- `run.das` - the harness, by one of two methods (`--method`, section 6). By the default one it
  composes each kernel (`perf_compose.das`), builds the native lane
  with the pinned clang at `-O3 -funsigned-char` (dasProfile's Release build gives its C++
  kernels `-O3`, and the lane follows its method), converts the same file through `converter/pipeline.das` (three times: the second under
  `--param-writes copy` for the `interp-copy` lane, the third under `--loops while` for the
  `interp-while` lane), and runs each
  lane as its own process `--samples` times (five by default). A cell is the median, with ±
  half the sample range as a share of it; startup never enters a cell because the program
  times itself; each das lane logs its argv at `info`. The `exe` and `aot` lanes each stand
  only on the binary their build leaves (an earlier run's removed first), since the tier
  returns the build's exit code when the build fails: a failed build is the lane's error,
  carrying the exe build's linker message (the first line after daslang's `Output:` line,
  else its first line past the `info` lines) or the AOT host build's last line; a tier that
  refuses before any build (the AOT host takes no program arguments) gives its own text alone.
  The run writes
  `results_linux.json` (`results_method_linux.json` under `--method dasprofile`), or
  the `--out <file>` it is given (which `--table` then reads; the delta's default baseline stays
  the method's committed file at HEAD), and prints the results table,
  `--ratios` adds the ratio table, and the delta table follows whenever a baseline capture
  exists (section 5); `--table` renders the stored file instead of measuring, `--readme`
  rewrites the method's section between its markers in `README.md` (the results table, or the
  comparison with dasProfile's capture) from the run or, under `--table`, the stored file, `--report <path>` writes
  the results, ratio and delta tables as one markdown block to `<path>` and prints it, and
  `--check` exits 1 when a cell drifts from the baseline past `--tolerance` percent (10 by
  default), or past twice the baseline cell's spread where that is wider, either way, or one
  capture lacks a cell the other has, each named on an error line, and
  0 otherwise, a lane error the baseline shares included (a cell both lack reproduces it).
- `perf_lanes.das` - the lanes and the sample arithmetic `run.das` shares with
  `ports/publish.das`: the native lane's build command (the pinned clang, `NATIVE_FLAGS`
  `-O3 -w -funsigned-char`, a program's C files in order), the interpreter and JIT commands over a converted module, the `exe`
  and `aot` builds through `converter/tiers.das` (each standing only on the binary it leaves,
  named as the tier names it, an earlier run's removed first, with the build's line as the
  error), the median and the spread of a cell, the CPU model and the clang and daslang version
  lines (each the first line past the `info` lines), and the helpers `lua/run.das` shares with
  `ports/publish.das`: `lines_without` (a text's lines not starting with a prefix),
  `program_output` (a run's output without the JIT's `info` lines) and `in_folder` (a command run
  in a folder through `sh`). `BUILD_TIMEOUT`, 3600 s, bounds each step
  of an `exe` or `aot` build and the run it ends with: `run_tier` passes its timeout to every
  process the tier starts.
- `perf_compose.das` - the C program of a kernel, by either method: `composed_source` puts the kernel between
  the profile prologue (the `printf` and `clock` prototypes, the CRT's `CLOCKS_PER_SEC` as a
  constant) and epilogue (dastest's budget loop in C: a 0.5 s budget, reps regrown from the
  measured rate as `reps * budget / total * 1.2`, at most a hundredfold and at least one more
  per round, so a sub-tick kernel still converges, then one line `<seconds per run> <runs>
  <result>`), and `write_composed` writes it into a work folder. The harness builds and
  converts that program; the readability metric converts it. The kernels are listed by
  `c_file_ids` of `suites/suite_files.das`, and `kernel_ids` names the kernels a method runs.
  `composed_method_source` is dasProfile's `profile.h` around a method kernel (section 6),
  `write_method_composed` writes it into `work/<kernel>/method/`; its native build takes
  `METHOD_NATIVE_DEFINE`, which compiles the clock's C body.
- `perf_tables.das` - the lanes and the tables over a capture read as JSON, in the lanes the
  capture lists (`lanes_of`, every lane for one that lists none): the results
  table (the fastest lane of a row bold), the ratio table (each lane's median over native's,
  two decimals, native 1.00) with its `SUSPECT` lines, the delta table against a baseline
  capture with its `FLAG` lines, the report holding the three, the cells `--check` finds
  drifted (`drifted_cells`), and the comparison of the dasProfile-method capture with
  dasProfile's own (`render_method_comparison`, `SHARED_KERNELS`, `DIFFERENT_PROGRAMS`). A missing cell is `n/a`
  in every table. All of them render through daslib's `md_boost` `render_md_table`. It
  measures nothing and reads no file.
- `perf_cli.das` - the file side of the harness: the baseline capture (section 5), the text a
  run prints and writes as its report, the `--check` verdict (`check_drift`), and the README
  section of either method between its markers (`write_readme`); whole files are read and written through daslib
  `fio`'s `fread(path)` and `fwrite(path, text)`.
- `tests/` - the dastest suite over `perf_tables.das`, `perf_cli.das` and the method kernels'
  selection, driven by JSON fixtures and a scratch README, over `perf_lanes.das`'s arithmetic, commands and the AOT tier's refusal of program
  arguments, and `run.das` itself as a child process: `-?`, one sample of `blit` into an
  `--out` file, whose `interp-copy` and `interp-while` cells must time their conversions and match
  the native result, one sample of the dasProfile method over `fib_loop` and `fib_recursive`
  whose five lanes must stand and whose `--check` against a far-off baseline must exit 1 naming
  the drifted and the missing cells, the committed method capture under `--table`, `--method
  nope` a usage error, `dasprofile_capture.das`'s usage error, refusal and stamp, and one sample of
  `fib_recursive` under a `PATH_TO_LIBCLANG` whose `clang++` (the AOT host's compiler) fails,
  whose `aot` error must carry that compiler's output, and one under a `PATH` whose `c++` (the
  linker daslang's `-exe` build calls) fails, whose `exe` error must carry the failed link; the
  preflight tests lane runs it.
- `results_linux.json` - the committed capture: CPU, platform, timestamp, the method, the clang
  and daslang versions, the sample count, the lanes, and per kernel and lane the median, spread,
  rep count, the result and raw samples. `results_method_linux.json` - the same of the
  dasProfile method.
- `dasprofile_linux.json` - borisbat/dasProfile's own capture (`profile_results_linux.json`)
  from this machine, with `dasprofile_commit` and `toolchain` stamped on by
  `dasprofile_capture.das`; `dasprofile.sh` makes it (section 6).
- `scripts/run_perf.sh` - runs the harness from the repository root with both module folders
  loaded; `--from-scratch` and `--check` run both methods (section 6).
- `dasprofile.sh` - dasProfile at the commit `VERSIONS.md` pins, run on this machine: the daScript
  SDK installed from `DASLANG_ROOT`'s build tree at the path `VERSIONS.md` names, the headers the
  install omits copied in (`docs/probe-findings.md` F68), dasProfile cloned into
  `work/dasprofile/src`, configured against the SDK with the pinned clang and clang++, its C++
  lane, its module and its AOT module built, its runner run `--json --das-only` from the SDK's
  `examples/profile`, and its capture handed to `dasprofile_capture.das`.
- `dasprofile_capture.das` - writes `dasprofile_linux.json`: dasProfile's capture with the
  commit and the toolchain line (its C++ compiler, daslang and LLVM) on top.

## 2. The lanes

`native` is the C program; `interp` and `jit` are `daslang` and `daslang -jit` over the
converted module with `-load_module` for `c_runtime` and `dasCRuntime`; `interp-copy` is
`daslang` over a second conversion of the kernel under `--param-writes copy`, into
`work/<kernel>/copy/`, the faster form of the "speed vs idiomatic" pair the converter offers
(`converter/ARCHITECTURE_EMITTER.md` section 4): every other lane runs the default `in-place`
conversion, and the copy lane's cells read beside `interp`'s, since the interpreter writes a
local faster than an argument slot (`blit` writes its three parameters in its loop);
`interp-while` is `daslang` over a third conversion under `--loops while`, into
`work/<kernel>/while/`, the `while` forms a canonical counting `for` took before the range
rewrite (`converter/ARCHITECTURE_EMITTER_LOOPS.md`), so the opt-out of the default is measured
beside it; `exe` is the
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
built with the platform's `char`. Under the default method the kernels reach the CRT
clock through the converter's libc map (`clock` is `crt::clock`, process CPU time), so every
lane times itself with the same clock; under the dasProfile method every lane reads the steady
clock (`clock_gettime(CLOCK_MONOTONIC)` natively, `crt::c_monotonic_ns`, `std::chrono::steady_clock`,
in the conversion), the clock dasProfile's harness reads. The dasProfile method has the lanes
`native`, `interp`, `jit`, `exe` and `aot`, over `work/<kernel>/method/`.

## 3. What the table says

The ratio table reads across machines where the times do not. The JIT and exe lanes run at
most 10 percent behind clang on `bit_pack`, `do_while_effect` and `sieve`, level with it or ahead
on `fib_recursive` and `primes`, and ahead of it on `fixed_mandel`, `matmul` and `switch_goto`;
the AOT lane runs at most 5 percent behind clang on `compound_lit` and `fib_loop`, and level with
it or ahead on `blit`, `do_while_effect`, `fixed_mandel`, `fib_recursive`, `primes` and
`switch_goto`. The JIT and exe lanes run `fib_loop` at 2.3 times native, and that row is the
JIT's code for a loop whose trip count it cannot see, not the program: the JIT tunes for the
host CPU (`bdver2` here), and dasProfile's own das kernel, which passes a literal count, runs at
1.00x under it; the dasProfile method's table sets the two side by side (section 6). `blit` runs at 8.6 and 10.5 times, a byte loop through walking pointers.
The interpreter lane is the loop shape the emitter writes, not the optimizer: with canonical
counting loops as range loops, C's wrapping sum as the plain one and `x = x op y` as `x op= y`
(`converter/ARCHITECTURE_EMITTER_LOOPS.md`), `fib_loop` runs 31.6 times native and `primes`
2.8 times, against 186 and 7.5 with the earlier `while` forms; the `interp-while` lane keeps the
`while` forms of the canonical loops and runs them 56.1 and 3.8 times. Under the dasProfile
method, over dasProfile's own programs, the converted kernels run within 2 percent of its
hand-written das in the interpreter on `fib_loop` (31.5 against 31.6 times native) and
`fib_recursive` (8.76 against 8.60), and `primes` at 4.45 against 2.92: its two loops test `!=`,
which the range rewrite does not take, so they keep the `while` form where the hand-written das
spells `range`. Under the JIT and AOT the converted cells match the hand-written ones but on
`fib_loop` under the JIT (2.28 against 1.00, the literal count) and `primes` under AOT (0.63
against 0.58), and AOT `fib_recursive` runs ahead (1.05 against 1.13). A volatile object's every access is a
`c_volatile_load` or `c_volatile_store`: `setjmp_general` reads its volatile counter four times
per pass and runs 24 percent slower under the interpreter than with the volatile dropped, and
`compound_lit`'s JIT cell is 18 percent slower than the same module with its volatile parameter
dropped (0.00066 against 0.00055 s, the cell before the volatile was kept), one read per run
that bounds the run's loop. The AOT `sieve` and `matmul` cells are ledgered in section 4.
Of the kernels only `blit` writes a parameter, so its module is the only one the copy mode
changes (its three parameters copied on entry); the `interp-copy` lane runs it about 10 percent
faster than `interp`, and every other row of the lane times the same module as `interp`, the
two cells apart by the samples' spread alone.

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
markdown block. `--check` holds a cell to `--tolerance` or to twice the baseline cell's own
spread, whichever is wider: a cell whose samples spread that far in the committed capture (the
interpreter's `fib_loop` under `--loops while` at 29 percent, its bimodal `x = x + y` loop)
reproduces anywhere inside the bar.

## 6. Methods and reproduction

The default method is this tree's: the program times the kernel's calls with the CRT clock and
keeps the result in the kernel's global. The dasProfile method (`--method dasprofile`) follows
borisbat/dasProfile's `tests/cpp/profile.h` step for step over dasProfile's own kernels in C
(`kernels/dasprofile/`), so the two repositories' tables compare one program by one harness:
the kernel functions carry their `noinline` (dasProfile's `PROFILE_NOINLINE`) and `kernel_run`,
the body of dasProfile's timed lambda, none, every run stores the kernel's result
into a `volatile` sink (its `profile::keep`), the budget is 0.5 s of steady-clock time with
the count regrown as `budget / per-run * 1.2` (at most a hundredfold, at least one more,
capped at 1e9), and the line printed is the default method's. The das side keeps the sink's
store and the kernel's `volatile` parameter read through `c_volatile_store` and
`c_volatile_load`, so it runs with the unknown trip count dasProfile's C++ has; dasProfile's own
das kernels pass a literal count, which the JIT unrolls where it does not unroll the unknown one
(`docs/implementation_order.md` P7.0). The das side carries no `noinline`, since the converter
emits no inline control: the volatile accesses keep each run's work whether the JIT inlines a
kernel function or not, as dasProfile's own das kernels, which carry `[sideeffects]` instead,
keep theirs. The method runs the kernels of `kernels/dasprofile/`, which `SHARED_KERNELS` of
`perf_tables.das` maps to dasProfile's test names; `DIFFERENT_PROGRAMS` names the rest, the
first table's versions of the three among them, never compared (`fixed_mandel` is not
dasProfile's `mandelbrot`). `README.md` sets the method's capture beside dasProfile's own from
the same machine, `dasprofile_linux.json`, one generated table: each hand-written cell over
dasProfile's C++, each converted one over the composed C program.

`scripts/run_perf.sh --from-scratch` rebuilds the crt, removes `work/`, reruns dasProfile
(`dasprofile.sh`), and records both captures and both `README.md` sections.
`scripts/run_perf.sh --check` reruns both methods into a scratch folder and passes `--check` to
each run, so it exits 1 when a cell drifts from its committed capture past 10 percent or twice
its committed spread either way (`--tolerance <percent>` sets the 10) or a cell is missing from
either side; on another CPU the comparison is of lane/native ratios (section 5). It reruns this
tree's lanes only: the hand-written and dasProfile C++ columns of the comparison come from
`dasprofile_linux.json`, which `--from-scratch` alone reruns. `.github/workflows/perf.yml` runs it on the
self-hosted runner for every release tag and on request.

## 7. What a capture depends on

A capture's cells change with: a file under `kernels/`; the prologue and epilogue
`perf_compose.das` puts around a kernel; the argv of a timed lane - the native `clang` command
(`native_build_command` and `NATIVE_FLAGS` in `perf_lanes.das`), `run.das`'s `convert` calls, the
`interp` and `jit` lanes' `daslang` argv (`das_lane_command`) and the exe and AOT builds'
`run_tier` call (`built_binary` in `perf_lanes.das`); the sample count (the `samples` default of
`run.das`'s `Args`); the lane list (`LANES` in `perf_tables.das`); and the sample arithmetic -
`measure`, `cell_of` and `accept_lane` in `run.das`, `median_of` and `last_line` in
`perf_lanes.das`.
