# lua Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
converts Lua 5.4.8 (MIT), the interpreter `lua` and the compiler `luac`, as whole programs: the
release is fetched, never committed, and each program is converted from its separate C files as the
Makefile builds it, linked by the converter, in each of its layouts: a module per C file with the
every cycle one module (the source layout, the default), a module per C file with the cycles cut by
late binding (the source-cut layout), and one module (the single layout).

## 1. File charters

- `fetch.sh` - downloads the release tarball and the test-suite tarball the `lua:` line of
  `VERSIONS.md` names into `fetch/` unless present, checks each against the line's sha256 and
  refuses a mismatch, and extracts them into `fetch/lua-5.4.8/` and `fetch/lua-5.4.8-tests/`.
- `profile.das` - the profile the source-cut layout's cycle cut weighs by (section 5), written to
  `lua.profile.json`.
- `lua.profile.json` - that profile, committed beside the sidecar, which names it.
- `sources.das` - the release's sources as the Makefile links each program (section 2):
  `program_sources`, the C files of `lua` or `luac` in link order, and the sidecar's path, which
  `run.das` converts and `metrics/readability.das` (repo root) measures.
- `run.das` - writes each program's manifest `work/<stem>.program.json` (section 2), converts the
  program it names through `converter/pipeline.das`'s `convert_program` with `lua.c2das` as the
  sidecar, the compile check included, in each layout `--layout` names (`all`, the default,
  `source`, `source-cut` or `single`): the source layout into the tree `work/<stem>/`, its entry
  `work/<stem>/<stem>.das`, the source-cut layout into `work/source-cut/<stem>/`, the single layout into
  `work/single/<stem>/<stem>.das`, a folder each so each run's module caches stay apart (`--switch-dispatch` hands the converter's
  option on, `lua.c2das` leaving it at `chain`; under `goto` each layout's folder sits under `work/goto/`, so
  the two conversions and their caches stay apart; `--variant <file>` converts under the variant's
  sidecar, `lua.c2das` with the knobs of `ports/variants/lua.<variant>.json` set
  (`ports/ARCHITECTURE_VARIANTS.md`), written to `work/variants/<variant>/lua.c2das`, each layout's
  folder, its `goto/` and its test-suite verdicts then under `work/variants/<variant>/`); it reports
  the numbers of section 4 per layout, an error at the Lua source and line the dumper names.
  `--native` builds each native oracle from the same sources into `work/<stem>_native`; `--run` runs
  the converted interpreter of each layout under the tier `--tier` names (`interp`, the default, or
  `jit`) with each `--arg` (default `-e "print(1+1)"`; a script is `--arg <path>`) and compares it
  with the oracle, which runs under the name `lua`, the `argv[0]` the converted program gets and
  Lua's messages quote; `--luac-check <folder>` compiles every `.lua` file of the folder with the
  converted compiler of each layout under the tier, `-o` into `work/<stem>/luac_check/`
  (`work/single/luac/luac_check/` for the single one, `work/source-cut/luac/luac_check/` for the source-cut one),
  and compares the bytes and the exit code with the native compiler's, refusing a folder with no
  script; `--error-check` runs the converted interpreter of each layout under the tier with each of
  `run.das`'s `ERROR_CHECKS` (an error caught by `pcall`, one uncaught, nested protected calls, an
  error the VM raises, a table as the error object, an error in a coroutine, `xpcall`'s handler, a
  memory error) and compares each with the oracle; `--suite-check` runs the release's test suite
  with the converted interpreter of each layout under the tier, file by file against the oracle,
  each run in a memory-capped scope (`--suite-memory`, default `4G`) under `--suite-timeout` seconds
  (default 1800), the verdicts to `work/<layout>/suite.txt`, each side's `lua` on `PATH` to
  `work/native_bin/` and `work/<layout>/bin/`; `--suite-filter <file>` runs one file of it,
  `--suite-port` (`true`, the default, or `false`) the value of the global `_port` each file gets
  (section 6); `--run`, `--error-check` and `--suite-check` compare the exit code, stdout and
  stderr, the two streams apart, each run's stderr going to `work/run.stderr`, read and removed
  after the run, its stdin a pipe whose writer has exited (it reads at its end at once and does not
  seek), and the JIT's `[I]` lines, which land on stdout, dropped from it; `--filter <stem>`
  converts that program alone; a run of more than one conversion makes each in a process of its own
  (section 7). Run from the repository root: `daslang -load_module dasCRuntime
  -load_module c_runtime lua/run.das -- [--native] [--run] [--error-check] [--suite-check] [--tier
  jit] [--luac-check lua/fetch/lua-5.4.8-tests]`.
