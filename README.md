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

Each project of the Rust repository's `tests/manual` on its own fixture, checked against the output its README gives; the native build (the pinned clang with the README's flags) must print it too. Captured: binjgb (Rust `b1d012eb5d26`, 2026-11-01 20:17 UTC); wasm3 (Rust `b1d012eb5d26`, 2026-11-01 19:52 UTC).

| Project | Side | Native | interpreter |     JIT |     exe |     AOT |
| :------ | :--- | :----- | ----------: | ------: | ------: | ------: |
| binjgb  | Ours | pass   |     refused | refused | refused | refused |
| binjgb  | Rust | pass   |        pass |    pass |    pass | skipped |
| wasm3   | Ours | pass   |     refused | refused | refused | refused |
| wasm3   | Rust | pass   |        pass |    pass |    pass | skipped |

Why a lane does not pass:

- binjgb, Ours, interpreter JIT exe AOT: refused: dumper: libclang: /root/c2das/tests/manual/binjgb/src/all.c:11:10: fatal error: 'common.c' file not found
- binjgb, Rust, AOT: skipped: the aot host passes the program no arguments, and it reads its input from its last one
- wasm3, Ours, interpreter JIT exe AOT: refused: dumper: libclang: /root/c2das/tests/manual/wasm3/src/all.c:80:10: fatal error: 'm3_bind.c' file not found
- wasm3, Rust, AOT: skipped: the aot host passes the program no arguments, and it reads its input from its last one

The bench entry's timed loop (`decode_us`), a lane's median over the native build's (lower is faster), 5 samples a cell:

| Project | Side | Native compiler      | Native s | interpreter |     JIT |     exe |     AOT |
| :------ | :--- | :------------------- | -------: | ----------: | ------: | ------: | ------: |
| binjgb  | Ours | clang version 22.1.8 | 0.062580 |     refused | refused | refused | refused |
| binjgb  | Rust | clang version 22.1.8 | 0.062580 |       71.34 |    1.07 |    1.05 | skipped |
| wasm3   | Ours | clang version 22.1.8 | 0.002223 |     refused | refused | refused | refused |
| wasm3   | Rust | clang version 22.1.8 | 0.002223 |       58.07 |    2.23 |    2.10 | skipped |

The code of each side's module (the Rust runtime is its `c2da_rt_` and `c2da_std_` declarations):

| Project | Side | Code    | Files | Lines | Runtime lines | c_function | goto | label | literal_named | pointer_arith | pointer_index | reinterpret | unsafe_block | unsafe_expr | while_rangeable |
| :------ | :--- | :------ | ----: | ----: | ------------: | ---------: | ---: | ----: | ------------: | ------------: | ------------: | ----------: | -----------: | ----------: | --------------: |
| binjgb  | Ours | refused |     - |     - |             - |          - |    - |     - |             - |             - |             - |           - |            - |           - |               - |
| binjgb  | Rust | ok      |     1 | 11481 |           956 |          0 |  670 |   867 |          2393 |            33 |           939 |        3818 |            8 |        5049 |              12 |
| wasm3   | Ours | refused |     - |     - |             - |          - |    - |     - |             - |             - |             - |           - |            - |           - |               - |
| wasm3   | Rust | ok      |     1 | 25827 |          1009 |          0 | 2393 |  2162 |          1827 |          2074 |           430 |        4550 |          814 |        6589 |              24 |

#### `binjgb`: `emulator_step_internal`

Ours: not found in this side's module.

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

Ours: not found in this side's module.

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
- project binjgb: Rust passes interpreter, JIT, exe, ours does not.
- project wasm3: Rust passes interpreter, JIT, exe, ours does not.
- counter `pointer_arith`: Rust 606, ours 843 over all keys.
<!-- compare:end -->
