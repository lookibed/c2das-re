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
Captured on 2026-10-21 15:10 UTC, linux x86_64, AMD FX(tm)-6300 Six-Core Processor; clang version 22.1.8 (https://github.com/llvm/llvm-project ca7933e47d3a3451d81e72ac174dcb5aa28b59d1), 0.6.4. A cell is the median of 5 samples, each its own process, ± half the sample range as a share of the median; the fastest lane per row is bold.

| Test          |      C (clang -O3) | DAS interpreter | DAS interp, copied params |            DAS JIT |        DAS exe |            DAS AOT |
| :------------ | -----------------: | --------------: | ------------------------: | -----------------: | -------------: | -----------------: |
| bit_pack      | **0.000206s ±1%** |  0.070337s ±1% |            0.070072s ±1% |     0.000250s ±0% | 0.000225s ±0% |     0.000232s ±0% |
| blit          |     0.000427s ±1% |  0.041851s ±2% |            0.036653s ±5% |     0.004024s ±3% | 0.004506s ±1% | **0.000420s ±2%** |
| fib_loop      | **0.001904s ±0%** |  0.359380s ±6% |            0.361806s ±8% |     0.004364s ±1% | 0.004361s ±0% |     0.001904s ±0% |
| fib_recursive |     0.008441s ±0% |  0.072294s ±2% |            0.072785s ±5% | **0.007882s ±1%** | 0.008418s ±0% |     0.007962s ±1% |
| fixed_mandel  |     0.000843s ±0% |  0.036167s ±3% |            0.036156s ±8% | **0.000547s ±0%** | 0.000551s ±0% |     0.000759s ±0% |
| matmul        |     0.000599s ±0% |  0.060164s ±2% |            0.060354s ±5% | **0.000346s ±0%** | 0.000576s ±0% |     0.000861s ±1% |
| primes        |     0.048708s ±0% |  0.358674s ±4% |            0.377556s ±6% |     0.045262s ±0% | 0.045274s ±0% | **0.035951s ±0%** |
| qsort_cmp     | **0.000208s ±1%** |  0.001944s ±2% |            0.001989s ±3% |    0.000545s ±24% | 0.000531s ±1% |    0.000572s ±11% |
| sieve         | **0.006860s ±1%** |  0.182189s ±6% |            0.172688s ±0% |     0.007285s ±0% | 0.007146s ±0% |     0.036649s ±0% |
| str_copy      | **0.000731s ±2%** |  0.047244s ±1% |            0.045590s ±5% |     0.000869s ±0% | 0.000869s ±0% |     0.004084s ±0% |
<!-- perf-table:end -->
