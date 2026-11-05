# dasCRuntime Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The
folder is the native glue module `crt`: the C runtime library bound into daslang by
`addExtern`, one line per entry, and nothing that decides anything.

## 1. File charters

- `src/dasCRuntime.h` - the forwarders: one `inline` C++ function per CRT entry, spelling the
  entry's signature in fixed-width types and raw pointers. A forwarder is one CRT call plus
  the casts that spelling needs; no branch, no loop, no state lives here. AOT output includes
  this header, so it must stay self-contained.
- `src/dasCRuntime.cpp` - `Module_CRT`: the `addExtern` and `addConstant` lines, the
  `aotRequire` that names the header, the two `REGISTER_*` lines. Never a forwarder body.
- `CMakeLists.txt` - builds `dasModuleCRuntime.shared_module` beside this file, against
  `DASLANG_ROOT` (section 6). `scripts/build_crt.sh` drives it.
- `.das_module` - the descriptor that registers the `.shared_module` under class
  `Module_CRT`; `.das_module.manifest` beside it is generated and ignored.
- `tests/test_crt.das` - the dastest suite: one arm family per header, every bind called at
  least once against a value the C standard fixes.
- `REVIEW.das` - the mechanical gate: every name `dasCRuntime.cpp` binds appears in the test.

## 2. Naming and qualification

The module is named `crt` and every entry keeps its C name (`malloc`, `strlen`, `fmod`).
Several of those names exist in daslang's `builtin` module with different signatures
(`malloc(uint64) : void?` over the system aligned allocator, `memcpy`, `free`), and daslang
resolves an unqualified call against every visible module, so converted code and this
folder's tests always write `crt::malloc(...)`. The names the C standard reserves as macros
or that have no function form become accessors: `errno` is `crt::c_errno()` and
`crt::c_set_errno(v)`, and `crt::c_errno_location()` is its address, which converted code reaches
through glibc's spelling of `errno`, `(*__errno_location())`; `CLOCKS_PER_SEC`, `RAND_MAX`,
`EDOM`, `ERANGE`, `EINVAL` and `HUGE_VAL` (a `double`, what `__builtin_huge_val()` gives) are constants
read from the CRT that built the module, never restated in das; the standard streams `stdin`,
`stdout` and `stderr` are `crt::c_stdin()`, `crt::c_stdout()` and `crt::c_stderr()`. The entries
no C name covers keep a `c_` name: `c_strtol32`, `c_strtoul32`, `c_atol32` and `c_ftell32` (section
3), and `c_signal_host(sig, ignore)`, which installs the host's `SIG_IGN` or `SIG_DFL` for
`c_runtime/c_signal.das`; `c_volatile_load_<w>(p)` and `c_volatile_store_<w>(p, v)` for `w` in
`i8 u8 i16 u16 i32 u32 i64 u64 f32 f64`, one access through a `volatile` pointer each, for
`c_runtime/c_volatile.das`, which moves a pointer or a function value through `u64`; and
`c_monotonic_ns()`, the steady clock's nanoseconds (`std::chrono::steady_clock`, CLOCK_MONOTONIC
on linux), which the perf harness's dasProfile method times by (`perf/ARCHITECTURE.md` section 2).

The binds are the malloc family; `mem*`; string.h; ctype.h; the `strto*` and `ato*` conversions;
libm's exotica; errno; `getenv`, `rand`, `srand`, `system`; time.h (`time`, `clock`, `difftime`,
`mktime`, `localtime`, `gmtime`, `strftime`, and POSIX's `clock_gettime` over glibc's
`CLOCK_REALTIME` (0, the system clock) and `CLOCK_MONOTONIC` (1, the steady clock
`c_monotonic_ns` reads), any other id -1 with `EINVAL`, its `struct timespec *` a `void *` the
program lays out as `<time.h>` does); locale.h (`setlocale`, `localeconv`); stdio (`fopen`,
`freopen`, `fclose`, `fread`, `fwrite`, `fgets`, `fputs`, `getc`, `ungetc`, `feof`, `ferror`,
`clearerr`, `fflush`, `fseek`, `ftell`, `setvbuf`, `tmpfile`, `tmpnam`, `remove`, `rename`, and
`fwrite_stdout`/`fflush_stdout` for the printf family); and the per-directive `snprintf` and
`sscanf` families (section 5). Every stdio entry a program calls binds here, none through daslib
`fio`: one binding family serves one header.

