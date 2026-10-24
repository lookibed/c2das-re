# lua Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
converts Lua 5.4.8 (MIT), the interpreter `lua` and the compiler `luac`, as whole programs: the
release is fetched, never committed, and each program is converted from its separate C files as the
Makefile builds it, linked by the converter into one module.

## 1. File charters

- `fetch.sh` - downloads the release tarball and the test-suite tarball the `lua:` line of
  `VERSIONS.md` names into `fetch/` unless present, checks each against the line's sha256 and
  refuses a mismatch, and extracts them into `fetch/lua-5.4.8/` and `fetch/lua-5.4.8-tests/`.
- `run.das` - writes each program's manifest `work/<stem>.program.json` (section 2), converts the
  program it names through `converter/pipeline.das`'s `convert_program` into `work/<stem>/<stem>.das`
  with `lua.c2das` as the sidecar, the compile check included, and reports the numbers of section 4,
  an error at the Lua source and line the dumper names; `--native` builds each native oracle from
  the same sources into `work/<stem>_native`, `--run` runs the converted interpreter under the tier
  `--tier` names (`interp`, the default, or `jit`) with each `--arg` (default `-e "print(1+1)"`; a
  script is `--arg <path>`) and compares it with the oracle, and `--filter <stem>` converts that
  program alone. Run from the repository root: `daslang -load_module dasCRuntime -load_module
  c_runtime lua/run.das -- [--native] [--run] [--tier jit]`.
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
(`converter/ARCHITECTURE_LINK.md`): the program's module is named by the file holding `main`,
`lua.das` and `luac.das`. The build is the ANSI one, no `LUA_USE_*` platform macro: `lua_Integer`
is `long long`, `lua_Number` `double`.

The headers stay in the release's `src/`: the converter takes a declaration as the program's when
its file is under the main file's directory (`converter/ARCHITECTURE_DUMPER.md`, "The program's
files"), and every Lua source and header shares that directory. Within either program no two files
define a static of one name and no static is named like a name another file references or the
converter maps to libc, so the link renames nothing; `luac.c` and `lstrlib.c` both define a
static `writer`, which the link would rename `luac_writer` and `lstrlib_writer` were both in one
program.

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
module and how many of its functions carry `[c_function]`. `--native` adds each oracle's size in
bytes.