- `lua.c2das` - the sidecar both programs convert under (section 3).
- `REVIEW.das` - the mechanical gate: no file under `fetch/` or `work/` is tracked, and `SOURCES` in
  `sources.das` names the folder of the release the `lua:` line of `VERSIONS.md` pins.

## 2. The programs {#program}

`work/lua.program.json` names the sources of the Makefile's `CORE_O`, then those of its `LIB_O` (the
auxiliary library `lauxlib.c` and the standard libraries, `linit.c` last), then `lua.c`;
`work/luac.program.json` the same core and `lauxlib.c`, then `luac.c`. The compiler calls none of
the standard libraries, so the Makefile's link of the archive pulls none into it, and neither does
its manifest. Each manifest lists the full paths of the release's own `src/` files in link order
and `"entry": "main"`; the converter dumps every file as its own translation unit, with the macros
the file defines itself (`LUA_CORE`, `LUA_LIB`, `lua_c`, `luac_c`), and links them
(`converter/ARCHITECTURE_LINK.md`): in the single layout the program's module is named by the file
holding `main`, `lua.das` and `luac.das`; in the module-per-file layouts
(`converter/ARCHITECTURE_LAYOUT.md`) `lua.das` and `luac.das` are the entry modules of a tree: in
`source` the core files that call each other are one module, `lcode_cluster.das`, and the headers
whose records point at each other two (`lobject.h lstate.h lua.h`, `llex.h lparser.h`); in
`source-cut` the core's cycles are cut by late binding through `lua_link.das` and `luac_link.das`,
only the two header clusters left. Each tree's `program.layout.txt`, beside its modules, lists
the modules, each cluster's members and every cut. The build is the ANSI one, no `LUA_USE_*`
platform macro: `lua_Integer` is `long long`, `lua_Number` `double`.

The headers stay in the release's `src/`: the converter takes a declaration as the program's when
its file is under the main file's directory (`converter/ARCHITECTURE_DUMPER.md`, "The program's
files"), and every Lua source and header shares that directory. Within either program no two files
define a static of one name and no static is named like a name another file references or the
converter maps to libc, so the link renames nothing; `luac.c` and `lstrlib.c` both define a
static `writer`, which the link would rename `luac_writer` and `lstrlib_writer` were both in one
module of one program.

## 3. The sidecar keys

- `defines`: `LUA_USE_JUMPTABLE=0`. `lvm.c` turns on its computed-goto dispatch (`ljumptab.h`,
  `&&L_OP_MOVE`, a GNU extension outside the dialect) whenever `__GNUC__` is defined, which
  clang defines; `0` selects the `switch` dispatch every ISO compiler gets.
- No define touches Lua's error recovery: neither `LUA_USE_LINUX` nor `LUA_USE_POSIX` is defined
  (the native oracle is built without them too), so `ldo.c` takes its ISO C definitions, a `jmp_buf`
  in `struct lua_longjmp`, `LUAI_TRY` as `if (setjmp((c)->b) == 0) { a }` and `LUAI_THROW` as
  `longjmp((c)->b, 1)`. The converter's setjmp lowering takes both (`converter/ARCHITECTURE_EMITTER.md`
  "setjmp / longjmp"): `luaD_rawrunprotected` is the single-branch trampoline, `luaD_throw` a
  `c_longjmp` through the handler chain, and `struct lua_longjmp` keeps clang's layout with a
  padding field after its `CJmpBuf`. A Lua error is caught as the native build catches it under the
  interpreter; under the JIT the trampoline's `return lj.status` leaves only its `try` arm
  (`docs/probe-findings.md` F75), so every protected call reports success there.
