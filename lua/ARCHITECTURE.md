# lua Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
converts Lua 5.4.8 (MIT), the interpreter `lua` and the compiler `luac`, as whole programs: the
release is fetched, never committed, and each program is composed into one C file the converter
takes as one translation unit.

## 1. File charters

- `fetch.sh` - downloads the release tarball and the test-suite tarball the `lua:` line of
  `VERSIONS.md` names into `fetch/` unless present, checks each against the line's sha256 and
  refuses a mismatch, and extracts them into `fetch/lua-5.4.8/` and `fetch/lua-5.4.8-tests/`.
- `run.das` - composes `work/lua_all.c` and `work/luac_all.c` (section 2), converts each through
  `converter/pipeline.das`'s `convert` with `lua.c2das` as the sidecar, the compile check
  included, and reports the numbers of section 4, an error at a line of the composed file with
  the Lua source line beside it (`lobject.c:264`, by the banner above the line); `--native`
  builds each native oracle into
  `work/<stem>_native`, `--run` runs the converted interpreter under the tier `--tier` names
  (`interp`, the default, or `jit`) with each `--arg` (default `-e "print(1+1)"`; a script is
  `--arg <path>`) and compares it with the oracle. Run from the repository root: `daslang
  -load_module dasCRuntime -load_module c_runtime lua/run.das -- [--native] [--run] [--tier jit]`.
- `lua.c2das` - the sidecar both programs convert under (section 3).
- `REVIEW.das` - the mechanical gate: no file under `fetch/` or `work/` is tracked.

## 2. The composition {#composition}

`work/lua_all.c` is `#define LUA_CORE`, `#define LUA_LIB` and `#define lua_c`, then the sources
of the Makefile's `CORE_O` and `LIB_O` in its order and `lua.c`, each under a `/* ==== name.c
==== */` line. `work/luac_all.c` holds `luac_c` in place of `lua_c`, the core sources and
`lauxlib.c`, then `luac.c`: in one translation unit `luac.c`'s static `writer` clashes with
`lstrlib.c`'s, and the compiler uses none of the standard libraries, which is how Lua's own
`onelua.c` composes it. The build is the ANSI one, no `LUA_USE_*` platform macro: `lua_Integer`
is `long long`, `lua_Number` `double`.

The headers are copied beside the composed files rather than the quoted includes rewritten to
`fetch/`: the converter takes a declaration as the program's when its file is the main file or
under the main file's directory (`converter/ARCHITECTURE_DUMPER.md`, "The program's files"), so
headers left in `fetch/` would be external and every Lua record, typedef and prototype would
drop out.

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

Each conversion prints `[I]` lines: the dumper's seconds (clang's JSON dump, the libclang pass,
the parse of the JSON and the walk) and the bytes of clang's JSON; then, when the dump
succeeds, the emitter's seconds (the formatter included), the compile check's seconds (daslang
compiling the module with its default policies, as `convert` checks it), the lines of the `.das`
module and how many of its functions carry `[c_function]`. `--native` adds each oracle's size in
bytes.
