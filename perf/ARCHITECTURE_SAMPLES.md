# perf Architecture - the guarded samples

Companion to `ARCHITECTURE.md` in this folder: how a timed sample is started, how its failure
reads in a cell, how samples become a cell and how two arms of a batch are decided, for the perf
harness, `compare/run.das`, `ports/publish.das` and `doom/run.das --fps` alike.

## 1. The guard

`measure` starts every sample through `timed` (`perf_lanes.das`, section 4), the pin before
`guarded`: `sh -c '"$@"; exit $?' sh prlimit --core=1 --
<argv>`. `prlimit` (util-linux; the fast tier's `env` gate checks it is on `PATH`) sets the core
file limit to one byte before it executes the program, so a sample that crashes writes no core:
a capture's crashes are findings in its cells, not dumps on the disk. The limit is 1, not 0,
because `/proc/sys/kernel/core_pattern` here is a pipe handler (WSL's `|/wsl-capture-crash`), and
the kernel hands a crash to a pipe handler whatever a limit of 0 says, while at a limit of 1 it
skips the pipe, and a file dump smaller than a page is never written either. `guarded` with an
address-space size adds `--as=<bytes>` to the same `prlimit`, the cap `compare/run.das --project`
gives its measured runs (`compare/ARCHITECTURE_PROJECTS.md`). The run an `exe` or `aot` build
ends with, the program's first, is guarded too (`lane_binary` runs the binary `build_tier` builds or
reuses under the guard), under the same cap. The guard runs before the program
times itself, so it never enters a cell; a timeout kills the whole process group, the shell and
the program in it.

## 2. A failed sample

daslib's `run_and_capture` reports a child killed by signal N as the exit code N, the same code
as a child exiting N, so a crash read bare is an exit code with whatever the program printed
first. The guard's shell waits for the program instead of becoming it, and a shell reports a
death by signal N as 128 + N. `exit_text` reads a code from 129 to 192 as `signal N (<name>)`,
the name for the signals 1 to 15 (`SIGNAL_NAMES`), and any other code as `exited <code>`. The
reading is ambiguous: a program that itself exits with a code from 129 to 192 (`exit(134)`) reads
as that signal (`signal 6 (ABRT)`), since the shell reports both alike; no kernel exits so.
`run_error` adds the first line of the output that is neither empty, nor an `info` line, nor the
shell's own report of the death (`shell_signal_line`: `Segmentation fault`, `Aborted`, `Bus error`
and the rest, with or without ` (core dumped)`), or `no output` when none is left: daslang's
report of an exception it cannot unwind starts with an empty line, and the shell prints its
report after everything the program printed, so it would otherwise name a silent crash.
`compare/projects.das`'s `error_line` skips the shell's report as well. A sample that exits 0
without the kernel's line is `exited 0` with that line.

## 3. The exclusive run