- `layout`: `{"profile": "lua.profile.json"}`, the counts the source-cut layout's cycle cut weighs its
  edges by (section 5); no `threshold`, since the late-bound calls cost 2 to 3 percent under the
  JIT and nothing measurable under the interpreter (`docs/implementation_order.md` P5.1b2).
- `over_indexed`: `TString.contents`, `Udata.uv`, `CClosure.upvalue` and `LClosure.upvals`, the
  C89 `T a[1]` trailing arrays `lobject.h` indexes past their length over a larger allocation (a
  string's bytes, a userdata's user values, a closure's upvalues); das would range-check them at
  one element.
- `jit_whole_program`: true, so each layout's entry module pins the cached JIT's DLL to one LLVM
  module (`converter/ARCHITECTURE_EMITTER.md` section 4): the source layout's 30 modules then keep
  the inlining across modules that the default partition per das module loses (the `lobject_h_cluster`
  accessors, called from every core file), which is what the ports' `jit` lanes measure
  (`ports/ARCHITECTURE.md` section 4). The interpreter, the exe and AOT ignore the pin.

## 4. The numbers

Each conversion prints `[I]` lines: the dumper's seconds over all the program's files (clang's JSON
dump, the libclang pass, the parse of the JSON and the walk, file by file) and the bytes of clang's
JSON summed; then, when every dump succeeds, the link's seconds with how many declarations bound to
another file's definition, how many statics it renamed (a line each) and how many header functions
it kept once, the emitter's seconds (the formatter included), the compile check's seconds (daslang
compiling the module with its default policies, as `convert` checks it), the lines of the `.das`
module and how many of its functions carry `[c_function]`. Each line names the program and the
layout (`lua: lua (source): ...`); in the module-per-file layouts the lines of das are those of every module
and fragment, and the report adds the count of modules and fragments and a line per module, its
members when it is a cluster, while the edges that tie each cluster's members, with the names that
make each, go to `partition <stem> (source): ...` lines. `--native` adds each oracle's size in
bytes.

## 5. The profile {#profile}

The source-cut layout cuts the cycles of Lua's core where the cut is cheap, by the calls a run makes
(`converter/ARCHITECTURE_LAYOUT.md`, "The cycle cut"). `profile.das` measures them: it compiles
every file of `lua` with the pinned clang at `-O0 -fno-pie -finstrument-functions`, each file apart
so its functions name it (`nm`), links them `-no-pie` with a counting runtime (each callee and call
site counted in an open-addressed table, written at exit), and runs the release's test suite
(`-e "_port=true" all.lua` in the test folder, the real error recovery in place) and the four
benchmark scripts of `ports/lua/bench/` at their default sizes. Each call site resolves to the
function holding it, so a count is a callee's calls from one file; `lua.profile.json` keeps every
call that crosses files, by callee and calling file's stem, sorted. `luac` shares the core and its
profile. The conversion depends on the file only through the sidecar naming it. The file's
provenance is its command and its inputs: `profile.das` run from the repository root over the
release, clang and `nm` `VERSIONS.md` pins (an `nm` of a version the pin does not list, a failed
listing or an empty one refused), the commit that last wrote the file being its git history.

## 6. The test suite

`--suite-check` runs the test suite of the release, `fetch/lua-5.4.8-tests/`, file by file: each
file `all.lua` runs, in its order, with the globals it sets for them (`-e "_port=true" <file>`, so
the tests that assume a POSIX build skip; `--suite-port false` gives `_port=false`, which runs them
against the same ANSI build natively, `main.lua` then running the interpreter by its `argv[0]`
through `os.execute`; `_soft` stays false, so the long tests run; `T`, the debug build's test
library, is absent), `big.lua` as `all.lua` runs it (a coroutine whose yields are checked, since the
file yields at its top level), then `all.lua` itself. `main.lua` returns at once under `_port`, and
`heavy.lua`, which `all.lua` never runs, is no file of the lane. Each file runs first with the
native oracle, then with the converted interpreter, both in the suite's folder with a pipe at its
end as stdin (`files.lua`'s invalid-seek check expects `io.stdin:seek` to fail, which `/dev/null`,
`run_and_capture`'s own stdin, does not), each with a `lua` of its own side first on `PATH`
(`work/native_bin/lua`, a link named `lua` to the oracle, the name the nested runs look up;
`work/<layout>/bin/lua`, a script running the converted interpreter of the layout under the tier
with its arguments), which `main.lua` runs through `os.execute` under `_port=false`, each under the
memory cap `--suite-memory` names (anything systemd's `MemoryMax` takes, which the prlimit tier
needs as bytes with K, M, G or T) and under `--suite-timeout` seconds. The cap is the first of three
the lane can apply, each probed with `true` before the first run: a scope of the system manager
(`systemd-run --scope --collect -p MemoryMax=<memory> -p MemorySwapMax=0`, root's: a cgroup cap with
swap excluded, which the kernel enforces by killing the run, and the scope is unloaded when it
ends), the same scope of the user's own manager (`systemd-run --user`, a user with one running), or
the address-space limit `prlimit --as=<bytes>` sets (any user, the CI runner's `gha` among them),
under which an allocation past it fails and `lua.c` exits with `not enough memory`, which the lane
reads as the cap ending the run; a run the limit ends elsewhere than in `malloc` (the daslang
runtime's own allocations, where the converted interpreter dies with a signal) reads as `fail` with
its exit code. The verdict is `pass` when the exit codes agree and stdout and stderr each agree line
by line once every number reads as one, whatever its sign or notation (the suite prints random
seeds, timings and the date, `%g` picking the notation by the value), and every line of dots alone
as one dot (the progress dots of `all.lua`'s collections run as long as the collector's timing makes),
and without the warning `all.lua` prints when its time differs from the one the previous run left
in `time.txt` of the folder, the other build's: the warning goes with the newline ending it, so a
warning among the progress dots, which go on after it, leaves the dots on either side joined on
one line, and one on its own line leaves no line; `fail` with the first line that differs, stdout before stderr, quoted
from both runs and naming its stream, or the two exit codes; `timeout` or `memory` naming the run
the timeout or the cap ended, or `oracle` with the exit code and the first non-empty line of the native stderr, stripped,
when the native build fails on its own (in both the converted one does not run: an oracle's failure
never passes by agreement); `missing` for a file the folder lacks. The verdicts go to
`work/<layout>/suite.txt`, a line `<file> <verdict> <seconds of the converted run> [<detail>]` per
file, and the totals to a `lua: suite under <tier> (<layout>): ...` line. A cap none of the three
applies (`--suite-memory lots`: no manager takes it, and it is no byte count) refuses the lane
before any run, naming each attempt, as does a `lua` launcher the lane cannot write.

## 7. A process per conversion {#apart}

A daslang context keeps every string it allocates until the process exits, unless the code frees it
(the dumper frees clang's JSON text once parsed), and its heaps never shrink, so the conversions of
one process add up: each conversion of `lua` holds about 1.4 GB at its peak, and the six of a plain
`run.das` (two programs, three layouts) would hold about their sum in one process. A run that makes
more than one conversion therefore makes each in a process of its own: `run.das` writes each
program's manifest and builds its oracle, then runs itself once per layout with its own arguments
and `--filter <stem> --layout <layout> --oracle-built` last, which override any earlier ones, a `--`
before them when the run had none; the child shares its stdout and stderr, whose lines `to_log`
flushes one by one, so the report is the one a single process prints, line for line and in order.
`--oracle-built` marks the child: it skips the oracle build, so the oracle is built once per
program, refuses a run whose oracle is missing, and converts in its own process whatever else its
arguments name, so no child starts another. A child that does not exit 0 fails the run and is logged
as `lua: <stem> (<layout>): the conversion process exited <code>` or `was killed by signal <n>`, the
next layout still converted; one ended by SIGINT stops the run, which starts no further conversion.
A run of one conversion (`--filter` and a single `--layout`) converts in its own process.
