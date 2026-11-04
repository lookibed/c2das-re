# compare Architecture - the perf comparison

Companion to `ARCHITECTURE.md` in this folder; section numbers are unique across the family.

## 8. The perf comparison {#perf}

`run.das --perf` times every kernel of `perf/kernels/` and `perf/kernels/dasprofile/`, nineteen,
through both translators. A kernel's key is its file stem, `dasprofile/<stem>` for the second
folder, since the two folders share stems. Each kernel is composed by the dasProfile method
(`perf/perf_compose.das`'s `composed_method_source`: the steady clock, the `volatile` sink, the
0.5 s budget) into `work/perf/<key>/<stem>.c`, and that one C text feeds all three builds:

- `native` - the pinned clang at `-O3` with `-DC2DAS_NATIVE`, which compiles the clock's C body,
  `clock_gettime(CLOCK_MONOTONIC)`; its result is the oracle.
- ours - the file converted for `linux` without the define, so the clock is the CRT's
  `c_monotonic_ns`, run with both module folders loaded.
- Rust - `translate_file` with `-DC2DAS_NATIVE` as a clang argument and a 600 s limit: the
  translator lowers `clock_gettime` but not `clock`, so the default method's program, which
  calls `clock`, is refused under `--strict`, and the method's program is not. Its entry runs
  with no module folder.

Both sides are measured in the same run with the same `--samples` (five by default), so the two
columns come from one machine state and one set of parameters; the perf folder's own captures
are never read as our side. The das lanes are `interp`, `jit`, `exe` and `aot`, each side's
measured as perf measures its lanes (`perf/perf_measure.das`): each sample its own process, the
cell the median with the spread, and a cell stands only when its result is the oracle's,
otherwise it is an error cell `result <x> differs from the native <y>`. `exe` and `aot` build
through `perf/perf_lanes.das`'s `build_exe` and `build_aot`, which load both module folders; a
program that requires neither runs the same with them loaded, so the Rust output builds there
unchanged, and a build that leaves no binary is that lane's error cell with the build's line. A
lane that has no cell is `{"error": <line>}`, never dropped: its own line, else the step every
lane stands on (`convert: ...`, `no native result: ...`). A refused Rust translation is `{status:
"refused", error}` with no lanes; one with no module defining `main` is refused the same way.

Each das lane of both sides has `COMPARE_LIMITS`: 120 s a sample, 300 s an `exe` or `aot` build
with the run it ends with, past which the lane is an error cell naming the limit (perf's own
limits, 600 s and 3600 s, fit programs that always end). The Rust translator drops `volatile` from
a file-scope object (`static volatile int depth = 31;` becomes `var depth : int = 31`), so under
the JIT nothing stops the optimizer from hoisting the kernel's work out of the budget loop; the
loop's per-run time then stays under its 1 ns floor, the count grows by one a round, and the
program never ends: the Rust `fib_recursive` under `daslang -jit` runs past 60 s, while the
native build of the same C text ends once its 0.5 s budget is spent. The Rust side's cells thus
time a program the optimizer may reshape; the oracle checks the result only, and the 120 s sample
limit is what catches the endless loop.

The section `perf` is `{cpu, box, platform, versions {clang, daslang}, rust_commit, rust_commit_error,
samples, timestamp, lanes, kernels, geomean}`. `lanes` is `native` and the four das lanes;
`kernels` maps each key to `{native, ours: {lane: cell}, rust: {status, error?, lanes?}}`, a cell
as the perf capture writes it (`time`, `spread`, `count`, `result`, `samples`). `geomean` maps
each das lane to `{ours, rust, kernels}`: the geometric mean of each side's lane time over the
native time, over the `kernels` kernels where native and both sides' cells stand, so the two means
cover the same kernels; with none both are 0.

Verified on the binary at the pinned commit: `c2dascript-transpile --file fib_loop.c --libc std
--strict --output-dir o -DC2DAS_NATIVE` over the method's composition exits 0 (with `warning:
Skipping type decl __time_t` lines), and `daslang o/fib_loop.das` prints the native build's result
`1781508648`; `sieve` likewise prints `78498`; `qsort_cmp` is refused with exit 2. A missing input
file makes the binary panic (exit 101, `thread 'main' panicked at 'Could not canonicalize ...'`),
which reaches the translation's `error`.

A `--perf` run with `--filter`, a comma-separated list whose every part names the kernels whose
key holds it, re-measures only those kernels into the capture `--out` names (`merge_perf_rerun`),
so a suspect cell runs again alone: each such kernel's entry is replaced, every other kernel stays
as read, `geomean` covers them all, and the re-run appends `{timestamp, kernels}` to the section's
`reruns`, while the section's own stamps stay the first run's. A capture holds one box (ruling 27)
and one set of parameters, so the re-run refuses, exit 1 with the file untouched, a capture
without a `perf` section and one whose `box`, `rust_commit` or `samples` is not the re-run's.
