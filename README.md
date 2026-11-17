# c2das-re

C99 to daslang source-to-source translator. Frontend: `libclang` (via `dasClangBind` or
`clang -ast-dump=json`). Backend: consumes **C-IR** and emits gen2 daslang. A rethink of the older
Rust-based c2das; the goal is maximal C99 coverage inside daslang and, later, `require "x.c"`.

![License](https://img.shields.io/badge/license-MIT-green)

## Architecture

```text
.c --> libclang / Dumper B --> C-IR (JSON) --> emitter --> .das
                                                            |
                    +---------------------------------------+-----------------------------+
                    v                                       v                             v
             daslang interp                         daslang -jit (LLVM)       daslang -exe / -ctx (AOT)
```

### Suites

| Suite       |  ids |   passed |  share |
| :---------- | ---: | -------: | -----: |
| c_testsuite |  220 |      203 |  92.3% |
| csmith      |  182 |      182 | 100.0% |
| gcc_torture | 1656 |     1204 |  72.7% |
| **total**   | 2058 | **1589** |  77.2% |

Passed: `suites/<suite>/expected_pass.txt`; ids: `compare/results_linux.json`.

### Speed

| Lane        |  x native |
| :---------- | --------: |
| interpreter | 55.15 (7) |
| JIT         |  1.29 (7) |
| exe         |  1.29 (7) |
| AOT         |  1.79 (7) |

Geometric mean over the real projects below (count in parentheses), from
`ports/variants/<project>.readable.json`.

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

Percent, 100 = what a human port would have; `metrics/criteria_linux.json`.

## Quick Start

```sh
git clone https://github.com/lookibed/c2das-re.git
cd c2das-re
. scripts/env.sh            # bind DASLANG_ROOT (default /root/daScript)
scripts/verify_daslang.sh   # report what's missing
scripts/build_crt.sh        # build the dasCRuntime module
scripts/preflight.sh        # gate every change must clear
```

Run a single translation (writes `out/input.das`):

```sh
das converter/main.das -- input.c --target linux --out out
```

## Toolchain

Binds to one daScript checkout, `DASLANG_ROOT`, built with `dasClangBind`, `dasStdDlg`, `dasHV`,
`dasLLVM` at the commit pinned in `VERSIONS.md` (`b7d8f6f52f`).

## Performance

Machine: AMD Ryzen 7 7435HS, WSL2 Linux x86_64, clang 22.1.8, daslang 0.6.5. A cell is the median
of 5 samples (3 for Doom and real projects); spread > 20% is marked `suspect`.

### Microbenchmarks

| Test          | C (clang -O3) | DAS interp | DAS JIT | DAS exe |    DAS AOT |
| :------------ | ------------: | ---------: | ------: | ------: | ---------: |
| bit_pack      |    0.000083 s |     135.06 |    1.22 |    1.17 |       1.17 |
| blit          |    0.000358 s |      45.51 |    0.17 |    0.80 |       0.82 |
| fib_loop      |    0.001457 s |      22.03 |    1.00 |    1.00 |       1.00 |
| fib_recursive |    0.003241 s |       7.51 |    1.00 |    0.91 |       1.00 |
| matmul        |    0.000220 s |      40.89 |    0.58 |    0.58 |       1.04 |
| primes        |    0.014585 s |       4.43 |    1.00 |    1.00 |       0.54 |
| sieve         |    0.001759 s |      20.83 |    1.12 |    1.12 |       1.62 |

C is seconds per run, DAS cells are x C. fib_loop, fib_recursive, primes: dasProfile's programs,
`perf/results_method_linux.json`; the rest `perf/results_linux.json`. AOT of matmul and sieve:
the exclusive check of 2026-11-17 on daScript `b7d8f6f52f`, 7 runs (ledger P8.14).

### Doom

Rendered by `doom/run.das --readme` from `doom/results_linux.json`.

<!-- doom-fps:begin -->
Box PC (AMD Ryzen 7 7435HS), linux x86_64; c2das-re `7862dde4d19d-dirty`, captured 2026-11-14 08:54 UTC; clang version 22.1.8 (https://github.com/llvm/llvm-project ca7933e47d3a3451d81e72ac174dcb5aa28b59d1); daslang 0.6.5.

PureDOOM `-timedemo demoN` on freedoom2.wad. fps is the demo's gametics over the process CPU time (`clock()`) of the host's update loop in the speed build, which leaves the patch's per-tic checksums and tic lines out: the playback alone, the module load, the JIT compile and `doom_init` outside it. Per demo and lane one run of the sync build first holds every tic to the reference log; a cell is then the median of 3 speed runs, each its own process ending in the demo's `timed N gametics`, ± half the range over the median; above 20% it is `suspect`, without a ratio. `X / native` is native fps over X's.

| Workload |   native fps | interp fps |      JIT fps |      exe fps |     AOT fps | interp / native | JIT / native | exe / native | AOT / native |
| :------- | -----------: | ---------: | -----------: | -----------: | ----------: | --------------: | -----------: | -----------: | -----------: |
| demo1    |  9881.6 ±1% | 224.6 ±1% |  9433.8 ±2% |  9614.3 ±2% | 1752.4 ±0% |            44.0 |          1.0 |          1.0 |          5.6 |
| demo2    | 11037.4 ±1% | 250.6 ±0% | 10133.6 ±0% | 10384.6 ±0% | 2198.6 ±0% |            44.1 |          1.1 |          1.1 |          5.0 |
| demo3    |  9666.4 ±1% | 217.2 ±0% |  9102.6 ±1% |  9269.1 ±0% | 1958.9 ±1% |            44.5 |          1.1 |          1.0 |          4.9 |

<!-- doom-fps:end -->

## Real projects

| Project                                                                          |      Native | interp |  JIT |   exe |        AOT |
| :------------------------------------------------------------------------------- | ----------: | -----: | ---: | ----: | ---------: |
| [binjgb](https://github.com/lookibed/c2das-ports/tree/main/binjgb)               |     61.7 ms |  73.40 | 1.15 |  1.19 |       1.15 |
| [doomgeneric](https://github.com/lookibed/c2das-ports/tree/main/doomgeneric)     |    117.4 ms |  43.31 | 1.08 |  1.08 |       1.13 |
| [h264bsd-mp4](https://github.com/lookibed/c2das-ports/tree/main/h264bsd-mp4)     |     78.7 ms |  59.64 | 1.05 |  1.05 |       1.13 |
| [lua](https://github.com/lookibed/c2das-ports/tree/main/lua)                     |      6.45 s | 110.92 | 1.54 | error |       1.36 |
| [plmpeg-stream](https://github.com/lookibed/c2das-ports/tree/main/plmpeg-stream) |     40.6 ms |  29.35 | 0.98 |  1.02 |       1.08 |
| [puredoom](https://github.com/lookibed/c2das-ports/tree/main/puredoom)           | 10177.8 fps |  44.19 | 1.07 |  1.04 |       1.15 |
| [wasm3](https://github.com/lookibed/c2das-ports/tree/main/wasm3)                 |     1.85 ms |  56.88 | 2.79 |  2.61 |       1.59 |

Native: `compare/results_linux.json`; PureDOOM `doom/results_linux.json`; Lua, the sum of its 5
workloads, c2das-ports `lua/perf/capture_2026-11-14T095846Z.json`. Other cells are x native, from
`ports/variants/<project>.readable.json`. `error`: the lane does not run the whole benchmark.

AOT of doomgeneric and puredoom (demo1): the exclusive check of 2026-11-17 on daScript
`b7d8f6f52f`, 7 runs (ledger P8.14); the Doom section's AOT column is its 2026-11-14 capture, before that fix.

## License

MIT (`LICENSE`); `doom/` is GPL-2.