A capture runs as `heavy --exclusive` (the box's queue, owner rule 2026-11-06): the job waits for
every other job to end and for the CPU to be quiet (under 4 percent busy, twice over 5 s), runs
alone, and `/var/log/heavy-exclusive.log` keeps the busy share; a capture from a run that was not
exclusive, or that the log marks `NOT quiet`, is not recorded. The runners convert and build inside
the run today (the kernels' conversions, the exe and AOT builds), which the rule tolerates until a
build-only step exists (`docs/implementation_order.md`).

## 4. The pin

The pin is opt-in: with `$C2DAS_TIMING_CORE` set to a core, a timed sample runs on that core alone,
`taskset -c <core>` before the guarded command (`timing_prefix`); unset, empty or `off`, no sample
is pinned. Every timed path takes it: `measure` through `timed`, `compare/projects.das`'s bench runs
and `perf/audit_lua.das`'s whole-run benches (`wall_cell`) through `timed` too, `ports/publish.das`'s
`measure_sample` and the speed runs of `doom/fps_run.das` (`DemoSpec.pin`) through
`timing_prefix`. A build, a warm-up, a sync run or a correctness run is not pinned. A core this
process may not run on (`Cpus_allowed_list` of `/proc/self/status`) or no `taskset` on `PATH` leaves
the samples unpinned with a warning; the process reads the pin once and logs it. Every capture
records the core as `pinned_core`, -1 for none (`pinned_core`).

The pin is off by default because it buys nothing measured. On the box (WSL2) pure CPU work spreads
1.4 percent with or without it; the noise probe's allocation-heavy kernel spread 20.5 percent free
and 12.5 percent pinned, with as many runs more than 5 percent slow pinned as free (12 and 10 of
200). On the Lua benches under the JIT (P9.41, 15 samples a side, interleaved) the pinned medians
were the free ones (0.992, inside an 8.0 percent band), the robust spread narrowed on nbody and
spectral_norm only, and on the allocating `binary_trees` it was wider pinned, 8.0 percent of the
median against 5.8 free (full widths). A default pin would also send every timed child of
concurrent harnesses and parallel test lanes to one core, and confine a JIT's compile threads in a
cell that times the whole run (a ports `startup` cell, `wall_cell`), whose time includes the
`taskset` exec as well; a program timed inside the process (a kernel's budget loop,
`bench/timed.lua`, a bench's `decode_us`, Doom's host) leaves its compile out either way.

## 5. The cell and its spread

A cell is the median of its samples (`samples.das`). Its spread is half the range of the samples
as a share of the median, the one sample farthest from the median left out from
`OUTLIER_MIN_SAMPLES` (5) samples on (`spread_of`), and the cell records that sample's signed
distance from the median as `outlier` (0 under five samples), so a dropped sample stays in the
record beside the raw samples. Every capture records the rule its cells took as `spread_rule`
(`spread_rule_of` of its sample count): `trimmed` from five samples a cell on, `range` under five
(Doom's default of 3), where nothing is left out; the perf, compare, Lua-audit, ports and Doom
captures all stamp it, a compare `--filter` re-run joins only a capture of its own rule and pin
(`rerun_refusal`), and a table's header names the trimming (`spread_note`). A capture without the
field holds half the whole range (`range_spread_of`) and renders as before. One slow sample in a batch on the box comes out 1.5 to
2.3 times the others (0.59 against 0.89 s, 0.51 against 1.175 s, 27 against 41 s); the median
survives it and the whole range does not: a band built on the range widened to 51 to 127 percent.
The trimmed range keeps the unit and the meaning of the old `±` for a clean cell, so
`SUSPECT_SPREAD` and the `--check` bar read as before, and one outlier cannot inflate it while two
still do: two slow samples out of five are noise a reader should see. `1.4826 * MAD` was the
alternative: over five samples it is the third-smallest distance from the median, which hides a
bimodal cell's second mode.

The samples a cell takes come from `samples_for`, the one place the count is set: the count the
command line names, else `NOISY_SAMPLES` (9) for a workload whose native run takes under
`SHORT_RUN` (1 s) or that allocates heavily, else `DEFAULT_SAMPLES` (5). A perf kernel's native
sample runs its 0.5 s budget, so every kernel takes 9 (`--samples` 0 by default, the count
recorded); a ports workload takes its count after the native lane's first sample (the work time
under `bench/timed.lua`, else the whole run), Lua's `binary_trees` marked as allocating, and the
capture records `samples` 0 with the header naming both counts (`samples_text`); one sample decides,
so a workload whose native run lies near 1 s may take either count from one publish to the next,
its cell's samples holding the count it took. `--samples` below 0 is refused in both harnesses.
`compare/run.das`, `doom/run.das --fps` and `perf/audit_lua.das` keep their own `--samples`.

## 6. The A/B decision

`ab_band.das` decides a knob from one batch of interleaved runs, its lines `key=value` words with
`bench=`, `lane=` (the tier), `arm=` and the value (`work_s` by default, seconds); `ab.das` is its
command line (`--file`, `--arm`, `--base`, `--value`, `--cells`). Per tier the ratio is the geometric
mean over the benches of the arm's median over the base's; the band is the widest robust full
spread (twice `spread_of`) of either arm over the benches; the verdict is `F` when the ratio is
under 1 less the band, `S` when it is over 1 plus the band, else `-`. The whole-range band is
printed beside it. A knob stays when it is `F` on at least one tier and its `F` tiers outnumber its
`S` tiers (the lead's rule of 2026-11-22). A run line whose value is not a number or that carries
`OUTPUT_DIFFERS` is skipped and counted; one whose value is 0, below 0, NaN or infinite is refused
and named by its line. A bench timed under `native` alone is left out of every tier and named; a
tier where a bench lacks one arm's samples has no verdict, the line saying which.
