# suites Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
holds the external C test suites that verify the backend: for each suite a fetch script, a
runner, the ratchet state and the skip ledger; csmith's suite is generated, its ids the seeds
(section 3). Fetched inputs (`<suite>/fetch/`) and converted
output (`<suite>/work/`) are gitignored; only the runner and its two state files are tracked.

## 1. File charters

- `suite_runner.das` - the runner every suite shares: `run_suite_main(spec, verdict)` converts
  every `<id>.c` directly under the suite's tests folder into `work/<id>/` through
  `converter/pipeline.das` under the `linux` dialect (the baseline of a differential run is a
  native build on this host), runs the module under `--tier` (`SUITE_TIERS`: `interp`, the
  default, `jit` or `exe`) with both module folders loaded and a per-suite timeout in
  `work/<id>/` (a file the C program writes, c-testsuite 00187's `fred.txt`, lands there, never in
  the tree; the run's JIT and module caches too), and hands
  the exit code and merged output to the suite's verdict. The ratchet is the interpreter's: a
  `jit` or `exe` run judges the same list, so its regressions are the ids that pass under the
  interpreter and fail under that tier, and `tier_refusal` refuses an unknown tier and
  `--update` under any tier but `interp` (exit 2). The run's children log at `warning`
  whatever `DAS_LOG_LEVEL` the runner has: the JIT and the exe build report themselves at
  `info`, and their lines would join the output a verdict judges. Every tier writes the same
  `work/<id>/` folders and `work/skip_audit.tsv` (csmith: `work/<seed>/` and its verdict), so two
  runs of one suite under different tiers never run at the same time. Each test ends in one status: `pass`, `convert` (the dumper, the emitter or the
  compile check refused it), `timeout` (the module ran past the suite's limit), `exit`,
  `output`, or `skip`. The ratchet and the ledger live
  here too: a listed id that stops passing fails the run; an id that starts passing is
  reported, and `--update` rewrites the file as the ids the run passed, so a listed id that
  failed leaves it while the run exits 1; a failing test that is not listed is a count in the
  summary, not a skip. `--audit-skips` (`audit_suite`) runs the ledgered ids alone
  (`audited_lines`: each id once, sorted), as an unlisted id would run, and does not judge the
  ratchet: `finish_audit` writes `work/skip_audit.tsv` (id, feature, status, the reason's first
  line) and logs the tally per feature, where `audit_status` names a `convert` by the stage its
  error names (`dumper`, `emitter`, `compile`) and an `output` as `mismatch`, and a ledgered id
  with no `.c` file is `missing`; the csmith driver's `--audit-skips` judges its ledgered seeds
  the same way, its own `native` (the native build or run failed) and `crash` (a worker ended
  without a verdict) passing through. With `--update` an audit only adds to the ratchet
  (`join_audit_passes`): the ids that passed join, sorted, and nothing leaves; their skip lines
  stay until the ledger is rewritten, by `gcc_torture/filter.das` for the torture suite and by
  hand for csmith's. Its pieces serve the csmith driver too: `record` and `count_status` (one outcome into the `Tally`),
  `finish_run` (the summary, `--update`'s write of the ids it is handed unless the run was
  filtered, the exit code), `convert_and_run` (one C file converted and run under a
  tier, with extra interpreter or JIT flags when a suite needs them), `tier_refusal`, `compare_output` (an
  exit code and output judged against the expected output), and `run_workers` with
  `spawn_one` (indices through worker processes of a script's `--one` and the worker's own
  arguments, csmith's `--tier`, a number at a time, each
  killed past a limit, its printed output kept), which the readability metric runs on too;
  `C_TESTSUITE_TESTS` and `GCC_TORTURE_TESTS` name the folders the two file-based suites'
  tests sit in.
- `suite_files.das` - what the suites and the readability metric agree on, needing no module
  folder so the `REVIEW.das` gates require it: `read_lines` and `read_ratchet` (the ratchet and
  the ledger as a run reads them), `c_file_ids` (the `.c` files of a folder by id, the suites'
  tests and the perf kernels), `phase_well_formed` (a phase column is `never` or a row id,
  `P<n>` or `P<n>.<m>` with at most one lowercase letter after `<m>`), `phase_number`,
  `highest_closed_phase` and `names_closed_phase` (the closed-phase check of `REVIEW.das`), `expected_input_keys` (the input keys the readability capture
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
- `gcc_torture/filter.das` - the import's filter, run by hand after a fetch and after a change to
  the ratchet: `skip.txt` gets a line for every top-level `execute/*.c` the first of the `RULES`
  in `gcc_torture/filter_rules.das` matches, less the ids `expected_pass.txt` lists
  (`skip_lines`), since a test that passes is judged, never skipped (a rule can only read the
  text; the ratchet knows what runs), so the file is reproducible from the filter and the
  ratchet. Both directions follow: an id an audit's `--update` adds to the ratchet loses its line
  at the next rewrite, and an id taken out of the ratchet by hand gets its line back when a rule
  matches it. The rules fire in their table order, the first match naming the line: the
  constructs no emulation reaches (asm with template text or operands, `-finstrument-functions`,
  the argument forwarding builtins, the builtins clang does not know, a variable-length array in
  a block-scope struct, frame and return addresses, the non-standard floating types, atomics and
  thread-local storage, a function defined inside a function) with the phase `never`, then the rules naming a ledger row (a test asking
  gcc for `-std=gnu89` or `-fpermissive`, or calling `__builtin_exit`, which only the permissive
  flags declare, under P7.8; `_Complex`, wide literals and a block-scope function declaration
  under P7.5; `__int128`, vectors, labels as values, an attribute
  outside the dumper's dropped list (`attribute_names`), `packed` or `aligned` alone, the
  setjmp builtins and any `__builtin_*` the emitter does not map (`unmapped_builtins`) under
  P7.6). A test that fails for a reason no rule can read is an ordinary failure the run counts.
  The `builtins/` and `ieee/` subfolders are not part of the suite.
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
- `csmith/run.das` - the differential driver (section 3): its own `main` over the shared
  runner's pieces, one worker process per seed (`--one <seed>`), the judge of a generated
  program the reducer calls (`--check <file>`), and the nightly run (`--nightly`, section 4).
- `csmith/nightly.das` - the nightly run's pieces (section 4): `night_generator` and
  `nightly_seeds` (the seeds a start seed draws), `date_start` and `parse_start` (the start a
  date or `--start` names), `night_status`, `nightly_verdict`, `is_judged`, `fails_night` and
  `keeps_files` (a seed's status as the night counts it, whether it counts toward N, fails the
  night, keeps its work folder), `draw_cap`, `night_refusal`, `nightly_report`,
  `nightly_result_path`, `write_atomically` and `nightly_exit_code`.
- `csmith/generate.das` - a seed's program (section 3): `csmith_program` runs the pinned csmith
  with `CSMITH_OPTIONS` and splices the runtime headers in; the driver and the readability
  metric generate through it.
- `csmith/verdict.das` - a seed's verdict file (`<seed>.verdict`, written and read) and
  `worker_outcome`, the outcome the driver draws from a worker that ended: its verdict,
  `timeout` when the driver killed it, `crash` when it exited without a verdict.
- `csmith/reduce.sh <seed> [reducer]` - the minimization harness (section 3): judges the seed
  afresh, writes the interestingness test `work/<seed>/interesting.sh`, runs the reducer (cvise
  by default) and leaves the result at `work/<seed>/min.c`.
- `<suite>/expected_pass.txt` - the ratchet: the sorted ids that pass.
- `<suite>/skip.txt` - the ledger of tests never run: one tab-separated line per id with the
  feature, the reason and the ledger row (`P<n>.<m>`) or phase that unblocks it, `never` for a
  feature no row will lift.
- `REVIEW.das` - the gate over the three suites: `expected_pass.txt` sorted and unique, every
  `skip.txt` line in the four-field shape with a row id or `never` (`phase_well_formed`), no line naming a closed phase
  (`names_closed_phase` in `suite_files.das`: a phase at or below the highest `v0.<N>.0` tag the
  repository carries, `highest_closed_phase`, never below `CLOSED_PHASE_FLOOR`, 4, since a
  shallow clone carries no tag), the same two checks over the `phase` of every `RULES` entry of
  `gcc_torture/filter_rules.das`, no id in both files, every csmith id a decimal seed, nothing tracked under a suite's `fetch/` or `work/`, and the
  module keys of `metrics/readability_linux.json` the expected input keys, so a diff to a
  ratchet list re-records the readability capture.
- `scripts/run_suite.sh <suite> [flags]` - fetches when needed and runs the runner from the
  repository root with `-load_module` for `dasCRuntime` and `c_runtime`.

## 2. Why the suites are not preflight gates

A full c-testsuite run converts every test file and spawns clang and daslang for each, about a
minute on this box; the torture suite converts every test its ledger does not skip, and a csmith
seed takes up to a minute to convert. The preflight `tests` lane stays the sub-second dastest
suites. The runners keep their own ratchet and run on their own schedule, the way
`docs/very-detailed-plan.md` section 8 describes.

## 3. The csmith run

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

The reference is the gcc `VERSIONS.md` pins, run as the `CC` environment variable (`gcc` when it
is unset or empty, `reference_compiler` in `csmith/verdict.das`), which the run checks against
`$CC -dumpfullversion` before it starts, at `-O0 -fwrapv -w -funsigned-char`: the dialect's wrapping
overflow and unsigned `char` (`converter/ARCHITECTURE_DUMPER.md`). The converter's own fixtures
build their natives with the pinned clang at its default level and no `-fwrapv`, which suits a
hand-written fixture with no overflow; a csmith program exercises every integer width and the
dialect's wrapping, so the oracle states `-fwrapv` and `-O0` outright (no optimization folds an
expression another way) and pins its compiler, gcc, whose version the run checks. A
native run gets 2 seconds, since the interpreter runs csmith's code a hundred times slower; a
gcc refusal or a non-zero native exit ends the seed as `native`, which is no divergence. The
converted module runs under `--tier` (the interpreter unless given; every worker of a run gets
the driver's tier) with both module folders loaded,
`-no-module-cache` (a seed's module is never compiled twice, so a cache record would only churn
the cache the test lanes share, and a cache message on stdout would be judged as output) and
300 seconds, and its complete merged output is compared with the native one. The default 16 KB
context stack holds the csmith programs the run converts, so the run writes no sidecar `stack`;
one would go beside the program as `<seed>.c2das`.

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
so the worker ends inside the driver's limit and the driver's kill does not land while a timed
child is alive: daScript's timed process capture starts each child in a process group of its own,
and a kill of the worker's group misses it.

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

## 4. The nightly run

`run.das --nightly` is the V3 schedule (`docs/very-detailed-plan.md`, clean at N=1000 a night).
It judges `--seeds` fresh seeds (1000 unless given) and nothing else: the ratchet and the skip
ledger are neither read nor written, a seed either list holds is judged like any other, and a
timeout is not retried. The flags it takes are `--seeds`, `--start`, `--jobs`, `--tier` and
`--force`; beside `--update`, `--audit-skips`, `--seed`, `--from`, `--filter`, `--one` or
`--check`, with `--seeds` 0 or below, or with a start that is no decimal of at most nine digits
it exits 2 before any seed.

The seeds come from one sequence per start (`nightly_seeds`): the `daslib/random` generator
seeded with a hash of the start in each lane (`night_generator`), so the same start draws the
same seeds in the same order, a longer night begins with a shorter one's seeds, and consecutive
starts draw unrelated seeds (`random_seed(start)` would make one night's low bits the previous
night's high bits). The start is the UTC date's digits (`20261122`) unless `--start` names one.

Each seed runs through the same worker as the ratchet's run (`--one`, under `--tier`, the
interpreter unless given) and its verdict maps onto the night's (`night_status`,
`nightly_verdict`): `pass`, `differs` (`output` or `exit`), `refused` (`convert`), `timeout`
(the conversion or the converted run past its limit after the native side passed, or a worker
the driver killed), `crash`, `native` (gcc refused the program or its run exited non-zero) and
`native-timeout` (csmith or the native run past its limit: csmith writes programs whose gcc
`-O0` build runs for minutes). The first five are judged seeds; `native` and `native-timeout`
are the reference side's and never count. N is a count of judged seeds: the night draws from the
sequence in rounds, each round the seeds still missing, until N are judged or `draw_cap` (1.5 N)
seeds are drawn, and the result file says so when the cap stops it.

The result file is `work/nightly/<date>-<start>.txt` (`-<tier>` added for a tier but the
interpreter), written through a temporary file and a rename after every seed, so a night cut
short still reports what it judged and a reader never sees half a file. It holds a header
naming the start, the seeds asked, the tier, the reference compiler, the csmith commit and
options, the c2das-re and daScript commits (`+dirty` when a tracked file differs) and the
command that replays the night; the line `judged X of N asked, drew Y, native-timeout Z`; the
draw cap; the wall time; a count per verdict; the seeds of each verdict in draw order; and for
each failure or crash its first reason line and folder, a divergence also its two outputs and
its `reduce.sh` line. Two runs of one night differ in the wall line alone. The run exits 1 when
any seed `differs` or has a `timeout`, else 0.

A night runs once per date and start: a lock file beside the result names the driver's pid, and
a second night of that date and start is refused while that process lives; an existing result
file refuses it too unless `--force` names the rerun.

A seed that differs, timed out or crashed keeps its `work/<seed>/` folder: the spliced program,
the conversion, and for a divergence the native and converted outputs `judge` writes beside the
program (`<seed>.native.out`, `<seed>.das.out`) whenever a converted run does not pass. Every
other seed's folder, a native timeout's included, is removed as soon as its worker ends, since
its program regenerates from its number; a seed's folder is about 9 MB, and a thousand of them
would fill the disk. No reduction runs inside the night: `reduce.sh <seed>` takes a listed
divergence afterwards.

To replay a night, run the header's replay line with `--force` beside the old file, or move the
file away; to replay one seed of it, `run_suite.sh csmith --seed <seed>`. The JIT is not part
of the night: a seed's cost is its conversion, which a second tier repeats (25 s a seed under
the interpreter, 26 s under the JIT, measured on one ratchet seed), so a JIT night is the same
replay line with `--tier jit` and doubles the box time.

The night runs on this box as a queued job; no scheduler is installed. A worker holds a seed's
conversion in memory (clang's dump of a csmith program is about 170 MB), and three workers with
the driver peak near 3.5 GB, so a 4 GB scope runs three, and a night of 1000 seeds takes
about 70 minutes:

    heavy --low --label csmith-nightly --max 4G -- env CC=gcc-14 scripts/run_suite.sh csmith --nightly --jobs 3
