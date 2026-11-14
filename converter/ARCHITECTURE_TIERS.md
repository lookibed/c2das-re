# converter Architecture - the tiers

Companion to `ARCHITECTURE.md` in this folder; section numbers are unique across the family.

## 5. The four tiers

`interp` runs `daslang <module>`, `jit` runs `daslang -jit <module>`, `exe` runs `daslang -exe
<module> -output <work>/<stem>_exe` (the caller's interpreter flags, `-no-module-cache`, before
`-exe`; the build's log joins the output only when the build fails) and executes the binary
(written at the `-output` path as given),
`aot` runs `daslang utils/aot/main.das -- -ctx <module> <work>/ctx/` and compiles
the generated context with a C++ host (`<work>/ctx/<stem>_host.cpp`, `aot_host_source`: `das::setCommandLineArguments(argc,
argv)` as `daslang` and an `-exe` binary call it, so the program's arguments, passed after `--`,
reach `get_user_args`; then `<stem>_create`, `<stem>_main`, `<stem>_destroy` from the generated
header, `<stem>` spelled as a C++ identifier, which also names the binary `aot_binary` answers) against the static runtime: `liblibDaScript.a`,
`liblibDaScript_runtime.a`, `liblibUriParser.a`, with the checkout's ABI flags (no RTTI,
`DAS_FUSION=2`, `SIZE_OF_VOID_P=8`). The compiler is the pinned clang's `clang++` at `-O3`,
the native perf lane's compiler and level (`perf/ARCHITECTURE.md` section 2); `default_clang()`
answers `clang` on PATH when `PATH_TO_LIBCLANG` is unset, so the host is then `clang++` on
PATH, the same requirement the conversion already has. Every tier takes the module folders
from the caller (`suites/c_testsuite/run.das` passes both): the interpreter and the JIT load
them, `exe` loads them while it builds the executable, and `aot` uses them twice, loaded while `-ctx` generates the context and
as sources, where a folder holding `src/*.cpp` (`dasCRuntime`) compiles into the host with its
`src/` on the include path, because the generated context declares the module and includes
its header. The exit code is the program's own on every tier,
which is why the wrapper returns from `main`. A caller's `wrapper` (perf's sample guard) goes
before the program's own command line on every tier, `daslang` or the built binary, never before
a build step. An unhandled exception exits -2 (254, daslang's `DAS_PANIC_EXIT_CODE`) with `EXCEPTION:
<text>` on every compiled tier, as under `daslang`: the `-exe` binary's entry runs `main` inside the context's
`runWithCatch`, and the AOT host does the same around `<stem>_main` and prints the text on
stderr, since a context called with no catch frame reports the exception and raises SIGTRAP,
which a bare spawn reads as exit code 5 (the generated context class derives from `das::Context` alone, so the host
reads the handle as one).

### The build and its reuse {#build-reuse}

`exe` and `aot` build first and run the binary after (`build_tier`, then `binary_argv`), and a
build is skipped when the binary an earlier one left still matches its inputs: `build_key` lists
the tier; the daslang checkout (the commit `.git/HEAD` names, and the size and mtime of
`bin/daslang`, the three static libraries and `utils/aot/main.das`, which a rebuild at the same
commit changes); the build commands (`flags` among them under `exe`) and the AOT host's text; every
file of the program, found by following each `require` and `include` that names a file from the
naming file's folder; and every file of the module folders (but a hidden, `tests`, `build` or
`_build` folder's and daslang's own `.das_module.manifest`), each with its size and its text's hash,
a native library (`.shared_module`, `.so`) with its mtime. A name that resolves to no file there is
daslib's, a module folder's or a native module's, which the checkout and the module folders
already cover. The key goes to `<binary>.key` after a build that leaves the binary, with the
binary's own size and mtime, so a failed build leaves no key, and a binary replaced since (perf's
tests plant a stale one) is built again. The key does not cover the system toolchain a command
names by its bare name (`c++` on `PATH` under daslang's `-exe`), nor daslib files edited without a
commit; neither changes on this tree's workflow. Each build step's log joins the output only when
the step fails, so a reused build and a fresh one print the same. A caller that loops over
inputs (Lua's `--luac-check`, one Doom run per demo, perf's and compare's lanes) builds once; a
folder per variant of a program keeps each variant's binary (`aot_binary` names the binary by the
stem alone, so two layouts of one program in one `work_dir` would share one).

## 9. Typed aliasing under the JIT and exe {#typed-aliasing}

The JIT and `-exe` tag every load and store with a `!tbaa` class: `float`, `double`, and one
class for every integer wider than a byte and every pointer; bytes, bools, vectors and
aggregates carry no tag and alias everything (`modules/dasLLVM/ARCHITECTURE.md` section 13 in
`DASLANG_ROOT`). A function whose body holds a punning `reinterpret` - to a pointer other than
`void?` or a byte pointer, from a typed pointer, a `void?`, an integer or a reference - is left untagged, and
so is every function the punned view reaches through a call, a return, an out argument, a
lambda or a shared global. Two tagged accesses of different classes never alias, so only a
`float` or `double` view of memory another tagged access sees as an integer or pointer (or as the
other floating type) can be miscompiled; a program with no floating data has nothing to lose.
The converter spells every C pointer cast as a `reinterpret`, which puts each converted shape in
one of two groups (`probes/test_jit_tbaa.das`, `converter/tests/fixtures/p8_alias_safe.c` and
`p8_alias_unsafe.c`, docs/probe-findings.md F95).

Shapes the model keeps right with its tags on:

- **Union members** (`[c_union]`): each member accessor is `*addr<T?>(s._storage)`, a punning
  `reinterpret` of the storage, and returns a reference, so the accessor and every function
  calling it are untagged. A `float`/`unsigned` union and a Lua-style `double`/`long long`
  value read back the bits stored last.
- **A cast between typed pointers** (`(unsigned *)fp`, `(T *)` of an integer, the
  `first_member` `reinterpret` of a record pointer): punning by the model's own test, so the
  function is untagged; the first-member view is one class with the member anyway.
- **Byte views** (`unsigned char *`, the marshalled records' `uint8?` readers and writers,
  `c_runtime`'s byte buffers): byte accesses carry no tag.
- **`memcpy` and the CRT**: das's builtin `memcpy` lowers to LLVM's untagged intrinsic, and an
  extern CRT call is opaque to the optimizer.
- **Integer widths and pointers** (`short *` over an `int`, `uintptr_t` round trips, bitfield
  units over `uint` storage): one class, so the views alias even where the model sees no pun.
- **A cast from `void *`**: `reinterpret<float?>(p)` with `p : void?` is a pun to the model
  (lookibed/daScript#44, fixed in daScript `67e3515e60`), so a function viewing one object as
  `float` and as `unsigned` through two `void *` parameters, `malloc` memory or the `alloca`
  arena is untagged.

Shapes the model misses, where a converted program returns what clang `-O2` returns and not
what the C program means:

- **Views that travel through memory**: a function that loads a `float *` and an `unsigned *`
  to one object from a record, the record filled by a function that shares no call, return or
  global with it, holds no `reinterpret` of its own and keeps its tags (the one escape
  `modules/dasLLVM/ARCHITECTURE.md` names). The fixture's `record_views` keeps its tags, yet on
  daScript `6401904cf9` its JIT and exe code reads back the stored bits (3, not clang `-O2`'s 2):
  the model allows the reordering, the generated code does not make it there.

It is a strict-aliasing violation in C, which a program compiled with `-fno-strict-aliasing`
(Doom, Quake and most game code) is entitled to make; the interpreter never reorders by type,
and the AOT host is compiled with `-fno-strict-aliasing` (section 5).

The module holding `main` carries `options strict_aliasing = false` (`assemble_module`), so a
converted program runs with no tags under `-jit` and `-exe`, as it does under the interpreter.
The option sits in the root because daslang reads it from the root program alone: a required
module's line is ignored, and the converted entry module is the root on every tier and harness
(`run_tier`, perf, ports, the Lua and Doom runners). One line covers every module, where
`[hint(no_strict_aliasing)]` would be one line per function. The sidecar's `strict_aliasing:
true` drops the line and keeps the model, for a program whose C is clean under
`-fstrict-aliasing`: none of the shapes above that the model misses, and a native build at `-O2`
that prints what `-O0` prints. A program rooted in a hand-written module that requires converted
ones carries the option in that root itself.
