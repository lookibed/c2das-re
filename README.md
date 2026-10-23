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

The comparison `docs/very-detailed-plan.md` section 2 asks for. These are microbenchmarks: small
C kernels under `perf/kernels/`, each timed alone, which say how the converted code of one kind of
loop or call runs, not how a program does; the program-level number is Doom's timedemo frame
rate, which this table gains when P6 lands, and none is published before then.

**Machine.** Every number below is from one machine: an AMD FX-6300 (Piledriver, six cores,
`bdver2`), Linux x86_64, the pinned clang 22.1.8 and daslang 0.6.4 (LLVM 22.1.5) of
`VERSIONS.md`, with no other job on it while it runs (the self-hosted Actions runner shares the
machine, so a capture waits for it to idle). Times from another machine do not compare; ratios to
native on the same machine do, which is what the delta against an earlier capture on another CPU
uses (`perf/ARCHITECTURE.md` section 5).

**Samples.** A cell is the median of five samples, each its own process, ± half the sample range
as a share of the median. Inside a sample the program runs the kernel as many times as fit a
0.5 s budget, the count regrown each round by 1.2 times the projection (at most a hundredfold),
and reports the seconds per run of the round that met the budget, so startup and compilation
never enter a cell.

**Lanes and flags.** `C (clang -O3)` is the C program built by the pinned clang at
`-O3 -w -funsigned-char` (dasProfile's Release level for its C++). The das lanes run the pipeline's
conversion of the same C file: `DAS interpreter` is `daslang` with the `c_runtime` and
`dasCRuntime` modules loaded; `DAS JIT` is `daslang -jit` (LLVM at O3, tuned for the host CPU);
`DAS exe` is daslang's `-exe` build, the JIT's code linked into an executable; `DAS AOT` is the
`-ctx` C++ context compiled with the pinned `clang++ -O3 -fwrapv -fno-strict-aliasing` into a
host. Two more interpreter lanes run the conversion under a non-default converter option:
`--param-writes copy` (copied params) and `--loops while` (while loops, the `for` form before the
range rewrite).

**Two methods.** The first table is this tree's harness over every kernel: the program times
itself with the CRT's `clock()` (process CPU time) around a plain call per run, the result kept
in a global. The second follows [dasProfile](https://github.com/borisbat/dasProfile)'s harness
step for step over the kernels both repositories share (the same C program at the same
parameter): `kernel_run` never inlined into the timing loop, each run's result stored into a
`volatile` sink, wall time by the steady clock (`clock_gettime(CLOCK_MONOTONIC)` natively,
`std::chrono::steady_clock` through `crt::c_monotonic_ns` in the conversion); the das side
reads the kernel's `volatile` parameter through `c_volatile_load`, the same unknown trip count
dasProfile's C++ reads, and the table sets dasProfile itself, built and run on the same machine
at the commit `VERSIONS.md` pins, beside it. Kernels that are not the same program are named and
not compared.

`scripts/run_perf.sh --readme` (and `--method dasprofile --readme`) regenerate the two tables from
`perf/results_linux.json` and `perf/results_method_linux.json`; `scripts/run_perf.sh
--from-scratch` rebuilds everything and reruns both methods and dasProfile;
`scripts/run_perf.sh --check` reruns both methods and fails when a cell moves more than 10% from
the committed capture, which CI runs on every release tag.

<!-- perf-table:begin -->
Captured on 2026-10-23 00:57 UTC, linux x86_64, AMD FX(tm)-6300 Six-Core Processor; clang version 22.1.8 (https://github.com/llvm/llvm-project ca7933e47d3a3451d81e72ac174dcb5aa28b59d1), 0.6.4. A cell is the median of 5 samples, each its own process, ± half the sample range as a share of the median; the fastest lane per row is bold.

| Test            |      C (clang -O3) | DAS interpreter | DAS interp, copied params | DAS interp, while loops |            DAS JIT |            DAS exe |            DAS AOT |
| :-------------- | -----------------: | --------------: | ------------------------: | ----------------------: | -----------------: | -----------------: | -----------------: |
| bit_pack        | **0.000207s ±0%** |  0.070448s ±1% |            0.070400s ±2% |          0.071064s ±1% |     0.000227s ±0% |     0.000227s ±0% |     0.000232s ±0% |
| blit            |     0.000430s ±1% |  0.040704s ±5% |            0.036459s ±5% |          0.043224s ±4% |     0.003685s ±0% |     0.004498s ±1% | **0.000422s ±1%** |
| compound_lit    | **0.000533s ±1%** |  0.059182s ±6% |            0.055383s ±4% |          0.059557s ±4% |     0.000655s ±1% |     0.000590s ±0% |     0.000557s ±0% |
| do_while_effect |     0.003403s ±0% |  0.077647s ±3% |            0.075294s ±4% |          0.077756s ±3% |     0.003467s ±0% |     0.003425s ±0% | **0.003380s ±0%** |
| fib_loop        |     0.001906s ±0% |  0.060183s ±1% |            0.059744s ±1% |         0.106861s ±29% |     0.004350s ±0% |     0.004376s ±0% | **0.001904s ±0%** |
| fib_recursive   |     0.008476s ±0% |  0.073413s ±5% |            0.073124s ±3% |          0.074809s ±3% |     0.007945s ±0% |     0.008455s ±0% | **0.007912s ±1%** |
| fixed_mandel    |     0.000843s ±0% |  0.033329s ±5% |            0.034044s ±8% |          0.033979s ±3% | **0.000579s ±0%** |     0.000579s ±0% |     0.000800s ±0% |
| matmul          |     0.000600s ±0% |  0.054456s ±3% |            0.054327s ±7% |          0.054819s ±5% | **0.000347s ±0%** |     0.000576s ±0% |     0.000866s ±1% |
| primes          |     0.048710s ±0% |  0.134604s ±0% |            0.134662s ±0% |          0.182880s ±0% |     0.046769s ±0% |     0.046798s ±0% | **0.030733s ±0%** |
| qsort_cmp       | **0.000209s ±0%** |  0.002012s ±4% |            0.001981s ±8% |          0.002039s ±4% |     0.000538s ±3% |     0.000537s ±1% |     0.000563s ±1% |
| setjmp_general  | **0.000211s ±1%** |  0.009024s ±1% |            0.008418s ±3% |          0.009102s ±3% |     0.004716s ±6% |     0.004562s ±6% |     0.003721s ±1% |
| sieve           | **0.006846s ±1%** |  0.151542s ±5% |            0.153519s ±7% |          0.148616s ±4% |     0.007241s ±0% |     0.007147s ±0% |     0.034492s ±0% |
| str_copy        | **0.000722s ±2%** |  0.046793s ±4% |           0.041210s ±10% |          0.046607s ±2% |     0.000867s ±0% |     0.000875s ±0% |     0.004089s ±0% |
| switch_goto     |     0.003583s ±0% |  0.189769s ±2% |            0.192251s ±5% |          0.197678s ±3% |     0.001983s ±0% | **0.001971s ±0%** |     0.002403s ±5% |
| switch_local    | **0.001164s ±0%** |  0.089089s ±3% |            0.085260s ±5% |          0.085449s ±3% |     0.006998s ±9% |     0.007740s ±6% |                n/a |
| va_forward      | **0.000598s ±1%** |  0.127643s ±2% |            0.121947s ±6% |          0.128498s ±6% |     0.008301s ±1% |     0.006428s ±0% |     0.008238s ±0% |
<!-- perf-table:end -->

<!-- perf-method:begin -->
The dasProfile method on AMD FX(tm)-6300 Six-Core Processor (2026-10-23 01:01 UTC; clang version 22.1.8 (https://github.com/llvm/llvm-project ca7933e47d3a3451d81e72ac174dcb5aa28b59d1), daslang 0.6.4) beside borisbat/dasProfile 436d58d2840ff839550d44d32f98e10a15b57bf2 run on AMD FX(tm)-6300 Six-Core (Thu Oct 22 20:55:43 2026; Clang 22.1.8, daslang 0.6.4, LLVM 22.1.5). Seconds per run, median of five samples; a hand-written cell's ratio is over dasProfile's C++, a converted cell's over the C program.

| Test          | C (clang -O3) | dasProfile C++ | hand-written interp |  hand-written JIT |  hand-written AOT |   converted interp |     converted JIT |     converted AOT |     converted exe |
| :------------ | ------------: | -------------: | ------------------: | ----------------: | ----------------: | -----------------: | ----------------: | ----------------: | ----------------: |
| fib_loop      |     0.001906s |      0.001906s |  0.060231s (31.60x) | 0.001906s (1.00x) | 0.001906s (1.00x) | 0.059845s (31.39x) | 0.004336s (2.27x) | 0.001904s (1.00x) | 0.004370s (2.29x) |
| fib_recursive |     0.008401s |      0.008433s |   0.072531s (8.60x) | 0.008844s (1.05x) | 0.009518s (1.13x) |  0.073639s (8.77x) | 0.008829s (1.05x) | 0.008839s (1.05x) | 0.008452s (1.01x) |
| primes        |     0.048735s |      0.049543s |   0.144809s (2.92x) | 0.046757s (0.94x) | 0.028860s (0.58x) |  0.134606s (2.76x) | 0.046817s (0.96x) | 0.031117s (0.64x) | 0.046813s (0.96x) |

- `fixed_mandel` (16.16 fixed point, 96x96, 48 iterations, struct vectors by value) is not dasProfile's `mandelbrot` (double, 64x64, 255 iterations): different programs, not compared
- `matmul`, `sieve`, `blit` and the construct kernels have no dasProfile twin; dasProfile's `n-bodies`, `spectral norm`, `sha256`, `sort`, `tree`, `queen`, `dictionary`, `exp loop`, `particles kinematics`, `string2float`, `float2string` and `interop host calls` have no kernel here: different programs, not compared
<!-- perf-method:end -->
