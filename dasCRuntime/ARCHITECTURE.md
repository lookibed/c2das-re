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
`crt::c_set_errno(v)`; `CLOCKS_PER_SEC`, `RAND_MAX`, `EDOM`, `ERANGE`, `EINVAL` are constants
read from the CRT that built the module, never restated in das.

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

C strings are bytes, never das `string`: a forwarder takes `uint8_t *` so the das side sees
`uint8?`, and a test reads a result back through `reinterpret<string>`. `long` is the width
of the CRT that built the module, 64 bits here; the converter's dialect (`long` = 32) is
applied by the emitter at the call site, not by the forwarder, so the module tells the truth
about the platform and the converter owns the narrowing.

## 4. Side effects and unsafe

Every bind that takes or returns a raw pointer is registered `unsafeOperation`, matching
daslang's own `memcpy` and `malloc`: converted bodies that use them carry `[c_function]`,
which makes the whole body unsafe, and a hand-written caller writes `unsafe`. Pure scalar
entries (libm, ctype, `abs`) are `SideEffects::none` and safe. Anything that writes memory,
reads or writes CRT state (`errno`, the `rand` seed, the environment, the clock, the
`strerror` buffer) is `modifyExternal`: the optimizer may not fold or drop it.

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
(`c_runtime/scanf.das`) how far the input moved.

## 6. Build and loading

`CMakeLists.txt` compiles against `DASLANG_ROOT/include` and links the checkout's
`lib/liblibDaScriptDyn*` libraries. The checkout builds without RTTI and with the
header-visible defines `DAS_ENABLE_DYN_INCLUDES=1` and `DAS_FUSION=2`; the module compiles
with the same, because a `typeinfo` reference from a module compiled with RTTI is an
undefined symbol at load time and a define that changes a header changes an ABI.
`scripts/build_crt.sh` configures into `_build/` (with `compile_commands.json` for the C++
MCP tools) and leaves the `.shared_module` beside `.das_module`.

The module lives outside `DASLANG_ROOT/modules`, so every daslang run that needs it passes
`-load_module <repo>/dasCRuntime` before the script path: `scripts/preflight.sh` does for
every gate, `.mcp.json` does for the MCP server, and a manual run does by hand. `require crt`
without that flag fails with "missing prerequisite 'crt'".

## 7. Exception ledger

Empty.
