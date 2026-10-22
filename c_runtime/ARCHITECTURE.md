# c_runtime Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The
folder is the daslang module converted programs require: the semantic layer the bind-first
strategy leaves on the das side (`docs/stdlib-examples.md`), grown one piece at a time with an
as-if-converted fixture test landing first.

## 1. File charters

- `.das_module` - the descriptor: one `register_native_path("c_runtime", <name>, ...)` per
  file under `c_runtime/`, so a converted module writes `require c_runtime/<name>`. A file
  the descriptor does not name is unreachable; `REVIEW.das` keeps the two in step.
- `c_runtime/c_function.das` - the `[c_function]` function annotation: `apply` replaces the
  body with `unsafe { <body> }` before inference. The converter emits it only on a function
  whose body contains an unsafe operation, so its count across a converted program is the
  port-progress metric of the follow-up story; nothing else about the function changes.
  `unsafe` does not reach into a lambda or generator body, which C never produces.
- `c_runtime/enum_from_int.das` - `enum_from_int(type<E>, i)`, the C int-to-enum conversion:
  one generic over the type witness holding the one `unsafe(reinterpret)`, so an out-of-range
  value survives by value as C's does.
- `c_runtime/c_exit.das` - the process-exit protocol: `c_atexit` registers into a module
  list, `c_run_atexit` walks it once in LIFO order, the `[finalize]` walker runs it after a
  normal return from `main` and then flushes every C stream (`crt::fflush(null)`) while the
  context lives, since a buffer the program handed `setvbuf` is das memory that libc's own flush
  at process exit would read freed (the emitter requires the piece for a program calling
  `setvbuf`); `c_exit(code)` runs the handlers and ends the process with `exit_now`, whose libc
  exit flushes with the context alive, because daslang's `exit` reports 1 whatever its argument
  (`docs/probe-findings.md` F1), `c_abort` is `exit_now(3)` with no handler run, which is C's rule
  and the baseline's code.
- `c_runtime/c_signal.das` - C's `signal` in the dialect (`docs/stdlib-examples.md` "signal.h",
  `docs/c-feature-matrix.md`): a converted handler never runs, since das code cannot run from a
  host signal, so `c_signal(sig, handler)` keeps the handler of each number from 1 to 64 in a
  module array and returns the one before it, `SIG_DFL` (the null function value, `default<...>`)
  until the first call; Lua's Ctrl-C hook (`lua.c`'s `laction`) never fires. `SIG_IGN`,
  `(void (*)(int)) 1`, and `SIG_ERR`, `(void (*)(int)) -1`, are the emitter's integer sentinels of
  a function value (`converter/ARCHITECTURE_EMITTER_AGGREGATES.md`). `SIG_IGN` and `SIG_DFL` are
  applied to the host process through `crt::c_signal_host`, so a signal the program ignores
  (`SIGPIPE`) does not end it, and a host signal to a number with a converted handler takes the
  host's disposition. A number the dialect's C library refuses (linux: 0, `SIGKILL`, `SIGSTOP`,
  the two glibc reserves for its threads, 32 and 33, and past 64; msvc: all but its eight) returns
  `SIG_ERR` with `errno` EINVAL; `c_signal_msvc`, which the converted module's dialect `[init]`
  sets, selects msvc's numbers, its `SIGABRT` (22) applied as the host's. `raise` is not bound.
- `c_runtime/c_label.das` - `c_label_end()`, the statement a C label stands on in a das block
  other than a loop's body: daslang's interpreter jumps only to a statement inside such a block,
  and its optimizer folds an empty block or a statement without effect away
  (`docs/probe-findings.md` F62); a `[sideeffects]` call stays and does nothing.
- `c_runtime/c_args.das` - C's `main(argc, argv)`: `c_runtime_init(name)`, which the converted
  module's `main` calls first, builds the argument vector once in C-allocator memory (`malloc`),
  `name` (the C source's stem) then each argument `get_user_args` gives (after `--` under the
  interpreter and the JIT, after the binary in a `-exe` one) as a NUL-terminated copy, then the
  null C puts at `argv[argc]`; `c_argc()` and `c_argv()` hand them to `c_main`. The program owns
  and may write every byte, so none is on the das heap; a second call keeps the first vector.
