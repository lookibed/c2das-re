# suites Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
holds the external C test suites that verify the backend: for each suite a fetch script, a
runner, the ratchet state and the skip ledger; csmith's suite is generated, its ids the seeds
(section 4). Fetched inputs (`<suite>/fetch/`) and converted
output (`<suite>/work/`) are gitignored; only the runner and its two state files are tracked.

## 1. File charters

- `suite_runner.das` - the runner every suite shares: `run_suite_main(spec, verdict)` converts
  every `<id>.c` directly under the suite's tests folder into `work/<id>/` through
  `converter/pipeline.das` under the `linux` dialect (the baseline of a differential run is a
  native build on this host), runs the module under the interpreter with both module folders
  loaded and a per-suite timeout, and hands the exit code and merged output to the suite's
  verdict. Each test ends in one status: `pass`, `convert` (the dumper, the emitter or the
  compile check refused it), `exit`, `output`, or `skip`. The ratchet and the ledger live
  here too: a listed id that stops passing fails the run; an id that starts passing is
  reported and `--update` writes it in; a failing test that is not listed is a count in the
  summary, not a skip. Its pieces serve the csmith driver too: `record` and `count_status` (one outcome into the `Tally`),
  `finish_run` (the summary, `--update`'s write of the ids it is handed unless the run was
  filtered, the exit code), `convert_and_run` (one C file converted and run under the
  interpreter, with extra interpreter flags when a suite needs them), `compare_output` (an
  exit code and output judged against the expected output), and `run_workers` with
  `spawn_one` (indices through worker processes of a script's `--one`, a number at a time, each
  killed past a limit, its printed output kept), which the readability metric runs on too;
  `C_TESTSUITE_TESTS` and `GCC_TORTURE_TESTS` name the folders the two file-based suites'
  tests sit in.
- `suite_files.das` - what the suites and the readability metric agree on, needing no module
  folder so the `REVIEW.das` gates require it: `read_lines` and `read_ratchet` (the ratchet and
  the ledger as a run reads them), `c_file_ids` (the `.c` files of a folder by id, the suites'
  tests and the perf kernels), `expected_input_keys` (the input keys the readability capture
  holds: each suite's listed ids less its ledgered ones, and every kernel as `perf/<kernel>` and
  `perf/<kernel>@copy`) and `gate_untracked`
  (a gate finding per tracked file under regenerated folders).
- `fetch_common.sh` - sourced by the three fetch scripts: `pin_of` (a pin out of
  `VERSIONS.md`), `at_pin` (a checkout at its pin with its build present) and
  `checkout_if_stale` (a fresh clone at the pin unless `at_pin` holds).
- `c_testsuite/fetch.sh` - clones c-testsuite at the commit `VERSIONS.md` pins into
  `c_testsuite/fetch/c-testsuite`; a checkout already at the pin is left alone.
- `c_testsuite/run.das` - the single-exec suite on the shared runner: a test passes when its
  module exits 0 with the merged output `<id>.c.expected` holds, the suite's contract.
- `gcc_torture/fetch.sh` - a blob-less sparse clone of gcc-mirror/gcc at the release tag and
  commit `VERSIONS.md` pins, holding only `gcc/testsuite/gcc.c-torture/execute`.
- `gcc_torture/filter.das` - the import's filter, run by hand after a fetch: every top-level
  `execute/*.c` whose text carries a GNU extension gets its `skip.txt` line, first matching
  rule wins - the dialect's exclusions (inline asm, `_Complex`, `__int128`, the non-standard
  floating types, vector types, atomics, GNU keywords, `&&label` and `__label__`) with the phase
  `never`, then the constructs a later row carries (`__builtin_*` and `__attribute__` under the
  phase P4; wide string literals and a string literal outside a pointer context, a row of a 2-D
  `char` array, under the row P4.9). The `builtins/` and `ieee/` subfolders are not part of the
  suite.
- `gcc_torture/run.das` - the torture suite on the shared runner: a test passes when its module
  exits 0, the gcc harness's own contract (a failing test calls `abort`); output is not
  judged, as that harness does not judge it.
- `csmith/fetch.sh` - clones csmith at the commit `VERSIONS.md` pins into
  `csmith/fetch/csmith` and builds it there with cmake (`build/src/csmith`, and the generated
  `build/runtime/safe_math.h` beside the `runtime/` headers); with `--cvise` it also clones and
  builds the pinned cvise into `csmith/fetch/cvise` against `PATH_TO_LIBCLANG`, its Python
  packages at the versions the script names in the venv `csmith/fetch/cvise-venv`. A checkout at
  its pin with its build present is left alone; a failed build shows its log's tail; the venv
  records the package set it installed and installs again when the list differs.
