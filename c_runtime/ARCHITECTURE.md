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
  normal return from `main`, `c_exit(code)` runs it and ends the process with `exit_now`
  because daslang's `exit` reports 1 whatever its argument (`docs/probe-findings.md` F1),
  `c_abort` is `exit_now(3)` with no handler run, which is C's rule and the baseline's code.
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
  macro, so a requirer's call sites are intercepted too. The registration goes through
  `compiling_module()`, never `this_module()`, which is unreachable once the macro module
  has compiled.
- `c_runtime/printf.das` - the printf family over a `CVaList`: `c_vformat` splits the C
  format at its directives, resolves `*` widths and precisions from the list, and renders
  each directive through the one `crt::snprintf_*` matching its conversion and length
  modifier (`l` is wide only where `crt::LONG_BITS` is 64, so the CRT sees its own `long`),
  retrying into a CRT buffer when the 512-byte scratch is short; `c_vsnprintf` and
  `c_vprintf` (bytes through `crt::fwrite_stdout`, so they order with every other CRT write)
  are the fronts, and `printf`, `sprintf`, `snprintf` are `[variadic]` over them. An
  argument of the wrong class for its directive panics, which is the C undefined behavior
  made visible; a null format renders nothing. The bytes are the CRT's by construction,
  which `tests/test_printf.das` proves against a native battery compiled by the pinned clang.
- `c_runtime/setjmp.das` - the setjmp/longjmp protocol over das's own unwinding
  (`docs/lowering-examples.md` "setjmp / longjmp"): `CJmpBuf` holds the longjmp value,
  `c_jmp_target` the buffer a longjmp in flight targets, and `c_longjmp(buf, v)` records both
  (a zero value as 1, as C says) and panics; the `recover` of every setjmp site the unwind
  passes compares `c_jmp_target` with its own buffer, rethrows another's or a genuine panic
  (a null target), and clears its own. das skips `finally` on a panic, which is C's
  no-cleanup-on-longjmp rule. The buffer arrives as C passes it, through a pointer a `let`
  parameter may hold, so the write goes through a pointer re-made from its address.
- `c_runtime/c_bitfields.das` - the `[c_bitfields(...)]` structure annotation over a struct
  written C-shaped (`docs/lowering-examples.md` "Bitfields"). `apply` reads the argument list in
  order: `_bits<N> = "uint8"` (or `"uint16"`, `"uint"`, `"uint64"`) opens an allocation unit
  with its bit cursor at 0, `_<K> = n` advances the cursor by `n` padding bits, any other `name =
  width` places the field `name` at the cursor; a bitfield with no unit open opens `_bits<K>`
  sized by the field's own type. The opener's value is a string because the storage type names
  are keywords the argument grammar does not take as identifiers. A unit's fields must be
  adjacent and of an integer or `bool` type, and must fit; a unit's name, opened or implied,
  must be no field of the struct and no other unit's, so the storage never replaces a field. Each unit's fields become one
  `_bits<N>` field at the place of its first, and each bitfield gets `operator . name` and
  `operator . name :=`: the getter shifts and masks (a signed field shifts its top bit to the
  word's top and back, which sign-extends), the setter clears the field's bits and ors the
  masked value in. The arithmetic runs in `uint`, or `uint64` for an 8-byte unit, since das
  defines no shift on `uint8` and `uint16`; the value narrows on store.
- `tests/` - one dastest file per piece, written as the converter will emit the code,
  including a control that the same code without the piece is rejected or wrong.

## 2. Loading

The module lives outside `DASLANG_ROOT/modules`; every daslang run that reaches it passes
`-load_module <repo>/c_runtime` before the script path (`scripts/preflight.sh`, `.mcp.json`),
the same way `dasCRuntime/` is loaded.

## 3. Exception ledger

Empty.
