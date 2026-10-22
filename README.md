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
Captured on 2026-10-22 16:39 UTC, linux x86_64, AMD FX(tm)-6300 Six-Core Processor; clang version 22.1.8 (https://github.com/llvm/llvm-project ca7933e47d3a3451d81e72ac174dcb5aa28b59d1), 0.6.4. A cell is the median of 5 samples, each its own process, ± half the sample range as a share of the median; the fastest lane per row is bold.

| Test            |      C (clang -O3) | DAS interpreter | DAS interp, copied params |            DAS JIT |            DAS exe |            DAS AOT |
| :-------------- | -----------------: | --------------: | ------------------------: | -----------------: | -----------------: | -----------------: |
| bit_pack        | **0.000206s ±0%** |  0.069415s ±1% |            0.069362s ±2% |     0.000250s ±0% |     0.000225s ±0% |     0.000232s ±0% |
| blit            |     0.000429s ±1% |  0.041442s ±5% |            0.036436s ±1% |     0.003851s ±1% |     0.004391s ±2% | **0.000427s ±1%** |
| compound_lit    | **0.000532s ±0%** |  0.060002s ±2% |            0.060888s ±4% |     0.000553s ±0% |     0.000569s ±0% |     0.000558s ±0% |
| do_while_effect |     0.003403s ±0% |  0.077160s ±1% |            0.078513s ±2% |     0.003488s ±0% |     0.003420s ±0% | **0.003379s ±0%** |
| fib_loop        | **0.001905s ±0%** |  0.354339s ±6% |            0.354152s ±2% |     0.004377s ±0% |     0.004376s ±0% |     0.001906s ±0% |
| fib_recursive   |     0.008498s ±3% |  0.074879s ±4% |            0.073910s ±3% |     0.007976s ±0% |     0.008459s ±0% | **0.007922s ±1%** |
| fixed_mandel    |     0.000844s ±0% |  0.035605s ±2% |            0.036332s ±6% | **0.000547s ±0%** |     0.000551s ±0% |     0.000759s ±0% |
| matmul          |     0.000600s ±0% |  0.061380s ±1% |            0.061910s ±2% | **0.000347s ±0%** |     0.000576s ±0% |     0.000864s ±2% |
| primes          |     0.048718s ±0% | 0.364598s ±11% |            0.355286s ±4% |     0.045278s ±0% |     0.045300s ±0% | **0.035979s ±0%** |
| qsort_cmp       | **0.000209s ±0%** |  0.002013s ±4% |            0.002001s ±3% |     0.000544s ±1% |     0.000533s ±1% |     0.000560s ±1% |
| setjmp_general  | **0.000214s ±1%** |  0.007275s ±4% |            0.007236s ±6% |     0.004977s ±5% |     0.004317s ±7% |     0.003766s ±4% |
| sieve           | **0.006784s ±0%** |  0.173903s ±2% |            0.176089s ±1% |     0.007294s ±0% |     0.007162s ±1% |     0.036677s ±0% |
| str_copy        | **0.000726s ±2%** |  0.047504s ±1% |            0.044314s ±7% |     0.000870s ±0% |     0.000870s ±0% |     0.004082s ±0% |
| switch_goto     |     0.003593s ±1% |  0.189078s ±3% |            0.198910s ±7% |     0.001984s ±0% | **0.001977s ±1%** |    0.004221s ±20% |
| switch_local    | **0.001166s ±0%** |  0.116479s ±3% |            0.119614s ±2% |     0.006986s ±0% |    0.008374s ±11% |                n/a |
| va_forward      | **0.000604s ±1%** |  0.129394s ±7% |            0.125739s ±2% |     0.008175s ±1% |     0.006557s ±4% |     0.008173s ±0% |
<!-- perf-table:end -->
