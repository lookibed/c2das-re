# frontend/include Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder is
the converter's own libc header set: C99 headers that declare what a converted program can reach
when it runs, under the C names, and nothing more of a libc.

## 1. File charters

- `<name>.h`, `sys/<name>.h`, `bits/gnuc_va_list.h` - the C header of that name (the last holds
  `__gnuc_va_list` for `<stdarg.h>` and `<stdio.h>`): the prototypes, objects, macros and types
  of section 2, each line in a form of section 3. Never a prototype of a function nothing binds.
- `tests/_header_scan.das` - the line scanner of section 3 and `BASE_TYPES`, the types a
  declaration bottoms out in with the das type `crt` binds each as.
- `tests/test_headers.das` - the equations of section 2 between the headers, read as text, and the
  loaded `crt` module and the emitter's tables; and the scanner's own cases.

## 2. What the headers declare

**Functions.** The prototypes of all headers together are exactly two sets of names:

- every function the `crt` module (`dasCRuntime/`, repo root) exports under a C name. `crt` also
  exports helpers that are no C function, and those have no prototype: a name starting `c_`
  (`c_strtol32`, `c_errno_location`, `c_stdin`); `<function>_<kind>` where `<function>` is a name
  the emitter lowers through `c_runtime/printf` or `c_runtime/scanf` (`snprintf_int`,
  `sscanf_one`, `fscanf_none`: C's variadics served one directive a call); and `fwrite_stdout` and
  `fflush_stdout`, which the printf lowering writes through.
- every libc name the emitter lowers itself: the keys of `C_RUNTIME_CALLS` in `converter/emit.das`
  (repo root) that are not `__builtin_` names (the printf and scanf families, `exit`, `abort`,
  `signal`, `longjmp`, `qsort`, `bsearch`, the `<math.h>` functions das `math` covers, glibc's
  `__assert_fail` and `__errno_location`), and `setjmp`.

One name the emitter maps is declared by no header: `__sigsetjmp`, what glibc's `sigsetjmp` macro
calls; no `siglongjmp` is lowered to pair it with. `<setjmp.h>` is glibc's otherwise: prototypes of
`setjmp`, `_setjmp`, `longjmp` and `_longjmp`, and `setjmp(env)` a macro for `_setjmp (env)`, so a
program's `setjmp` reaches the C-IR as `_setjmp`, as it does over glibc.

**Shapes.** A prototype of a `crt` function has the bind's parameter count, parameter types and
result type, a C type read as `crt` spells it: `char` is `uint8`, `int` is `int`, `unsigned int`
is `uint`, `long` and `long long` are `int64`, `unsigned long` and `unsigned long long` are
`uint64`, `float` and `double`
themselves; a pointer adds `?` and keeps the pointee's `const`; a pointer to `void` or to a record
(`FILE *`, `struct tm *`) is `void?`. A typedef name is read as the type its header declares it
as, through every typedef between, down to a C type or a predefined type macro pinned at the width
both dialects give it (`__SIZE_TYPE__` is `uint64`, `__INT64_TYPE__` is `int64`): `time_t` is
`int64` because `<time.h>` declares it `__INT64_TYPE__`, not by its name, and a name no header
declares is an error. C's `long` is `int64` there under both dialects: `crt` binds
the host libc at the host's widths, and the emitter narrows at the call site where the dialect's
`long` is 32 bits. A prototype of a lowered function is checked by name only, since no bind has
its shape.

**Objects.** The `extern` objects are the keys of the emitter's `CRT_OBJECTS`: `stdin`, `stdout`,
`stderr`.

**Constants.** Every constant `crt` exports under a C name is a macro of that name:
`CLOCKS_PER_SEC`, `RAND_MAX`, `EDOM`, `ERANGE`, `EINVAL`, `HUGE_VAL`. `LONG_BITS`, the width of the
host's `long`, is no C name and has no macro.

**Macros and types beyond those.** A header also holds the macros and types the C standard gives
it that need no function behind them (`NULL`, `offsetof`, the `va_` macros, `EOF`, `SEEK_SET`,
the limits of `<limits.h>`, `<float.h>` and `<stdint.h>`, the format macros of `<inttypes.h>`,
`bool`), and those of glibc's that a program of the suites or of a converted project uses (`M_PI`
and its family, `EISDIR`, `CLOCK_MONOTONIC`, `struct timespec`). No test bounds this part; the
checklist does. A macro whose expansion calls a function exists only over a name the emitter maps:
`errno`, `assert`, `HUGE_VAL` (`__builtin_huge_val`), `signbit` (`__builtin_signbit`), `alloca`
(`__builtin_alloca`, in `<alloca.h>`, which `<stdlib.h>` includes as glibc's does), `offsetof` and
the `va_` macros. So `<math.h>` has no `NAN`, `INFINITY` or `isnan`, whose builtins nothing
lowers, and `<float.h>` no `LDBL_` macro, `long double` being `double` to the converter. Section 6
holds the one macro outside this.

`<unistd.h>` and `<fcntl.h>` declare nothing: no function of theirs is bound, and a converted
project (doomgeneric) includes them and uses none. `<sys/types.h>` holds `mode_t` for `mkdir` of
`<sys/stat.h>`. `<string.h>` includes `<strings.h>`, as glibc's does by default, so
`strcasecmp` is visible through either.

## 3. Line forms

`tests/_header_scan.das` reads a header line by line, and every line is one of these forms; any
other line is an error of the test, so the scanner is the format gate. A line is printable ASCII
and ends in no blank. The scanner reads each line as it stands, so no line may change how C reads
another: a comment is a whole line (no other line holds `/*`, `*/` or `//`); a string literal
stands whole in a `#define` and nowhere else; and no line holds a backslash, `??`, a `'`, or one
of `` ` ``, `@` and `$`.

- an empty line;
- a comment on one line, `/* ... */`;
- a directive on one line: `#ifndef`, `#ifdef`, `#if`, `#else`, `#endif`, `#undef`, `#define`
  (object-like or function-like), `#include <name>` (`name` a header of this folder);
- a typedef, one declaration whose only `;` ends the line: `typedef <type> <name>;` with no
  pointer, an array `typedef <type> <name>[<count>];`, or a function pointer
  `typedef <type> (*<name>)(<types>);`. A name is declared by one line of one header;
- a record: `struct <tag> {`, member lines `    <type> <name>;` with no parenthesis or brace, then
  `};`;
- an object: `extern <type> <name>;`;
- a prototype: `<type> <name>(<type>, <type>);`, the parameters unnamed, `(void)` for none, `...`
  last for a variadic. A type is an optional `const`, then a C base type, `struct <tag>` or a
  typedef name, then for a pointer one space and the stars (`const char *`, `char **`). A parameter
  that is a function pointer is spelled through a typedef (`__compar_fn_t`, `__sighandler_t`).

The scanner evaluates no condition, so it counts only what no condition can remove:

- a header that declares a type starts with its include guard: `#ifndef <guard>` as its first
  line of code, `#define <guard>` on the next line, the matching `#endif` its last line. The guard
  is the header's name in capitals behind an underscore (`_SYS_STAT_H`), and no other line of any
  header defines it. `<assert.h>` has none: its prototype may repeat, and its macro is defined
  anew at each inclusion;
- every other conditional holds `#define` lines only, has an `#else`, and holds no conditional.
  So a prototype, an object, a typedef, a record and an `#include` stand under the include guard
  alone;
- a macro takes no name that any line of any header declares (a typedef, a function, an object,
  a record tag or member, a word of a type) and no C keyword, wherever its `#define` stands: such
  a macro would rewrite a declaration the scan has read as written. `MIRRORS` in the scanner lists
  the names that may, each with the exact lines that may define it: `stdin`, `stdout` and `stderr`
  as themselves, `setjmp(env)` as `_setjmp (env)`, and the two type macros of `<stdint.h>`;
- a macro of a conditional counts as defined when both arms define it (`assert` under `NDEBUG`,
  `INT64_C` under the width of `long`), and a conditional whose arms define different names is an
  error. An `#undef` takes its name out of the count. Where a type depends on the dialect, the
  conditional defines a macro for it and the typedef stands after it (`__FAST16_TYPE` for
  `int_fast16_t`).

## 4. Spellings kept from glibc

Dumper A recognises some libc entities by glibc's spelling and the emitter maps some glibc-internal
names (`converter/ARCHITECTURE_DUMPER.md`, `converter/emit.das`), and a converted program's text
carries the tags and member names of the libc records it lays out. The headers keep those
spellings, so that a program converts to the same text over these headers as over glibc's:

- `errno` is `(*__errno_location ())`.
- `assert(e)` is `((e) ? (void) (0) : __assert_fail (#e, __FILE__, __LINE__, __func__))` with
  glibc's prototype of `__assert_fail`, and `((void) (0))` under `NDEBUG`. This is glibc's ISO form:
  no statement expression, and `__func__` where glibc under GNU C passes `__PRETTY_FUNCTION__`.
  `<assert.h>` defines `assert` anew at every inclusion, as C requires.
- `jmp_buf` is `struct __jmp_buf_tag[1]`, the record at glibc's size (200 bytes), and `setjmp` is
  glibc's macro over `_setjmp`.
- `va_list` is `__builtin_va_list`, and `<stdio.h>` spells it `__gnuc_va_list`, whose one
  declaration is `<bits/gnuc_va_list.h>`.
- `FILE` is `struct _IO_FILE`, declared and never defined.
- `struct tm` ends in `__tm_gmtoff` and `__tm_zone`, glibc's names for the two members outside ISO
  C when a feature macro such as `_XOPEN_SOURCE` narrows it, which Lua's sources define.
- `SIG_DFL`, `SIG_IGN` and `SIG_ERR` are casts of 0, 1 and -1 to `__sighandler_t`;
  `CLOCKS_PER_SEC` is a cast of 1000000 to `clock_t`.
- the limits of `<limits.h>` and `<float.h>` are spelled as clang's own headers spell them, each
  through the macro the compiler predefines (`INT_MAX` is `__INT_MAX__`, `UCHAR_MAX` is
  `(__SCHAR_MAX__*2 +1)`, `DBL_MAX` is `__DBL_MAX__`), and those of `<stdint.h>` as glibc's, in
  literals (`INT32_MIN` is `(-2147483647-1)`). The token's origin matters: Dumper A reads the
  arguments of a function-like macro call differently when a limit inside one is a literal of a
  header file, and Lua's `luaL_argcheck(L, n <= MAXSIZE - size, ...)` over `INT_MAX` then dumps to
  another C-IR.

Macro values, typedefs and record layouts are glibc's on linux x86_64 under both dialects, since
`crt` binds the host libc and hands the program records the host laid out: `struct tm` is 56
bytes, `struct lconv` 96, `struct timespec` 16; `time_t` and `clock_t` are 64 bits.

## 5. Predefined names

The headers read these macros the compiler predefines, and no other; `PREDEFINED` in
`tests/test_headers.das` is the same list, held equal to the headers' text, and every name of it is
an entry of both predefined-macro tables (`../ARCHITECTURE.md` section 3), which spell a type as
clang does (`long unsigned int` for the `unsigned long` below).

| Names | Read by | `linux` | `msvc` |
|---|---|---|---|
| `__SIZE_TYPE__` | `size_t` | `unsigned long` | `unsigned long long` |
| `__PTRDIFF_TYPE__` | `ptrdiff_t` | `long` | `long long` |
| `__WCHAR_TYPE__` | `wchar_t` | `int` | `unsigned short` |
| `__INT64_TYPE__` | the 64-bit types of `<stdint.h>` and `<time.h>`, `intptr_t`, `intmax_t` | `long` | `long long` |
| `__LONG_MAX__` | `LONG_MAX`, `LONG_MIN`, `ULONG_MAX`; whether a 64-bit constant and format take `L`/`l` or `LL`/`ll`; the types of `int_fast16_t` and `int_fast32_t` | `9223372036854775807L` | `2147483647L` |
| `__CHAR_BIT__`, `__SCHAR_MAX__`, `__SHRT_MAX__`, `__INT_MAX__`, `__LONG_LONG_MAX__` | `<limits.h>` | `8`, `127`, `32767`, `2147483647`, `9223372036854775807LL` | the same |
| `__FLT_RADIX__`; `__FLT_<n>__` and `__DBL_<n>__` for `<n>` in `MANT_DIG`, `DIG`, `MIN_EXP`, `MIN_10_EXP`, `MAX_EXP`, `MAX_10_EXP`, `MAX`, `EPSILON`, `MIN` | `<float.h>` | `2`; IEEE 754 single and double as clang writes them (`__DBL_MAX__` is `1.7976931348623157e+308`) | the same |

`<assert.h>` also reads `NDEBUG`, which the program defines, and the language's `__FILE__`,
`__LINE__` and `__func__`. Everything else is written out for what both dialects share: `char` is
unsigned (`CHAR_MIN` is 0), `int` is 32 bits, a pointer 64. The typedefs are the types glibc with
clang gives under the `linux` triple and clang's own headers under the `msvc` one (`int64_t` is
`long` and `long long`; `int_fast16_t` is `long` and `short`).

## 6. Exception ledger

- `REVIEW.md`, the rule that a macro calls only a name the emitter maps, fires on `HUGE_VALF`
  (`__builtin_huge_valf`, which nothing lowers). Lua's `luaconf.h` takes a libm with `HUGE_VAL`
  and no `HUGE_VALF` for a C89 one and then defines `l_mathop` and `lua_str2number` another way,
  so without the macro every Lua unit that calls `<math.h>` converts to other text. A program that
  uses `HUGE_VALF` itself is refused by the emitter, as it is over glibc.
