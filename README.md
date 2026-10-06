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
is a C program built natively by the pinned clang at `-O2` and converted by the pipeline, run
under every daslang tier; `scripts/run_perf.sh --readme` refreshes this table from
`perf/results_linux.json`.

<!-- perf-table:begin -->
Captured on 2026-10-06 22:15 UTC, linux x86_64, AMD Ryzen 7 7435HS; clang version 22.1.8 (https://github.com/llvm/llvm-project ca7933e47d3a3451d81e72ac174dcb5aa28b59d1), 0.6.4. A cell is the median of 5 samples, each its own process, ± half the sample range as a share of the median; the fastest lane per row is bold.

| Test | C (clang -O2) | DAS interpreter | DAS JIT | DAS exe | DAS AOT |
| --- | ---: | ---: | ---: | ---: | ---: |
| fib_loop | 0.001578s ±1% | 0.219282s ±8% | 0.001568s ±4% | **0.001522s ±4%** | 0.001577s ±5% |
| fib_recursive | 0.003240s ±2% | 0.026546s ±1% | 0.003174s ±1% | 0.003553s ±6% | **0.001809s ±4%** |
| fixed_mandel | 0.000283s ±1% | 0.016079s ±3% | 0.000218s ±0% | **0.000206s ±1%** | 0.001343s ±1% |
| matmul | 0.000243s ±7% | 0.024571s ±9% | **0.000137s ±3%** | 0.000229s ±2% | 0.001064s ±3% |
| primes | 0.015130s ±1% | 0.167253s ±4% | 0.015234s ±1% | 0.015067s ±1% | **0.011649s ±5%** |
| sieve | 0.001889s ±4% | 0.083223s ±4% | 0.002133s ±5% | **0.001878s ±4%** | 0.014352s ±3% |
<!-- perf-table:end -->
