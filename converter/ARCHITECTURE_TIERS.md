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
