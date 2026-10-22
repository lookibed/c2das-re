# c2das-re

A C-to-daslang source converter, written in daslang. The frontend is libclang (through
daScript's dasClangBind module, or `clang -ast-dump=json`); the backend consumes the C-IR
interchange format and emits gen2 daslang source. The headline metric is the one the design
documents state: convert PureDOOM, run doom2.wad demo-sync-verified, and publish the
interpreter / JIT / AOT / native perf table.

This is the second attempt. The first, `/root/c2das`, is a Rust fork of C2Rust whose typed
C AST survives here as **Dumper B**, the second producer of C-IR for differential frontend
testing (docs/very-detailed-plan.md, 4.0). Its problems are what the documents under `docs/`
answer; its pipeline and repository structure are not a template for anything here. The
template for how this repository is developed is daScript itself: its document system,
agent set, review round and preflight discipline, carried over as described in `CLAUDE.md`.

## Documents

`docs/` holds the normative design, authored in their own repository and copied here:

- `very-detailed-plan.md` - decisions, architecture, verification plan, phases, risks
- `implementation_order.md` - the phases as ordered, acceptance-tested work items
- `c-ir-spec.md` - the C-IR interchange format (v0.1), the dumper-backend contract
- `c-feature-matrix.md` - every C99 construct and its lowering status
- `lowering-examples.md` - normative C to das code pairs, the emitter's golden reference
- `stdlib-examples.md` - the c_runtime designs for the C standard library
- `sidequest.md` - daslang core-language follow-ups this project never blocks on

## Toolchain

The repository binds to one daScript checkout, `DASLANG_ROOT` (`scripts/env.sh`, default
`/root/daScript`), built with dasClangBind, dasStdDlg, dasHV and dasLLVM at the commit
`VERSIONS.md` pins. Nothing of daScript is vendored except the generic skills under
`skills/` (`scripts/sync_daslang_skills.sh`). `scripts/verify_daslang.sh` says what is
missing; `scripts/preflight.sh` is the gate a change clears before it is pushed.

## Layout

See `ARCHITECTURE.md` for the folder charters: `converter/`, `c_runtime/`, `dasCRuntime/`,
`probes/`, `suites/`, `docs/`, `skills/`, `scripts/`.

## Performance

The comparison `docs/very-detailed-plan.md` section 2 asks for, measured the way
[dasProfile](https://github.com/borisbat/dasProfile) measures: each kernel under `perf/kernels/`
is a C program built natively by the pinned clang at `-O3`, dasProfile's level for its C++ kernels, and converted by the pipeline, run
under every daslang tier, and once more under the interpreter as converted with
`--param-writes copy` (the "copied params" column); `scripts/run_perf.sh --readme` refreshes this table from
`perf/results_linux.json`.

<!-- perf-table:begin -->
Captured on 2026-10-22 03:11 UTC, linux x86_64, AMD FX(tm)-6300 Six-Core Processor; clang version 22.1.8 (https://github.com/llvm/llvm-project ca7933e47d3a3451d81e72ac174dcb5aa28b59d1), 0.6.4. A cell is the median of 5 samples, each its own process, ± half the sample range as a share of the median; the fastest lane per row is bold.

| Test           |      C (clang -O3) | DAS interpreter | DAS interp, copied params |            DAS JIT |         DAS exe |            DAS AOT |
| :------------- | -----------------: | --------------: | ------------------------: | -----------------: | --------------: | -----------------: |
| bit_pack       | **0.000207s ±0%** |  0.069716s ±1% |            0.069466s ±1% |     0.000250s ±0% |  0.000225s ±0% |     0.000232s ±0% |
| blit           |     0.000427s ±1% |  0.041652s ±3% |            0.036503s ±2% |     0.003998s ±5% |  0.004516s ±1% | **0.000422s ±2%** |
| compound_lit   | **0.000530s ±0%** |  0.061043s ±4% |            0.060849s ±4% |     0.000553s ±0% |  0.000568s ±0% |     0.000557s ±0% |
| fib_loop       |     0.001904s ±0% |  0.356160s ±2% |            0.355996s ±7% |     0.004362s ±0% |  0.004375s ±0% | **0.001904s ±0%** |
| fib_recursive  |     0.008470s ±0% |  0.073838s ±5% |            0.072743s ±2% |     0.007965s ±0% |  0.008443s ±0% | **0.007894s ±1%** |
| fixed_mandel   |     0.000843s ±0% | 0.035188s ±14% |            0.035925s ±2% | **0.000547s ±0%** |  0.000551s ±0% |     0.000760s ±0% |
| matmul         |     0.000600s ±0% |  0.059743s ±1% |            0.060532s ±3% | **0.000347s ±0%** |  0.000576s ±0% |     0.000862s ±2% |
| primes         |     0.048717s ±0% |  0.398931s ±6% |            0.361962s ±5% |     0.045270s ±0% |  0.045269s ±0% | **0.035954s ±0%** |
| qsort_cmp      | **0.000209s ±1%** |  0.001968s ±4% |           0.002078s ±11% |     0.000542s ±3% |  0.000532s ±0% |     0.000559s ±0% |
| setjmp_general | **0.000211s ±6%** |  0.007842s ±8% |            0.007598s ±7% |     0.004948s ±7% |  0.004346s ±6% |     0.003829s ±2% |
| sieve          | **0.006780s ±1%** |  0.174759s ±5% |            0.175611s ±5% |     0.007350s ±2% |  0.007141s ±0% |     0.036669s ±0% |
| str_copy       | **0.000730s ±1%** |  0.047157s ±3% |            0.044681s ±4% |     0.000869s ±0% |  0.000869s ±0% |     0.004087s ±0% |
| switch_local   | **0.001163s ±0%** |  0.117292s ±7% |            0.116427s ±3% |     0.007287s ±3% | 0.008157s ±10% |                n/a |
| va_forward     | **0.000601s ±1%** |  0.126227s ±2% |            0.126796s ±2% |     0.008131s ±0% |  0.006730s ±4% |     0.008175s ±1% |
<!-- perf-table:end -->
