# c_runtime Architecture - the compile-time pieces

Companion to `ARCHITECTURE.md` in this folder, whose contract, loading and fixture-test
spelling bind it. A piece here is an annotation or a call macro: it acts while the program
compiles, rewriting converted code in place or generating a type's accessors, so the
interpreter, the JIT and AOT all run the code it produced.

## 1. File charters

- `c_runtime/c_function.das` - the `[c_function]` function annotation: `apply` replaces the
  body with `unsafe { <body> }` before inference. The converter emits it only on a function
  whose body contains an unsafe operation, so its count across a converted program is the
  port-progress metric of the follow-up story; nothing else about the function changes.
  `unsafe` does not reach into a lambda or generator body, which C never produces.
- `c_runtime/enum_from_int.das` - `enum_from_int(type<E>, i)`, the C int-to-enum conversion:
  a call macro that expands in place to the one `reinterpret<E>(i)`, flagged safe, so converted
  code carries no `unsafe`, the interpreter makes no call per conversion, and an out-of-range
  value survives by value as C's does.
- `c_runtime/cstr.das` - `cstr("...")`, a C string literal in a pointer context: a call macro that
  expands in place to the one `reinterpret<uint8?>("...")`, flagged safe, so a literal needs no
  `unsafe` (and alone no `[c_function]`) and the interpreter makes no call per literal; a call
  whose argument is no string literal is left to a program's own `cstr`, which C's `cstr("x")`
  becomes as `cstr(cstr("x"))`.
- `c_runtime/int_of.das` - `int_of(a < b)`, C's int value of a truth, 1 or 0: a call macro that
  expands in place, once its argument is inferred, to the ternary `a < b ? 1 : 0`, so it is the same
  nodes and no call under any tier (das has no `int(bool)`). An argument that is no `bool` is a
  compile error; the name is reserved for the converter, so no program's function takes it.
- `c_runtime/c_do_while.das` - `c_do_while (c) { body }`, C's `do { body } while (c);`: a call macro
  that expands in place before its arguments are inferred (`canVisitArgument` is false, so the
  block is never typed as a block), splicing the block's statements into `while (true) { body;
  if (!(c)) { break } }`, or, when the body holds a `continue` outside every loop it nests (an
  inner `c_do_while` included, a `match` arm's counted), into `var first = true; while (first || c)
  { first = false; body }` under a fresh name, so a `continue` reaches the test. The loop's own
  nodes take the call's line; a `break`, `return` or `goto` in the body leaves as from the spelled
  loop. The name is reserved for the converter.
- `c_runtime/c_switch.das` - `c_switch (x) { case (A, B) { body } case (_) { body } }`, C's switch
  with C's meaning: a call macro expanding in place before its arguments are inferred, inner
  switches first. An arm not ending in `break`, `return`, `continue` or `goto` falls into the next;
  `_` is `default`, anywhere. With no arm falling into the next and no `break` of the switch's own
  level (outside every loop and inner `c_do_while`) but an arm's tail, it is `if (x == A || x ==
  B) { } elif ... else { }` with the tail breaks dropped, else the matched-flag loop `while (true)
  { var flag = false; flag ||= x == A; if (flag) { body } ... break }`, an arm neither entered nor
  entering testing its values in its own `if`, an own `continue` setting a flag, leaving the loop
  and continuing after it. `x` is read in place when it is a variable (a store into it decides no
  later test: an arm runs only once matched), else once through a `let`. A duplicate value, a
  second `_` and a statement that is no arm are compile errors (`switch` is no module name).
- `c_runtime/cstr_array.das` - the `cstr_array("abc", N)` call macro: C's `char buf[N] = "abc"`
  as a `uint8[N]` literal built at compile time from the decoded string bytes, a NUL and zero
  padding; an exact fit carries no NUL, a longer string is a compile error. The das literal
  does the escape decoding, so the macro only spells bytes.
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
- `c_runtime/c_macro.das` - the `[c_macro]` function annotation, the carrier of a C function-like
  macro folded back into a def: `transform` replaces every inferred call with the def's written
  body (a generic instance's is its generic's), each parameter substituted by its argument
  expression as written, so an argument is evaluated where and as often as the body names it, as
  C's expansion does, and the interpreter runs no argument copy, result local or lowered condition,
  which `[inline]`'s splice binds (`docs/probe-findings.md` F104, F107). An expression body becomes
  the expression, a bare `null` the def's result type's `default`; a void def's statement body
  becomes a block in the call's place, every local and `for` iterator it declares renamed
  `_cm<n>_<name>` with `n` counting the expansions, so neither the caller's names nor a nested
  expansion's are captured or shadowed. `[c_function]`'s `unsafe` stays with the body: each node of
  an expression is flagged safe before the arguments go in, a block is wrapped in `unsafe`. A body of
  any other shape, a value returned after a statement or a bare `return`, is a compile error, so
  the emitter and the macro cannot disagree silently.
