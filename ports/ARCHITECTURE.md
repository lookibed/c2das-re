# ports Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
publishes the ports repository, `lookibed/c2das-ports`: one directory per real program this
repository converts, each regenerated from the pinned upstream release and
committed there with the c2das-re commit that produced it. The ports repository holds generated
code; this repository holds only the generator and its inputs.

## 1. File charters

- `publish.das` - the publisher: per program, the conversion (unless `--no-convert`), the
  measurement (with `--perf` only), the program's directory in the clone, the top-level README,
  and with `--commit` one commit per program (`--push` pushes the clone's HEAD). Run from the
  repository root through `scripts/publish_ports.sh`, which loads the `crt` and `c_runtime`
  modules and passes its flags through. The programs it knows are a constant table in it (the
  `Port` records): the harness folder, the converted modules, the module the workloads run, the
  libraries the native build links, the header holding the license, the upstream-test claims with
  the c2das-re item that recorded them, and the workloads. Beside them it publishes every real
  project of `compare/projects.das`'s `project_table` (section 5), then PureDOOM (`ARCHITECTURE_PUREDOOM.md`),
  each program in a process of its own (`ARCHITECTURE_RUN.md`); the variant files, `ARCHITECTURE_VARIANTS.md`; the cells a daslang defect slows, `ARCHITECTURE_UPSTREAM.md`.
- `ports_render.das` - the text: the capture records, the startup, work, times, ratio and not-yet
  text of a capture, the variants table (`ARCHITECTURE_VARIANTS.md`), the projects table and the top-level README below its marker, the license
  block of a C header, and the `VERSIONS.md` pin of a program. It measures nothing and reads no file.
- `lua/bench/*.lua` - the Lua benchmark workloads (`fib`, `binary_trees`, `nbody`,
  `spectral_norm`): plain scripts that print their result, take their size from `arg[1]` and
  default to about one second under the native build. They use no `pcall` and no
  `string.format` beyond `%d` and `%.9f`, since under the JIT the converted interpreter's protected
  calls report success (`docs/probe-findings.md` F75). Beside them `timed.lua`, the wrapper that
  times a workload inside its process (section 4).
- `tests/` - `test_ports_render.das` over fixed captures (golden tables), and
  `test_publish.das`, the publisher as a child process over a scratch c2das-re root (a stand-in
  release, harness and work tree with its stamp, its own git repository, and a stand-in Rust
  checkout `rust/` whose projects a test writes) and a scratch bare repository cloned as the ports
  clone. The stand-in interpreter counts its runs in a file of the
  folder it runs in, so the warm-ups and the test-suite folder are observable.

## 2. What a publish writes

The program's directory in the clone holds a fixed set of files, each replaced whole on every publish:

- per variant `<v>` (`ARCHITECTURE_VARIANTS.md`), in `<v>/`: the variant's conversion in the
  layout its knob names, every `.das` and `.das.inc` file its module list names (the single
  layout's one module) under `lua/work/variants/<v>/`'s layout folder of `<stem>`, in its folders,
  into `<v>/<stem>/`, with its `program.layout.txt`; the sidecar the variant converted under
  (`published_sidecar`, `<v>/lua.c2das`); and the variant file (`<v>/variant.json`). The
  conversion's C-IR and `luac -o` checks stay out.
- `LICENSE`: the block of the release's `src/lua.h` from the line `* Copyright (C)` to the line
  ending `DEALINGS IN THE SOFTWARE.`, the leading `* ` stripped.
- the benchmark scripts under `bench/`.
- `README.md`.

A variant's folder mirrors its conversion's module list: before copying, the publisher removes
every file under `<v>/<stem>/` the list does not name (`program.layout.txt` excepted). Beyond those folders
the publisher deletes nothing: a file it no longer writes stays until removed by hand in the ports
repository, which is the only hand edit that repository takes. The captures under `perf/` accumulate, one per
measuring publish.

Beside the program directories the clone holds the top-level `README.md` and c2das-re's raw
captures, each copied under its own path and replaced whole on every publish when the c2das-re
tree holds it: `compare/results_linux.json` (the head-to-head), `metrics/criteria_linux.json` (the
readability criteria), `perf/results_linux.json` and `perf/results_method_linux.json` (perf's two
methods) and `perf/dasprofile_linux.json` (the dasProfile lane). The top-level README names, in
one line under the projects table, every one of these the clone holds, a copy the tree no longer
has included (it stays, as above), then renders the readability criteria table from
`metrics/criteria_linux.json` (`render_criteria` of `metrics/criteria_file.das`) and the
head-to-head from `compare/results_linux.json`, each section absent without its file; a file that
does not read fails the publish before the top-level README and the copies are written.

The README holds the variants section (`ARCHITECTURE_VARIANTS.md` section 3), states the release and both tarballs with their sha256 as the `lua:` line of
`VERSIONS.md` names them (the publisher holds no version of its own), the commit the published
conversion ran at (the stamp's, section 3: `git describe --tags --always --dirty`, the full sha
and the commit date), the publish command with every flag that shapes the output, how to run the
modules, the upstream-test claims of the `Port` record as the results the c2das-re item it names
recorded (not results of the publish), the clock-free lines of the harness's report of each
variant's conversion (the lines of its `publish_run.log` naming the program, each clause that is a
count of seconds dropped: the binary sizes, JSON bytes, line and `[c_function]` counts and exit
codes stay), and the perf section rendered from the directory's latest capture. Nothing in it
depends on the clock of the publish, so a publish of an unchanged tree with the same flags,
converting or not, changes no file and commits nothing; the seconds of a conversion stay in its
log, and a measuring publish adds a capture.

The publisher refuses a `--repo` that is not the top of a git work tree, a c2das-re tree with
uncommitted changes unless `--allow-dirty`, an unknown `--program` or lane, `--push` without
`--commit`, `--samples` below 1, a `--timeout` of 0 seconds or less, a `VERSIONS.md` without the
program's line naming two tarballs, under `--no-convert` a missing stamp or one naming another
commit than `HEAD` unless `--allow-stale`, a variant file that does not read, a missing converted
module or module list, a header without its license block, and a missing sidecar. Every refusal comes before the first write into the clone,
which a refused publish leaves as it was. The clone is `--repo`, else `$C2DAS_PORTS`, else
`../c2das-ports` beside the repository root.

## 3. The conversion

Without `--no-convert` the publisher removes the stamp an earlier conversion left, so a
conversion that fails leaves none naming `HEAD`, and runs `lua/fetch.sh` and then, per variant,
`lua/run.das -- --native --run --variant <its file> --layout <its layout>` as a child process, its
output kept in `lua/work/variants/<v>/publish_run.log`. A child rather than a `require`:
`lua/run.das` is a command-line program whose `main`, `Args` and relative paths make it one, and
its report reaches the README as the lines it logs, under the variant's name. A failed fetch or a
failed conversion stops the publish before the clone is touched. All finished, the conversion leaves its stamp,
`lua/work/publish.generation`: the sha, the describe and the date of the tree it ran in, one a
line. `--no-convert` publishes what `lua/work/` holds and reuses the log an earlier conversion
left, under the stamp's commit, and only when the stamp names `HEAD`: a work folder converted at
another commit, or one with no stamp, is published only with `--allow-stale`, under the stamp's
commit, or, without a stamp, as converted at an unrecorded commit and published from the tree's.

## 4. The measurement {#measurement}

`--perf` is off by default. Without `--perf` the publisher measures nothing and writes no
capture; with it, it measures as this section states and writes one. Either way the program's perf
section and its row of the top-level projects table render from the directory's latest capture.
A program with no capture has the perf section ``not yet: the publisher measures only under
`--perf`, off by default because a capture takes hours and runs only on an idle machine``
(`PERF_NOT_YET`), and the projects section is that line when no program has a capture.

The lanes are perf's (`perf/ARCHITECTURE.md` section 2), built by `perf/perf_lanes.das`, the
module `perf/run.das` builds its kernels' lanes with:

- `native`: the C files the harness's program manifest `work/<runs>.program.json` lists, in its
  order, built by the pinned clang at `-O3 -w -funsigned-char` (with `-lm`). A missing or refused
  manifest is the lane's reason. An earlier build is reused while `<binary>.key` holds the command,
  each `.c` and `.h` file of the C files' folders with its size and text hash, and the binary's
  size and mtime (`native_build_key`), as the exe and AOT lanes reuse theirs
  (`converter/ARCHITECTURE_TIERS.md` section 5): a capture after a building publish builds nothing.
- `interp` and `jit`: daslang over the `readable` variant's entry module
  (`work/variants/readable/<layout folder>/<runs>.das`) with the module folders loaded.
- `exe`: daslang's `-exe` build of it.
- `aot`: the `-ctx` context with the host of `converter/tiers.das`, compiled by the pinned
  `clang++ -O3`. `--lanes` defaults to every das lane, the AOT ones among them.
- `interp-fast`, `jit-fast`, `exe-fast` and `aot-fast`: the same over the `fast` variant's
  module, its binaries under `work/bench/fast/`.

Every variant converts under the harness's sidecar (`lua/lua.c2das` for `lua`) with its knobs set, whose `jit_whole_program`
pins the entry module's cached JIT build to one LLVM module (`converter/ARCHITECTURE_EMITTER.md` section 4),
so the `jit` lanes keep the inlining across the program's modules that the default partition per das module
loses and that the `exe` lane's one-unit build has; the lane passes no `--jit-split-modules` after `--`, where
the converted program would read it as its own argument and Lua's `-e` startup row refuses it (F92).

Each lane is built once, before the workloads, and its binary runs once with the startup
arguments (the AOT host hands its command line to the program as daslang does). A lane whose
build fails is `not yet` with its first error line for every workload; the publish still
exits 0. A lane `--lanes` leaves out is `not measured` in the tables, never `not yet`.

The workloads of `lua` are the startup row (`-e "print(1)"`), the four benchmark scripts, and
the release's test suite (`-e "_port=true" all.lua` in the fetched test folder; `_port` skips the
tests that assume a POSIX build, and the ANSI build passes the rest). The scripts and the suite run
under `bench/timed.lua` (`timed.lua <script> [arguments]`; the suite `-e "_port=true" timed.lua
all.lua`, which changes nothing for `all.lua`: under `_port` no test reads the interpreter's own
`arg` entries). The wrapper shifts `arg` by one, reads `os.clock()`, runs the script with `dofile`,
reads the clock again and writes `c2das_work_s=<seconds>` (`%.6f`) to stderr; it holds `os.clock`,
`io.stderr` and `string.format` before the script runs, since `all.lua` ends by clearing the
globals. `os.clock()` is C `clock()`, the process's CPU time: libc's under the native lane,
`crt::clock` under every converted lane, the clock perf's default method reads too, so every
lane's work seconds come from one clock. The work seconds are process CPU time (`clock()`, user
plus system), unlike dasProfile's steady wall clock, because stock Lua has no in-process wall clock
finer than `os.time()`'s whole seconds. The startup row runs bare. A sample is one process: its
time is the wall time from the spawn to the end of its output, which the child closes on exit
(popen's return lags the exit by up to its 100 ms watchdog tick, so the return is not the clock),
and under the wrapper also its work seconds, the line taken out of the merged stdout and stderr
wherever it lands before any check reads the output.
The spawn is the publisher's, so every sample includes it: on the reference machine, the FX-6300
the captures run on, a null spawn costs about 24 ms the first time and about 7 ms after, and the
`sh -c` that enters the test-suite folder adds about 8 ms more; these figures are that machine's.
The interpreter and the JIT each cache the compiled module in the folder they run in, so one
unmeasured run of the wrapper over an empty script (`work/bench/empty.lua`) precedes each lane's
samples in each folder; the exe and AOT lanes, with no cache, take that run once in the
repository root after their build's own run, so the wrapper's clock and stderr are shown working
under every das lane before its samples (the native lane, the reference build, takes none). A warm-up that fails, times out or prints no
`c2das_work_s=` line with seconds fails the lane (in the repository root) or the cell (in the
test-suite folder) with its first reported line, or for the missing line its last. The startup
row times the program's load and no work: under a das lane that is the load from the warm cache,
not a compile; with the spawn inside it, the row is an upper bound of the load. A cell is the
median of `--samples` samples (5 by default), with the spread as half the sample range over the
median, perf's rule; under the wrapper its work time is the median of the samples' work seconds,
with their spread by the same rule. The samples of a workload interleave (`sample_order`): round
`k` takes one sample of every lane still standing, native first, whose first sample is the
oracle, then the das lanes in `--lanes` order in an even round and in the reverse order in an odd
one, so a drift of the machine over the run weighs on every das lane alike and two lanes compared
in an A/B never take their samples in one fixed order.

The native lane's first sample is the oracle. A sample fails the cell when:

- it is the native lane's first sample and exits nonzero. The cell names the exit code and the
  sample's first reported line.
- it is a later sample of any lane and exits otherwise than the oracle. The cell names the exit
  codes and the sample's first reported line (an exception line comes before its trailer).
- it is a later sample of any lane and prints otherwise than the oracle. The cell names the first
  line where the two outputs part. The test-suite row's output is not compared, since it prints
  its random seeds and timings.
- it leaves out the closing line its workload names; this holds for the native lane's first
  sample too. The cell names the sample's last line. The test-suite row's closing line is
  `final OK !!!`, the line `all.lua` prints after its last test passes; a finalizer prints one
  more as the state closes. The check is there because a suite that stops early can exit 0: under
  the JIT an uncaught Lua error exits 0 (`docs/probe-findings.md` F75), and `all.lua` stops in
  `db.lua`, the third file it runs.
- it runs under the wrapper and prints no `c2das_work_s=` line, or one without seconds; this holds
  for the native lane's first sample too, and is checked after the closing line. The cell names
  what it printed and the sample's last line.
- it runs past `--timeout` seconds.

A native first sample without the closing line leaves no oracle. A failed cell keeps the samples
it took, the failing one last. A das cell without a native one is `no native run to compare with`.

A measuring publish writes `<program>/perf/capture_<UTC timestamp>.json`, the timestamp inside
and in the name both the end of the run: the c2das-re commit of the conversion it timed (the
stamp's), the command that reproduces it (`--samples`, `--lanes` and `--timeout` named), the
machine (`uname -m`, the CPU model of `/proc/cpuinfo`, the box, which is the `--box` name else
`perf/boxes.das`'s `box_of` the CPU, the clang version line with the path of the
clang the native lane ran, which the lane's command names, and daslang's version line), the
sample count and the timeout, every lane with its command and error, and every cell with its
samples. The perf section's `Captured` line and the projects table's Machine column name the box
as `perf/boxes.das`'s `box_label` (`machine_label`), a capture without `box` showing its CPU's box;
its `Reproduced by` command adds `--box <box>` when the capture recorded one (`reproduce_command`). The
README's tables render from the latest capture by name; a latest capture that is not
JSON fails the publish. A cell of the capture holds its whole runs' seconds (`samples`) and, under
the wrapper, their work seconds (`work_samples`) with their median and spread (`work_time`,
`work_time_spread`); every speed number the tables show is the work alone. A workload's work time
under a lane is its cell's in-process work time. A cell without work seconds, which only a capture
written before the wrapper holds, has a work time by subtraction: its median less the median of
the same lane's startup cell, native included, its spread the two cells' half ranges over the work
time; such a work time renders `(by subtraction)`, as does every ratio with it on either side and
every projects mean over such a ratio, so the two methods never look alike. A work time by
subtraction not above 0 is `within the start`, and where the lane's startup cell is missing or
failed it is `not yet`, the lane's not-yet line giving the reason `no startup cell`. A cell or a
work time whose spread is above 20% is suspect and never a number: it renders `suspect (±N%)`, its
ratios `suspect`, and it leaves the projects table's means as a missing cell does; a suspect
startup cell makes every work time by subtraction of its lane `suspect (startup)`, since each
inherits its noise. The tables' das lanes
are `interp`, `jit` and `exe`, each `not measured` where the capture left it out, then each AOT
lane whose build stood (a lane that did not build is its not-yet line alone, never a column), then
each `-fast` lane, and each `jit-goto`, `-source-cut` or `-single` lane of a capture made before the
variants, the capture measured. The startup table holds native's and each such lane's startup
cell and its ratio to native's, the only place a startup number appears; the work table holds the
work times of the other rows; the times table holds the raw medians, the startup row included. The
ratio table holds work times only, no startup row: each das lane over native and the pairs
interpreter over JIT and interpreter over exe; a `jit-goto` or `aot` column adds the interpreter and
the JIT over it, a `-fast` column its pair over its readable twin, a `-source-cut` or `-single`
column its pair over its source-layout twin. The projects table has the same das lanes over every capture it
shows. The top-level README keeps the text above its marker line and holds below it one row per
program with a capture: its timestamp and machine, and the geometric mean, over the workloads other
than the startup row, of each das lane's work-time ratio to native, with the count when a lane
covers only some workloads, `not yet` when it covers none, and `not measured` when the capture left
the lane out.

## 5. The compare projects

A compare project (wasm3, binjgb, h264bsd-mp4, plmpeg-stream, doomgeneric, quakegeneric) is a row
of `compare/projects.das`'s `project_table` over the Rust checkout (`$C2DAS_RUST`, else
`/root/c2das`), read in place; a row whose folder the checkout lacks is skipped with a warning, so
a checkout without `tests/manual` publishes Lua alone. `--program` takes `lua` or a project's name.

A project converts on every publish, once per variant, in the publisher's process, through
`convert_project` of `compare/projects.das` with the variant as `ours_variant` (`ours_module`: the
row's sidecar with the knobs set, its units in the source layout when the case lists them), into
`compare/work/ports/<name>/<v>/whole/`; under `--no-convert` it is not published. A program the
converter refuses converts file by file into `compare/work/ports/<name>/<v>/files/`: its
units, else every `.c` file its unit includes by quotes, followed through the `all.c` graphs that
include `.c` files themselves.
The canonical case not read (`load_expected`) and an upstream folder with neither a `LICENSE*` or
`COPYING*` file nor an SPDX line refuse the project before the first write into the clone.

The project's directory `<name>/` in the clone holds, per variant `<v>/`:

- `<stem>/`, the unit's stem: every file of the whole conversion with its `program.layout.txt`, or
  nothing when the program refuses.
- `files/`: each file that converts alone, its module at its C path under the project folder with
  the `.c` dropped; nothing when the program converts whole.
- `<name>.c2das`: the sidecar of the whole conversion, the project folder in its paths written
  `<c2das>/tests/manual/<name>`, the README's name for the Rust checkout; `variant.json`.

and beside them:
- `LICENSE`: every license file under the project's `upstream/`, each under its path, else the
  license each upstream file names by an SPDX line (`spdx_notice`; for MIT its full text under the
  notice's author, `spdx_license`), then the Rust checkout's own `LICENSE` for the project's glue
  files under `src/` and `include/`.
- `README.md`: the variants section (`ARCHITECTURE_VARIANTS.md` section 3), each variant's
  conversion result (whole, or the refusal and a row per file), the files, the
  Rust checkout's commit, the generating commit, how to run the module on the fixture in the Rust
  checkout (no fixture is copied: game data and fixtures keep their own licenses there) and the
  native build, the speed and the readability criteria (below).

Both folders mirror their conversion as the layouts of section 2 do. The speed is the project's
entry of `compare/results_linux.json`, rendered by `compare_render.das`'s `projects_text` over that
entry alone. The section opens with `measured_on_line`: the entry's own `date` (the entries of one
capture are measured on different dates), the commit that last changed the capture, and that the
output changed since when a commit after that date changed `converter/`, `c_runtime/` or
`dasCRuntime/`. A Lua README's perf section opens with `measured_at_line` when its latest capture's
commit is not the published conversion's, saying the output changed since when those folders differ
between the two (or the capture's commit is not in the tree).

A project that fails (its canonical case, its license, a write) does not stop the publish: the
other programs publish and commit, the top-level README's `Directories` section (`render_programs`)
links every program directory of the clone and names each failure when some program published (a
run that published nothing leaves the clone as it was), a commit with `--commit` holds that line, `--push` pushes what was committed, and the run then exits 1. A failed Lua publish is
collected the same way.

The criteria section (`project_criteria_text`) renders the row `project/<name>` of
`metrics/criteria_linux.json` (same `convert_project` conversion): its table, coverage (`coverage_text`),
the commit that last changed the capture (`not committed yet` while it is dirty), and that the output
changed since when the converter or `CRITERIA_SOURCES` (`compare/projects.das`, the criteria's
computation; no capture, test or document) differ from the published conversion's; else a not-yet line. Counters: the head-to-head's code table (whole conversions only).
