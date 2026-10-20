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
under every daslang tier; `scripts/run_perf.sh --readme` refreshes this table from
`perf/results_linux.json`.

<!-- perf-table:begin -->
Captured on 2026-10-20 01:11 UTC, linux x86_64, AMD FX(tm)-6300 Six-Core Processor; clang version 22.1.8 (https://github.com/llvm/llvm-project ca7933e47d3a3451d81e72ac174dcb5aa28b59d1), 0.6.4. A cell is the median of 5 samples, each its own process, ± half the sample range as a share of the median; the fastest lane per row is bold.

| Test          |      C (clang -O3) | DAS interpreter |            DAS JIT |        DAS exe |            DAS AOT |
| :------------ | -----------------: | --------------: | -----------------: | -------------: | -----------------: |
| blit          |     0.000425s ±1% |  0.036487s ±1% |     0.003993s ±3% | 0.004512s ±0% | **0.000420s ±1%** |
| fib_loop      |     0.001904s ±0% |  0.354534s ±3% |     0.004369s ±0% | 0.004375s ±0% | **0.001904s ±0%** |
| fib_recursive |     0.008448s ±0% |  0.072166s ±1% |     0.007970s ±1% | 0.008423s ±1% | **0.007942s ±1%** |
| fixed_mandel  |     0.000843s ±0% |  0.037543s ±2% | **0.000544s ±0%** | 0.000551s ±0% |     0.000738s ±0% |
| matmul        |     0.000600s ±0% |  0.062883s ±6% | **0.000347s ±0%** | 0.000577s ±0% |     0.000864s ±1% |
| primes        |     0.048714s ±0% |  0.352135s ±9% |     0.045269s ±0% | 0.045260s ±0% | **0.035950s ±0%** |
| sieve         | **0.006830s ±1%** |  0.173264s ±2% |     0.007286s ±0% | 0.007149s ±0% |     0.036651s ±0% |
<!-- perf-table:end -->
