# lua Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
converts Lua 5.4.8 (MIT), the interpreter `lua` and the compiler `luac`, as whole programs: the
release is fetched, never committed, and each program is converted from its separate C files as the
Makefile builds it, linked by the converter, in each of its layouts: a module per C file with the
cycles cut by late binding (the source layout, the default), a module per C file with every cycle
one module (the scc layout), and one module (the single layout).

## 1. File charters

- `fetch.sh` - downloads the release tarball and the test-suite tarball the `lua:` line of
  `VERSIONS.md` names into `fetch/` unless present, checks each against the line's sha256 and
  refuses a mismatch, and extracts them into `fetch/lua-5.4.8/` and `fetch/lua-5.4.8-tests/`.
- `profile.das` - the profile the source layout's cycle cut weighs by (section 5), written to
  `lua.profile.json`.
- `lua.profile.json` - that profile, committed beside the sidecar, which names it.
- `sources.das` - the release's sources as the Makefile links each program (section 2):
  `program_sources`, the C files of `lua` or `luac` in link order, and the sidecar's path, which
  `run.das` converts and `metrics/readability.das` (repo root) measures.
- `run.das` - writes each program's manifest `work/<stem>.program.json` (section 2), converts the
  program it names through `converter/pipeline.das`'s `convert_program` with `lua.c2das` as the
  sidecar, the compile check included, in each layout `--layout` names (`all`, the default,
  `source`, `scc` or `single`): the source layout into the tree `work/<stem>/`, its entry
  `work/<stem>/<stem>.das`, the scc layout into `work/scc/<stem>/`, the single layout into
  `work/single/<stem>/<stem>.das`, a folder each so each run's module caches stay apart; it reports the numbers of section 4 per layout, an error at
  the Lua source and line the dumper names. `--native` builds each native oracle from the same
  sources into `work/<stem>_native`; `--run` runs the converted interpreter of each layout under
  the tier `--tier` names (`interp`, the default, or `jit`) with each `--arg` (default `-e
  "print(1+1)"`; a script is `--arg <path>`) and compares it with the oracle; `--luac-check
  <folder>` compiles every `.lua` file of the folder with the converted compiler of each layout
  under the tier, `-o` into `work/<stem>/luac_check/` (`work/single/luac/luac_check/` for the single
  one, `work/scc/luac/luac_check/` for the scc one), and compares the bytes and the exit code with the native compiler's, refusing a folder with
  no script; `--filter <stem>` converts that program alone. Run from the repository root: `daslang
  -load_module dasCRuntime -load_module c_runtime lua/run.das -- [--native] [--run] [--tier jit]
  [--luac-check lua/fetch/lua-5.4.8-tests]`.
- `lua.c2das` - the sidecar both programs convert under (section 3).
- `REVIEW.das` - the mechanical gate: no file under `fetch/` or `work/` is tracked.

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
`scc` of 28 and 17 modules, the 15 core files that call each other one module, `lcode_cluster.das`,
and the headers whose records point at each other two (`lobject.h lstate.h lua.h`, `llex.h
lparser.h`); in `source` of 43 and 32 modules, the core's cycles cut by late binding through
`lua_link.das` and `luac_link.das` (64 symbol-edge cuts of 51 functions on 34 edges, `program.layout.txt` beside the
modules), only the two header clusters left. The build is the ANSI one, no `LUA_USE_*` platform macro: `lua_Integer`
is `long long`, `lua_Number` `double`.

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
- `defines`: `luai_jmpbuf=int`, `LUAI_THROW(L,c)=abort()` and `LUAI_TRY(L,c,a)={ a }`, the stub of
  Lua's error recovery: `ldo.c` defines the three only when `LUAI_THROW` is not defined, and its
  ISO definitions hold a `jmp_buf` in `struct lua_longjmp` and call `setjmp` and `longjmp`, the
  setjmp lowering that is P5.2's item (`docs/implementation_order.md`). With the stub a script
  that raises no Lua error runs, and a Lua error aborts the process where the native build
  recovers; the stub stands until P5.2 lowers the three.
- `layout`: `{"profile": "lua.profile.json"}`, the counts the source layout's cycle cut weighs its
  edges by (section 5); no `threshold`, since the late-bound calls cost 2 to 3 percent under the
  JIT and nothing measurable under the interpreter (`docs/implementation_order.md` P5.1b2).
- `over_indexed`: `TString.contents`, `Udata.uv`, `CClosure.upvalue` and `LClosure.upvals`, the
  C89 `T a[1]` trailing arrays `lobject.h` indexes past their length over a larger allocation (a
  string's bytes, a userdata's user values, a closure's upvalues); das would range-check them at
  one element.

## 4. The numbers

Each conversion prints `[I]` lines: the dumper's seconds over all the program's files (clang's
JSON dump, the libclang pass, the parse of the JSON and the walk, file by file) and the bytes of
clang's JSON summed; then, when every dump succeeds, the link's seconds with how many declarations
bound to another file's definition, how many statics it renamed (a line each) and how many header
functions it kept once, the emitter's seconds (the formatter included), the compile check's seconds (daslang
compiling the module with its default policies, as `convert` checks it), the lines of the `.das`
module and how many of its functions carry `[c_function]`. Each line names the program and the
layout (`lua: lua (source): ...`); in the source layout the lines of das are those of every module
and fragment, and the report adds the count of modules and fragments and a line per module, its
members when it is a cluster, while the edges that tie each cluster's members, with the names that
make each, go to `partition <stem> (source): ...` lines. `--native` adds each oracle's size in
bytes.

## 5. The profile {#profile}

The source layout cuts the cycles of Lua's core where the cut is cheap, by the calls a run makes
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
release and clang `VERSIONS.md` pins, the commit that last wrote the file being its git history; a
change of the pinned release reruns it.
