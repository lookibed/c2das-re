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
Captured on 2026-10-06 22:57 UTC, linux x86_64, AMD Ryzen 7 7435HS; clang version 22.1.8 (https://github.com/llvm/llvm-project ca7933e47d3a3451d81e72ac174dcb5aa28b59d1), 0.6.4. A cell is the median of 5 samples, each its own process, ± half the sample range as a share of the median; the fastest lane per row is bold.

| Test | C (clang -O3) | DAS interpreter | DAS JIT | DAS exe | DAS AOT |
| --- | ---: | ---: | ---: | ---: | ---: |
| blit | **0.000387s ±1%** | 0.015691s ±2% | 0.000456s ±0% | 0.000866s ±2% | 0.000560s ±2% |
| fib_loop | **0.001484s ±0%** | 0.167980s ±3% | 0.001518s ±1% | 0.001575s ±3% | 0.001499s ±1% |
| fib_recursive | 0.003050s ±0% | 0.026555s ±2% | 0.003035s ±1% | 0.003430s ±2% | **0.002682s ±2%** |
| fixed_mandel | 0.000336s ±2% | 0.021544s ±4% | 0.000226s ±2% | **0.000201s ±1%** | 0.001336s ±1% |
| matmul | 0.000229s ±1% | 0.023499s ±4% | **0.000134s ±2%** | 0.000222s ±1% | 0.001199s ±6% |
| primes | 0.015142s ±1% | 0.153345s ±2% | 0.014973s ±1% | 0.015017s ±1% | **0.011350s ±0%** |
| sieve | **0.001767s ±3%** | 0.079244s ±3% | 0.002032s ±1% | 0.001935s ±3% | 0.017751s ±2% |
<!-- perf-table:end -->
