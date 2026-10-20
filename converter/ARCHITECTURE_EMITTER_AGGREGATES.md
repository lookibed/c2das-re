# converter Architecture - the emitter's aggregates, function pointers and variadics

Companion to `ARCHITECTURE.md` in this folder, continuing section 4 of `ARCHITECTURE_EMITTER.md`.

### Bitfields

A record with bitfields is the C-shaped struct under `[c_bitfields(...)]` (`c_runtime/c_bitfields`,
`docs/lowering-examples.md` "Bitfields"): each named bitfield is a field of its declared das
type, an unnamed one is no field, and the annotation lists the allocation units `bit_units`
finds, in order. A unit opens with `_bits<N> = "uint8"` (`"uint16"`, `"uint"`, `"uint64"`),
left out for the first unit when its storage is the one the macro opens by default for its
first field (the unsigned type of its declared type's width) and that
field starts the unit; then each bitfield of the unit as `name = width`, preceded by a padding
argument `_<K> = gap` (K counting across the record) when clang leaves bits before it. Under
the `msvc` dialect the documents' `[c_bitfields(a = 3, b = 5)]` comes out as written; under
`linux` the same struct packs into a byte, which takes the opener (F25). A member reads and
writes as a field, `s.a` and `p.a` alike, through the generated property pair; das has no `++`
on a property, so a bitfield step is `s.a += 1u` (`probes/test_bitfields.das`). A record
initializer folds each unit's initialized bitfields into one `_bits<N>` item, `U((W(v1) & m1)
| ((W(v2) & m2) << o2))` with `W` the unit's arithmetic type (`uint`, `uint64` for an 8-byte
unit) and `U` its storage, the setter's own conversions, since a global `fixed_array` of struct
literals naming a property crashes the program before `main` (`probes/test_bitfields.das`). A
record with only unnamed bitfields is a plain struct. A bitfield of enum type, a bitfield of a
marshal-only record, a record with bitfields no unit assignment reproduces (`packed`, with its
own message, never pointing at the sidecar), a flexible array member, a bitfield named like an
opener or a padding argument (`_bits0`, `_3`) and another field named like a storage field the
record emits fail closed. The layout check asserts the das alignment a record ends with, which
for a record holding bitfield units, or a record holding such a record, can be below clang's.

### Unions

A union is the C-shaped struct under `[c_union]` (`c_runtime/c_union`, `docs/lowering-examples.md`
"Unions"): each member a field of its das type, the annotation turning them into one storage
field and a pair of `operator .` per member. The bare annotation derives the size and alignment
from the members, so it stands when the members, each measured by its das alignment, give
clang's (`union_member_layout`) and no member's type spells a dimension by an enum constant,
which das folds only after the annotation has read the member types; otherwise the annotation
states clang's numbers, `[c_union(size = 4, align = 4)]` (a member record whose das alignment
is below clang's, F5; an `aligned` attribute up to 8). A member reads, stores, steps (`u.i++`),
takes compound stores and its address (`addr(u.i)`) and reaches a nested field (`u.pt.x = 7`)
as a field does, `u.f` and `p.f` alike, through the ref-returning operator; a const base reads
through the value one. `offsetof` of a member is `T(0)`, `sizeof` the type's
`typeinfo sizeof`. A struct literal cannot name a member, so an initializer never puts a union
in a literal: a union's list is the bare declaration and one store into the member it names
(`var u : U` then `u.d = 2.5lf`; `{0}` and `{}` store nothing, the storage starting at zero), a
union's list inside a record's or an array's list is left at the record's or array's zero and
stored after the literal (`var t : Tagged = Tagged(tag = 5)` then `t.m.i = 9`, `arr[1].pt =
Point(x = 5, y = 6)`), and for a global those stores run in `c2das_init_globals`. Since the
stores come after the literal, an initializer holding a union's list whose items have an effect
(a call, an assignment, a step) evaluates every item into a temporary first, in source order
(`let _t0 = side()`), and the literal and the stores read the temporaries, which keeps C's
left-to-right order. A global whose declaration carries no `=` (its value is stores) counts as
zero-initialized, so a later global taking its address is stored in `c2das_init_globals` too.
An anonymous member (a struct or union member with no declarator) is the field `_anon<N>`, `N`
its index, of the record type `anon_<slot>`, so `s.i` through an anonymous union is
`s._anon1.i`. A function-pointer member is a member like any other (Function pointers, below). Fail
closed: a bitfield member of a union; a union
the layout law finds unnatural, with its reason (no member, an alignment that is not 1, 2, 4 or
8 or does not divide the size, an alignment below a member's, a member that does not fit, a
member record das cannot lay out); a union holding a marshal-only record; a member named
`_storage`; a field spelled `_anon<N>` in a record with an anonymous member; a zero-length
array (`char z[0]`, GNU) anywhere; and a union's list anywhere but an initializer.

### Function pointers

A C function pointer is a das function value, 8 bytes like C's, so a record or union holding
one keeps clang's layout. das types a parameter's constness into a function type
(`probes/test_functions.das`), so one C pointer type has one spelling for every function
stored in it: a position of a function type is `var` exactly where a parameter of its type is
by the parameter rule of `ARCHITECTURE_EMITTER.md` section 4 (a data pointer, a record holding
one, a `va_list`), so every function of the signature fits it as it is
(`docs/probe-findings.md` F34), `c_qsort`'s and `c_bsearch`'s comparator `CCompare` included. A
cast between two function pointer types is `reinterpret<function<...>>(f)`, whatever the two
signatures: C defines the cast and the cast back for every pair and leaves only a call through
an incompatible type undefined, a das function value round-trips through any function type,
and a call through one passes the arguments it is given to the function itself, under the
interpreter and the JIT, as x86-64 C does, extra arguments ignored. Two types that spell one
das type (they differ in a pointee's `const` alone, which the emitter never spells) need no
cast, and the value passes as it is. An integer cast to a
function pointer is `reinterpret<function<...>>(uint64(n))`, which compares as C's does (a
`(handler_v)(-1)` sentinel); calling it is C's crash. A null function pointer reads `null` in a
comparison and is `default<function<...>>` as a value, an array's fill and a function's
fall-off return included. A call through a pointer whose callee is itself a call goes through
a temporary (`let _t0 = invoke(getter, 1)`), since the JIT crashes compiling `invoke(invoke(g,
1), 5)` of a local function value (`probes/test_functions.das`). A call through a pointer type
with another number of parameters than the call's arguments (an unprototyped `T (*)()`, which
the C-IR spells as `T (*)(void)`) fails closed.

A union whose members are function pointers (Doom's `actionf_t` shape) is the `[c_union]` of
Unions, above, with function-typed members: one 8-byte storage, every member a reinterpret of
the same bits, so a function stored through the one-argument member and called through the
two-argument one gets both arguments, as in C (`docs/probe-findings.md` F32). It needs no
sidecar entry; an array of function pointers is a member like any other.

`qsort` and `bsearch` are `c_qsort` and `c_bsearch` (`c_runtime/c_sort`), called with C's
arguments as C gives them and the converted comparator's `@@` value; the CRT binds neither,
since its `qsort` cannot call back into das (F33). The value of a function the unit does not
define (`strcmp` passed as a comparator) and a pointer to a variadic function fail closed.

### Variadics

A C variadic definition is `[variadic] def f(fixed...; va : va_args)` (`c_runtime/variadic`,
`docs/lowering-examples.md` "Variadics & printf"), the trailing parameter named `va` unless the
body takes that name (then `va1` and up), its annotation list merged with `[c_function]`
(`[c_function, variadic]`). The annotation renames the function `f`va`, makes it a generic over
the trailing tuple and registers a call macro under the C name, which tuples the trailing
arguments. A call of a variadic function of this module is spelled as that macro expands it,
`sum`va(3, (1.5lf, 2))`, `(a,)` for one trailing argument and `VaNone()` for none: a generic
body keeps a macro call uninferred, daScript's module cache refuses to write a macro the module
itself owns, and the spelled call resolves at inference, above its definition and inside it
(`docs/probe-findings.md` F37), so definitions stay in C's order and recursion, direct or
mutual, lowers. A call of the library's variadics (`printf`, `sscanf`) keeps C's spelling,
`printf(fmt, x)`. A `va_list` is `CVaCursor`, the list's
address and a position (F35): `va_start(v, last)` is `v = va_begin(va)`, `va_copy(w, v)` is
`w = v`, and `va_end` is no statement. `va_arg(v, T)` pops the class C's default promotions
gave the argument: `va_i(v)` narrowed to an integer `T` (`int(va_i(v))`, `va_i(v) != 0l` for
`_Bool`), `enum_from_int` of its `int` for an enum, `va_d(v)` for `double`,
`reinterpret<T>(va_p(v))` for a pointer, a function pointer included, which makes the body
`[c_function]`. A read at `char`, `short`, `_Bool` or `float` is undefined in C, since no
argument arrives as one, and reads the promoted value (`float(va_d(v))`). A pop is an effect
for statement-ification. A `va_list` parameter is `var ap : CVaCursor` and never takes the
callee copy: the callee's pops advance the caller's cursor, as linux's decayed array does
(msvc copies its `char *`, after which C leaves the caller's list indeterminate, so the two
agree on every defined program); a function type's `va_list` position is `var` alike, so
`int (*)(va_list)` holds such a function. A library function taking a `va_list` takes
`va_rest(v)`, the arguments from the cursor on (F36): `vprintf`, `vsprintf`, `vsnprintf` and
`vsscanf` are `c_vprintf`, `c_vsprintf`, `c_vsnprintf` and `c_vsscanf`, and `sscanf` is the
`[variadic]` front of `c_runtime/scanf`. A module reaching the printf or the scanf family opens
with `[init] def private c2das_dialect`, its first `[init]`, setting `c_long_bits` to the
dialect's `long` width, which every `l` directive then reads. `sizeof(va_list)` is clang's size. Fail closed: `va_arg` of a
record or of a `va_list`; a record or a `va_list` passed through `...`, naming the argument and
the callee; a `va_list` global or field; a pointer to a `va_list` and an array of them (the
dumper's); `va_start`, `va_end` or `va_copy` read as a value; a C name `_va_tuple` in a
variadic function, the annotation's own; and a pointer to a variadic function.
