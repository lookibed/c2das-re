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
`bdver2`), Linux x86_64, the clang 22.1.8 of the libclang archive and the daScript commit
`VERSIONS.md` pins (the captures record daslang 0.6.4, dasProfile's its LLVM 22.1.5), with no
other job on it while it runs (the self-hosted Actions runner shares the machine, so a capture
waits for it to idle). Times from another machine do not compare; ratios to
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
step for step over its own three scalar kernels in C (`perf/kernels/dasprofile/`: its functions,
loops, parameters and `noinline` marks, file for file; the first table's three are this tree's
versions of them): each run's result stored into a `volatile` sink, wall time by the steady
clock (`clock_gettime(CLOCK_MONOTONIC)` natively, `std::chrono::steady_clock` through
`crt::c_monotonic_ns` in the conversion). The conversion carries no `noinline`; the das side
reads the kernel's `volatile` parameter through `c_volatile_load`, the same unknown trip count
dasProfile's C++ reads, and the table sets dasProfile itself, built and run on the same machine
at the commit `VERSIONS.md` pins, beside it. Kernels that are not the same program are named and
not compared.

`scripts/run_perf.sh --readme` (and `--method dasprofile --readme`) regenerate the two tables from
`perf/results_linux.json` and `perf/results_method_linux.json`; `scripts/run_perf.sh
--from-scratch` rebuilds everything and reruns both methods and dasProfile;
`scripts/run_perf.sh --check` reruns both methods and fails when a cell moves more than 10% from
the committed capture, or more than twice the cell's committed spread where that is wider (the
interpreter's `fib_loop` under `--loops while` spreads 29%), which CI runs on every release tag;
it reruns this tree's lanes only, and dasProfile's columns rerun under `--from-scratch` alone.

<!-- perf-table:begin -->
Captured on 2026-10-30 17:31 UTC, linux x86_64, AMD FX(tm)-6300 Six-Core Processor; clang version 22.1.8 (https://github.com/llvm/llvm-project ca7933e47d3a3451d81e72ac174dcb5aa28b59d1), 0.6.4. A cell is the median of 5 samples, each its own process, ± half the sample range as a share of the median; the fastest lane per row is bold.

| Test            |      C (clang -O3) | DAS interpreter | DAS interp, copied params | DAS interp, while loops |            DAS JIT |            DAS exe |            DAS AOT |
| :-------------- | -----------------: | --------------: | ------------------------: | ----------------------: | -----------------: | -----------------: | -----------------: |
| bit_pack        | **0.000206s ±0%** |  0.070288s ±1% |            0.070251s ±2% |          0.069749s ±2% |     0.000227s ±0% |     0.000227s ±0% |     0.000232s ±0% |
| blit            | **0.000424s ±0%** |  0.040690s ±3% |            0.036452s ±3% |          0.040981s ±3% |     0.003682s ±0% |     0.004545s ±1% |     0.000427s ±2% |
| compound_lit    | **0.000530s ±0%** |  0.059797s ±3% |            0.056003s ±3% |          0.060610s ±7% |     0.000654s ±0% |     0.000589s ±0% |     0.000558s ±0% |
| do_while_effect |     0.003400s ±0% |  0.077971s ±2% |            0.076275s ±7% |          0.080382s ±4% |     0.003465s ±0% |     0.003421s ±0% | **0.003377s ±0%** |
| fib_loop        | **0.001904s ±0%** |  0.059674s ±1% |            0.059926s ±6% |          0.113616s ±6% |     0.004346s ±0% |     0.004367s ±0% |     0.001904s ±0% |
| fib_recursive   |     0.008460s ±0% |  0.072174s ±2% |            0.072452s ±2% |          0.074407s ±4% | **0.007922s ±1%** |     0.008434s ±0% |     0.007958s ±1% |
| fixed_mandel    |     0.000843s ±0% |  0.033504s ±4% |            0.034474s ±2% |          0.033826s ±4% | **0.000579s ±0%** |     0.000579s ±0% |     0.000800s ±0% |
| matmul          |     0.000599s ±0% |  0.053776s ±1% |            0.054292s ±2% |          0.054771s ±4% | **0.000347s ±0%** |     0.000577s ±0% |     0.000865s ±1% |
| primes          |     0.048713s ±0% | 0.134636s ±16% |           0.135167s ±13% |          0.182531s ±0% |     0.046748s ±0% |     0.046784s ±0% | **0.030683s ±0%** |
| qsort_cmp       | **0.000207s ±0%** |  0.002038s ±5% |           0.001992s ±13% |          0.002025s ±5% |     0.000538s ±0% |     0.000537s ±1% |     0.000559s ±1% |
| setjmp_general  | **0.000212s ±2%** |  0.008692s ±6% |            0.008678s ±5% |          0.008959s ±5% |     0.004752s ±8% |     0.004554s ±3% |    0.003700s ±13% |
| sieve           | **0.006876s ±1%** |  0.153031s ±4% |            0.148363s ±5% |          0.151576s ±4% |     0.007245s ±0% |     0.007146s ±0% |     0.034465s ±0% |
| str_copy        | **0.000721s ±0%** |  0.046886s ±5% |            0.043026s ±6% |          0.046616s ±2% |     0.000867s ±0% |     0.000875s ±0% |     0.004078s ±0% |
| switch_goto     |     0.003574s ±0% |  0.196304s ±2% |            0.198288s ±3% |          0.198367s ±6% |     0.001976s ±0% | **0.001965s ±0%** |     0.002376s ±3% |
| switch_local    | **0.001163s ±0%** |  0.088122s ±6% |            0.090822s ±6% |          0.081834s ±4% |     0.006977s ±0% |    0.006934s ±11% |                n/a |
| va_forward      | **0.000602s ±1%** |  0.127178s ±4% |            0.125351s ±2% |          0.128723s ±4% |     0.008159s ±0% |     0.006725s ±4% |     0.008076s ±0% |
<!-- perf-table:end -->

<!-- perf-method:begin -->
The dasProfile method on AMD FX(tm)-6300 Six-Core Processor (2026-10-23 05:28 UTC; clang version 22.1.8 (https://github.com/llvm/llvm-project ca7933e47d3a3451d81e72ac174dcb5aa28b59d1), daslang 0.6.4) beside borisbat/dasProfile 436d58d2840ff839550d44d32f98e10a15b57bf2 run on AMD FX(tm)-6300 Six-Core (Thu Oct 22 20:55:43 2026; Clang 22.1.8, daslang 0.6.4, LLVM 22.1.5). Seconds per run, median of five samples; a hand-written cell's ratio is over dasProfile's C++, a converted cell's over the C program. dasProfile's hand-written das passes its count as a literal (`fibI(6511134)`, `fibR(31)`, `primes(14000)`) where its C++ and the converted program read a `volatile` one, so a hand-written cell times a program whose count its compiler sees: the JIT unrolls that `fib_loop` and not the converted one (`perf/ARCHITECTURE.md` section 3).

| Test          | C (clang -O3) | dasProfile C++ | hand-written interp |   hand-written JIT |   hand-written AOT |   converted interp |      converted JIT |      converted AOT |      converted exe |
| :------------ | ------------: | -------------: | ------------------: | -----------------: | -----------------: | -----------------: | -----------------: | -----------------: | -----------------: |
| fib_loop      |    0.0019071s |     0.0019058s |  0.060231s (31.60x) | 0.0019058s (1.00x) | 0.0019064s (1.00x) | 0.060066s (31.50x) | 0.0043479s (2.28x) | 0.0019056s (1.00x) | 0.0043726s (2.29x) |
| fib_recursive |    0.0084092s |      0.008433s |   0.072531s (8.60x) | 0.0088441s (1.05x) | 0.0095176s (1.13x) |   0.07364s (8.76x) | 0.0088473s (1.05x) |   0.00883s (1.05x) | 0.0084476s (1.00x) |
| primes        |     0.049574s |      0.049543s |    0.14481s (2.92x) |  0.046757s (0.94x) |   0.02886s (0.58x) |    0.2204s (4.45x) |  0.046791s (0.94x) |  0.031046s (0.63x) |  0.046864s (0.95x) |

- the first table's `fib_loop`, `fib_recursive` and `primes` are this tree's versions of the three (`primes` tests `i < n` in `isprime` and returns `int`, and no kernel function is `noinline`): different programs, not compared
- `fixed_mandel` (16.16 fixed point, 96x96, 48 iterations, struct vectors by value) is not dasProfile's `mandelbrot` (double, 64x64, 255 iterations): different programs, not compared
- `matmul`, `sieve`, `blit` and the construct kernels have no dasProfile twin; dasProfile's `n-bodies`, `spectral norm`, `sha256`, `sort`, `tree`, `queen`, `dictionary`, `exp loop`, `particles kinematics`, `string2float`, `float2string` and `interop host calls` have no kernel here: different programs, not compared
<!-- perf-method:end -->
