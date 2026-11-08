# converter Architecture - the tiers

Companion to `ARCHITECTURE.md` in this folder; section numbers are unique across the family.

## 5. The four tiers

`interp` runs `daslang <module>`, `jit` runs `daslang -jit <module>`, `exe` runs `daslang -exe
<module> -output <work>/<stem>_exe` and executes the binary (the JIT names it `.exe` on every
platform), `aot` runs `daslang utils/aot/main.das -- -ctx <module> <work>/ctx/` and compiles
the generated context with a C++ host (`aot_host_source`: `das::setCommandLineArguments(argc,
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
a build step. An unhandled exception exits 1 with `EXCEPTION:
<text>` on every compiled tier: the `-exe` binary's entry runs `main` inside the context's
`runWithCatch`, and the AOT host does the same around `<stem>_main` and prints the text on
stderr, since a context called with no catch frame reports the exception and raises SIGTRAP,
which a bare spawn reads as exit code 5 (the generated context class derives from `das::Context` alone, so the host
reads the handle as one).

## 9. Typed aliasing under the JIT and exe

The JIT and `-exe` tag every load and store with a `!tbaa` class: `float`, `double`, and one
class for every integer wider than a byte and every pointer; bytes, bools, vectors and
aggregates carry no tag and alias everything (`modules/dasLLVM/ARCHITECTURE.md` section 13 in
`DASLANG_ROOT`). A function whose body holds a punning `reinterpret` - to a pointer other than
`void?` or a byte pointer, from a typed pointer, an integer or a reference - is left untagged, and
so is every function the punned view reaches through a call, a return, an out argument, a
lambda or a shared global. Two tagged accesses of different classes never alias, so only a
`float` or `double` view of memory another tagged access sees as an integer or pointer (or as the
other floating type) can be miscompiled; a program with no floating data has nothing to lose.
The converter spells every C pointer cast as a `reinterpret`, which puts each converted shape in
one of two groups (`probes/test_jit_tbaa.das`, `converter/tests/fixtures/p8_alias_safe.c` and
`p8_alias_unsafe.c`, docs/probe-findings.md F94).

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

Shapes the model misses, where a converted program returns what clang `-O2` returns and not
what the C program means:

- **A cast from `void *`**: `reinterpret<float?>(p)` with `p : void?` is no pun to the model
  (lookibed/daScript#44), so a function viewing one object as `float` and as `unsigned` through
  two `void *` parameters, `malloc` memory or the `alloca` arena keeps its tags. `void *` is
  how C passes untyped memory, so the shape is in nearly every program.
- **Views that travel through memory**: a function that loads a `float *` and an `unsigned *`
  to one object from a record, the record filled by a function that shares no call, return or
  global with it, holds no `reinterpret` of its own and keeps its tags (the one escape
  `modules/dasLLVM/ARCHITECTURE.md` names).

Both are strict-aliasing violations in C, which a program compiled with `-fno-strict-aliasing`
(Doom, Quake and most game code) is entitled to make; the interpreter never reorders by type,
and the AOT host is compiled with `-fno-strict-aliasing` (section 5).