- `csmith/run.das` - the differential driver (section 4): its own `main` over the shared
  runner's pieces, one worker process per seed (`--one <seed>`), and the judge of a generated
  program the reducer calls (`--check <file>`).
- `csmith/generate.das` - a seed's program (section 4): `csmith_program` runs the pinned csmith
  with `CSMITH_OPTIONS` and splices the runtime headers in; the driver and the readability
  metric generate through it.
- `csmith/verdict.das` - a seed's verdict file (`<seed>.verdict`, written and read) and
  `worker_outcome`, the outcome the driver draws from a worker that ended: its verdict,
  `timeout` when the driver killed it, `crash` when it exited without a verdict.
- `csmith/reduce.sh <seed> [reducer]` - the minimization harness (section 4): judges the seed
  afresh, writes the interestingness test `work/<seed>/interesting.sh`, runs the reducer (cvise
  by default) and leaves the result at `work/<seed>/min.c`.
- `<suite>/expected_pass.txt` - the ratchet: the sorted ids that pass.
- `<suite>/skip.txt` - the ledger of tests never run: one tab-separated line per id with the
  feature, the reason and the ledger row (`P<n>.<m>`) or phase that unblocks it, `never` for a
  feature no row will lift.
- `REVIEW.das` - the gate over the three suites: `expected_pass.txt` sorted and unique, every
  `skip.txt` line in the four-field shape with a phase or `never`, no id in both files, every
  csmith id a decimal seed, nothing tracked under a suite's `fetch/` or `work/`, and the
  module keys of `metrics/readability_linux.json` the expected input keys, so a diff to a
  ratchet list re-records the readability capture.
- `scripts/run_suite.sh <suite> [flags]` - fetches when needed and runs the runner from the
  repository root with `-load_module` for `dasCRuntime` and `c_runtime`.

## 2. Why the suites are not preflight gates

A full c-testsuite run converts 220 files and spawns clang and daslang for each, a minute on
this box, and the torture suite converts the 892 of its 1656 the ledger does not skip, and a csmith seed takes up
to a minute to convert; the
preflight `tests` lane stays the sub-second
dastest suites. The runners keep
their own ratchet and run on their own schedule, the way `docs/very-detailed-plan.md`
section 8 describes.

## 3. Exception ledger

- `REVIEW.md`, the rule that a `skip.txt` line and a `RULES` entry of `gcc_torture/filter.das`
  name a ledger row, never a bare phase: the two entries for `__attribute__` and `__builtin_*`
  (436 lines of `gcc_torture/skip.txt`) name the phase `P4`, since no `docs/implementation_order.md`
  row names those constructs; they move to a row when the owner adds one, and `REVIEW.das`
  accepts a bare phase until then.

## 4. The csmith run

csmith writes a random C program free of undefined behaviour that prints a checksum of its
globals, so a seed whose converted run disagrees with a native build is a converter bug by
construction (`docs/very-detailed-plan.md`, V3). A seed's program depends only on the seed, the
csmith commit `VERSIONS.md` pins and what `csmith_program` (`csmith/generate.das`) writes
around csmith's output (the option list below, the `#define UNSAFE_FLOAT` prelude and the
spliced runtime headers), which is why the seed alone is the test id: `expected_pass.txt` lists the seeds known clean and every run reruns them, `--seeds N`
adds N fresh random ones (4 by default, none when `--seed` or `--from` names the seeds; a
`--filter` narrows the fresh ones too), and `--update` writes the ratchet as it was, less the
seeds this run failed, plus those it passed. A seed `--seed` or `--from` names is judged whether
`skip.txt` lists it or not, and a listed one that passes is reported for moving out of the
ledger. A seed the native side discards is in neither file: a different csmith pin or option
list makes a different program of the same number, so changing either re-records the ratchet.

Each seed runs in `work/<seed>/`: csmith writes `<seed>.csmith.c`, and `<seed>.c` is that program
with every `#include "..."` the csmith runtime holds spliced in at every occurrence, the
headers' guards keeping one copy live. The runtime is `static` functions in headers, and the
dumper converts the main file's declarations alone, so the splice makes the program one unit,
which both sides then build. The splice opens with `#define UNSAFE_FLOAT`, which drops the
`fabsf` calls from the runtime's float wrappers; the wrappers are dead under csmith's default
`--no-float`, and `fabsf` has no c_runtime mapping.

