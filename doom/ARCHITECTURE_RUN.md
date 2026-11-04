# doom Architecture - the runs

Companion to `ARCHITECTURE.md` in this folder, its sections 8 and 9.

## 8. The converted run

`run_converted` runs the converted program's entry module, `doom_main.das` in every layout (the
module holding `main`), through `converter/tiers.das`'s `run_tier` from the repository root with
the converted program's module folders and the native run's C `argv`, `-timedemo demoN`.
`run_tier` takes no environment for the child, so the harness process sets `DOOMWADDIR` to the
wad's run folder, absolute, and the program inherits it: the wad opens as in the native run. A
wad link that fails stops the run. The `exe` and `aot` builds go to `work/run/<wad stem>/<layout>/`,
one folder per layout. The reference log is `<wad stem>_demo<N>.log` in `ref/`, else in `work/ref/` (a local
reference). The run's tic lines, a timed-out run's included, since
`run_and_capture` keeps the output a killed process wrote, are held to the log's by `tic_sync`:
the first `--tics` lines, or all of them, a run that goes on past the demo's last tic desyncing
there. Held to the whole demo, a run is in sync only when it also ends, not timed out, in the
`timed N gametics` line with N the log's tics, the end `demo_log` requires of a native run; under
`--tics` an exit after the compared tics passes, its exit code reported. The report names the
first desynced tic, the fields that differ (`tic`, `cs`, `fb`) and the lines, expected against
got, or `N tics in sync`, a run short of the compared tics, the exit code or the timeout, the first
error line of a run that ended in neither the `timed N gametics` line nor the host's `host: stopped
after N tics` (`first_error_line`, matching `error` or `exception` in any case, since PureDOOM's
`I_Error` text starts `Error: ` and a daslang panic `EXCEPTION: `), and the seconds per 35 tics
over the whole process, start included: a sanity number, not P6.7's measure. Under `--tics N` the program's `argv` starts with
the host's `-tics N` (`program_argv`), so the program stops after the compared tics with exit code
0 instead of playing the demo to its end or to `--timeout`.

Which tiers and layouts hold which demos in sync is the ledger's record (`docs/implementation_order.md`
P6.5 and P6.7), not this document's.

## 9. The frame rate

Two builds of the program serve the frame rate. The sync build is the one every other section
describes: under `DOOM_TIC_CHECKSUM` it hashes each tic's state and frame and prints the tic lines
the reference log holds. The speed build is the same program without that define, natively
(`work/native/doom-speed`) and converted (`work/<layout>-speed/`, under `work/doom-speed.c2das`,
the sidecar with the define taken out): it hashes nothing and prints no tic line, so the timed
window holds the game alone.

The host times the playback (section 4 of `ARCHITECTURE.md`): it reads `clock()`, the process CPU
time, after `doom_init` returns and again at the end, and prints `host: timed <N> gametics in <S> s`.
`clock()` is the clock the converter maps (`crt::clock`, the clock perf's default method reads,
`perf/ARCHITECTURE.md` section 2), so the native build and every tier time themselves with the same
clock. In the speed build's window: the demo's tics, their screen melts and their drawing. Outside
it: the process start, the module load, the JIT compile, the wad load and `R_Init`; and, having no
part in the speed build, the per-tic checksums and the tic lines.

`run.das --run --fps` takes every demo (or `--demo`'s) natively and under each tier of `--tiers`
(default `interp,jit`), each run its own process through `run_converted`, whose tier `native` runs
a native build alone under `prlimit --as` 3 GiB; the converted runs take `--layout`'s conversions.
`fps_run.das` runs it over an `FpsPlan` `run.das` fills. Per demo and lane one run of the sync build
comes first, held to every tic of the reference log as section 8 holds a run; a run out of sync
leaves the cell an error (`desync`) and no speed run follows, since the fps of a wrong replay is
never published. Then `--samples` runs of the speed build (default 3), each held to the demo's end:
`run_converted` under `DemoSpec.speed` compares no tic line, and `in_sync` passes a speed run only
when it ends in the demo's `timed N gametics` and prints no tic line. `fps.das`'s `run_problem`
also refuses a run without the host line, or whose host line times other tics than the reference's
or no time; the first speed run refused ends the cell. A cell's fps is the median of the speed runs'
`N / S`, its spread half their range over the median (`perf_lanes.das`'s `median_of` and
`spread_of`).

The capture is `results_linux.json` in this folder (`FpsCapture`): the c2das-re commit (`-dirty`
with tracked changes), the command, the end of the run, the platform, the CPU model and its box
(`perf/boxes.das`), clang's and daslang's version lines, the runs per cell, the clock, the lanes
with the command one timed run of each is, the demos and one cell per demo and lane with every
speed run's fps and seconds. `render_fps` turns a capture into the provenance line, the method line
and one table, demo by lane, each das lane's native fps over its own after the fps columns, and one
line per cell that does not stand; it reads no clock and no file. A cell whose spread is above 20%
(`SUSPECT_SPREAD` of `ports/ports_render.das`) renders `suspect (±N.N%)` and its ratio `suspect`.
`run.das --readme` rewrites `README.md` (repository root) between `<!-- doom-fps:begin -->` and
`<!-- doom-fps:end -->` from the committed capture.
