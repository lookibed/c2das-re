# Performance details

## Performance

The comparison `docs/very-detailed-plan.md` section 2 asks for. These are microbenchmarks: small
C kernels under `perf/kernels/`, each timed alone, which say how the converted code of one kind of
loop or call runs, not how a program does; the program-level number is Doom's timedemo frame
rate, in the Doom section below.

**Machine.** Every number below is from one machine, the box `PC`: an AMD Ryzen 7 7435HS (Zen 3+,
eight cores) under WSL2, Linux x86_64, the clang 22.1.8 of the libclang archive and the daScript
commit `VERSIONS.md` pins (the captures record daslang 0.6.5; dasProfile's records daslang 0.6.4 and its LLVM 22.1.5), with
no other timing job on it while it runs (the box's `heavy` queue admits one timing job at a time).
One exception, by owner ruling 34: the dasProfile method's hand-written column
(`perf/dasprofile_linux.json`) is the bench box's capture (AMD Ryzen 3 1200, 2026-11-03) and is
re-run only there at a phase end, since `perf/dasprofile.sh` installs a daScript SDK outside this
repository, which box PC does not host; the dasProfile section therefore names the two boxes and
compares nothing across them. Times from another machine do not compare; ratios to native on the same machine do, which is what
the delta against an earlier capture on another CPU uses (`perf/ARCHITECTURE.md` section 5).

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
Captured on 2026-11-09 15:59 UTC, linux x86_64, PC (AMD Ryzen 7 7435HS); clang version 22.1.8 (https://github.com/llvm/llvm-project ca7933e47d3a3451d81e72ac174dcb5aa28b59d1), 0.6.5. A cell is the median of 5 samples, each its own process, ± half the sample range as a share of the median; the fastest lane per row is bold; a cell whose spread is above 20% is `suspect` with its spread, no time, and in no ratio or delta.

| Test            |      C (clang -O3) | DAS interpreter | DAS interp, copied params | DAS interp, while loops | DAS interp, reinterpreted first members | DAS interp, inlined helpers | DAS interp, goto dispatch | DAS interp, checks off | DAS interp, past-end inline |            DAS JIT |            DAS exe |            DAS AOT |
| :-------------- | -----------------: | --------------: | ------------------------: | ----------------------: | --------------------------------------: | --------------------------: | ------------------------: | ---------------------: | --------------------------: | -----------------: | -----------------: | -----------------: |
| bit_pack        | **0.000083s ±0%** |  0.011240s ±1% |            0.011401s ±2% |          0.011586s ±1% |                          0.011344s ±4% |              0.011300s ±2% |            0.011339s ±2% |         0.011057s ±2% |              0.011293s ±5% |     0.000101s ±0% |     0.000097s ±0% |     0.000097s ±1% |
| blit            |     0.000358s ±1% |  0.016290s ±1% |            0.014589s ±1% |          0.016416s ±1% |                          0.016452s ±1% |              0.016382s ±1% |            0.016389s ±2% |         0.015474s ±1% |              0.016269s ±1% | **0.000060s ±1%** |     0.000286s ±1% |     0.000292s ±1% |
| compound_lit    |     0.000186s ±0% |  0.016479s ±1% |            0.017578s ±4% |          0.017213s ±1% |                          0.016265s ±1% |              0.016412s ±1% |            0.016188s ±1% |         0.015567s ±1% |              0.016294s ±1% |     0.000184s ±1% | **0.000177s ±0%** |     0.000187s ±0% |
| do_while_effect | **0.001942s ±0%** |  0.028351s ±2% |            0.029614s ±6% |          0.040024s ±2% |                          0.027614s ±2% |              0.028499s ±2% |            0.028521s ±0% |         0.030047s ±2% |              0.027816s ±2% |     0.001947s ±0% |     0.001943s ±0% |     0.001947s ±0% |
| fib_loop        |     0.001457s ±0% |  0.031644s ±2% |            0.031963s ±3% |          0.061599s ±1% |                          0.031943s ±2% |              0.031138s ±1% |            0.031896s ±2% |         0.031353s ±2% |              0.031178s ±1% |     0.001456s ±0% |     0.001458s ±0% | **0.001454s ±0%** |
| fib_recursive   | **0.002939s ±0%** |  0.024300s ±5% |            0.024693s ±2% |       suspect (±20.1%) |                          0.024407s ±2% |              0.024502s ±1% |            0.024409s ±2% |         0.024331s ±2% |              0.024446s ±1% |     0.002965s ±1% |     0.002948s ±0% |     0.003244s ±0% |
| first_member    | **0.000575s ±1%** |  0.058143s ±0% |            0.058172s ±1% |          0.063585s ±1% |                          0.041376s ±1% |              0.057880s ±1% |            0.058289s ±0% |         0.056701s ±1% |              0.058006s ±1% |     0.000670s ±0% |     0.000664s ±0% |     0.000636s ±0% |
| fixed_mandel    |     0.000270s ±0% |  0.013056s ±5% |            0.013022s ±0% |          0.013841s ±1% |                          0.013065s ±0% |              0.011577s ±1% |           0.013110s ±13% |         0.012300s ±1% |              0.013091s ±1% | **0.000216s ±0%** |     0.000218s ±0% |     0.000254s ±0% |
| matmul          |     0.000220s ±0% |  0.008986s ±0% |            0.008994s ±1% |          0.012121s ±1% |                          0.009035s ±0% |              0.008990s ±0% |            0.008978s ±6% |         0.008529s ±0% |              0.008996s ±0% | **0.000127s ±0%** |     0.000128s ±0% |     0.000352s ±0% |
| primes          |     0.014594s ±0% |  0.064506s ±2% |            0.065376s ±4% |          0.110420s ±0% |                          0.064403s ±2% |              0.064375s ±1% |            0.064445s ±1% |         0.035218s ±1% |              0.065963s ±4% |     0.014624s ±0% |     0.014634s ±0% | **0.007889s ±0%** |
| qsort_cmp       | **0.000089s ±0%** |  0.000865s ±1% |            0.000858s ±1% |          0.000877s ±1% |                          0.000868s ±3% |              0.000861s ±2% |           0.000860s ±13% |         0.000920s ±4% |              0.000857s ±1% |     0.000211s ±0% |     0.000229s ±0% |     0.000212s ±0% |
| setjmp_general  | **0.000108s ±0%** |  0.003647s ±2% |            0.003648s ±2% |          0.003685s ±1% |                          0.003642s ±2% |              0.003651s ±1% |            0.003649s ±1% |         0.003656s ±1% |              0.003658s ±1% |     0.001703s ±2% |     0.001755s ±1% |     0.001651s ±1% |
| sieve           | **0.001759s ±5%** |  0.036637s ±1% |            0.036598s ±0% |          0.036695s ±0% |                          0.036773s ±0% |              0.036610s ±0% |            0.036804s ±1% |         0.035752s ±1% |              0.036661s ±0% |     0.001972s ±1% |     0.001975s ±1% |     0.014373s ±1% |
| str_copy        | **0.000294s ±2%** |  0.017136s ±1% |            0.015762s ±1% |          0.017196s ±1% |                          0.017143s ±0% |              0.017070s ±1% |            0.017038s ±1% |         0.016270s ±1% |              0.017131s ±1% |     0.000311s ±0% |     0.000335s ±0% |     0.001060s ±2% |
| switch_goto     |     0.000941s ±1% |  0.042842s ±0% |            0.043251s ±1% |          0.044091s ±2% |                          0.042854s ±1% |              0.043428s ±1% |            0.025131s ±1% |         0.043082s ±1% |              0.043432s ±2% | **0.000418s ±0%** |     0.000419s ±0% |     0.000782s ±0% |
| switch_local    | **0.000514s ±0%** |  0.025927s ±1% |            0.025899s ±1% |          0.028692s ±2% |                          0.025568s ±0% |              0.025903s ±2% |            0.025675s ±1% |         0.024089s ±1% |              0.025736s ±2% |     0.000515s ±0% |     0.000515s ±0% |     0.000750s ±0% |
| va_forward      | **0.000209s ±0%** |  0.042777s ±2% |            0.041125s ±4% |          0.042610s ±2% |                          0.042520s ±2% |              0.042661s ±1% |            0.042738s ±2% |         0.042771s ±2% |              0.042408s ±2% |    0.003946s ±17% |     0.003327s ±9% |    0.003268s ±10% |
<!-- perf-table:end -->

<!-- perf-method:begin -->
no comparison: PC (AMD Ryzen 7 7435HS) against bench (AMD Ryzen 3 1200 Quad-Core), numbers of two boxes are not compared
<!-- perf-method:end -->

## Doom

PureDOOM's `-timedemo` frame rate on freedoom2.wad, natively and converted, every run held tic for
tic to the reference log (`doom/ARCHITECTURE_RUN.md` section 9). `doom/run.das --run --fps` measures
it into `doom/results_linux.json`; `doom/run.das --readme` renders the table from that file into
the root [README](../README.md#doom).
