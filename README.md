# c2das-re

A C99 to daslang source-to-source translator. The frontend is `libclang` (through `dasClangBind`, or
`clang -ast-dump=json`); the backend consumes **C-IR** and emits gen2 daslang. It is a rethink of
the earlier Rust-based c2das, aiming at the widest C99 coverage inside daslang and, in the future,
a plain `require "x.c"`.

[![CI](https://github.com/lookibed/c2das-re/actions/workflows/preflight.yml/badge.svg)](https://github.com/lookibed/c2das-re/actions/workflows/preflight.yml)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

## Architecture

```text
.c --> libclang / Dumper B --> C-IR (JSON) --> emitter --> .das
                                                            |
                    +---------------------------------------+-----------------------------+
                    v                                       v                             v
             daslang interp                         daslang -jit (LLVM)       daslang -exe / -ctx (AOT)
```

### Suites

| Suite       |  ids | passed | share |
| :---------- | ---: | -----: | ----: |
| c_testsuite |  220 |    203 | 92.3% |
| csmith      |  182 |    182 | 100.0% |
| gcc_torture | 1656 |   1204 | 72.7% |
| **total**   | 2058 | **1589** | **77.2%** |

Passed: the ratchet, `suites/<suite>/expected_pass.txt`. ids: `compare/results_linux.json`
(`suites.<suite>.ids`; csmith's ids are the generated seeds on record). Ids under a suite's
`skip.txt` count as not passed.

### Speed

| Lane        | x native  |
| :---------- | --------: |
| interpreter | 55.15 (7) |
| JIT         |  1.29 (7) |
| exe         |  1.29 (7) |
| AOT         |  1.79 (7) |

The geometric mean, over the real programs of [Real projects](#real-projects) (their count in
parentheses), of each program's lane time over its native build's time; lower is faster. Source:
the `results.speed.x_native` of `ports/variants/<program>.readable.json`.

### Readability

| Program       | criteria total |
| :------------ | -------------: |
| lua           |           88.9 |
| luac          |           88.5 |
| PureDOOM      |           86.9 |
| quakegeneric  |           84.3 |
| plmpeg-stream |           78.7 |
| doomgeneric   |           78.3 |
| h264bsd-mp4   |           77.9 |
| binjgb        |           76.4 |
| wasm3         |           71.6 |

A total is the unweighted mean of the compliance percentages (100 = what a human port would have)
of the criteria that apply, from `metrics/criteria_linux.json` (`totals`); the fast variant
(`--checks off`) is measured for Lua alone, 86.8 for both lua and luac.

## Quick Start

```sh
git clone https://github.com/lookibed/c2das-re.git
cd c2das-re
. scripts/env.sh            # bind DASLANG_ROOT (default /root/daScript) and define `das`
scripts/verify_daslang.sh   # report what the daScript checkout is missing
scripts/build_crt.sh        # build the dasCRuntime module the converter loads
scripts/preflight.sh        # the gate every change must clear
```

Run a single translation (writes `out/input.cir.json` and `out/input.das`):

```sh
das converter/main.das -- input.c --target linux --out out
```

## Toolchain

Binds to one daScript checkout, `DASLANG_ROOT`, built with `dasClangBind`, `dasStdDlg`, `dasHV`
and `dasLLVM` at the commit `VERSIONS.md` pins (daScript `6401904cf9`).

## Performance

Machine: box PC, AMD Ryzen 7 7435HS, WSL2, Linux x86_64; clang 22.1.8; daslang 0.6.5 (as the
captures record it; `VERSIONS.md` pins daScript `6401904cf9`). A cell is the median of 5 samples
(3 for Doom and the real projects), each its own process, ± half the sample range as a share of
the median; a spread above 20% is marked `suspect`.

### Microbenchmarks

| Test          | C (clang -O3) | DAS interp | DAS JIT | DAS exe | DAS AOT    | das by hand, dasProfile (interp / JIT / AOT) |
| :------------ | ------------: | ---------: | ------: | ------: | ---------: | :------------------------------------------- |
| bit_pack      |    0.000083 s |     135.06 |    1.22 |    1.17 |       1.17 | — [^nodp]                                    |
| blit          |    0.000358 s |      45.51 |    0.17 |    0.80 |       0.82 | — [^nodp]                                    |
| fib_loop      |    0.001457 s |      21.71 |    1.00 |    1.00 |       1.00 | 21.05 / 1.01 / 1.02 [^dp]                    |
| fib_recursive |    0.002939 s |       8.27 |    1.01 |    1.00 |       1.10 | 7.28 / 0.97 / 1.16 [^dp]                     |
| matmul        |    0.000220 s |      40.89 |    0.58 |    0.58 | 1.60 (#48) | — [^nodp]                                    |
| primes        |    0.014594 s |       4.42 |    1.00 |    1.00 |       0.54 | 1.19 / 1.00 / 0.31 [^dp]                     |
| sieve         |    0.001759 s |      20.83 |    1.12 |    1.12 | 8.17 (#48) | — [^nodp]                                    |

C is the time per run; every DAS cell is its lane's time over C's. Source: `perf/results_linux.json`
(captured 2026-11-09 15:59 UTC). The full table, with the `--param-writes copy`, `--loops while`,
`--checks off` and other interpreter lanes, is in [docs/performance.md](docs/performance.md),
rendered by `scripts/run_perf.sh --table --readme`.

[^dp]: dasProfile's hand-written das over its own C++, from `perf/dasprofile_linux.json`
    (dasProfile `436d58d`, box bench, AMD Ryzen 3 1200, 2026-11-03): a ratio, since times from
    two boxes do not compare; the capture runs daslang 0.6.4 on the bench box, not on box PC.
    Matched by name: this table's `fib_loop`, `fib_recursive` and `primes` are this tree's
    versions of dasProfile's `fibonacci loop`, `fibonacci recursive` and `primes loop`, at the same
    workload (count 6511134, depth 31, limit 14000), and `perf/perf_tables.das` `DIFFERENT_PROGRAMS`
    names them different programs: dasProfile's kernels are `noinline` and store each result into
    a `volatile` sink, and its `primes` tests `i < n` differently. (`SHARED_KERNELS` maps
    dasProfile's tests to its own kernels in C under `perf/kernels/dasprofile/`, not to these
    rows.) The column sets the two side by side and compares nothing.
[^nodp]: dasProfile has no test of this kernel.

### Doom

PureDOOM `-timedemo` on `freedoom2.wad`. fps = gametics / process CPU time of the host's update loop; one sync build verifies every tic
against the reference log, then the speed runs per lane. Rendered by `doom/run.das --readme` from
`doom/results_linux.json`.

<!-- doom-fps:begin -->
Box PC (AMD Ryzen 7 7435HS), linux x86_64; c2das-re `7862dde4d19d-dirty`, captured 2026-11-14 08:54 UTC; clang version 22.1.8 (https://github.com/llvm/llvm-project ca7933e47d3a3451d81e72ac174dcb5aa28b59d1); daslang 0.6.5.

PureDOOM `-timedemo demoN` on freedoom2.wad. fps is the demo's gametics over the process CPU time (`clock()`) of the host's update loop in the speed build, which leaves the patch's per-tic checksums and tic lines out: the playback alone, the module load, the JIT compile and `doom_init` outside it. Per demo and lane one run of the sync build first holds every tic to the reference log; a cell is then the median of 3 speed runs, each its own process ending in the demo's `timed N gametics`, ± half the range over the median; above 20% it is `suspect`, without a ratio. `X / native` is native fps over X's.

| Workload |   native fps | interp fps |      JIT fps |      exe fps |     AOT fps | interp / native | JIT / native | exe / native | AOT / native |
| :------- | -----------: | ---------: | -----------: | -----------: | ----------: | --------------: | -----------: | -----------: | -----------: |
| demo1    |  9881.6 ±1% | 224.6 ±1% |  9433.8 ±2% |  9614.3 ±2% | 1752.4 ±0% |            44.0 |          1.0 |          1.0 |    5.6 (#48) |
| demo2    | 11037.4 ±1% | 250.6 ±0% | 10133.6 ±0% | 10384.6 ±0% | 2198.6 ±0% |            44.1 |          1.1 |          1.1 |    5.0 (#48) |
| demo3    |  9666.4 ±1% | 217.2 ±0% |  9102.6 ±1% |  9269.1 ±0% | 1958.9 ±1% |            44.5 |          1.1 |          1.0 |    4.9 (#48) |


- (#48) daslang's AOT generator reads every module global through a hash lookup (`das_global<T, mnh>`), though the AOT context fixes each global's offset when it is generated; the same generated C++ with each read rewritten to its offset runs puredoom 1.14 (readable, demo1) x native: [lookibed/daScript#48](https://github.com/lookibed/daScript/issues/48).
<!-- doom-fps:end -->

## Real projects

| Project                                                                          |      Native | interp |  JIT |            exe |        AOT |
| :------------------------------------------------------------------------------- | ----------: | -----: | ---: | -------------: | ---------: |
| [binjgb](https://github.com/lookibed/c2das-ports/tree/main/binjgb)               |     61.7 ms |  73.40 | 1.15 |           1.19 |       1.15 |
| [doomgeneric](https://github.com/lookibed/c2das-ports/tree/main/doomgeneric)     |    117.4 ms |  43.31 | 1.08 |           1.08 |       3.69 |
| [h264bsd-mp4](https://github.com/lookibed/c2das-ports/tree/main/h264bsd-mp4)     |     78.7 ms |  59.64 | 1.05 |           1.05 |       1.13 |
| [lua](https://github.com/lookibed/c2das-ports/tree/main/lua)                     |    — [^lua] | 110.92 | 1.54 | 1.54 [^luaexe] |       1.36 |
| [plmpeg-stream](https://github.com/lookibed/c2das-ports/tree/main/plmpeg-stream) |     40.6 ms |  29.35 | 0.98 |           1.02 |       1.08 |
| [puredoom](https://github.com/lookibed/c2das-ports/tree/main/puredoom)           | 10177.8 fps |  44.19 | 1.07 |           1.04 | 5.19 (#48) |
| [wasm3](https://github.com/lookibed/c2das-ports/tree/main/wasm3)                 |     1.85 ms |  56.88 | 2.79 |           2.61 |       1.59 |

Native is the native build's measure: the bench's timed loop (median of 3) from
`compare/results_linux.json` (`projects.<name>.speed.native`), and for PureDOOM the geometric mean
of demo1-3 fps from `doom/results_linux.json`. Every other cell is the lane's time over native's,
the readable variant (the converter's default flags): `results.speed.x_native` of
`ports/variants/<program>.readable.json`, captured 2026-11-14. quakegeneric is left out: it passes
in every lane but has no bench unit, so no lane is timed.

[^lua]: Lua's native times are per workload (fib, binary_trees, nbody, spectral_norm and the test
    suite) and live in the ports repository's capture; no file committed here holds them.
[^luaexe]: exe over the four benches alone; its test-suite cell is not measured yet.

(#48) daslang's AOT generator reads every module global through a hash lookup
(`das_global<T, mnh>`); the same generated C++ with each read rewritten to its fixed offset runs
PureDOOM at 1.14 (readable, demo1), sieve at 1.63 and matmul at 1.01 x native:
[lookibed/daScript#48](https://github.com/lookibed/daScript/issues/48), cells from
`ports/upstream_cells.das`.

## Documents

- [docs/overview.md](docs/overview.md) - the project's history, the design documents under `docs/`, the toolchain, the layout, the license in full
- [docs/performance.md](docs/performance.md) - the perf method, the full microbenchmark tables, the dasProfile method, the Doom fps method
- [docs/rust-comparison.md](docs/rust-comparison.md) - the head-to-head with the Rust translator lookibed/c2das

## License

MIT (`LICENSE`), except `doom/`, which is GPL-2 ([docs/overview.md](docs/overview.md#license)).