## 3. Type spelling

| C | forwarder | das |
|---|---|---|
| `void *` | `void *` | `void?` |
| `char *` (any string) | `uint8_t *` | `uint8?` |
| `const char *` | `const uint8_t *` | `uint8 const?` |
| `char **` (`strtol` end pointer) | `uint8_t **` | `uint8??` |
| `size_t` | `uint64_t` | `uint64` |
| `long`, `time_t`, `clock_t` | `int64_t` | `int64` |
| `int` | `int32_t` | `int` |
| `int *`, `double *` out-parameters | `int32_t *`, `double *` | `int?`, `double?` |

A pointer to a record (`FILE *`, `struct tm *`, `struct lconv *`) is `void *` and `void?` in every
position, taken or returned: the module knows no record of a program, which lays the record out
itself (`converter/ARCHITECTURE_DUMPER.md` section 3) and converts the pointer at the call site
(`reinterpret<void?>(f)`, `reinterpret<tm?>(crt::localtime(addr(t)))`).

C strings are bytes, never das `string`: a forwarder takes `uint8_t *` so the das side sees
`uint8?`, and a test reads a result back through `reinterpret<string>`. `long` is the width
of the CRT that built the module, 64 bits here; the converter's dialect (`long` = 32) is
applied by the emitter at the call site, not by the forwarder, so the module tells the truth
about the platform and the converter owns the narrowing. Where C ranges a result at the dialect's
`long`, a narrowing would wrap where a 32-bit CRT clamps, so the module carries the 32-bit forms
the emitter calls instead: `c_strtol32`, `c_strtoul32` and `c_atol32` parse at 64 bits and apply
C11 7.22.1.4's range rule at 32 (LONG_MAX, LONG_MIN or ULONG_MAX with `errno` ERANGE, a negative
`strtoul` subject's magnitude range-checked before it is negated, `errno` untouched in range), and
`c_ftell32` gives C's failure, -1 with ERANGE, for a position past LONG_MAX.

## 4. Side effects and unsafe

Every bind that takes or returns a raw pointer is registered `unsafeOperation`, matching
daslang's own `memcpy` and `malloc`: converted bodies that use them carry `[c_function]`,
which makes the whole body unsafe, and a hand-written caller writes `unsafe`. Pure scalar
entries (ctype, `abs`, `difftime`, and the libm entries that never set `errno`: `cbrt`, `copysign`,
`trunc`, `round`) are `SideEffects::none` and safe. A reader through a pointer (`strlen`, `memcmp`,
`memchr`, `strcmp`, `strncmp`, `strchr`, `strrchr`, `strstr`, `strpbrk`, `strspn`, `atoi`,
`atol`, `atof`) is `accessExternal`: bound `none`, daslang's optimizer merged two of its calls on
the same pointer across a write the program made through another pointer to the same memory, under
the interpreter and the JIT alike. A bind that may write through a pointer argument (`memcpy`,
`memmove`, `memset`, the `str*cpy` and `str*cat` family, the `strto*` end pointers, `frexp`'s and
`modf`'s out-parameters, `time`, the `snprintf` and `sscanf` families, `fgets`, `fread`,
`strftime`, `mktime`, `realloc`, `free`, `tmpnam`, `setvbuf`, `clock_gettime`, the volatile stores)
is `modifyArgumentAndExternal`: bound `modifyExternal` alone, a reader on both sides of it in one
function was merged on every tier, and under the JIT a caller's local passed to a helper whose
pointer parameter is not `var` kept its bytes as they were. Anything else that reads or writes CRT
state (`errno`, the `rand` seed, the environment, the clock, the `strerror` buffer, a signal's
disposition, a `FILE` or a `tm` the CRT owns) is `modifyExternal`: the optimizer may not fold or
drop it (`docs/probe-findings.md` F85, `probes/test_crt_writes.das`). The volatile loads are too,
each an extern call the JIT cannot see into, and under AOT an inline body whose `volatile` access
clang++ keeps. The libm entries glibc reports a domain or range error through `errno` from (`fmod`,
`fmodf`, `ldexp`, `nextafter`, `hypot`, `expm1`, `log1p`, `remainder`, `erf`, `erfc`, `tgamma`,
`lgamma`, `fma`) are among them, so a call whose result the program discards, or whose arguments
are constant, still runs.