The reference is the gcc `VERSIONS.md` pins, which the run checks against `gcc
-dumpfullversion` before it starts, at `-O0 -fwrapv -w -funsigned-char`: the dialect's wrapping
overflow and unsigned `char` (`converter/ARCHITECTURE_DUMPER.md`). The converter's own fixtures
build their natives with the pinned clang at its default level and no `-fwrapv`, which suits a
hand-written fixture with no overflow; a csmith program exercises every integer width and the
dialect's wrapping, so the oracle states `-fwrapv` and `-O0` outright (no optimization folds an
expression another way) and pins its compiler, gcc, whose version the run checks. A
native run gets 2 seconds, since the interpreter runs csmith's code a hundred times slower; a
gcc refusal or a non-zero native exit ends the seed as `native`, which is no divergence. The
converted module runs under the interpreter with both module folders loaded,
`-no-module-cache` (a seed's module is never compiled twice, so a cache record would only churn
the cache the test lanes share, and a cache message on stdout would be judged as output) and
300 seconds, and its complete merged output is compared with the native one. The default 16 KB
context stack holds every csmith program met so far, so the run writes no sidecar `stack`; one
would go beside the program as `<seed>.c2das`.

A seed ends in one status: `pass`, `convert`, `exit` (the converted run exited non-zero),
`output`, `native`, `crash` (the worker exited on its own without a verdict), `timeout` (a
stage ran past its limit, the stage named: csmith, the native run, the conversion, the converted
run, or the worker the driver killed) or `skip` (listed in `skip.txt`, on the ratchet's run). Every seed that does
not pass is logged with its status and reason. An `output` or `exit` verdict on any seed, fresh
or listed, fails the run: a divergence is what the run exists to find. A `convert` or `crash` on a
fresh seed is a count; on a listed seed, a regression. A timeout is never a regression and never
recorded: a listed seed that times out runs once more, alone, at the end of the run, and when
it times out again the ratchet keeps it as it was.

The options keep csmith inside what the converter takes: `--no-argc` (`main(argc, argv)` is not
lowered, and the argument only turns on a dump of every global) and `--no-packed-struct` (a
`#pragma pack(1)` record is marshal-only, which a sidecar lists by name). The pinned csmith's
defaults already exclude floats (a float program calls `fabsf`), builtins (a `__builtin_*` call
maps through a shim list the punning tier grows), `__int128` (outside the dialect), GNU
attributes (they reach the dialect only through the sidecar) and binary constants (GNU `0b`
literals, a coverage item the P4.5 row ledgers). Bitfields, unions, volatiles, pointers,
structs passed and returned by value, `goto` and the comma operator stay on.

A seed takes from 5 to 60 seconds: clang's JSON dump of a csmith program is about 170 MB, most of
the conversion time. So the driver runs one worker process per seed, `--jobs` at a time (4 by
default): `run.das --one <seed>` generates, splices, builds, converts and judges the seed and
writes `<seed>.verdict`, one line of status, signature and reason; the driver reads it when the
worker exits and kills a worker past 900 seconds. A file is the channel because a verdict then
needs no output parsing and survives for a person to read. The worker keeps its own deadline of
750 seconds: each timed child gets the lesser of its own limit and what is left of that budget,
so the worker ends inside the driver's limit. The driver's kill must never land while a timed
child is alive, since daScript's timed process capture starts each child in a process group of
its own, and a kill of the worker's group misses it (an upstream report is queued).

`reduce.sh` minimizes a seed that does not pass while every candidate keeps the seed's status
and signature: the converter's first error line with its location dropped and every name in
backticks or quotes blanked, `exit <rc>`, or `output`. A candidate is interesting when gcc's
`-O1 -Wall -Wextra` names none of the warnings that mark undefined behaviour a reduction
introduces (an uninitialized read, a missing return, an implicit declaration, an out-of-bounds
index, an unsequenced modification: "may be undefined"), its `-fsanitize=address,undefined`
build runs clean within 10 seconds, the pinned clang's build at gcc's flags prints what gcc's
does, and `run.das --check` gives the seed's verdict. The clang comparison rejects a candidate
whose output hangs on the order of evaluation, which the dialect fixes left to right while gcc
`-O0` evaluates a call's arguments right to left; an unspecified order that no warning names and
on which both compilers happen to agree passes through, and a reduced program is read with that
in mind. The reducer is cvise, which is maintained, builds against the pinned LLVM and reduces C
without a configuration; any reducer that takes `--n <jobs> <test> <file>` (creduce does) can be
named instead.
