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
`scripts/build_c2das_rust.sh` builds the Rust translator lookibed/c2das at its `VERSIONS.md` pin
for the head-to-head under `compare/`.

## Layout

See `ARCHITECTURE.md` for the folder charters: `converter/`, `c_runtime/`, `dasCRuntime/`,
`probes/`, `suites/`, `docs/`, `skills/`, `scripts/`, `lua/`, `doom/`.

## License

The repository is MIT (`LICENSE`), except `doom/`, which is GPL-2: its patch to PureDOOM and its
headless host carry PureDOOM's license. PureDOOM itself (GPL-2) and the WADs are never committed:
`doom/fetch.sh` fetches PureDOOM and freedoom2.wad (BSD) at the pins in `VERSIONS.md`, and
`doom2.wad` is user-supplied.

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
Captured on 2026-11-03 09:17 UTC, linux x86_64, AMD Ryzen 3 1200 Quad-Core Processor; clang version 22.1.8 (https://github.com/llvm/llvm-project ca7933e47d3a3451d81e72ac174dcb5aa28b59d1), 0.6.4. A cell is the median of 5 samples, each its own process, ± half the sample range as a share of the median; the fastest lane per row is bold.

| Test            |      C (clang -O3) | DAS interpreter | DAS interp, copied params | DAS interp, while loops | DAS interp, reinterpreted first members |            DAS JIT |            DAS exe |            DAS AOT |
| :-------------- | -----------------: | --------------: | ------------------------: | ----------------------: | --------------------------------------: | -----------------: | -----------------: | -----------------: |
| bit_pack        |     0.000150s ±0% |  0.033643s ±1% |            0.033429s ±1% |          0.033611s ±1% |                          0.033440s ±1% | **0.000148s ±2%** |     0.000159s ±0% |     0.000164s ±0% |
| blit            | **0.000232s ±1%** |  0.032160s ±0% |            0.029856s ±0% |          0.032056s ±1% |                          0.032250s ±4% |     0.001931s ±0% |     0.002083s ±0% |     0.000233s ±1% |
| compound_lit    | **0.000307s ±0%** |  0.034315s ±2% |            0.033706s ±1% |          0.035346s ±2% |                          0.034142s ±2% |     0.000413s ±0% |     0.000396s ±1% |     0.000318s ±0% |
| do_while_effect | **0.002878s ±0%** |  0.075403s ±1% |            0.075343s ±0% |          0.075574s ±0% |                          0.075607s ±1% |     0.002880s ±3% |     0.002880s ±0% |     0.002886s ±1% |
| fib_loop        | **0.002156s ±0%** |  0.045344s ±0% |            0.045283s ±0% |          0.088309s ±2% |                          0.045331s ±1% |     0.002588s ±0% |     0.002588s ±0% |     0.002157s ±0% |
| fib_recursive   |     0.006362s ±0% |  0.051641s ±0% |            0.051644s ±0% |          0.051614s ±1% |                          0.051621s ±1% |     0.006519s ±0% | **0.006151s ±1%** |     0.006749s ±0% |
| first_member    | **0.001138s ±0%** |  0.135239s ±1% |            0.135507s ±3% |          0.143689s ±0% |                          0.102349s ±0% |     0.001432s ±0% |     0.001547s ±1% |     0.001835s ±1% |
| fixed_mandel    |     0.000414s ±0% |  0.027074s ±0% |            0.027092s ±2% |          0.027058s ±1% |                          0.027054s ±0% |     0.000344s ±0% | **0.000340s ±0%** |     0.000418s ±0% |
| matmul          |     0.000337s ±0% |  0.031166s ±4% |            0.031032s ±1% |          0.031032s ±0% |                          0.030967s ±0% | **0.000199s ±0%** |     0.000331s ±0% |     0.000531s ±3% |
| primes          |     0.052252s ±0% |  0.062408s ±0% |            0.062546s ±2% |          0.102874s ±1% |                          0.062391s ±0% |     0.052507s ±1% |     0.052456s ±2% | **0.016384s ±0%** |
| qsort_cmp       | **0.000161s ±0%** |  0.001645s ±0% |            0.001646s ±0% |          0.001646s ±0% |                          0.001649s ±0% |     0.000423s ±1% |     0.000424s ±0% |     0.000436s ±0% |
| setjmp_general  | **0.000155s ±0%** |  0.006836s ±2% |            0.006812s ±1% |          0.006857s ±1% |                          0.006815s ±2% |     0.004173s ±6% |     0.004281s ±7% |     0.003500s ±1% |
| sieve           | **0.002608s ±2%** |  0.092171s ±5% |            0.092748s ±7% |          0.091830s ±5% |                          0.094974s ±6% |     0.003003s ±0% |     0.003179s ±0% |    0.040181s ±17% |
| str_copy        |     0.000515s ±1% |  0.037570s ±1% |           0.036191s ±14% |          0.037499s ±0% |                          0.037556s ±1% | **0.000511s ±0%** |     0.000516s ±0% |     0.001729s ±0% |
| switch_goto     |     0.003673s ±0% |  0.105842s ±0% |            0.105729s ±2% |          0.104194s ±2% |                          0.105456s ±1% |     0.001581s ±0% | **0.001533s ±1%** |     0.002173s ±0% |
| switch_local    | **0.000765s ±0%** |  0.059477s ±0% |            0.059569s ±0% |          0.059618s ±0% |                          0.059453s ±0% |     0.004853s ±0% |     0.004778s ±5% |                n/a |
| va_forward      | **0.000399s ±0%** |  0.096239s ±3% |            0.090737s ±2% |          0.097180s ±3% |                          0.096524s ±2% |    0.008984s ±29% |    0.004219s ±58% |    0.005142s ±49% |
<!-- perf-table:end -->

<!-- perf-method:begin -->
The dasProfile method on AMD Ryzen 3 1200 Quad-Core Processor (2026-11-03 09:19 UTC; clang version 22.1.8 (https://github.com/llvm/llvm-project ca7933e47d3a3451d81e72ac174dcb5aa28b59d1), daslang 0.6.4) beside borisbat/dasProfile 436d58d2840ff839550d44d32f98e10a15b57bf2 run on AMD Ryzen 3 1200 Quad-Core (Tue Nov  3 11:59:00 2026; Clang 22.1.8, daslang 0.6.4, LLVM 22.1.5). Seconds per run, median of five samples; a hand-written cell's ratio is over dasProfile's C++, a converted cell's over the C program. dasProfile's hand-written das passes its count as a literal (`fibI(6511134)`, `fibR(31)`, `primes(14000)`) where its C++ and the converted program read a `volatile` one, so a hand-written cell times a program whose count its compiler sees: the JIT unrolls that `fib_loop` and not the converted one (`perf/ARCHITECTURE.md` section 3).

| Test          | C (clang -O3) | dasProfile C++ | hand-written interp |   hand-written JIT |   hand-written AOT |   converted interp |      converted JIT |      converted AOT |      converted exe |
| :------------ | ------------: | -------------: | ------------------: | -----------------: | -----------------: | -----------------: | -----------------: | -----------------: | -----------------: |
| fib_loop      |    0.0019707s |     0.0019432s |  0.040912s (21.05x) | 0.0019564s (1.01x) | 0.0019869s (1.02x) | 0.041038s (20.82x) | 0.0023287s (1.18x) |  0.001941s (0.98x) | 0.0023297s (1.18x) |
| fib_recursive |     0.006385s |     0.0063855s |   0.046477s (7.28x) | 0.0061979s (0.97x) | 0.0073895s (1.16x) |  0.046485s (7.28x) | 0.0058767s (0.92x) | 0.0062197s (0.97x) | 0.0055476s (0.87x) |
| primes        |     0.047105s |      0.047025s |   0.056156s (1.19x) |  0.047027s (1.00x) |  0.014731s (0.31x) |   0.09296s (1.97x) |   0.04702s (1.00x) |  0.014733s (0.31x) |   0.04701s (1.00x) |

- the first table's `fib_loop`, `fib_recursive` and `primes` are this tree's versions of the three (`primes` tests `i < n` in `isprime` and returns `int`, and no kernel function is `noinline`): different programs, not compared
- `fixed_mandel` (16.16 fixed point, 96x96, 48 iterations, struct vectors by value) is not dasProfile's `mandelbrot` (double, 64x64, 255 iterations): different programs, not compared
- `matmul`, `sieve`, `blit` and the construct kernels have no dasProfile twin; dasProfile's `n-bodies`, `spectral norm`, `sha256`, `sort`, `tree`, `queen`, `dictionary`, `exp loop`, `particles kinematics`, `string2float`, `float2string` and `interop host calls` have no kernel here: different programs, not compared
<!-- perf-method:end -->

## Head-to-head with the Rust translator

Ledger item P8.1 runs this converter and the Rust translator
[lookibed/c2das](https://github.com/lookibed/c2das) on the same inputs: the three suites, the perf
kernels, Lua and, once P6 exists, PureDOOM, with one runner, oracle, machine and daslang for both
(`compare/ARCHITECTURE.md`). `compare/run.das --readme` regenerates the block below from
`compare/results_linux.json`, and `compare/run.das --report <path>` writes it as a document of
its own.

<!-- compare:begin -->
Rendered from c2das-re's `compare/results_linux.json` alone, never edited by hand. Both translators run on one machine and one daslang, under the same runner and oracle (c2das-re's `compare/ARCHITECTURE.md`).

### Suites

Captured: c_testsuite (Rust `ce4647af2826`, 2026-11-01 02:54 UTC); csmith (Rust `ce4647af2826`, 2026-11-01 03:12 UTC); gcc_torture (Rust `ce4647af2826`, 2026-11-01 03:04 UTC). Ours is the ratchet (c2das-re's `suites/<suite>/expected_pass.txt`); the Rust side runs every id under `--libc std --strict`, the interpreter.

| Suite       |  ids | ours pass (ratchet) | Rust pass | Rust pass of ours | of our skips | of unlisted | Rust refused | Rust compile | Rust timeout | Rust exit | Rust output | Rust native | Rust crash |
| :---------- | ---: | ------------------: | --------: | ----------------: | -----------: | ----------: | -----------: | -----------: | -----------: | --------: | ----------: | ----------: | ---------: |
| c_testsuite |  220 |                 199 |       202 |               194 |            0 |           8 |            4 |           11 |            0 |         2 |           1 |           0 |          0 |
| csmith      |  182 |                 151 |        47 |                42 |            5 |           0 |           88 |           42 |            0 |         5 |           0 |           0 |          0 |
| gcc_torture | 1656 |                1179 |      1197 |              1089 |           41 |          67 |          364 |           52 |            0 |        43 |           0 |           0 |          0 |
| total       | 2058 |                1529 |      1446 |              1325 |           46 |          75 |          456 |          105 |            0 |        50 |           1 |           0 |          0 |

### Speed

Captured 2026-11-01 07:27 UTC on linux x86_64, AMD FX(tm)-6300 Six-Core Processor; clang version 22.1.8 (https://github.com/llvm/llvm-project ca7933e47d3a3451d81e72ac174dcb5aa28b59d1); daslang 0.6.4; Rust `ce4647af2826`; 5 samples a cell. A cell is a lane's time over the native build's (lower is faster); the geomean row covers the kernels where native and both sides stand, their count in parentheses.

| Kernel                   | native (s) | ours interpreter | Rust interpreter |  ours JIT |  Rust JIT |  ours exe |  Rust exe |  ours AOT |  Rust AOT |
| :----------------------- | ---------: | ---------------: | ---------------: | --------: | --------: | --------: | --------: | --------: | --------: |
| bit_pack                 |   0.000213 |           330.27 |           638.52 |      1.06 |      exit |      1.07 |      exit |      1.09 |     45.37 |
| blit                     |   0.000428 |            96.71 |            53.86 |      8.65 |      9.21 |     10.40 |     10.77 |      0.99 |      1.66 |
| compound_lit             |   0.000531 |           111.19 |            94.11 |      1.04 |      1.32 |      1.07 |      1.16 |      1.05 |      2.44 |
| dasprofile/fib_loop      |   0.001905 |            31.44 |           116.98 |      2.28 |      2.29 |      2.29 |      2.29 |      1.00 |      1.00 |
| dasprofile/fib_recursive |   0.008354 |             8.66 |            12.00 |      1.05 |   timeout |      1.01 |   timeout |      1.06 |      1.04 |
| dasprofile/primes        |   0.049542 |             4.44 |             4.44 |      0.94 |      0.96 |      0.94 |      0.94 |      0.63 |      0.58 |
| do_while_effect          |   0.003408 |            22.14 |            18.89 |      1.02 |      1.02 |      1.00 |      1.02 |      0.99 |      1.01 |
| fib_loop                 |   0.001906 |            31.51 |           117.26 |      2.28 |      2.30 |      2.30 |      2.29 |      1.00 |      1.00 |
| fib_recursive            |   0.007529 |             9.94 |            13.46 |      1.17 |   timeout |      1.12 |   timeout |      1.17 |      1.17 |
| fixed_mandel             |   0.000844 |            39.84 |            48.35 |      0.69 |      0.69 |      0.70 |      0.69 |      0.95 |      0.92 |
| matmul                   |   0.000597 |            92.91 |            38.11 |      0.58 |      0.58 |      0.97 |      0.96 |      1.43 |      1.40 |
| primes                   |   0.049269 |             2.73 |             2.85 |      0.95 |      0.95 |      0.95 |      0.95 |      0.63 |      0.59 |
| qsort_cmp                |   0.000210 |             9.26 |          refused |      2.56 |   refused |      2.53 |   refused |      2.65 |   refused |
| setjmp_general           |   0.000211 |            42.96 |          refused |     22.01 |   refused |     21.16 |   refused |     17.59 |   refused |
| sieve                    |   0.006701 |            22.61 |            11.84 |      1.06 |      1.18 |      1.04 |      1.15 |      5.15 |      5.15 |
| str_copy                 |   0.000720 |            65.51 |            55.17 |      1.20 |      1.21 |      1.22 |      1.22 |      5.68 |      5.56 |
| switch_goto              |   0.004559 |            42.01 |            16.87 |      0.43 |      0.29 |      0.43 |      0.29 |      0.51 |      0.85 |
| switch_local             |   0.001164 |            73.51 |            60.15 |      5.96 |      0.98 |      6.15 |      0.99 |   compile |      2.61 |
| va_forward               |   0.000603 |           215.67 |           131.56 |     13.55 |     47.21 |     10.45 |     47.37 |     13.42 |     14.76 |
| geomean (kernels)        |            |       36.08 (17) |       35.92 (17) | 1.61 (14) | 1.55 (14) | 1.66 (14) | 1.60 (14) | 1.37 (16) | 1.92 (16) |

Error cells:

- bit_pack, Rust exe: exited 1: EXCEPTION: array resize to 8388609 elements of 8 bytes each grows past max_unreserved_size (67108864 bytes); reserve the final size first, ensure_c...
- bit_pack, Rust JIT: exited 1: [I] LLVM JIT: DLL cache hit .cache/daslang/_anon_3100298793229362603/0x39ac7f92b83497ee.dll
- dasprofile/fib_recursive, Rust exe: the build or its run took longer than 300 s
- dasprofile/fib_recursive, Rust JIT: a sample took longer than 120 s
- fib_recursive, Rust exe: the build or its run took longer than 300 s
- fib_recursive, Rust JIT: a sample took longer than 120 s
- qsort_cmp, Rust: refused: translation failed: operation=top-level declaration lowering; c_type=Function(CQualTypeId { qualifiers: Qualifiers { is_const: false, is_restrict: false, is_...
- setjmp_general, Rust: refused: translation failed: operation=top-level declaration lowering; c_type=Function(CQualTypeId { qualifiers: Qualifiers { is_const: false, is_restrict: false, is_...
- switch_local, ours AOT: the build exited 1 and left no binary: 1 error generated.

### Readability and size

Captured Rust `b1d012eb5d26`, 2026-11-01 11:19 UTC, over every input both sides translated into daslang that compiles. The Rust lines hold the runtime it writes into every module; ours sits in `c_runtime` and `crt`. The Rust counters count its whole module, runtime included.

| Group       | keys counted | files ours | files Rust | lines ours | lines Rust | Rust runtime | Rust without runtime | Rust / ours | without runtime / ours |
| :---------- | -----------: | ---------: | ---------: | ---------: | ---------: | -----------: | -------------------: | ----------: | ---------------------: |
| c_testsuite |   196 of 196 |        196 |        196 |       5831 |      79899 |        73036 |                 6863 |       13.70 |                   1.18 |
| csmith      |     45 of 45 |         45 |         45 |      48145 |      98408 |        28710 |                69698 |        2.04 |                   1.45 |
| gcc_torture | 1118 of 1118 |       1118 |       1118 |      62188 |     408624 |       330506 |                78118 |        6.57 |                   1.26 |
| perf        |     17 of 17 |         17 |         17 |       1601 |      13899 |        11752 |                 2147 |        8.68 |                   1.34 |
| all         | 1376 of 1376 |       1376 |       1376 |     117765 |     600830 |       444004 |               156826 |        5.10 |                   1.33 |

| Counter (all keys) | ours |   Rust |
| :----------------- | ---: | -----: |
| c_function         | 1310 |      0 |
| goto               |   89 |   2251 |
| label              |   78 |   2317 |
| literal_named      | 3250 |   3600 |
| pointer_arith      |  843 |    606 |
| pointer_index      |  433 |  25466 |
| reinterpret        | 4099 |  29007 |
| unsafe_block       |    0 |    425 |
| unsafe_expr        | 5670 | 102348 |
| while_rangeable    | 1308 |   2170 |

### Functions side by side

#### `perf/fib_loop`: `fibI`

Ours:

```das
def private fib_loop__fibI(n : int) : int {
    var last : int = 1
    var cur : int = 0
    for (i in range(n)) {
        var tmp : int = cur
        cur += last
        last = tmp
    }
    return cur
}
```

Rust:

```das
[export, sideeffects]
def fibI(var n : int) : int {
    var last : int
    var cur : int
    var tmp : int
    last = 1
    cur = 0
    for (i in range(0, n)) {
        tmp = cur
        cur = int(uint(cur) + uint(last))
        last = tmp
    }
    return cur
}
```

#### `perf/fib_loop`: `kernel_run`

Ours:

```das
def private fib_loop__kernel_run {
    fib_loop__result = fib_loop__fibI(c_volatile_load(fib_loop__count))
}
```

Rust:

```das
[export, sideeffects]
def kernel_run() {
    result_0 = fibI(count)
    return
}
```

#### `perf/sieve`: `kernel_run`

Ours:

```das
def private sieve__kernel_run {
    var n : int = c_volatile_load(sieve__limit)
    var i : int
    var k : int
    var count : int = 0
    {
        i = 0
        while (i <= n) {
            sieve__flags[i] = uint8(1)
            i++
        }
    }
    {
        i = 2
        while (i <= n) {
            if (sieve__flags[i] != 0) {
                {
                    k = i + i
                    while (k <= n) {
                        sieve__flags[k] = uint8(0)
                        k += i
                    }
                }
                count++
            }
            i++
        }
    }
    sieve__result = count
}
```

Rust:

```das
[export, sideeffects]
def kernel_run() {
    var n : int
    var i : int
    var k : int
    var count : int
    n = limit
    count = 0
    i = 0
    while (i <= n) {
        flags[i] = 1u8
        i++
    }
    i = 2
    while (i <= n) {
        if (flags[i] != 0x0) {
            k = i + i
            while (k <= n) {
                flags[k] = 0u8
                k += i
            }
            count++
        }
        i++
    }
    result_0 = count
    return
}
```

#### `perf/str_copy`: `copy_text`

Ours:

```das
[c_function]
def private str_copy__copy_text(var d : uint8?; var s : uint8?) : uint {
    var n : uint = uint(0)
    while (true) {
        var _t0 = d
        d = d + 1
        var _t1 = s
        s = s + 1
        deref(_t0) = deref(_t1)
        if (!(deref(_t0) != 0)) {
            break
        }
        n++
    }
    return n
}
```

Rust:

```das
[export, sideeffects]
def copy_text(var d : uint8?; var s : uint8 const?) : uint {
    var n : uint = 0u
    while (true) {
        var c2da_postinc : uint8? = d
        unsafe {  // nolint:STYLE025
            d += 1
        }
        var c2da_postinc_0 : uint8 const? = s
        unsafe {  // nolint:STYLE025
            s += 1
        }
        *c2da_postinc = uint8(*c2da_postinc_0)  // nolint:PERF020
        if (*c2da_postinc == 0x0) {
            break
        }
        n++
    }
    return n
}
```

#### `perf/str_copy`: `work`

Ours:

```das
[c_function]
def private str_copy__work(r : int) : uint {
    var sum : uint = uint(0)
    var k : int
    {
        k = 0
        while (k < r) {
            var i : int = 0
            var v : uint = uint(k)
            while (i < 4096) {
                v = v * 1103515245u + 12345u
                let _t0 = i
                i++
                str_copy__text[_t0] = uint8(uint(1) + (v >> 16u) % uint(255))
                sum += uint(str_copy__text[_t0])
            }
            str_copy__text[i] = uint8(0)
            sum += str_copy__copy_text(addr(str_copy__copy[0]), addr(str_copy__text[0]))
            sum = sum * uint(33) + uint(str_copy__copy[k * 13 & 4095])
            k++
        }
    }
    return sum
}
```

Rust:

```das
[export, sideeffects]
def work(var r : int) : uint {
    var sum : uint
    var i : int
    var v : uint
    sum = 0u
    for (k in range(0, r)) {
        i = 0
        v = uint(k)
        while (i < 4096) {
            v = v * 1103515245u + 12345u
            let c2da_postinc_1 : int = i
            i++
            text[c2da_postinc_1] = uint8(1u + (v >> 16u) % 255u)
            sum += uint(text[c2da_postinc_1])
        }
        text[i] = 0u8
        sum = sum + copy_text(unsafe(addr<uint8?>(copy[0])), unsafe(addr<uint8 const?>(text[0])))
        sum = sum * 33u + uint(copy[k * 13 & 4095])
    }
    return sum
}
```

#### `perf/switch_local`: `step`

Ours:

```das
def private switch_local__step(op : int; x : int) : int {
    let _cond = op & 3
    var v : int
    if (_cond == 0) {
        v = x * 3
        return v + 1
    } elif (_cond == 1) {
        v = x ^ 5
        return v - 2
    } elif (_cond == 2) {
        v = x >> 1
        return v + g
    } else {
        return x + g
    }
    return 0
}
```

Rust:

```das
[export, sideeffects]
def step(var op : int; var x : int) : int {
    var c2da_fresh0 : int
    var v : int
    c2da_fresh0 = op & 3
    if (c2da_fresh0 == 0) {
        v = x * 3
        return v + 1
    } elif (c2da_fresh0 == 1) {
        v = x ^ 5
        return v - 2
    } elif (c2da_fresh0 == 2) {
        v = x >> 1
        return v + g
    } else {
        return x + g
    }
}
```

#### `perf/switch_local`: `kernel_run`

Ours:

```das
def private switch_local__kernel_run {
    var n : int = c_volatile_load(switch_local__rounds)
    var acc : uint = uint(0)
    var i : int
    {
        i = 0
        while (i < n) {
            acc = acc * uint(33) + uint(switch_local__step(i, i & 1023))
            acc ^= uint(switch_local__hidden(i & 255))
            i++
        }
    }
    switch_local__result = int(acc & uint(2147483647))
}
```

Rust:

```das
[export, sideeffects]
def kernel_run() {
    var n : int
    var acc_0 : uint
    n = rounds
    acc_0 = 0u
    for (i in range(0, n)) {
        acc_0 = acc_0 * 33u + uint(step(i, i & 1023))
        acc_0 = acc_0 ^ uint(hidden(i & 255))
    }
    result_0 = int(acc_0 & 0x7fffffffu)
    return
}
```

#### `c_testsuite/00156`: `main`

Ours:

```das
[c_function]
def c_main : int {
    var Count : int
    {
        Count = 1
        while (Count <= 10) {
            printf(reinterpret<uint8?>("%d\n"), Count)
            Count++
        }
    }
    return 0
}
```

Rust:

```das
[export, sideeffects]
def main_0() : int {
    var Count : int = 1
    while (Count <= 10) {
        c2da_std_printf(unsafe(addr<int8 const?>(c2da_str_0[0])), [C2daVaArg(tag = 1, i64 = int64(Count), f64 = 0.0lf, raw = 0x0)])
        Count++
    }
    return 0
}
```

#### `c_testsuite/00205`: `main`

Ours:

```das
[c_function]
def c_main : int {
    var i : int
    var j : int
    {
        j = 0
        while (uint64(j) < uint64(typeinfo sizeof(type<PT[9]>)) / uint64(typeinfo sizeof(type<PT>))) {
            {
                i = 0
                while (uint64(i) < uint64(typeinfo sizeof(type<int64[4]>)) / uint64(typeinfo sizeof(type<int64>))) {
                    printf(reinterpret<uint8?>("cases[%d].c[%d]=%ld\n"), j, i, cases[j].c[i])
                    i++
                }
            }
            printf(reinterpret<uint8?>("cases[%d].b=%ld\n"), j, cases[j].b)
            printf(reinterpret<uint8?>("cases[%d].e=%ld\n"), j, cases[j].e)
            printf(reinterpret<uint8?>("cases[%d].k=%ld\n"), j, cases[j].k)
            printf(reinterpret<uint8?>("\n"))
            j++
        }
    }
    return 0
}
```

Rust:

```das
[export, sideeffects]
def main_0() : int {
    var i : int
    var j : int = 0
    while (uint64(j) < 504ul / 56ul) {
        i = 0
        while (uint64(i) < 32ul / 8ul) {
            c2da_std_printf(unsafe(addr<int8 const?>(c2da_str_0[0])), [C2daVaArg(tag = 1, i64 = int64(j), f64 = 0.0lf, raw = 0x0), C2daVaArg(tag = 1, i64 = int64(i), f64 = 0.0lf, raw = 0x0), C2daVaArg(tag = 1, i64 = unsafe(unsafe(addr(cases[j].c[0]))[i]), f64 = 0.0lf, raw = 0x0)])
            i++
        }
        c2da_std_printf(unsafe(addr<int8 const?>(c2da_str_1[0])), [C2daVaArg(tag = 1, i64 = int64(j), f64 = 0.0lf, raw = 0x0), C2daVaArg(tag = 1, i64 = cases[j].b, f64 = 0.0lf, raw = 0x0)])
        c2da_std_printf(unsafe(addr<int8 const?>(c2da_str_2[0])), [C2daVaArg(tag = 1, i64 = int64(j), f64 = 0.0lf, raw = 0x0), C2daVaArg(tag = 1, i64 = cases[j].e, f64 = 0.0lf, raw = 0x0)])
        c2da_std_printf(unsafe(addr<int8 const?>(c2da_str_3[0])), [C2daVaArg(tag = 1, i64 = int64(j), f64 = 0.0lf, raw = 0x0), C2daVaArg(tag = 1, i64 = cases[j].k, f64 = 0.0lf, raw = 0x0)])
        c2da_std_printf(unsafe(addr<int8 const?>(c2da_str_4[0])), [])
        j++
    }
    return 0
}
```


### Lua and Doom

Lua: the Rust translator refuses `lua` (33 units, `--libc std`): `unsupported external call: ldexp`, so the Rust side has no Lua speed or output to compare. The C library functions it calls that the Rust translator lowers in no mode (20): `__ctype_b_loc`, `clock`, `difftime`, `freopen`, `frexp`, `gmtime`, `ldexp`, `localeconv`, `localtime`, `log2`, `mktime`, `setlocale`, `signal`, `strcoll`, `strftime`, `strpbrk`, `strspn`, `time`, `tmpfile`, `tmpnam`. Our Lua numbers are in the ports repository (lookibed/c2das-ports); whether to write host modules for the gap waits on a ruling (c2das-re's `docs/rulings-pending.md`, P8.1).

Doom: pending (P6).

### Real projects

Each project of the Rust repository's `tests/manual` on its own fixture, checked against the `expected.stdout` of its canonical case in the Rust repository's `tests/canonical/cases.json`; the native build (the pinned clang with the README's flags) must print it too. Captured: binjgb (Rust `b1d012eb5d26`, 2026-11-03 00:18 UTC, 4 GiB address-space cap); doomgeneric (Rust `b1d012eb5d26`, 2026-11-03 00:41 UTC, 4 GiB address-space cap); h264bsd-mp4 (Rust `b1d012eb5d26`, 2026-11-03 00:23 UTC, 4 GiB address-space cap); plmpeg-stream (Rust `b1d012eb5d26`, 2026-11-03 00:22 UTC, 4 GiB address-space cap); quakegeneric (Rust `b1d012eb5d26`, 2026-11-03 00:33 UTC, 4 GiB address-space cap); wasm3 (Rust `b1d012eb5d26`, 2026-11-03 00:39 UTC, 4 GiB address-space cap).

| Project       | Side | Native | interpreter |     JIT |     exe |     AOT |
| :------------ | :--- | :----- | ----------: | ------: | ------: | ------: |
| binjgb        | Ours | pass   |        pass |    pass |    pass | compile |
| binjgb        | Rust | pass   |        pass |    pass |    pass |    pass |
| doomgeneric   | Ours | pass   |     refused | refused | refused | refused |
| doomgeneric   | Rust | pass   |        pass |    pass |    pass | timeout |
| h264bsd-mp4   | Ours | pass   |     refused | refused | refused | refused |
| h264bsd-mp4   | Rust | pass   |        pass |    pass |    pass |    pass |
| plmpeg-stream | Ours | pass   |        pass |    pass |    pass |    pass |
| plmpeg-stream | Rust | pass   |        pass |    pass |    pass |    pass |
| quakegeneric  | Ours | pass   |     refused | refused | refused | refused |
| quakegeneric  | Rust | pass   |        pass |  output |    pass |    pass |
| wasm3         | Ours | pass   |     refused | refused | refused | refused |
| wasm3         | Rust | pass   |        pass |    pass |    pass |    pass |

Defines of our side's sidecar alone (the Rust side and the native build do not get them):

- plmpeg-stream, Ours: `-Dc2da_rt_reset(...)=`

Why a lane does not pass:

- binjgb, Ours, AOT: compile: aot build: the build exited 1 and left no binary: compare/work/projects/binjgb/ours_run/aot/ctx/binjgb_all.das.cpp:8637:9: error: cannot jump from t...
- doomgeneric, Ours, interpreter JIT exe AOT: refused: dumper: /root/c2das/tests/manual/doomgeneric/upstream/doomgeneric/doomgeneric/d_main.c:1336:13: a block-scope `extern` declaration of `forwardmove` ...
- doomgeneric, Rust, AOT: timeout: the build or its run took longer than 300 s
- h264bsd-mp4, Ours, interpreter JIT exe AOT: refused: dumper: /root/c2das/tests/manual/h264bsd-mp4/src/../upstream/h264bsd/src/h264bsd_deblocking.c:669:21: a reference to `h264bsdClip` before a definiti...
- quakegeneric, Ours, interpreter JIT exe AOT: refused: dumper: /root/c2das/tests/manual/quakegeneric/upstream/quakegeneric/source/console.c:520:14: a block-scope `extern` declaration of `chat_buffer` wit...
- quakegeneric, Rust, JIT: output: line 1: got `[W] LLVM JIT: return inside try/recover leaves the try arm, not the function. at compare/work/projects/quakegeneric/rust/host.das.inc:66...
- wasm3, Ours, interpreter JIT exe AOT: refused: dumper: /root/c2das/tests/manual/wasm3/upstream/wasm3/source/m3_exec_defs.h:55:29: unsupported type spelling `vectorcall m3ret_t`

The bench entry's timed loop (`decode_us`), a lane's median over the native build's (lower is faster), not measured in this capture (`--samples 0`):

| Project       | Side | Native compiler      |     Native s |  interpreter |          JIT |          exe |          AOT |
| :------------ | :--- | :------------------- | -----------: | -----------: | -----------: | -----------: | -----------: |
| binjgb        | Ours | clang version 22.1.8 | not measured | not measured | not measured | not measured | not measured |
| binjgb        | Rust | clang version 22.1.8 | not measured | not measured | not measured | not measured | not measured |
| doomgeneric   | Ours | clang version 22.1.8 | not measured | not measured | not measured | not measured | not measured |
| doomgeneric   | Rust | clang version 22.1.8 | not measured | not measured | not measured | not measured | not measured |
| h264bsd-mp4   | Ours | clang version 22.1.8 | not measured | not measured | not measured | not measured | not measured |
| h264bsd-mp4   | Rust | clang version 22.1.8 | not measured | not measured | not measured | not measured | not measured |
| plmpeg-stream | Ours | clang version 22.1.8 | not measured | not measured | not measured | not measured | not measured |
| plmpeg-stream | Rust | clang version 22.1.8 | not measured | not measured | not measured | not measured | not measured |
| quakegeneric  | Ours | clang version 22.1.8 | not measured | not measured | not measured | not measured | not measured |
| quakegeneric  | Rust | clang version 22.1.8 | not measured | not measured | not measured | not measured | not measured |
| wasm3         | Ours | clang version 22.1.8 | not measured | not measured | not measured | not measured | not measured |
| wasm3         | Rust | clang version 22.1.8 | not measured | not measured | not measured | not measured | not measured |

The code of each side's module (the Rust runtime is its `c2da_rt_` and `c2da_std_` declarations):

| Project       | Side | Code    | Files | Lines | Runtime lines | c_function | goto | label | literal_named | pointer_arith | pointer_index | reinterpret | unsafe_block | unsafe_expr | while_rangeable |
| :------------ | :--- | :------ | ----: | ----: | ------------: | ---------: | ---: | ----: | ------------: | ------------: | ------------: | ----------: | -----------: | ----------: | --------------: |
| binjgb        | Ours | ok      |     1 |  8260 |             0 |        110 |   38 |    19 |          1778 |            88 |            43 |         295 |            0 |         119 |              23 |
| binjgb        | Rust | ok      |     1 | 11481 |           956 |          0 |  670 |   867 |          2393 |            33 |           939 |        3818 |            8 |        5049 |              12 |
| doomgeneric   | Ours | refused |     - |     - |             - |          - |    - |     - |             - |             - |             - |           - |            - |           - |               - |
| doomgeneric   | Rust | ok      |     1 | 37045 |          1579 |          0 |  435 |   612 |         43595 |           523 |          3454 |       10418 |          260 |       15426 |             169 |
| h264bsd-mp4   | Ours | refused |     - |     - |             - |          - |    - |     - |             - |             - |             - |           - |            - |           - |               - |
| h264bsd-mp4   | Rust | ok      |     1 | 24316 |           822 |          0 |  362 |   309 |          7164 |          1738 |          2701 |        5172 |         1208 |        8557 |              73 |
| plmpeg-stream | Ours | ok      |     1 |  3618 |             0 |         64 |    0 |     0 |          2062 |            11 |           387 |          66 |            0 |           6 |               6 |
| plmpeg-stream | Rust | ok      |     1 |  4988 |           822 |          0 |    0 |     0 |          1891 |            10 |           587 |         505 |            0 |        1259 |              11 |
| quakegeneric  | Ours | refused |     - |     - |             - |          - |    - |     - |             - |             - |             - |           - |            - |           - |               - |
| quakegeneric  | Rust | ok      |    72 | 59613 |          1781 |          0 |  461 |   578 |          2275 |           745 |          5761 |       10506 |          219 |       20287 |             203 |
| wasm3         | Ours | refused |     - |     - |             - |          - |    - |     - |             - |             - |             - |           - |            - |           - |               - |
| wasm3         | Rust | ok      |     1 | 25827 |          1009 |          0 | 2393 |  2162 |          1827 |          2074 |           430 |        4550 |          814 |        6589 |              24 |

#### `binjgb`: `emulator_step_internal`

Ours:

```das
def private binjgb_all__emulator_step_internal(var e : Emulator?) {
    if (e.state.hdma.state == DmaState.DMA_INACTIVE) {
        if (int(Bool.FALSE) != 0) {
            return
        }
        binjgb_all__execute_instruction(e)
    } else {
        binjgb_all__tick(e)
        binjgb_all__hdma_copy_byte(e)
        binjgb_all__hdma_copy_byte(e)
    }
}
```

Rust:

```das
[sideeffects]
def emulator_step_internal(var e_114 : Emulator?) {
    if (uint(e_114.state.hdma.state) == 0u) {
        if (0 != 0) {
            return
        }
        execute_instruction(e_114)
    } else {
        tick(e_114)
        hdma_copy_byte(e_114)
        hdma_copy_byte(e_114)
    }
    return
}
```

#### `binjgb`: `ppu_mode3_synchronize`

Ours:

```das
[c_function]
def private binjgb_all__ppu_mode3_synchronize(var e : Emulator?) {
    var x : uint8 = e.state.ppu.render_x
    var y : uint8 = e.state.ppu.line_y
    if (e.state.ppu.stat.mode != PPUMode.PPU_MODE_MODE3 || int(x) >= SCREEN_WIDTH) {
        return
    }
    var display_bg : Bool = enum_from_int(type<Bool>, (uint(int(e.state.is_cgb)) != 0 || uint(int(e.state.ppu.lcdc.bg_display)) != 0) && !(int(e.config.disable_bg) != 0) ? 1 : 0)
    var display_obj : Bool = enum_from_int(type<Bool>, uint(int(e.state.ppu.lcdc.obj_display)) != 0 && !(int(e.config.disable_obj) != 0) ? 1 : 0)
    var rendering_window : Bool = e.state.ppu.rendering_window
    var window_counter : int = uint(int(rendering_window)) != 0 ? 0 : 255
    if (!(int(rendering_window) != 0) && uint(int(e.state.ppu.lcdc.window_display)) != 0 && !(int(e.config.disable_window) != 0) && int(e.state.ppu.wx) <= WINDOW_MAX_X && int(y) >= int(e.state.ppu.wy)) {
        window_counter = 0 > int(e.state.ppu.wx) - (int(x) + 7) ? 0 : int(e.state.ppu.wx) - (int(x) + 7)
    }
    var data_select : TileDataSelect = e.state.ppu.lcdc.bg_tile_data_select
    var mx : uint8 = uint8(int(e.state.ppu.scx) + int(x))
    var my : uint8 = uint8(int(e.state.ppu.scy) + int(y))
    var map_base : uint16 = uint16(int(binjgb_all__map_select_to_address(e.state.ppu.lcdc.bg_tile_map_select)) | (int(my) >> 3) * TILE_MAP_WIDTH)
    var pixel : uint?
    if (e.state.sgb.mask != SgbMask.SGB_MASK_CANCEL) {
        pixel = addr(ppu_mode3_synchronize_s_dummy_frame_buffer_line[0])
    } else {
        pixel = addr(e.frame_buffer[0]) + end_index(int(y) * SCREEN_WIDTH + int(x), 23040)
    }
    // Cache map_addr info.
    var map_addr : uint16 = uint16(0)
    var pal : PaletteRGBA? = null
    var lo : uint8 = uint8(0)
    var hi : uint8 = uint8(0)
    var priority : Bool = Bool.FALSE
    var i : int
    {
        while (e.state.ppu.mode3_render_ticks < e.state.ticks && int(x) < SCREEN_WIDTH) {
            var bg_is_zero : Bool[4] = fixed_array(Bool.TRUE, Bool.TRUE, Bool.TRUE, Bool.TRUE)
            var bg_priority : Bool[4] = fixed_array(Bool.FALSE, Bool.FALSE, Bool.FALSE, Bool.FALSE)
            {
                i = 0
                while (i < 4) {
                    let _t0 = window_counter
                    window_counter--
                    if (!!(_t0 == 0)) {
                        display_bg = Bool.TRUE
                        rendering_window = display_bg
                        e.state.ppu.rendering_window = rendering_window
                        mx = uint8(int(x) + i + WINDOW_X_OFFSET - int(e.state.ppu.wx))
                        my = e.state.ppu.win_y
                        map_base = uint16(int(binjgb_all__map_select_to_address(e.state.ppu.lcdc.window_tile_map_select)) | (int(my) >> 3) * TILE_MAP_WIDTH)
                        map_addr = uint16(0)
                    }
                    if (int(display_bg) != 0) {
                        var new_map_addr : uint16 = uint16(int(map_base) | int(mx) >> 3)
                        if (int(map_addr) == int(new_map_addr)) {
                            lo = uint8(uint(lo) << 1u)
                            hi = uint8(uint(hi) << 1u)
                        } else {
                            map_addr = new_map_addr
                            var tile_index : uint16 = uint16(e.state.vram.data[int(map_addr)])
                            var my7 : uint8 = uint8(int(my) & 7)
                            if (data_select == TileDataSelect.TILE_DATA_8800_97FF) {
                                tile_index = uint16(256 + int(int8(tile_index)))
                            }
                            if (int(e.state.is_cgb) != 0) {
                                var attr : uint8 = e.state.vram.data[8192 + int(map_addr)]
                                pal = addr(e.state.ppu.bgcp.palettes[0]) + end_index(int(attr) & 7, 8)
                                if ((int(attr) & 8) != 0) {
                                    tile_index = uint16(int(tile_index) + 512)
                                }
                                if ((int(attr) & 64) != 0) {
                                    my7 = uint8(7 - int(my7))
                                }
                                priority = enum_from_int(type<Bool>, (int(attr) & 128) != 0 ? 1 : 0)
                                var tile_addr : uint16 = uint16((int(tile_index) * TILE_HEIGHT + int(my7)) * TILE_ROW_BYTES)
                                lo = e.state.vram.data[int(tile_addr)]
                                hi = e.state.vram.data[int(tile_addr) + 1]
                                if ((int(attr) & 32) != 0) {
                                    lo = binjgb_all__reverse_bits_u8(lo)
                                    hi = binjgb_all__reverse_bits_u8(hi)
                                }
                            } else {
                                if (int(e.state.is_sgb) != 0) {
                                    var idx : int = (int(y) >> 3) * (SCREEN_WIDTH >> 3) + (int(x) >> 3)
                                    var palidx : uint8 = uint8(int(e.state.sgb.attr_map[idx >> 2]) >> 2 * (3 - (idx & 3)) & 3)
                                    pal = addr(e.sgb_pal[0]) + end_index(int(palidx), 4)
                                } else {
                                    pal = addr(e.pal[0]) + end_index(int(PaletteType.PALETTE_TYPE_BGP), 3)
                                }
                                priority = Bool.FALSE
                                var tile_addr : uint16 = uint16((int(tile_index) * TILE_HEIGHT + int(my7)) * TILE_ROW_BYTES)
                                lo = e.state.vram.data[int(tile_addr)]
                                hi = e.state.vram.data[int(tile_addr) + 1]
                            }
                            var shift : uint8 = uint8(int(mx) & 7)
                            lo = uint8(uint(lo) << uint(int(shift)))
                            hi = uint8(uint(hi) << uint(int(shift)))
                        }
                        var palette_index : uint8 = uint8(int(hi) >> 6 & 2 | int(lo) >> 7)
                        deref(pixel + i) = pal.color[int(palette_index)]
                        bg_is_zero[i] = enum_from_int(type<Bool>, int(palette_index) == 0 ? 1 : 0)
                        bg_priority[i] = priority
                    } else {
                        if (int(e.state.is_cgb) != 0) {
                            deref(pixel + i) = e.state.ppu.bgcp.palettes[0].color[0]
                        } elif (int(e.state.is_sgb) != 0) {
                            deref(pixel + i) = e.sgb_pal[0].color[0]
                        } else {
                            deref(pixel + i) = e.color_to_rgba[0].color[0]
                        }
                    }
                    i++
                    mx = uint8(uint(mx) + 1)
                }
            }
            // LCDC bit 0 works differently on cgb; when it's cleared OBJ will always
            // have priority over bg and window.
            if (uint(int(e.state.is_cgb)) != 0 && !(int(e.state.ppu.lcdc.bg_display) != 0)) {
                crt::memset(reinterpret<void?>(addr(bg_is_zero)), int(Bool.TRUE), uint64(typeinfo sizeof(type<Bool[4]>)))
                crt::memset(reinterpret<void?>(addr(bg_priority)), int(Bool.FALSE), uint64(typeinfo sizeof(type<Bool[4]>)))
            }
            if (int(display_obj) != 0) {
                var obj_height : uint8 = binjgb_all__s_obj_size_to_height[int(e.state.ppu.lcdc.obj_size)]
                var n : int
                {
                    n = int(e.state.ppu.line_obj_count) - 1
                    while (n >= 0) {
                        {
                            var o : Obj? = addr(e.state.ppu.line_obj[0]) + end_index(n, 10)
                            // Does [x, x + 4) intersect [o->x, o->x + 8)? Note that the sums must
                            // wrap at 256 (i.e. arithmetic is 8-bit).
                            var ox_start : int8 = int8(int(o.x) - int(x))
                            // ox_end is inclusive.
                            var ox_end : int8 = int8(int(ox_start) + 7)
                            var oy : uint8 = uint8(int(y) - int(o.y))
                            if (int(uint8(ox_start)) >= 4 && int(uint8(ox_end)) >= 8 || int(oy) >= int(obj_height)) {
                                continue
                            }
                            if (int(o.yflip) != 0) {
                                oy = uint8(int(obj_height) - 1 - int(oy))
                            }
                            var tile_index : uint16 = uint16(o.tile)
                            if (int(obj_height) == 16) {
                                if (int(oy) < 8) {
                                    // Top tile of 8x16 sprite.
                                    tile_index = uint16(int(tile_index) & 254)
                                } else {
                                    // Bottom tile of 8x16 sprite.
                                    tile_index = uint16(int(tile_index) | 1)
                                    oy = uint8(int(oy) - 8)
                                }
                            }
                            var pal1 : PaletteRGBA? = null
                            if (int(e.state.is_cgb) != 0) {
                                pal1 = addr(e.state.ppu.obcp.palettes[0]) + end_index(int(o.cgb_palette) & 7, 8)
                                if (o.bank != 0) {
                                    tile_index = uint16(int(tile_index) + 512)
                                }
                            } else {
                                pal1 = addr(e.pal[0]) + end_index(int(o.palette) + 1, 3)
                            }
                            var tile_addr : uint16 = uint16((int(tile_index) * TILE_HEIGHT + (int(oy) & 7)) * TILE_ROW_BYTES)
                            var lo1 : uint8 = e.state.vram.data[int(tile_addr)]
                            var hi1 : uint8 = e.state.vram.data[int(tile_addr) + 1]
                            if (!(int(o.xflip) != 0)) {
                                lo1 = binjgb_all__reverse_bits_u8(lo1)
                                hi1 = binjgb_all__reverse_bits_u8(hi1)
                            }
                            var tile_data_offset : int = 0 > -int(ox_start) ? 0 : -int(ox_start)
                            lo1 = uint8(uint(lo1) >> uint(tile_data_offset))
                            hi1 = uint8(uint(hi1) >> uint(tile_data_offset))
                            var start : int = 0 > int(ox_start) ? 0 : int(ox_start)
                            // end is inclusive.
                            var end : int = 3 < int(ox_end) ? 3 : int(ox_end)
                            {
                                i = start
                                while (i <= end) {
                                    var palette_index : uint8 = uint8((int(hi1) & 1) << 1 | int(lo1) & 1)
                                    if (int(palette_index) != 0 && (!(int(bg_priority[i]) != 0) || uint(int(bg_is_zero[i])) != 0) && (o.priority == ObjPriority.OBJ_PRIORITY_ABOVE_BG || uint(int(bg_is_zero[i])) != 0)) {
                                        deref(pixel + i) = pal1.color[int(palette_index)]
                                    }
                                    i++
                                    lo1 = uint8(uint(lo1) >> 1u)
                                    hi1 = uint8(uint(hi1) >> 1u)
                                }
                            }
                        } finally {
                            n--
                        }
                    }
                }
            }
            e.state.ppu.mode3_render_ticks += uint64(CPU_TICK)
            pixel = pixel + 4
            x = uint8(int(x) + 4)
        }
    }
    e.state.ppu.render_x = x
}
```

Rust:

```das
[sideeffects]
def ppu_mode3_synchronize(var e_10 : Emulator?) {
    var x_2 : uint8
    var y : uint8
    var display_bg : Bool = Bool()
    var display_obj : Bool = Bool()
    var rendering_window : Bool = Bool()
    var window_counter : int
    var data_select : TileDataSelect = TileDataSelect()
    var mx : uint8
    var my : uint8
    var map_base : uint16
    var pixel : uint?
    var map_addr : uint16
    var pal_1 : PaletteRGBA?
    var lo : uint8
    var hi : uint8
    var priority : Bool = Bool()
    var i_3 : int
    var bg_is_zero : Bool[4] = fixed_array<Bool>(Bool(), Bool(), Bool(), Bool())
    var bg_priority : Bool[4] = fixed_array<Bool>(Bool(), Bool(), Bool(), Bool())
    var new_map_addr : uint16
    var tile_index : uint16
    var my7 : uint8
    var attr : uint8
    var tile_addr : uint16
    var idx : int
    var palidx : uint8
    var tile_addr_0 : uint16
    var shift : uint8
    var palette_index_0 : uint8
    var obj_height : uint8
    var n : int
    var o : Obj?
    var ox_start : int8
    var ox_end : int8
    var oy : uint8
    var tile_index_0 : uint16
    var pal_2 : PaletteRGBA?
    var tile_addr_1 : uint16
    var lo_0 : uint8
    var hi_0 : uint8
    var tile_data_offset : int
    var start : int
    var end : int
    var palette_index_1 : uint8
    x_2 = e_10.state.ppu.render_x
    y = e_10.state.ppu.line_y
    if (uint(e_10.state.ppu.stat.mode) != 3u || int(x_2) >= 160) {
        return
    }
    display_bg = unsafe(reinterpret<Bool>(uint((uint(e_10.state.is_cgb) != 0x0 || uint(e_10.state.ppu.lcdc.bg_display) != 0x0) && uint(e_10.config.disable_bg) == 0u ? 1 : 0)))
    display_obj = unsafe(reinterpret<Bool>(uint(uint(e_10.state.ppu.lcdc.obj_display) != 0x0 && uint(e_10.config.disable_obj) == 0u ? 1 : 0)))
    rendering_window = e_10.state.ppu.rendering_window
    window_counter = uint(rendering_window) != 0x0 ? 0 : 255
    if (uint(rendering_window) == 0u && uint(e_10.state.ppu.lcdc.window_display) != 0x0 && uint(e_10.config.disable_window) == 0u && int(e_10.state.ppu.wx) <= 166 && int(y) >= int(e_10.state.ppu.wy)) {
        window_counter = 0 > int(e_10.state.ppu.wx) - (int(x_2) + 7) ? 0 : int(e_10.state.ppu.wx) - (int(x_2) + 7)
    }
    data_select = e_10.state.ppu.lcdc.bg_tile_data_select
    mx = uint8(int(e_10.state.ppu.scx) + int(x_2))
    my = uint8(int(e_10.state.ppu.scy) + int(y))
    var c2da_fresh46 : TileMapSelect = e_10.state.ppu.lcdc.bg_tile_map_select
    map_base = uint16(int(uint16(uint(c2da_fresh46) == 0u ? 6144 : 7168)) | (int(my) >> 3) * 32)
    if (uint(e_10.state.sgb.mask) != 0u) {
        pixel = unsafe(addr<uint?>(ppu_mode3_synchronize__s_dummy_frame_buffer_line[0]))
    } else {
        var c2da_fresh47 : uint? = unsafe(reinterpret<uint?>(unsafe(reinterpret<uint64>(e_10)) + 212000ul))
        pixel = unsafe(addr<uint?>(unsafe(unsafe(reinterpret<uint?>(c2da_fresh47))[int(y) * 160 + int(x_2)])))
    }
    map_addr = uint16(0)
    pal_1 = null
    lo = 0u8
    hi = 0u8
    priority = unsafe(reinterpret<Bool>(0u))
    var c2da_pixel_addr : uint64 = unsafe(reinterpret<uint64>(pixel))
    while (e_10.state.ppu.mode3_render_ticks < e_10.state.ticks && int(x_2) < 160) {
        bg_is_zero = fixed_array<Bool>(unsafe(reinterpret<Bool>(1u)), unsafe(reinterpret<Bool>(1u)), unsafe(reinterpret<Bool>(1u)), unsafe(reinterpret<Bool>(1u)))
        bg_priority = fixed_array<Bool>(unsafe(reinterpret<Bool>(0u)), unsafe(reinterpret<Bool>(0u)), unsafe(reinterpret<Bool>(0u)), unsafe(reinterpret<Bool>(0u)))
        i_3 = 0
        while (i_3 < 4) {
            let c2da_postinc : int = window_counter
            window_counter--
            if ((!(!(c2da_postinc == 0)) ? 1l : 0l) != 0) {
                display_bg = unsafe(reinterpret<Bool>(1u))
                rendering_window = display_bg
                e_10.state.ppu.rendering_window = rendering_window
                mx = uint8(int(x_2) + i_3 + 7 - int(e_10.state.ppu.wx))
                my = e_10.state.ppu.win_y
                var c2da_fresh48 : TileMapSelect = e_10.state.ppu.lcdc.window_tile_map_select
                map_base = uint16(int(uint16(uint(c2da_fresh48) == 0u ? 6144 : 7168)) | (int(my) >> 3) * 32)
                map_addr = uint16(0)
            }
            if (uint(display_bg) != 0u) {
                new_map_addr = uint16(int(map_base) | int(mx) >> 3)
                if (int(map_addr) == int(new_map_addr)) {
                    lo = uint8(int(lo) << 1)
                    hi = uint8(int(hi) << 1)
                } else {
                    map_addr = new_map_addr
                    var c2da_fresh49 : uint8? = unsafe(reinterpret<uint8?>(unsafe(reinterpret<uint64>(e_10)) + 12484ul))
                    tile_index = uint16(unsafe(unsafe(reinterpret<uint8?>(c2da_fresh49))[int(map_addr)]))
                    my7 = uint8(int(my) & 7)
                    if (uint(data_select) == 0u) {
                        tile_index = uint16(256 + int(int8(tile_index)))
                    }
                    if (uint(e_10.state.is_cgb) != 0u) {
                        var c2da_fresh50 : uint8? = unsafe(reinterpret<uint8?>(unsafe(reinterpret<uint64>(e_10)) + 12484ul))
                        attr = unsafe(unsafe(reinterpret<uint8?>(c2da_fresh50))[8192 + int(map_addr)])
                        var c2da_fresh51 : PaletteRGBA? = unsafe(reinterpret<PaletteRGBA?>(unsafe(reinterpret<uint64>(e_10)) + 211140ul))
                        pal_1 = unsafe(addr<PaletteRGBA?>(unsafe(unsafe(reinterpret<PaletteRGBA?>(c2da_fresh51))[int(attr) & 7])))
                        if ((int(attr) & 8) != 0) {
                            tile_index = uint16(int(tile_index) + 512)
                        }
                        if ((int(attr) & 64) != 0) {
                            my7 = uint8(7 - int(my7))
                        }
                        priority = unsafe(reinterpret<Bool>(uint((int(attr) & 128) != 0 ? 1 : 0)))
                        tile_addr = uint16((int(tile_index) * 8 + int(my7)) * 2)
                        var c2da_fresh52 : uint8? = unsafe(reinterpret<uint8?>(unsafe(reinterpret<uint64>(e_10)) + 12484ul))
                        lo = unsafe(unsafe(reinterpret<uint8?>(c2da_fresh52))[int(tile_addr)])
                        var c2da_fresh53 : uint8? = unsafe(reinterpret<uint8?>(unsafe(reinterpret<uint64>(e_10)) + 12484ul))
                        hi = unsafe(unsafe(reinterpret<uint8?>(c2da_fresh53))[int(tile_addr) + 1])
                        if ((int(attr) & 32) != 0) {
                            lo = reverse_bits_u8(lo)
                            hi = reverse_bits_u8(hi)
                        }
                    } else {
                        if (uint(e_10.state.is_sgb) != 0u) {
                            idx = (int(y) >> 3) * (160 >> 3) + (int(x_2) >> 3)
                            var c2da_fresh54 : uint8? = unsafe(reinterpret<uint8?>(unsafe(reinterpret<uint64>(e_10)) + 209930ul))
                            palidx = uint8(int(unsafe(unsafe(reinterpret<uint8?>(c2da_fresh54))[idx >> 2])) >> 2 * (3 - (idx & 3)) & 3)
                            var c2da_fresh55 : PaletteRGBA? = unsafe(reinterpret<PaletteRGBA?>(unsafe(reinterpret<uint64>(e_10)) + 533688ul))
                            pal_1 = unsafe(addr<PaletteRGBA?>(unsafe(unsafe(reinterpret<PaletteRGBA?>(c2da_fresh55))[int(palidx)])))
                        } else {
                            var c2da_fresh56 : PaletteRGBA? = unsafe(reinterpret<PaletteRGBA?>(unsafe(reinterpret<uint64>(e_10)) + 533640ul))
                            pal_1 = unsafe(addr<PaletteRGBA?>(unsafe(unsafe(reinterpret<PaletteRGBA?>(c2da_fresh56))[0])))
                        }
                        priority = unsafe(reinterpret<Bool>(0u))
                        tile_addr_0 = uint16((int(tile_index) * 8 + int(my7)) * 2)
                        var c2da_fresh57 : uint8? = unsafe(reinterpret<uint8?>(unsafe(reinterpret<uint64>(e_10)) + 12484ul))
                        lo = unsafe(unsafe(reinterpret<uint8?>(c2da_fresh57))[int(tile_addr_0)])
                        var c2da_fresh58 : uint8? = unsafe(reinterpret<uint8?>(unsafe(reinterpret<uint64>(e_10)) + 12484ul))
                        hi = unsafe(unsafe(reinterpret<uint8?>(c2da_fresh58))[int(tile_addr_0) + 1])
                    }
                    shift = uint8(int(mx) & 7)
                    lo = uint8(int(lo) << int(shift))
                    hi = uint8(int(hi) << int(shift))
                }
                palette_index_0 = uint8(int(hi) >> 6 & 2 | int(lo) >> 7)
                var c2da_fresh59 : uint? = unsafe(reinterpret<uint?>(unsafe(reinterpret<uint64>(pal_1))))
                unsafe(unsafe(reinterpret<uint?>(c2da_pixel_addr))[i_3]) = uint(unsafe(unsafe(reinterpret<uint?>(c2da_fresh59))[int(palette_index_0)]))  // nolint:PERF020
                bg_is_zero[i_3] = unsafe(reinterpret<Bool>(uint(int(palette_index_0) == 0 ? 1 : 0)))
                bg_priority[i_3] = priority
            } elif (uint(e_10.state.is_cgb) != 0u) {
                var c2da_fresh60 : PaletteRGBA? = unsafe(reinterpret<PaletteRGBA?>(unsafe(reinterpret<uint64>(e_10)) + 211140ul))
                unsafe(unsafe(reinterpret<uint?>(c2da_pixel_addr))[i_3]) = uint(unsafe(unsafe(addr(unsafe(unsafe(reinterpret<PaletteRGBA?>(c2da_fresh60))[0]).color[0]))[0]))  // nolint:PERF020
            } elif (uint(e_10.state.is_sgb) != 0u) {
                var c2da_fresh61 : PaletteRGBA? = unsafe(reinterpret<PaletteRGBA?>(unsafe(reinterpret<uint64>(e_10)) + 533688ul))
                unsafe(unsafe(reinterpret<uint?>(c2da_pixel_addr))[i_3]) = uint(unsafe(unsafe(addr(unsafe(unsafe(reinterpret<PaletteRGBA?>(c2da_fresh61))[0]).color[0]))[0]))  // nolint:PERF020
            } else {
                var c2da_fresh62 : PaletteRGBA? = unsafe(reinterpret<PaletteRGBA?>(unsafe(reinterpret<uint64>(e_10)) + 533592ul))
                unsafe(unsafe(reinterpret<uint?>(c2da_pixel_addr))[i_3]) = uint(unsafe(unsafe(addr(unsafe(unsafe(reinterpret<PaletteRGBA?>(c2da_fresh62))[0]).color[0]))[0]))  // nolint:PERF020
            }
            i_3++
            mx = uint8(int(mx) + 1)
        }
        if (uint(e_10.state.is_cgb) != 0x0 && uint(e_10.state.ppu.lcdc.bg_display) == 0u) {
            unsafe(reinterpret<uint8?>(c2da_rt_memset(unsafe(reinterpret<uint64>(unsafe(addr<uint8?>(bg_is_zero)))), 1u8, 16ul)))
            unsafe(reinterpret<uint8?>(c2da_rt_memset(unsafe(reinterpret<uint64>(unsafe(addr<uint8?>(bg_priority)))), 0u8, 16ul)))
        }
        if (uint(display_obj) != 0u) {
            obj_height = s_obj_size_to_height[int(e_10.state.ppu.lcdc.obj_size)]
            n = int(e_10.state.ppu.line_obj_count) - 1
            while (n >= 0) {
                var c2da_fresh63 : Obj? = unsafe(reinterpret<Obj?>(unsafe(reinterpret<uint64>(e_10)) + 211572ul))
                o = unsafe(addr(unsafe(unsafe(reinterpret<Obj?>(c2da_fresh63))[n])))
                ox_start = int8(int(o.x) - int(x_2))
                ox_end = int8(int(ox_start) + 7)
                oy = uint8(int(y) - int(o.y))
                if (int(uint8(ox_start)) >= 4 && int(uint8(ox_end)) >= 8 || int(oy) >= int(obj_height)) {
                    n--
                    continue
                }
                if (uint(o.yflip) != 0u) {
                    oy = uint8(int(obj_height) - 1 - int(oy))
                }
                tile_index_0 = uint16(o.tile)
                if (int(obj_height) == 16) {
                    if (int(oy) < 8) {
                        tile_index_0 = uint16(int(tile_index_0) & 254)
                    } else {
                        tile_index_0 = uint16(int(tile_index_0) | 1)
                        oy = uint8(int(oy) - 8)
                    }
                }
                pal_2 = null
                if (uint(e_10.state.is_cgb) != 0u) {
                    var c2da_fresh64 : PaletteRGBA? = unsafe(reinterpret<PaletteRGBA?>(unsafe(reinterpret<uint64>(e_10)) + 211340ul))
                    pal_2 = unsafe(addr<PaletteRGBA?>(unsafe(unsafe(reinterpret<PaletteRGBA?>(c2da_fresh64))[int(o.cgb_palette) & 7])))
                    if (o.bank != 0x0) {
                        tile_index_0 = uint16(int(tile_index_0) + 512)
                    }
                } else {
                    var c2da_fresh65 : PaletteRGBA? = unsafe(reinterpret<PaletteRGBA?>(unsafe(reinterpret<uint64>(e_10)) + 533640ul))
                    pal_2 = unsafe(addr<PaletteRGBA?>(unsafe(unsafe(reinterpret<PaletteRGBA?>(c2da_fresh65))[int(o.palette) + 1])))
                }
                tile_addr_1 = uint16((int(tile_index_0) * 8 + (int(oy) & 7)) * 2)
                var c2da_fresh66 : uint8? = unsafe(reinterpret<uint8?>(unsafe(reinterpret<uint64>(e_10)) + 12484ul))
                lo_0 = unsafe(unsafe(reinterpret<uint8?>(c2da_fresh66))[int(tile_addr_1)])
                var c2da_fresh67 : uint8? = unsafe(reinterpret<uint8?>(unsafe(reinterpret<uint64>(e_10)) + 12484ul))
                hi_0 = unsafe(unsafe(reinterpret<uint8?>(c2da_fresh67))[int(tile_addr_1) + 1])
                if (uint(o.xflip) == 0u) {
                    lo_0 = reverse_bits_u8(lo_0)
                    hi_0 = reverse_bits_u8(hi_0)
                }
                tile_data_offset = 0 > -int(ox_start) ? 0 : -int(ox_start)
                lo_0 = uint8(int(lo_0) >> tile_data_offset)
                hi_0 = uint8(int(hi_0) >> tile_data_offset)
                start = 0 > int(ox_start) ? 0 : int(ox_start)
                end = 3 < int(ox_end) ? 3 : int(ox_end)
                i_3 = start
                while (i_3 <= end) {
                    palette_index_1 = uint8((int(hi_0) & 1) << 1 | int(lo_0) & 1)
                    if (int(palette_index_1) != 0 && (uint(bg_priority[i_3]) == 0u || uint(bg_is_zero[i_3]) != 0x0) && (uint(o.priority) == 0u || uint(bg_is_zero[i_3]) != 0x0)) {
                        var c2da_fresh68 : uint? = unsafe(reinterpret<uint?>(unsafe(reinterpret<uint64>(pal_2))))
                        unsafe(unsafe(reinterpret<uint?>(c2da_pixel_addr))[i_3]) = uint(unsafe(unsafe(reinterpret<uint?>(c2da_fresh68))[int(palette_index_1)]))  // nolint:PERF020
                    }
                    i_3++
                    lo_0 = uint8(int(lo_0) >> 1)
                    hi_0 = uint8(int(hi_0) >> 1)
                }
                n--
            }
        }
        e_10.state.ppu.mode3_render_ticks += 4ul
        c2da_pixel_addr += 16ul
        x_2 = uint8(int(x_2) + 4)
    }
    e_10.state.ppu.render_x = x_2
    return
}
```


#### `doomgeneric`: `R_DrawColumn`

Ours: not found in this side's module.

Rust:

```das
[sideeffects]
def R_DrawColumn() {
    var count_9 : int
    var dest_8 : uint8?
    var frac_7 : int
    var fracstep : int
    count_9 = dc_yh - dc_yl
    if (count_9 < 0) {
        return
    }
    if (uint(dc_x) >= 320u || dc_yl < 0 || dc_yh >= 200) {
        I_Error(unsafe(addr<int8?>(c2da_str_393[0])), [C2daVaArg(tag = 1, i64 = int64(dc_yl), f64 = 0.0lf, raw = 0x0), C2daVaArg(tag = 1, i64 = int64(dc_yh), f64 = 0.0lf, raw = 0x0), C2daVaArg(tag = 1, i64 = int64(dc_x), f64 = 0.0lf, raw = 0x0)])
    }
    dest_8 = unsafe(reinterpret<uint8?>(unsafe(ylookup[dc_yl] + columnofs[dc_x])))
    fracstep = dc_iscale
    frac_7 = dc_texturemid + (dc_yl - centery) * fracstep
    var c2da_dest_8_addr : uint64 = unsafe(reinterpret<uint64>(dest_8))
    for (c2da_iter in urange64(0ul, uint64(uint(count_9)) + 1ul)) {
        *unsafe(reinterpret<uint8?>(c2da_dest_8_addr)) = uint8(unsafe(dc_colormap[int(unsafe(dc_source[frac_7 >> 16 & 127]))]))  // nolint:PERF020
        c2da_dest_8_addr += 320ul
        frac_7 += fracstep
    }
    return
}
```

#### `doomgeneric`: `R_DrawSpan`

Ours: not found in this side's module.

Rust:

```das
[sideeffects]
def R_DrawSpan() {
    var position_1 : uint
    var step : uint
    var dest_14 : uint8?
    var count_16 : int
    if (ds_x2 < ds_x1 || ds_x1 < 0 || ds_x2 >= 320 || uint(ds_y) > 200u) {
        I_Error(unsafe(addr<int8?>(c2da_str_395[0])), [C2daVaArg(tag = 1, i64 = int64(ds_x1), f64 = 0.0lf, raw = 0x0), C2daVaArg(tag = 1, i64 = int64(ds_x2), f64 = 0.0lf, raw = 0x0), C2daVaArg(tag = 1, i64 = int64(ds_y), f64 = 0.0lf, raw = 0x0)])
    }
    position_1 = uint(ds_xfrac << 10) & 0xffff0000u | uint(ds_yfrac >> 6 & 65535)
    step = uint(ds_xstep << 10) & 0xffff0000u | uint(ds_ystep >> 6 & 65535)
    dest_14 = unsafe(reinterpret<uint8?>(unsafe(ylookup[ds_y] + columnofs[ds_x1])))
    count_16 = ds_x2 - ds_x1
    var c2da_dest_14_addr : uint64 = unsafe(reinterpret<uint64>(dest_14))
    for (c2da_iter_5 in urange64(0ul, uint64(uint(count_16)) + 1ul)) {
        *unsafe(reinterpret<uint8?>(c2da_dest_14_addr)) = uint8(unsafe(ds_colormap[int(unsafe(ds_source[int(position_1 >> 26u | position_1 >> 4u & 0xfc0u)]))]))  // nolint:PERF020
        c2da_dest_14_addr++
        position_1 += step
    }
    return
}
```


#### `h264bsd-mp4`: `h264bsdProcessBlock`

Ours: not found in this side's module.

Rust:

```das
[sideeffects]
def h264bsdProcessBlock(var data_28 : int?; var qp : uint; var skip : uint; var coeffMap_0 : uint) : uint {
    var tmp0 : int
    var tmp1_14 : int
    var tmp2_14 : int
    var tmp3_12 : int
    var d2 : int
    var d3 : int
    var row_3 : uint
    var col_3 : uint
    var qpDiv : uint
    var ptr_3 : int?
    qpDiv = uint(qpDiv6[int(qp)])
    tmp1_14 = levelScale[int(qpMod6[int(qp)])][0] << int(qpDiv)
    tmp2_14 = levelScale[int(qpMod6[int(qp)])][1] << int(qpDiv)
    tmp3_12 = levelScale[int(qpMod6[int(qp)])][2] << int(qpDiv)
    if (skip == 0) {
        unsafe(data_28[0]) *= tmp1_14
    }
    if ((coeffMap_0 & 0xff9cu) != 0x0) {
        d2 = unsafe(data_28[14])
        d3 = unsafe(data_28[15])
        unsafe(data_28[1]) *= tmp2_14
        unsafe(data_28[14]) = d2 * tmp2_14
        unsafe(data_28[15]) = d3 * tmp3_12
        d2 = unsafe(data_28[5])
        d3 = unsafe(data_28[4])
        unsafe(data_28[4]) = unsafe(data_28[2]) * tmp2_14
        unsafe(data_28[2]) = d2 * tmp1_14
        unsafe(data_28[5]) = d3 * tmp3_12
        d3 = unsafe(data_28[6])
        tmp0 = unsafe(data_28[8]) * tmp2_14
        unsafe(data_28[8]) = unsafe(data_28[3]) * tmp1_14
        unsafe(data_28[3]) = d3 * tmp2_14
        d2 = unsafe(data_28[12])
        d3 = unsafe(data_28[9])
        unsafe(data_28[6]) = unsafe(data_28[7]) * tmp2_14
        unsafe(data_28[7]) = d2 * tmp3_12
        unsafe(data_28[12]) = d3 * tmp2_14
        unsafe(data_28[9]) = tmp0
        d2 = unsafe(data_28[11])
        d3 = unsafe(data_28[13])
        unsafe(data_28[13]) = unsafe(data_28[10]) * tmp3_12
        unsafe(data_28[10]) = d2 * tmp1_14
        unsafe(data_28[11]) = d3 * tmp2_14
        row_3 = 4u
        ptr_3 = unsafe(reinterpret<int?>(data_28))
        while (true) {
            let c2da_postinc_60 : uint = row_3
            row_3--
            if (c2da_postinc_60 == 0x0) {
                break
            }
            tmp0 = unsafe(ptr_3[0]) + unsafe(ptr_3[2])
            tmp1_14 = unsafe(ptr_3[0]) - unsafe(ptr_3[2])
            tmp2_14 = (unsafe(ptr_3[1]) >> 1) - unsafe(ptr_3[3])
            tmp3_12 = unsafe(ptr_3[1]) + (unsafe(ptr_3[3]) >> 1)
            unsafe(ptr_3[0]) = tmp0 + tmp3_12
            unsafe(ptr_3[1]) = tmp1_14 + tmp2_14
            unsafe(ptr_3[2]) = tmp1_14 - tmp2_14
            unsafe(ptr_3[3]) = tmp0 - tmp3_12
            unsafe {  // nolint:STYLE025
                ptr_3 += 4
            }
        }
        var c2da_data_28_addr : uint64 = unsafe(reinterpret<uint64>(data_28))
        col_3 = 4u
        while (true) {
            let c2da_postinc_61 : uint = col_3
            col_3--
            if (c2da_postinc_61 == 0x0) {
                break
            }
            tmp0 = unsafe(unsafe(reinterpret<int?>(c2da_data_28_addr))[0]) + unsafe(unsafe(reinterpret<int?>(c2da_data_28_addr))[8])
            tmp1_14 = unsafe(unsafe(reinterpret<int?>(c2da_data_28_addr))[0]) - unsafe(unsafe(reinterpret<int?>(c2da_data_28_addr))[8])
            tmp2_14 = (unsafe(unsafe(reinterpret<int?>(c2da_data_28_addr))[4]) >> 1) - unsafe(unsafe(reinterpret<int?>(c2da_data_28_addr))[12])
            tmp3_12 = unsafe(unsafe(reinterpret<int?>(c2da_data_28_addr))[4]) + (unsafe(unsafe(reinterpret<int?>(c2da_data_28_addr))[12]) >> 1)
            unsafe(unsafe(reinterpret<int?>(c2da_data_28_addr))[0]) = tmp0 + tmp3_12 + 32 >> 6
            unsafe(unsafe(reinterpret<int?>(c2da_data_28_addr))[4]) = tmp1_14 + tmp2_14 + 32 >> 6
            unsafe(unsafe(reinterpret<int?>(c2da_data_28_addr))[8]) = tmp1_14 - tmp2_14 + 32 >> 6
            unsafe(unsafe(reinterpret<int?>(c2da_data_28_addr))[12]) = tmp0 - tmp3_12 + 32 >> 6
            if (uint(unsafe(unsafe(reinterpret<int?>(c2da_data_28_addr))[0]) + 512) > 1023u || uint(unsafe(unsafe(reinterpret<int?>(c2da_data_28_addr))[4]) + 512) > 1023u || uint(unsafe(unsafe(reinterpret<int?>(c2da_data_28_addr))[8]) + 512) > 1023u || uint(unsafe(unsafe(reinterpret<int?>(c2da_data_28_addr))[12]) + 512) > 1023u) {
                return 1u
            }
            c2da_data_28_addr += 4ul
        }
    } elif ((coeffMap_0 & 0x62u) == 0u) {
        tmp0 = unsafe(data_28[0]) + 32 >> 6
        if (uint(tmp0 + 512) > 1023u) {
            return 1u
        }
        unsafe(data_28[15]) = tmp0
        unsafe(data_28[14]) = int(unsafe(data_28[15]))  // nolint:PERF020
        unsafe(data_28[13]) = int(unsafe(data_28[14]))  // nolint:PERF020
        unsafe(data_28[12]) = int(unsafe(data_28[13]))  // nolint:PERF020
        unsafe(data_28[11]) = int(unsafe(data_28[12]))  // nolint:PERF020
        unsafe(data_28[10]) = int(unsafe(data_28[11]))  // nolint:PERF020
        unsafe(data_28[9]) = int(unsafe(data_28[10]))  // nolint:PERF020
        unsafe(data_28[8]) = int(unsafe(data_28[9]))  // nolint:PERF020
        unsafe(data_28[7]) = int(unsafe(data_28[8]))  // nolint:PERF020
        unsafe(data_28[6]) = int(unsafe(data_28[7]))  // nolint:PERF020
        unsafe(data_28[5]) = int(unsafe(data_28[6]))  // nolint:PERF020
        unsafe(data_28[4]) = int(unsafe(data_28[5]))  // nolint:PERF020
        unsafe(data_28[3]) = int(unsafe(data_28[4]))  // nolint:PERF020
        unsafe(data_28[2]) = int(unsafe(data_28[3]))  // nolint:PERF020
        unsafe(data_28[1]) = int(unsafe(data_28[2]))  // nolint:PERF020
        unsafe(data_28[0]) = int(unsafe(data_28[1]))  // nolint:PERF020
    } else {
        unsafe(data_28[1]) *= tmp2_14
        unsafe(data_28[2]) = unsafe(data_28[5]) * tmp1_14
        unsafe(data_28[3]) = unsafe(data_28[6]) * tmp2_14
        tmp0 = unsafe(data_28[0]) + unsafe(data_28[2])
        tmp1_14 = unsafe(data_28[0]) - unsafe(data_28[2])
        tmp2_14 = (unsafe(data_28[1]) >> 1) - unsafe(data_28[3])
        tmp3_12 = unsafe(data_28[1]) + (unsafe(data_28[3]) >> 1)
        unsafe(data_28[0]) = tmp0 + tmp3_12 + 32 >> 6
        unsafe(data_28[1]) = tmp1_14 + tmp2_14 + 32 >> 6
        unsafe(data_28[2]) = tmp1_14 - tmp2_14 + 32 >> 6
        unsafe(data_28[3]) = tmp0 - tmp3_12 + 32 >> 6
        unsafe(data_28[12]) = int(unsafe(data_28[0]))  // nolint:PERF020
        unsafe(data_28[8]) = int(unsafe(data_28[12]))  // nolint:PERF020
        unsafe(data_28[4]) = int(unsafe(data_28[8]))  // nolint:PERF020
        unsafe(data_28[13]) = int(unsafe(data_28[1]))  // nolint:PERF020
        unsafe(data_28[9]) = int(unsafe(data_28[13]))  // nolint:PERF020
        unsafe(data_28[5]) = int(unsafe(data_28[9]))  // nolint:PERF020
        unsafe(data_28[14]) = int(unsafe(data_28[2]))  // nolint:PERF020
        unsafe(data_28[10]) = int(unsafe(data_28[14]))  // nolint:PERF020
        unsafe(data_28[6]) = int(unsafe(data_28[10]))  // nolint:PERF020
        unsafe(data_28[15]) = int(unsafe(data_28[3]))  // nolint:PERF020
        unsafe(data_28[11]) = int(unsafe(data_28[15]))  // nolint:PERF020
        unsafe(data_28[7]) = int(unsafe(data_28[11]))  // nolint:PERF020
        if (uint(unsafe(data_28[0]) + 512) > 1023u || uint(unsafe(data_28[1]) + 512) > 1023u || uint(unsafe(data_28[2]) + 512) > 1023u || uint(unsafe(data_28[3]) + 512) > 1023u) {
            return 1u
        }
    }
    return 0u
}
```

#### `h264bsd-mp4`: `FilterVerLumaEdge`

Ours: not found in this side's module.

Rust:

```das
[sideeffects]
def FilterVerLumaEdge(var data_40 : uint8?; var bS_7 : uint; var thresholds_8 : edgeThreshold_t?; var imageWidth_1 : uint) {
    var delta_4 : int
    var tc_4 : int
    var tmp_54 : int
    var i_81 : uint
    var p0_4 : int
    var q0_4 : int
    var p1_12 : int
    var q1_4 : int
    var p2_1 : int
    var q2_1 : int
    var tmpFlag_0 : uint
    var clp_15 : uint8 const?
    var alpha_0 : uint
    var beta_0 : uint
    var val_3 : int
    clp_15 = unsafe(unsafe(addr(h264bsdClip[0])) + 512)
    alpha_0 = thresholds_8.alpha
    beta_0 = thresholds_8.beta
    if (bS_7 < 4u) {
        tc_4 = int(unsafe(thresholds_8.tc0[int(bS_7 - 1u)]))
        tmp_54 = tc_4
        i_81 = 4u
        while (i_81 != 0x0) {
            p1_12 = int(unsafe(data_40[-2]))
            p0_4 = int(unsafe(data_40[-1]))
            q0_4 = int(unsafe(data_40[0]))
            q1_4 = int(unsafe(data_40[1]))
            if (uint(p0_4 - q0_4 < 0 ? -(p0_4 - q0_4) : p0_4 - q0_4) < alpha_0 && uint(p1_12 - p0_4 < 0 ? -(p1_12 - p0_4) : p1_12 - p0_4) < beta_0 && uint(q1_4 - q0_4 < 0 ? -(q1_4 - q0_4) : q1_4 - q0_4) < beta_0) {
                p2_1 = int(unsafe(data_40[-3]))
                q2_1 = int(unsafe(data_40[2]))
                if (uint(p2_1 - p0_4 < 0 ? -(p2_1 - p0_4) : p2_1 - p0_4) < beta_0) {
                    val_3 = p2_1 + (p0_4 + q0_4 + 1 >> 1) - (p1_12 << 1) >> 1
                    unsafe(data_40[-2]) = uint8(p1_12 + (val_3 < -tc_4 ? -tc_4 : val_3 > tc_4 ? tc_4 : val_3))
                    tmp_54++
                }
                if (uint(q2_1 - q0_4 < 0 ? -(q2_1 - q0_4) : q2_1 - q0_4) < beta_0) {
                    val_3 = q2_1 + (p0_4 + q0_4 + 1 >> 1) - (q1_4 << 1) >> 1
                    unsafe(data_40[1]) = uint8(q1_4 + (val_3 < -tc_4 ? -tc_4 : val_3 > tc_4 ? tc_4 : val_3))
                    tmp_54++
                }
                val_3 = (q0_4 - p0_4 << 2) + (p1_12 - q1_4) + 4 >> 3
                delta_4 = val_3 < -tmp_54 ? -tmp_54 : val_3 > tmp_54 ? tmp_54 : val_3
                q0_4 = int(unsafe(clp_15[q0_4 - delta_4]))
                tmp_54 = tc_4
                unsafe(data_40[-1]) = uint8(unsafe(clp_15[p0_4 + delta_4]))  // nolint:PERF020
                unsafe(data_40[0]) = uint8(q0_4)
            }
            i_81--
            unsafe {  // nolint:STYLE025
                data_40 += int64(imageWidth_1)
            }
        }
    } else {
        i_81 = 4u
        while (i_81 != 0x0) {
            p1_12 = int(unsafe(data_40[-2]))
            p0_4 = int(unsafe(data_40[-1]))
            q0_4 = int(unsafe(data_40[0]))
            q1_4 = int(unsafe(data_40[1]))
            if (uint(p0_4 - q0_4 < 0 ? -(p0_4 - q0_4) : p0_4 - q0_4) < alpha_0 && uint(p1_12 - p0_4 < 0 ? -(p1_12 - p0_4) : p1_12 - p0_4) < beta_0 && uint(q1_4 - q0_4 < 0 ? -(q1_4 - q0_4) : q1_4 - q0_4) < beta_0) {
                tmpFlag_0 = uint(uint(p0_4 - q0_4 < 0 ? -(p0_4 - q0_4) : p0_4 - q0_4) < (alpha_0 >> 2u) + 2u ? 1 : 0)
                p2_1 = int(unsafe(data_40[-3]))
                q2_1 = int(unsafe(data_40[2]))
                if (tmpFlag_0 != 0x0 && uint(p2_1 - p0_4 < 0 ? -(p2_1 - p0_4) : p2_1 - p0_4) < beta_0) {
                    tmp_54 = p1_12 + p0_4 + q0_4
                    unsafe(data_40[-1]) = uint8(p2_1 + 2 * tmp_54 + q1_4 + 4 >> 3)
                    unsafe(data_40[-2]) = uint8(p2_1 + tmp_54 + 2 >> 2)
                    unsafe(data_40[-3]) = uint8(2 * int(unsafe(data_40[-4])) + 3 * p2_1 + tmp_54 + 4 >> 3)
                } else {
                    unsafe(data_40[-1]) = uint8(2 * p1_12 + p0_4 + q1_4 + 2 >> 2)
                }
                if (tmpFlag_0 != 0x0 && uint(q2_1 - q0_4 < 0 ? -(q2_1 - q0_4) : q2_1 - q0_4) < beta_0) {
                    tmp_54 = p0_4 + q0_4 + q1_4
                    unsafe(data_40[0]) = uint8(p1_12 + 2 * tmp_54 + q2_1 + 4 >> 3)
                    unsafe(data_40[1]) = uint8(tmp_54 + q2_1 + 2 >> 2)
                    unsafe(data_40[2]) = uint8(2 * int(unsafe(data_40[3])) + 3 * q2_1 + tmp_54 + 4 >> 3)
                } else {
                    unsafe(data_40[0]) = uint8(2 * q1_4 + q0_4 + p1_12 + 2 >> 2)
                }
            }
            i_81--
            unsafe {  // nolint:STYLE025
                data_40 += int64(imageWidth_1)
            }
        }
    }
    return
}
```


#### `plmpeg-stream`: `plm_video_idct`

Ours:

```das
[c_function]
def plm_video_idct(var _c_block : int?) {
    var b1 : int
    var b3 : int
    var b4 : int
    var b6 : int
    var b7 : int
    var tmp1 : int
    var tmp2 : int
    var m0 : int
    var x0 : int
    var x1 : int
    var x2 : int
    var x3 : int
    var x4 : int
    var y3 : int
    var y4 : int
    var y5 : int
    var y6 : int
    var y7 : int
    // Transform columns
    for (i in range(8)) {
        b1 = deref(_c_block + (4 * 8 + i))
        b3 = deref(_c_block + (2 * 8 + i)) + deref(_c_block + (6 * 8 + i))
        b4 = deref(_c_block + (5 * 8 + i)) - deref(_c_block + (3 * 8 + i))
        tmp1 = deref(_c_block + (1 * 8 + i)) + deref(_c_block + (7 * 8 + i))
        tmp2 = deref(_c_block + (3 * 8 + i)) + deref(_c_block + (5 * 8 + i))
        b6 = deref(_c_block + (1 * 8 + i)) - deref(_c_block + (7 * 8 + i))
        b7 = tmp1 + tmp2
        m0 = deref(_c_block + (0 * 8 + i))
        x4 = (b6 * 473 - b4 * 196 + 128 >> 8) - b7
        x0 = x4 - ((tmp1 - tmp2) * 362 + 128 >> 8)
        x1 = m0 - b1
        x2 = ((deref(_c_block + (2 * 8 + i)) - deref(_c_block + (6 * 8 + i))) * 362 + 128 >> 8) - b3
        x3 = m0 + b1
        y3 = x1 + x2
        y4 = x3 + b3
        y5 = x1 - x2
        y6 = x3 - b3
        y7 = -x0 - (b4 * 473 + b6 * 196 + 128 >> 8)
        deref(_c_block + (0 * 8 + i)) = b7 + y4
        deref(_c_block + (1 * 8 + i)) = x4 + y3
        deref(_c_block + (2 * 8 + i)) = y5 - x0
        deref(_c_block + (3 * 8 + i)) = y6 - y7
        deref(_c_block + (4 * 8 + i)) = y6 + y7
        deref(_c_block + (5 * 8 + i)) = x0 + y5
        deref(_c_block + (6 * 8 + i)) = y3 - x4
        deref(_c_block + (7 * 8 + i)) = y4 - b7
    }
    // Transform rows
    {
        var i : int = 0
        while (i < 64) {
            b1 = deref(_c_block + (4 + i))
            b3 = deref(_c_block + (2 + i)) + deref(_c_block + (6 + i))
            b4 = deref(_c_block + (5 + i)) - deref(_c_block + (3 + i))
            tmp1 = deref(_c_block + (1 + i)) + deref(_c_block + (7 + i))
            tmp2 = deref(_c_block + (3 + i)) + deref(_c_block + (5 + i))
            b6 = deref(_c_block + (1 + i)) - deref(_c_block + (7 + i))
            b7 = tmp1 + tmp2
            m0 = deref(_c_block + (0 + i))
            x4 = (b6 * 473 - b4 * 196 + 128 >> 8) - b7
            x0 = x4 - ((tmp1 - tmp2) * 362 + 128 >> 8)
            x1 = m0 - b1
            x2 = ((deref(_c_block + (2 + i)) - deref(_c_block + (6 + i))) * 362 + 128 >> 8) - b3
            x3 = m0 + b1
            y3 = x1 + x2
            y4 = x3 + b3
            y5 = x1 - x2
            y6 = x3 - b3
            y7 = -x0 - (b4 * 473 + b6 * 196 + 128 >> 8)
            deref(_c_block + (0 + i)) = b7 + y4 + 128 >> 8
            deref(_c_block + (1 + i)) = x4 + y3 + 128 >> 8
            deref(_c_block + (2 + i)) = y5 - x0 + 128 >> 8
            deref(_c_block + (3 + i)) = y6 - y7 + 128 >> 8
            deref(_c_block + (4 + i)) = y6 + y7 + 128 >> 8
            deref(_c_block + (5 + i)) = x0 + y5 + 128 >> 8
            deref(_c_block + (6 + i)) = y3 - x4 + 128 >> 8
            deref(_c_block + (7 + i)) = y4 - b7 + 128 >> 8
            i += 8
        }
    }
}
```

Rust:

```das
[sideeffects]
def plm_video_idct(var block_2 : int?) {
    var b1 : int
    var b3 : int
    var b4 : int
    var b6 : int
    var b7 : int
    var tmp1 : int
    var tmp2 : int
    var m0 : int
    var x0 : int
    var x1 : int
    var x2 : int
    var x3 : int
    var x4 : int
    var y3 : int
    var y4 : int
    var y5 : int
    var y6 : int
    var y7 : int
    var i_6 : int
    for (i_5 in range(0, 8)) {
        b1 = unsafe(block_2[4 * 8 + i_5])
        b3 = unsafe(block_2[2 * 8 + i_5]) + unsafe(block_2[6 * 8 + i_5])
        b4 = unsafe(block_2[5 * 8 + i_5]) - unsafe(block_2[3 * 8 + i_5])
        tmp1 = unsafe(block_2[1 * 8 + i_5]) + unsafe(block_2[7 * 8 + i_5])
        tmp2 = unsafe(block_2[3 * 8 + i_5]) + unsafe(block_2[5 * 8 + i_5])
        b6 = unsafe(block_2[1 * 8 + i_5]) - unsafe(block_2[7 * 8 + i_5])
        b7 = tmp1 + tmp2
        m0 = unsafe(block_2[0 * 8 + i_5])
        x4 = (b6 * 473 - b4 * 196 + 128 >> 8) - b7
        x0 = x4 - ((tmp1 - tmp2) * 362 + 128 >> 8)
        x1 = m0 - b1
        x2 = ((unsafe(block_2[2 * 8 + i_5]) - unsafe(block_2[6 * 8 + i_5])) * 362 + 128 >> 8) - b3
        x3 = m0 + b1
        y3 = x1 + x2
        y4 = x3 + b3
        y5 = x1 - x2
        y6 = x3 - b3
        y7 = -x0 - (b4 * 473 + b6 * 196 + 128 >> 8)
        unsafe(block_2[0 * 8 + i_5]) = b7 + y4
        unsafe(block_2[1 * 8 + i_5]) = x4 + y3
        unsafe(block_2[2 * 8 + i_5]) = y5 - x0
        unsafe(block_2[3 * 8 + i_5]) = y6 - y7
        unsafe(block_2[4 * 8 + i_5]) = y6 + y7
        unsafe(block_2[5 * 8 + i_5]) = x0 + y5
        unsafe(block_2[6 * 8 + i_5]) = y3 - x4
        unsafe(block_2[7 * 8 + i_5]) = y4 - b7
    }
    i_6 = 0
    while (i_6 < 64) {
        b1 = unsafe(block_2[4 + i_6])
        b3 = unsafe(block_2[2 + i_6]) + unsafe(block_2[6 + i_6])
        b4 = unsafe(block_2[5 + i_6]) - unsafe(block_2[3 + i_6])
        tmp1 = unsafe(block_2[1 + i_6]) + unsafe(block_2[7 + i_6])
        tmp2 = unsafe(block_2[3 + i_6]) + unsafe(block_2[5 + i_6])
        b6 = unsafe(block_2[1 + i_6]) - unsafe(block_2[7 + i_6])
        b7 = tmp1 + tmp2
        m0 = unsafe(block_2[0 + i_6])
        x4 = (b6 * 473 - b4 * 196 + 128 >> 8) - b7
        x0 = x4 - ((tmp1 - tmp2) * 362 + 128 >> 8)
        x1 = m0 - b1
        x2 = ((unsafe(block_2[2 + i_6]) - unsafe(block_2[6 + i_6])) * 362 + 128 >> 8) - b3
        x3 = m0 + b1
        y3 = x1 + x2
        y4 = x3 + b3
        y5 = x1 - x2
        y6 = x3 - b3
        y7 = -x0 - (b4 * 473 + b6 * 196 + 128 >> 8)
        unsafe(block_2[0 + i_6]) = b7 + y4 + 128 >> 8
        unsafe(block_2[1 + i_6]) = x4 + y3 + 128 >> 8
        unsafe(block_2[2 + i_6]) = y5 - x0 + 128 >> 8
        unsafe(block_2[3 + i_6]) = y6 - y7 + 128 >> 8
        unsafe(block_2[4 + i_6]) = y6 + y7 + 128 >> 8
        unsafe(block_2[5 + i_6]) = x0 + y5 + 128 >> 8
        unsafe(block_2[6 + i_6]) = y3 - x4 + 128 >> 8
        unsafe(block_2[7 + i_6]) = y4 - b7 + 128 >> 8
        i_6 += 8
    }
    return
}
```

#### `plmpeg-stream`: `plm_video_decode_block`

Ours:

```das
[c_function]
def plm_video_decode_block(var self : plm_video_t?; _c_block : int) {
    var n : int = 0
    var quant_matrix : uint8?
    // Decode DC coefficient of intra-coded blocks
    if (self.macroblock_intra != 0) {
        var predictor : int
        var dct_size : int
        // DC prediction
        var plane_index : int = _c_block > 3 ? _c_block - 3 : 0
        predictor = self.dc_predictor[plane_index]
        dct_size = int(plm_buffer_read_vlc(self.buffer, plmpeg_file_all__PLM_VIDEO_DCT_SIZE[plane_index]))
        // Read DC coeff
        if (dct_size > 0) {
            var differential : int = plm_buffer_read(self.buffer, dct_size)
            if ((differential & 1 << dct_size - 1) != 0) {
                self.block_data[0] = predictor + differential
            } else {
                self.block_data[0] = predictor + (-(1 << dct_size) | differential + 1)
            }
        } else {
            self.block_data[0] = predictor
        }
        // Save predictor value
        self.dc_predictor[plane_index] = self.block_data[0]
        // Dequantize + premultiply
        self.block_data[0] <<= 3 + 5
        quant_matrix = addr(self.intra_quant_matrix[0])
        n = 1
    } else {
        quant_matrix = addr(self.non_intra_quant_matrix[0])
    }
    // Decode AC coefficients (+DC for non-intra)
    var level : int = 0
    while (TRUE != 0) {
        var run : int = 0
        var coeff : uint16 = plm_buffer_read_vlc_uint(self.buffer, addr(plmpeg_file_all__PLM_VIDEO_DCT_COEFF[0]))
        if (int(coeff) == 1 && n > 0 && plm_buffer_read(self.buffer, 1) == 0) {
            // end_of_block
            break
        }
        if (int(coeff) == 65535) {
            // escape
            run = plm_buffer_read(self.buffer, 6)
            level = plm_buffer_read(self.buffer, 8)
            if (level == 0) {
                level = plm_buffer_read(self.buffer, 8)
            } elif (level == 128) {
                level = plm_buffer_read(self.buffer, 8) - 256
            } elif (level > 128) {
                level -= 256
            }
        } else {
            run = int(coeff) >> 8
            level = int(coeff) & 255
            if (plm_buffer_read(self.buffer, 1) != 0) {
                level = -level
            }
        }
        n += run
        if (n < 0 || n >= 64) {
            // invalid
            return
        }
        var de_zig_zagged : int = int(plmpeg_file_all__PLM_VIDEO_ZIG_ZAG[n])
        n++
        // Dequantize, oddify, clip
        level = int(uint(level) << 1u)
        if (!(self.macroblock_intra != 0)) {
            level += level < 0 ? -1 : 1
        }
        level = level * self.quantizer_scale * int(deref(quant_matrix + de_zig_zagged)) >> 4
        if ((level & 1) == 0) {
            level -= level > 0 ? 1 : -1
        }
        if (level > 2047) {
            level = 2047
        } elif (level < -2048) {
            level = -2048
        }
        // Save premultiplied coefficient
        self.block_data[de_zig_zagged] = level * int(plmpeg_file_all__PLM_VIDEO_PREMULTIPLIER_MATRIX[de_zig_zagged])
    }
    // Move block to its place
    var d : uint8?
    var dw : int
    var di : int
    if (_c_block < 4) {
        d = self.frame_current.y.data
        dw = self.luma_width
        di = self.mb_row * self.luma_width + self.mb_col << 4
        if ((_c_block & 1) != 0) {
            di += 8
        }
        if ((_c_block & 2) != 0) {
            di += self.luma_width << 3
        }
    } else {
        d = _c_block == 4 ? self.frame_current.cb.data : self.frame_current.cr.data
        dw = self.chroma_width
        di = (self.mb_row * self.luma_width << 2) + (self.mb_col << 3)
    }
    var s : int? = addr(self.block_data[0])
    var si : int = 0
    if (self.macroblock_intra != 0) {
        // Overwrite (no prediction)
        if (n == 1) {
            var clamped : int = int(plmpeg_file_all__plm_clamp(deref(s + 0) + 128 >> 8))
            var _first = true
            while (_first || 0 != 0) {
                _first = false
                var dest_scan : int = dw - 8
                var source_scan : int = 8 - 8
                for (y in range(8)) {
                    for (x in range(8)) {
                        deref(d + di) = uint8(clamped)
                        si++
                        di++
                    }
                    si += source_scan
                    di += dest_scan
                }
            }
            deref(s + 0) = 0
        } else {
            plm_video_idct(s)
            var _first2 = true
            while (_first2 || 0 != 0) {
                _first2 = false
                var dest_scan : int = dw - 8
                var source_scan : int = 8 - 8
                for (y in range(8)) {
                    for (x in range(8)) {
                        deref(d + di) = plmpeg_file_all__plm_clamp(deref(s + si))
                        si++
                        di++
                    }
                    si += source_scan
                    di += dest_scan
                }
            }
            crt::memset(reinterpret<void?>(addr(self.block_data[0])), 0, uint64(typeinfo sizeof(type<int[64]>)))
        }
    } else {
        // Add data to the predicted macroblock
        if (n == 1) {
            var value : int = deref(s + 0) + 128 >> 8
            var _first3 = true
            while (_first3 || 0 != 0) {
                _first3 = false
                var dest_scan : int = dw - 8
                var source_scan : int = 8 - 8
                for (y in range(8)) {
                    for (x in range(8)) {
                        deref(d + di) = plmpeg_file_all__plm_clamp(int(deref(d + di)) + value)
                        si++
                        di++
                    }
                    si += source_scan
                    di += dest_scan
                }
            }
            deref(s + 0) = 0
        } else {
            plm_video_idct(s)
            var _first4 = true
            while (_first4 || 0 != 0) {
                _first4 = false
                var dest_scan : int = dw - 8
                var source_scan : int = 8 - 8
                for (y in range(8)) {
                    for (x in range(8)) {
                        deref(d + di) = plmpeg_file_all__plm_clamp(int(deref(d + di)) + deref(s + si))
                        si++
                        di++
                    }
                    si += source_scan
                    di += dest_scan
                }
            }
            crt::memset(reinterpret<void?>(addr(self.block_data[0])), 0, uint64(typeinfo sizeof(type<int[64]>)))
        }
    }
}
```

Rust:

```das
[sideeffects]
def plm_video_decode_block(var self_92 : plm_video_t?; var block_1 : int) {
    var n : int
    var quant_matrix : uint8?
    var predictor : int
    var dct_size : int
    var plane_index : int
    var differential : int
    var level : int
    var run : int
    var coeff : uint16
    var de_zig_zagged : int
    var d_0 : uint8?
    var dw : int
    var di : int
    var s_0 : int?
    var si : int
    var clamped : int
    var dest_scan : int
    var source_scan : int
    var dest_scan_0 : int
    var source_scan_0 : int
    var value_1 : int
    var dest_scan_1 : int
    var source_scan_1 : int
    var dest_scan_2 : int
    var source_scan_2 : int
    n = 0
    if (self_92.macroblock_intra != 0) {
        plane_index = block_1 > 3 ? block_1 - 3 : 0
        var c2da_fresh93 : int? = unsafe(reinterpret<int?>(unsafe(reinterpret<uint64>(self_92)) + 144ul))
        predictor = unsafe(unsafe(reinterpret<int?>(c2da_fresh93))[plane_index])
        dct_size = int(plm_buffer_read_vlc(self_92.buffer, unsafe(reinterpret<plm_vlc_t const?>(PLM_VIDEO_DCT_SIZE[plane_index]))))
        if (dct_size > 0) {
            differential = plm_buffer_read(self_92.buffer, dct_size)
            if ((differential & 1 << dct_size - 1) != 0) {
                var c2da_fresh94 : int? = unsafe(reinterpret<int?>(unsafe(reinterpret<uint64>(self_92)) + 376ul))
                unsafe(unsafe(reinterpret<int?>(c2da_fresh94))[0]) = predictor + differential
            } else {
                var c2da_fresh95 : int? = unsafe(reinterpret<int?>(unsafe(reinterpret<uint64>(self_92)) + 376ul))
                unsafe(unsafe(reinterpret<int?>(c2da_fresh95))[0]) = predictor + (-(1 << dct_size) | differential + 1)
            }
        } else {
            var c2da_fresh96 : int? = unsafe(reinterpret<int?>(unsafe(reinterpret<uint64>(self_92)) + 376ul))
            unsafe(unsafe(reinterpret<int?>(c2da_fresh96))[0]) = predictor
        }
        var c2da_fresh97 : int? = unsafe(reinterpret<int?>(unsafe(reinterpret<uint64>(self_92)) + 144ul))
        var c2da_fresh98 : int? = unsafe(reinterpret<int?>(unsafe(reinterpret<uint64>(self_92)) + 376ul))
        unsafe(unsafe(reinterpret<int?>(c2da_fresh97))[plane_index]) = int(unsafe(unsafe(reinterpret<int?>(c2da_fresh98))[0]))  // nolint:PERF020
        var c2da_fresh99 : int? = unsafe(reinterpret<int?>(unsafe(reinterpret<uint64>(self_92)) + 376ul))
        unsafe(unsafe(reinterpret<int?>(c2da_fresh99))[0]) <<= 3 + 5
        var c2da_fresh100 : uint8? = unsafe(reinterpret<uint8?>(unsafe(reinterpret<uint64>(self_92)) + 632ul))
        quant_matrix = unsafe(reinterpret<uint8?>(c2da_fresh100))
        n = 1
    } else {
        var c2da_fresh101 : uint8? = unsafe(reinterpret<uint8?>(unsafe(reinterpret<uint64>(self_92)) + 696ul))
        quant_matrix = unsafe(reinterpret<uint8?>(c2da_fresh101))
    }
    level = 0
    while (true) {
        run = 0
        coeff = plm_buffer_read_vlc_uint(self_92.buffer, unsafe(addr<plm_vlc_uint_t const?>(PLM_VIDEO_DCT_COEFF[0])))
        if (int(coeff) == 1 && n > 0 && plm_buffer_read(self_92.buffer, 1) == 0) {
            break
        }
        if (int(coeff) == 65535) {
            run = plm_buffer_read(self_92.buffer, 6)
            level = plm_buffer_read(self_92.buffer, 8)
            if (level == 0) {
                level = plm_buffer_read(self_92.buffer, 8)
            } elif (level == 128) {
                level = plm_buffer_read(self_92.buffer, 8) - 256
            } elif (level > 128) {
                level -= 256
            }
        } else {
            run = int(coeff) >> 8
            level = int(coeff) & 255
            if (plm_buffer_read(self_92.buffer, 1) != 0) {
                level = -level
            }
        }
        n += run
        if (n < 0 || n >= 64) {
            return
        }
        de_zig_zagged = int(PLM_VIDEO_ZIG_ZAG[n])
        n++
        level = int(uint(level) << 1u)
        if (self_92.macroblock_intra == 0) {
            level += level < 0 ? -1 : 1
        }
        level = level * self_92.quantizer_scale * int(unsafe(quant_matrix[de_zig_zagged])) >> 4
        if ((level & 1) == 0) {
            level -= level > 0 ? 1 : -1
        }
        if (level > 2047) {
            level = 2047
        } elif (level < -2048) {
            level = -2048
        }
        var c2da_fresh102 : int? = unsafe(reinterpret<int?>(unsafe(reinterpret<uint64>(self_92)) + 376ul))
        unsafe(unsafe(reinterpret<int?>(c2da_fresh102))[de_zig_zagged]) = level * int(PLM_VIDEO_PREMULTIPLIER_MATRIX[de_zig_zagged])
    }
    if (block_1 < 4) {
        d_0 = unsafe(reinterpret<uint8?>(self_92.frame_current.y.data))
        dw = self_92.luma_width
        di = self_92.mb_row * self_92.luma_width + self_92.mb_col << 4
        if ((block_1 & 1) != 0) {
            di += 8
        }
        if ((block_1 & 2) != 0) {
            di += self_92.luma_width << 3
        }
    } else {
        d_0 = unsafe(reinterpret<uint8?>(block_1 == 4 ? self_92.frame_current.cb.data : self_92.frame_current.cr.data))
        dw = self_92.chroma_width
        di = (self_92.mb_row * self_92.luma_width << 2) + (self_92.mb_col << 3)
    }
    var c2da_fresh103 : int? = unsafe(reinterpret<int?>(unsafe(reinterpret<uint64>(self_92)) + 376ul))
    s_0 = c2da_fresh103
    si = 0
    if (self_92.macroblock_intra != 0) {
        if (n == 1) {
            let c2da_fresh104 : int = unsafe(s_0[0]) + 128 >> 8
            clamped = int(uint8(c2da_fresh104 > 255 ? 255 : c2da_fresh104 < 0 ? 0 : c2da_fresh104))
            dest_scan = dw - 8
            source_scan = 8 - 8
            for (y in range(0, 8)) {
                for (x in range(0, 8)) {
                    unsafe(d_0[di]) = uint8(clamped)
                    si++
                    di++
                }
                si += source_scan
                di += dest_scan
            }
            unsafe(s_0[0]) = 0
        } else {
            plm_video_idct(s_0)
            dest_scan_0 = dw - 8
            source_scan_0 = 8 - 8
            for (y_0 in range(0, 8)) {
                for (x_0 in range(0, 8)) {
                    let c2da_fresh105 : int = unsafe(s_0[si])
                    unsafe(d_0[di]) = uint8(c2da_fresh105 > 255 ? 255 : c2da_fresh105 < 0 ? 0 : c2da_fresh105)
                    si++
                    di++
                }
                si += source_scan_0
                di += dest_scan_0
            }
            var c2da_fresh106 : int? = unsafe(reinterpret<int?>(unsafe(reinterpret<uint64>(self_92)) + 376ul))
            unsafe(reinterpret<uint8?>(c2da_rt_memset(unsafe(reinterpret<uint64>(unsafe(reinterpret<uint8?>(c2da_fresh106)))), 0u8, 256ul)))
        }
    } elif (n == 1) {
        value_1 = unsafe(s_0[0]) + 128 >> 8
        dest_scan_1 = dw - 8
        source_scan_1 = 8 - 8
        for (y_1 in range(0, 8)) {
            for (x_1 in range(0, 8)) {
                let c2da_fresh107 : int = int(unsafe(d_0[di])) + value_1
                unsafe(d_0[di]) = uint8(c2da_fresh107 > 255 ? 255 : c2da_fresh107 < 0 ? 0 : c2da_fresh107)
                si++
                di++
            }
            si += source_scan_1
            di += dest_scan_1
        }
        unsafe(s_0[0]) = 0
    } else {
        plm_video_idct(s_0)
        dest_scan_2 = dw - 8
        source_scan_2 = 8 - 8
        for (y_2 in range(0, 8)) {
            for (x_2 in range(0, 8)) {
                let c2da_fresh108 : int = int(unsafe(d_0[di])) + unsafe(s_0[si])
                unsafe(d_0[di]) = uint8(c2da_fresh108 > 255 ? 255 : c2da_fresh108 < 0 ? 0 : c2da_fresh108)
                si++
                di++
            }
            si += source_scan_2
            di += dest_scan_2
        }
        var c2da_fresh109 : int? = unsafe(reinterpret<int?>(unsafe(reinterpret<uint64>(self_92)) + 376ul))
        unsafe(reinterpret<uint8?>(c2da_rt_memset(unsafe(reinterpret<uint64>(unsafe(reinterpret<uint8?>(c2da_fresh109)))), 0u8, 256ul)))
    }
    return
}
```


#### `quakegeneric`: `D_DrawSpans8`

Ours: not found in this side's module.

Rust:

```das
[export, sideeffects]
def D_DrawSpans8(var pspan : espan_s?) {
    var count : int
    var spancount : int
    var pbase : uint8?
    var pdest : uint8?
    var s : int
    var t : int
    var snext : int
    var tnext : int
    var sstep : int
    var tstep : int
    var sdivz : float
    var tdivz : float
    var zi : float
    var z : float
    var du : float
    var dv : float
    var spancountminus1 : float
    var sdivz8stepu : float
    var tdivz8stepu : float
    var zi8stepu : float
    sstep = 0
    tstep = 0
    pbase = unsafe(reinterpret<uint8?>(cacheblock))
    sdivz8stepu = d_sdivzstepu * 8.0
    tdivz8stepu = d_tdivzstepu * 8.0
    zi8stepu = d_zistepu * 8.0
    while (true) {
        pdest = unsafe(reinterpret<uint8?>(unsafe(unsafe(d_viewbuffer + int64(screenwidth * pspan.v)) + pspan.u)))
        count = pspan.count
        du = float(pspan.u)
        dv = float(pspan.v)
        sdivz = d_sdivzorigin + dv * d_sdivzstepv + du * d_sdivzstepu
        tdivz = d_tdivzorigin + dv * d_tdivzstepv + du * d_tdivzstepu
        zi = d_ziorigin + dv * d_zistepv + du * d_zistepu
        z = 65536.0 / zi
        s = int(sdivz * z) + sadjust
        if (s > bbextents) {
            s = bbextents
        } elif (s < 0) {
            s = 0
        }
        t = int(tdivz * z) + tadjust
        if (t > bbextentt) {
            t = bbextentt
        } elif (t < 0) {
            t = 0
        }
        while (true) {
            if (count >= 8) {
                spancount = 8
            } else {
                spancount = count
            }
            count -= spancount
            if (count != 0) {
                sdivz += sdivz8stepu
                tdivz += tdivz8stepu
                zi += zi8stepu
                z = 65536.0 / zi
                snext = int(sdivz * z) + sadjust
                if (snext > bbextents) {
                    snext = bbextents
                } elif (snext < 8) {
                    snext = 8
                }
                tnext = int(tdivz * z) + tadjust
                if (tnext > bbextentt) {
                    tnext = bbextentt
                } elif (tnext < 8) {
                    tnext = 8
                }
                sstep = snext - s >> 3
                tstep = tnext - t >> 3
            } else {
                spancountminus1 = float(spancount - 1)
                sdivz = sdivz + d_sdivzstepu * spancountminus1
                tdivz = tdivz + d_tdivzstepu * spancountminus1
                zi = zi + d_zistepu * spancountminus1
                z = 65536.0 / zi
                snext = int(sdivz * z) + sadjust
                if (snext > bbextents) {
                    snext = bbextents
                } elif (snext < 8) {
                    snext = 8
                }
                tnext = int(tdivz * z) + tadjust
                if (tnext > bbextentt) {
                    tnext = bbextentt
                } elif (tnext < 8) {
                    tnext = 8
                }
                if (spancount > 1) {
                    sstep = (snext - s) / (spancount - 1)
                    tstep = (tnext - t) / (spancount - 1)
                }
            }
            var c2da_pdest_addr : uint64 = unsafe(reinterpret<uint64>(pdest))
            while (true) {
                *unsafe(reinterpret<uint8?>(c2da_pdest_addr)) = uint8(*unsafe(unsafe(pbase + int64(s >> 16)) + int64((t >> 16) * cachewidth)))
                c2da_pdest_addr++
                s += sstep
                t += tstep
                spancount--
                if (spancount <= 0) {
                    break
                }
            }
            pdest = unsafe(reinterpret<uint8?>(c2da_pdest_addr))
            s = snext
            t = tnext
            if (count <= 0) {
                break
            }
        }
        pspan = unsafe(reinterpret<espan_s?>(pspan.pnext))
        if (pspan == null) {
            break
        }
    }
    return
}
```

#### `quakegeneric`: `D_DrawZSpans`

Ours: not found in this side's module.

Rust:

```das
[export, sideeffects]
def D_DrawZSpans(var pspan_0 : espan_s?) {
    var count_0 : int
    var doublecount : int
    var izistep : int
    var izi : int
    var pdest_0 : int16?
    var ltemp : uint
    izistep = int(d_zistepu * 32768.0 * 65536.0)
    while (true) {
        pdest_0 = unsafe(reinterpret<int16?>(unsafe(unsafe(d_pzbuffer + int64(d_zwidth * uint(pspan_0.v))) + pspan_0.u)))
        count_0 = pspan_0.count
        izi = int(double(d_ziorigin + float(pspan_0.v) * d_zistepv + float(pspan_0.u) * d_zistepu) * 32768.0lf * 65536.0lf)
        if ((int64(unsafe(reinterpret<uint64>(pdest_0))) & 2l) != 0) {
            *pdest_0 = int16(izi >> 16)
            unsafe {  // nolint:STYLE025
                pdest_0 += 1
            }
            izi += izistep
            count_0--
        }
        doublecount = count_0 >> 1
        if (doublecount > 0) {
            while (true) {
                ltemp = uint(izi >> 16)
                izi += izistep
                ltemp |= uint(izi) & 0xffff0000u
                izi += izistep
                *unsafe(reinterpret<int?>(pdest_0)) = int(ltemp)
                unsafe {  // nolint:STYLE025
                    pdest_0 += 2
                }
                doublecount--
                if (doublecount <= 0) {
                    break
                }
            }
        }
        if ((count_0 & 1) != 0) {
            *pdest_0 = int16(izi >> 16)
        }
        pspan_0 = unsafe(reinterpret<espan_s?>(pspan_0.pnext))
        if (pspan_0 == null) {
            break
        }
    }
    return
}
```


#### `wasm3`: `op_Call`

Ours: not found in this side's module.

Rust:

```das
[sideeffects]
def op_Call(var _pc_224 : pc_t; var _sp_224 : m3stack_t; var _mem_224 : M3MemoryHeader?; var _r0_224 : int64) : m3ret_t {
    var callPC_0 : pc_t
    var stackOffset_2 : int
    var memory_9 : IM3Memory
    var r_16 : m3ret_t
    var c2da_postinc_332 : pc_t = _pc_224
    unsafe {  // nolint:STYLE025
        _pc_224 += 1
    }
    callPC_0 = *unsafe(reinterpret<pc_t?>(c2da_postinc_332))
    var c2da_postinc_333 : pc_t = _pc_224
    unsafe {  // nolint:STYLE025
        _pc_224 += 1
    }
    stackOffset_2 = *unsafe(reinterpret<int?>(c2da_postinc_333))
    memory_9 = _mem_224.memory
    r_16 = Call(callPC_0, unsafe(_sp_224 + stackOffset_2), _mem_224, 0l)
    _mem_224 = unsafe(reinterpret<M3MemoryHeader?>(memory_9.mallocated))
    if ((!(!(r_16 == null)) ? 1l : 0l) != 0) {
        return invoke(unsafe(reinterpret<IM3Operation>(*_pc_224)), unsafe(_pc_224 + 1), _sp_224, _mem_224, _r0_224)
    } else {
        return r_16
    }
}
```

#### `wasm3`: `call_fib`

Ours: not found in this side's module.

Rust:

```das
[sideeffects]
def call_fib(var fib : IM3Function; var n_6 : int; var out_1 : int64?) : M3Result {
    var result_227 : M3Result
    var value_81 : uint64
    var value_82 : uint
    result_227 = m3Err_none
    if (uint(m3_GetArgType(fib, 0u)) == 2u) {
        value_81 = 0ul
        result_227 = m3_CallV(fib, [C2daVaArg(tag = 1, i64 = int64(uint64(n_6)), f64 = 0.0lf, raw = 0x0)])
        if (result_227 != null) {
            return result_227
        }
        result_227 = m3_GetResultsV(fib, [C2daVaArg(tag = 3, i64 = 0, f64 = 0.0lf, raw = unsafe(reinterpret<uint64>(unsafe(addr(value_81)))))])
        *out_1 = int64(value_81)
    } else {
        value_82 = 0u
        result_227 = m3_CallV(fib, [C2daVaArg(tag = 1, i64 = int64(uint(n_6)), f64 = 0.0lf, raw = 0x0)])
        if (result_227 != null) {
            return result_227
        }
        result_227 = m3_GetResultsV(fib, [C2daVaArg(tag = 3, i64 = 0, f64 = 0.0lf, raw = unsafe(reinterpret<uint64>(unsafe(addr(value_82)))))])
        *out_1 = int64(value_82)
    }
    return result_227
}
```


### Where the Rust translator is ahead

- c_testsuite: Rust passes 202 of 220 ids, our ratchet 199; of the Rust passes 0 are ids we skip and 8 ids our ratchet does not list.
- gcc_torture: Rust passes 1197 of 1656 ids, our ratchet 1179; of the Rust passes 41 are ids we skip and 67 ids our ratchet does not list.
- blit, interpreter: Rust 53.86x native, ours 96.71x.
- compound_lit, interpreter: Rust 94.11x native, ours 111.19x.
- dasprofile/primes, AOT: Rust 0.58x native, ours 0.63x.
- do_while_effect, interpreter: Rust 18.89x native, ours 22.14x.
- matmul, interpreter: Rust 38.11x native, ours 92.91x.
- primes, AOT: Rust 0.59x native, ours 0.63x.
- sieve, interpreter: Rust 11.84x native, ours 22.61x.
- str_copy, interpreter: Rust 55.17x native, ours 65.51x.
- switch_goto, interpreter: Rust 16.87x native, ours 42.01x.
- switch_goto, JIT: Rust 0.29x native, ours 0.43x.
- switch_goto, exe: Rust 0.29x native, ours 0.43x.
- switch_local, interpreter: Rust 60.15x native, ours 73.51x.
- switch_local, JIT: Rust 0.98x native, ours 5.96x.
- switch_local, exe: Rust 0.99x native, ours 6.15x.
- switch_local, AOT: Rust 2.61x native, ours has no cell (compile).
- va_forward, interpreter: Rust 131.56x native, ours 215.67x.
- project binjgb: Rust passes AOT, ours does not.
- project doomgeneric: Rust passes interpreter, JIT, exe, ours does not.
- project h264bsd-mp4: Rust passes interpreter, JIT, exe, AOT, ours does not.
- project quakegeneric: Rust passes interpreter, exe, AOT, ours does not.
- project wasm3: Rust passes interpreter, JIT, exe, AOT, ours does not.
- counter `pointer_arith`: Rust 606, ours 843 over all keys.
<!-- compare:end -->