## 5. `snprintf` and `sscanf` as per-directive families

C `snprintf` is variadic and cannot be bound. The family `snprintf_none`, `snprintf_int`,
`snprintf_uint`, `snprintf_int64`, `snprintf_uint64`, `snprintf_double`, `snprintf_str`,
`snprintf_ptr` takes `(buf, size, fmt, value)` where `fmt` holds exactly one directive of the
value's C type (or none). The printf lowering (`docs/lowering-examples.md`, Variadics) splits
a C format at its directives and issues one call per piece, so the rendering is the CRT's
byte for byte and no conversion engine is written in das. `snprintf_int64` and
`snprintf_uint64` pass `long long`, so their directives are the `ll` spellings.

C `sscanf` is variadic too and binds the same way, one directive per call: `sscanf_one(src,
fmt, out, consumed)` passes the C program's out-pointer as `void *`, so the CRT writes it at the
width `fmt`'s directive names, and `sscanf_none(src, fmt, consumed)` serves a directive that
assigns nothing; `fmt` ends in `%n`, whose `consumed` tells the scanf lowering
(`c_runtime/c_runtime/scanf.das`) how far the input moved.

## 6. Build and loading

`CMakeLists.txt` compiles against `DASLANG_ROOT/include` and links the checkout's
`lib/liblibDaScriptDyn*` libraries. The checkout builds without RTTI and with the
header-visible defines `DAS_ENABLE_DYN_INCLUDES=1`, `DAS_FUSION=2` and `SIZE_OF_VOID_P`; the module compiles
with the same, because a `typeinfo` reference from a module compiled with RTTI is an
undefined symbol at load time and a define that changes a header changes an ABI.
`scripts/build_crt.sh` configures into `_build/` (with `compile_commands.json` for the C++
MCP tools) and leaves the `.shared_module` beside `.das_module`.

The module lives outside `DASLANG_ROOT/modules`, so every daslang run that needs it passes
`-load_module <repo>/dasCRuntime` before the script path: `scripts/preflight.sh` does for
every gate, `.mcp.json` does for the MCP server, and a manual run does by hand. `require crt`
without that flag fails with "missing prerequisite 'crt'".

## 7. Exception ledger

- `REVIEW.md`, the rule registering `SideEffects::none` only for a call that changes nothing
  but its return value, reaches past this module: the converter maps `<math.h>`'s `floor`,
  `ceil`, `fabs`, `sqrt`, the trigonometric family, `exp`, `log`, `log2`, `log10` and `pow` to das
  `math::` (`converter/emit.das`, `C_RUNTIME_CALLS`), whose functions are pure on every tier, so
  daslang folds or drops such a call whose arguments are constant or whose result is discarded,
  and the JIT's `sqrt` is an intrinsic: `errno` after such a call is not reliably set
  (`log(0)` leaves `errno` 0 where glibc gives `ERANGE`). A dialect limit, ledgered on P5.1.
