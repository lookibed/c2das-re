# ports Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
publishes the ports repository, `lookibed/c2das-ports`: one directory per real program this
repository converts (`lua/` today), each regenerated from the pinned upstream release and
committed there with the c2das-re commit that produced it. The ports repository holds generated
code; this repository holds only the generator and its inputs.

## 1. File charters

- `publish.das` - the publisher: per program, the conversion (unless `--no-convert`), the
  measurement (with `--perf` only), the program's directory in the clone, the top-level README,
  and with `--commit` one commit per program (`--push` pushes the clone's HEAD). Run from the
  repository root through `scripts/publish_ports.sh`, which loads the `crt` and `c_runtime`
  modules and passes its flags through. The programs it knows are a constant table in it (the
  `Port` records): the harness folder, the composed modules, the module the workloads run, the
  libraries the native build links, the header holding the license, the upstream-test claims and
  the workloads.
- `ports_render.das` - the text: the capture records, the times, ratio and not-yet text of a
  capture, the projects table and the top-level README below its marker, the license block of a C
  header, and the `VERSIONS.md` pin of a program. It measures nothing and reads no file.
- `lua/bench/*.lua` - the Lua benchmark workloads (`fib`, `binary_trees`, `nbody`,
  `spectral_norm`): plain scripts that print their result, take their size from `arg[1]` and
  default to about one second under the native build. They use no `pcall` and no
  `string.format` beyond `%d` and `%.9f`, since the converted interpreter aborts on a Lua error.
- `tests/` - `test_ports_render.das` over fixed captures (golden tables), and
  `test_publish.das`, the publisher as a child process over a scratch c2das-re root (a stand-in
  release, harness and work tree, its own git repository) and a scratch bare repository cloned
  as the ports clone.

## 2. What a publish writes

The program's directory in the clone holds a fixed set of files, each replaced whole on every
publish: the converted modules (`lua_all.das`, `luac_all.das`, copied from
`lua/work/<stem>/<stem>.das`), the sidecar (`lua.c2das`), `LICENSE` (the block of the release's
`src/lua.h` from the line `* Copyright (C)` to the line ending `DEALINGS IN THE SOFTWARE.`, the
leading `* ` stripped), the benchmark scripts under `bench/`, and `README.md`. The publisher
deletes nothing: a file it no longer writes stays until removed by hand in the ports repository,
which is the only hand edit that repository takes. The captures under `perf/` accumulate, one per
measuring publish.

The README states the release and both tarballs with their sha256 as the `lua:` line of
`VERSIONS.md` names them (the publisher holds no version of its own), the generating commit
(`git describe --tags --always --dirty` and the full sha, with the commit's date), the publish
command, how to run the modules, the upstream-test claims of the `Port` record, the harness's
report of the conversion (the lines of `lua/work/publish_run.log` naming the program), and the
perf section rendered from the directory's latest capture. Nothing in it depends on the clock of
the publish, so a publish of an unchanged tree changes no file and commits nothing.

The publisher refuses a `--repo` that is not the top of a git work tree, a c2das-re tree with
uncommitted changes unless `--allow-dirty`, an unknown `--program` or lane, `--push` without
`--commit`, a `VERSIONS.md` without the program's line naming two tarballs, a missing converted
module under `--no-convert`, and a header without its license block. The clone is `--repo`, else
`$C2DAS_PORTS`, else `../c2das-ports` beside the repository root.

## 3. The conversion

Without `--no-convert` the publisher runs `lua/fetch.sh` and then `lua/run.das -- --native --run`
as a child process, its output kept in `lua/work/publish_run.log`. A child rather than a
`require`: `lua/run.das` is a command-line program whose `main`, `Args` and relative paths make
it one, and its report reaches the README as the lines it logs. A failed fetch or conversion
stops the publish before the clone is touched; `--no-convert` publishes what `lua/work/` holds
and reuses the log an earlier conversion left.

## 4. The measurement {#measurement}

`--perf` is off by default: the perf method audit (ledger item C, `p-perf-method`) settles the
method before any table is published. Without `--perf` the publisher measures nothing and writes
no capture, and the program's perf section and the top-level projects section are the one line
`not yet: the perf method audit (ledger item C, p-perf-method) comes first; the tables are
rendered from captures by this publisher once it lands` (`PERF_NOT_YET`). With `--perf` it
measures as this section states and renders the tables.

The lanes are perf's (`perf/ARCHITECTURE.md` section 2), built by `perf/perf_lanes.das`, the
module `perf/run.das` builds its kernels' lanes with: `native` is the composed C file built by
the pinned clang at `-O3 -w -funsigned-char` (with `-lm`), `interp` and `jit` are daslang over the
converted module with the module folders loaded, `exe` is daslang's `-exe` build, `aot` the
`-ctx` context with the host of `converter/tiers.das` compiled by the pinned `clang++ -O3`. Each
lane is built once, before the workloads. The AOT host passes the program no arguments, so the
tier refuses the lane for a program that needs them; that refusal is the lane's reason. A lane
whose build fails is `not yet` with its first error line for every workload; the publish still
exits 0.

The workloads of `lua` are the startup row (`-e "print(1)"`), the four benchmark scripts, and
the release's test suite (`-e "_port=true" all.lua` in the fetched test folder; `_port` skips the
tests that assume a POSIX build, and the ANSI build passes the rest). A sample is one process: its
time is the wall time from the spawn to the end of its output, which the child closes on exit
(popen's return lags the exit by up to its 100 ms watchdog tick, so the return is not the clock).
The startup row times the program's load and no work: under a das lane that is the module's
compile and load, which every other row includes. The JIT caches its compile in the folder it
runs in, so one unmeasured run of the startup arguments precedes the JIT's samples in each
folder. A cell is the median of `--samples` samples (5 by default), with the spread as half the
sample range over the median, perf's rule. The native lane's first sample is the oracle: a later
sample of any lane that exits otherwise, or prints otherwise (the test-suite row compares the exit
code alone, since it prints its random seeds and timings), fails the cell with the difference as
its reason; a sample past `--timeout` seconds fails it too. A das cell without a native one is
`no native run to compare with`.

A measuring publish writes `<program>/perf/capture_<UTC timestamp>.json`: the machine (`uname
-m`, the CPU model of `/proc/cpuinfo`, the clang and daslang version lines), the sample count,
every lane with its command and error, and every cell with its samples. The README's tables
render from the latest capture by name. The
ratio table holds each das lane over native and the pairs interpreter over JIT, interpreter
over exe, interpreter over AOT and JIT over AOT. The top-level README keeps the text above its
marker line and holds below it one row per program with a capture: the geometric mean, over the
workloads other than the startup row, of each das lane's ratio to native, with the count when a
lane covers only some workloads, and `not yet` when it covers none.