- `c_runtime/cstr_array.das` - the `cstr_array("abc", N)` call macro: C's `char buf[N] = "abc"`
  as a `uint8[N]` literal built at compile time from the decoded string bytes, a NUL and zero
  padding; an exact fit carries no NUL, a longer string is a compile error. The das literal
  does the escape decoding, so the macro only spells bytes.
- `c_runtime/variadic.das` - C varargs: `CVal` (`i : int64`, `d : double`, `p : void?`),
  `CVaList`, `to_cvalist` (the `apply` walk over a tuple with C's default promotions, `bool`
  dispatched on `stripped_typename` because no bool trait exists), and the `[variadic]`
  annotation. Its `apply` runs before the gen2 parser decides generic-or-not, so it turns the
  trailing `va : va_args` parameter into `_va_tuple : auto`, prepends `let va <-
  to_cvalist(_va_tuple)`
  to the body, renames the function `<name>`va`, and registers into the compiling module a
  call macro under the C name that tuples every argument past the fixed ones (`VaNone()` when
  there are none). `Program::makeCall` searches every module of the program for a call
  macro, so a requirer's call sites are intercepted too; a call the parser meets before the
  definition has no macro yet and does not resolve (`docs/probe-findings.md` F37). The
  registration goes through `compiling_module()`, never `this_module()`, which is unreachable
  once the macro module has compiled. A function value travels as `void?` like a pointer. A C
  `va_list` is `CVaCursor`, the address of the function's list and the position of the next
  argument (F35): `va_begin(va)` starts one, `va_i`, `va_d` and `va_p` pop an `int64`, a
  `double` and a `void?`, assignment copies one (`va_copy`), and `va_rest(v)` is the list from
  the cursor on, which a `CVaList` callee takes (F36). A `var CVaCursor` parameter is the
  caller's cursor. An integer pop reads a pointer's bits and a pointer pop reads an integer
  zero as null, as one x86-64 register carries either; any other class, a pop past the
  arguments passed and a pop of a cursor no `va_begin` started panic, each message naming the
  trailing argument by its index from 0 and the class found.
- `c_runtime/printf.das` - the printf family over a `CVaList`: `c_vformat` splits the C
  format at its directives, pops through a `CVaCursor`, resolves `*` widths and precisions
  from the list, and renders each directive through the one `crt::snprintf_*` matching its
  conversion and length modifier, retrying from the same argument into a CRT buffer when the
  512-byte scratch is short. `c_long_bits` is the dialect's `long` width (the host CRT's until
  a converted module's `[init]` sets it), and `c_dialect_spec` hands the CRT a directive with
  no `long` left in it: an integer `l` becomes nothing (32) or `ll` (64), an integer `L` `ll`
  (glibc reads it so), a floating `L` `l`, since the dialect's `long double` is a `double`; a
  wide `%lc`, `%ls` or `%l[` panics where the dialect's `wchar_t` is not the host's, which is
  where the two `long`s differ; `c_vsnprintf` and
  `c_vprintf` (bytes through `crt::fwrite_stdout`, so they order with every other CRT write)
  are the fronts with `c_vsprintf` (`c_vsnprintf` with no bound) and `c_vfprintf` (bytes
  through `crt::fwrite` to a stream, a `FILE *` as `void?`), and `printf`, `fprintf`,
  `sprintf`, `snprintf` are `[variadic]` over them. The directive parser, `c_parse_directive` and its
  `CFormatDirective`, serves the scanf family too: a `*` before the width (a scanf
  suppression, parsed in scanf mode, where a printf `*` takes the width's place) and a scanf
  set running to its `]` parse alike. An
  argument of the wrong class for its directive panics, which is the C undefined behavior
  made visible; a null format renders nothing. The bytes are the CRT's by construction,
  which `tests/test_printf.das` proves against a native battery compiled by the pinned clang.
- `c_runtime/scanf.das` - the scanf family over a `CVaList`: `c_vsscanf` walks the C format,
  matching its whitespace (any run of input whitespace) and its ordinary characters in das,
  and hands every other directive with a trailing `%n` (after `c_dialect_spec`) to `crt::sscanf_one` (the C program's
  out-pointer passed as it is, so the CRT writes at the width the directive names) or, for a
  directive that assigns nothing (`%*d`, `%%`), to `crt::sscanf_none`, moving on by the bytes
  the `%n` reports; `%n` itself stores the count at the dialect's width its length modifier
  names, in das. A directive C's scanf does not define (glibc's `%m`, `%q`, `%1$d`, a `%` ending
  the format) panics before it takes an argument. The scan stops at the first directive that
  does not match and returns the assignments made, or `C_EOF` when the input ends before the
  first; an out-argument that is no pointer panics. `sscanf` is the `[variadic]` front; a
  stream scanf is not here. The behavior is the CRT's by construction, which
  `tests/test_scanf.das` proves against a native battery.
- `c_runtime/setjmp.das` - the setjmp/longjmp protocol over das's own unwinding
  (`docs/lowering-examples.md` "setjmp / longjmp"): `CJmpBuf` holds the longjmp value,
  `c_jmp_target` the buffer a longjmp in flight targets, and `c_longjmp(buf, v)` records both
  (a zero value as 1, as C says) and panics; the `recover` of every setjmp site the unwind
  passes compares `c_jmp_target` with its own buffer, rethrows another's or a genuine panic
  (a null target), and clears its own. das skips `finally` on a panic, which is C's
  no-cleanup-on-longjmp rule. `c_longjmp` takes the buffer as a `var` pointer and writes
  `buf.val` through it; every converted pointer parameter is `var` (F3), so the buffer arrives
  writable.
- `c_runtime/c_bitfields.das` - the `[c_bitfields(...)]` structure annotation over a struct
  written C-shaped (`docs/lowering-examples.md` "Bitfields"). `apply` reads the argument list in
  order: `_bits<N> = "uint8"` (or `"uint16"`, `"uint"`, `"uint64"`, or `"uint8[k]"`, a byte
  unit of `k` bytes from 1 to 8 at alignment 1) opens an allocation unit with its bit cursor at
  0, `_<K> = n` advances the cursor by `n` padding bits, any other `name = width` places the
  field `name` at the cursor; a bitfield with no unit open opens `_bits<K>`
  sized by the field's own type. The opener's value is a string because the storage type names
  are keywords the argument grammar does not take as identifiers. A unit's fields must be
  adjacent and of an integer or `bool` type, and must fit; a unit's name, opened or implied,
  must be no field of the struct and no other unit's, so the storage never replaces a field.
  Each unit's fields become one `_bits<N>` field at the place of its first, and each bitfield
  gets the property pair `c_storage` builds over it. `c_unit_bytes(w, default<uint8[k]>)` is the
  bytes of a byte unit holding the word `w`, little-endian, which the converter's folded
  initializer names; its type parameter is `UnitBytesT`, since a generic's `auto(T)` binds a
  struct `T` visible where the generic is declared, its own module or one it requires
  (`probes/test_bitfields.das`).
- `c_runtime/c_storage.das` - the unsigned storage types and the bit arithmetic the layout
  annotations share: `C_STORAGES` (`uint8`, `uint16`, `uint`, `uint64`, each with its size in
  bytes, which is its alignment, its width in bits and its das base type), found by name or
  width (`storage_of`) or by size (`storage_of_bytes`); and `bit_getter`/`bit_setter`, the
  property pair `operator . name`/`operator . name :=` of one bitfield (`BitAccess`: its name,
  declared type, bit offset and width) over the field that holds it (`BitStore`: a scalar of a
  storage type, or an array of one whose first `count` elements hold the bits, little-endian).
  The getter shifts and masks (a signed field shifts its top bit to the word's top and back,
  which sign-extends), the setter clears the field's bits and ors the masked value in. The
  arithmetic runs in `uint`, or `uint64` past 32 bits of store, since das defines no shift on
  `uint8` and `uint16`; an array store is assembled into the word and written back one element
  at a time, each narrowing on store. `[c_bitfields]` builds a pair per unit field,
  `[c_union]` per bitfield member.
- `c_runtime/c_union.das` - the `[c_union]` structure annotation over a union written as a
  C-shaped struct (`docs/lowering-examples.md` "Unions"). `apply` replaces the members with one
  field `_storage : U[k]`, `U` the `c_storage` type of the union's alignment and `k` its size
  over that alignment, so das lays the union out at its C size and alignment, and gives each
  member two `operator . name`: over a `var` union a reference into the storage,
  `*addr<T?>(s._storage)`, which serves reads, stores, compound stores, `++`, a nested field and
  `addr`; over a const union the value, so a `let` parameter reads (`probes/test_unions.das`).
  Punning is memcpy semantics by construction. `[c_union(size = N, align = A)]` states the size
  and alignment; the bare form derives them from the members, the largest size rounded up to the
  largest alignment, which takes every member type known when the struct is parsed: `apply` runs
  before inference, where a struct declared earlier is resolved and a later one is an alias, a
  dimension spelled by a constant (`int[N]`, `int[int(E.A)]`) is not folded yet, and a
  zero-length dimension has no size; a pointer or a function value is pointer-sized whatever it
  points at. `patch` cannot take the derivation later, since it runs only once the whole program
  infers without error (`probes/test_unions.das`). An inference-time `static_assert` in each
  operator checks the member fits the storage. A function-typed member is pointer-sized like any
  other, so a union of function pointers (Doom's `actionf_t`) is one 8-byte storage and a
  call through any member calls the function last stored, with the arguments that call passes
  (`docs/probe-findings.md` F32). Any other argument `name = width` names a bitfield member at
  bit 0 (`[c_union(f0 = 8)]`): it gets the `c_storage` property pair over the storage's leading
  elements that hold the width, in place of the two operators, since bits are not addressable;
  a member spelled `size` or `align` is never a width. Another annotation on the same struct is
  not visible to `apply` (the parser attaches the list after every `apply` ran), which is why
  the widths are this annotation's own arguments. A class, a struct with no member, a member
  named `_storage`, one with an initializer, a lone `size` or `align`, a non-integer one, an
  alignment past 8, a size that is not a positive multiple of the alignment, an argument naming
  no member, a non-integer width and a width that does not fit its member's integer type or the
  storage are compile errors.
- `c_runtime/c_bounds.das` - `end_index(k, n)`, the index of C's `&a[k]` into an array of `n`
  elements: the converter spells that address `addr(a[0]) + end_index(k, n)`, since `addr(a[n])`
  trips das's range check while C forms the address one past the end (`docs/probe-findings.md`
  F45). It panics with das's own wording past `n` or below zero (an unsigned compare) and
  returns `k` in its own type.
- `c_runtime/c_sort.das` - C's `qsort` and `bsearch` as `c_qsort(base, n, size, cmp)` and
  `c_bsearch(key, base, n, size, cmp)`, over raw bytes in C's own signatures, since the
  element type is not at C's call site, whose `n` and `size` are run-time values
  (`docs/probe-findings.md` F33). The CRT's `qsort` is not bound: it cannot call back
  into das. The comparator is `CCompare`, `function<(var a : void?; var b : void?) : int>`,
  the converter's spelling of C's `int (*)(const void *, const void *)`, whose data pointer
  positions are `var` like every converted pointer parameter's, so a converted comparator
  arrives as it is. `qsort` is the runtime's byte sort, `__builtin_sort_any_cblock` (the
  engine under daslib's `sort`: median-of-three Hoare partitions over the bytes, its own pivot
  copy, no das value), with the comparator in a block testing `< 0`; it is unstable, as C
  allows, and counts elements and bytes in `int`, so a call past that panics. `bsearch` is a binary search calling `cmp(key, element)` in C's order.
- `tests/` - one dastest file per piece, written as the converter will emit the code,
  including a control that the same code without the piece is rejected or wrong. A test that
  compiles or runs a child program does so through `probes/_daslang_child.das`, the one child
  helper of the repository (`runtime_child` loads both modules), required by relative path.

## 2. Loading

The module lives outside `DASLANG_ROOT/modules`; every daslang run that reaches it passes
`-load_module <repo>/c_runtime` before the script path (`scripts/preflight.sh`, `.mcp.json`),
the same way `dasCRuntime/` is loaded.

## 3. Exception ledger

- `REVIEW.md`, the rule against storing on the das heap bytes the converted program can take
  the address of or that outlive the call that made them: `printf.das` and `scanf.das` build each directive's format text as a das string
  (`resolve_stars`, `c_dialect_spec`, `crt_piece`) and pass its bytes to one CRT call;
  `c_vformat` collects the rendered bytes in a das array that `c_vsnprintf` copies into the
  program's buffer and `c_vprintf` writes to stdout; a `CVaList` is the das array
  `[variadic]` builds from a call's trailing arguments, which the program reads only by value
  through a `CVaCursor` (`va_i`, `va_d`, `va_p`). The program addresses and keeps none of
  them, and each dies with the call, so none is an exception to the rule; the scanned bytes
  stay in the program's own buffers.
