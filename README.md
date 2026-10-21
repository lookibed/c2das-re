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
Captured on 2026-10-21 19:44 UTC, linux x86_64, AMD FX(tm)-6300 Six-Core Processor; clang version 22.1.8 (https://github.com/llvm/llvm-project ca7933e47d3a3451d81e72ac174dcb5aa28b59d1), 0.6.4. A cell is the median of 5 samples, each its own process, ± half the sample range as a share of the median; the fastest lane per row is bold.

| Test          |      C (clang -O3) | DAS interpreter | DAS interp, copied params |            DAS JIT |         DAS exe |            DAS AOT |
| :------------ | -----------------: | --------------: | ------------------------: | -----------------: | --------------: | -----------------: |
| bit_pack      | **0.000206s ±0%** |  0.069127s ±1% |            0.070568s ±1% |     0.000250s ±0% |  0.000225s ±0% |     0.000232s ±0% |
| blit          |     0.000426s ±1% |  0.042641s ±5% |            0.036502s ±7% |     0.003945s ±3% |  0.004503s ±1% | **0.000423s ±2%** |
| fib_loop      |     0.001904s ±0% |  0.353913s ±9% |            0.358871s ±1% |     0.004362s ±0% |  0.004373s ±0% | **0.001904s ±0%** |
| fib_recursive |     0.008448s ±0% |  0.073739s ±3% |            0.073767s ±5% |     0.007963s ±1% |  0.008442s ±0% | **0.007876s ±1%** |
| fixed_mandel  |     0.000844s ±0% |  0.034919s ±6% |            0.034816s ±2% | **0.000547s ±0%** |  0.000551s ±0% |     0.000759s ±0% |
| matmul        |     0.000600s ±0% |  0.060799s ±2% |            0.060710s ±2% | **0.000347s ±0%** |  0.000576s ±0% |     0.000861s ±1% |
| primes        |     0.048709s ±0% |  0.346629s ±7% |           0.375661s ±10% |     0.045267s ±0% |  0.045257s ±0% | **0.035950s ±0%** |
| qsort_cmp     | **0.000208s ±1%** |  0.001993s ±6% |            0.001977s ±6% |     0.000543s ±5% |  0.000536s ±1% |     0.000562s ±1% |
| sieve         | **0.006807s ±1%** |  0.173641s ±3% |            0.171762s ±1% |     0.007295s ±1% |  0.007157s ±0% |     0.036667s ±0% |
| str_copy      | **0.000729s ±1%** |  0.046789s ±0% |            0.046088s ±6% |     0.000869s ±0% |  0.000869s ±0% |     0.004086s ±0% |
| switch_local  | **0.001164s ±0%** |  0.116200s ±6% |            0.115750s ±2% |     0.007251s ±2% | 0.006860s ±13% |                n/a |
| va_forward    | **0.000602s ±0%** |  0.126139s ±4% |            0.124107s ±7% |     0.008124s ±1% |  0.006809s ±1% |     0.008137s ±0% |
<!-- perf-table:end -->
