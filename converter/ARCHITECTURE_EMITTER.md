# converter Architecture - the emitter

Companion to `ARCHITECTURE.md` in this folder; section numbers are unique across the family.

## 4. What the emitter spells

The module opens with the generated banner, `options gen2`, `options indenting = 4` and one
`require c_runtime/<name>` per piece the body reached (`printf`, `c_exit`, `c_function`).
Records come first: `struct Name` with adjacent fields of one type on one line, an unnamed
record named `anon_<slot>`, in declaration order; then `[init] def private c2das_layout_check`,
one `static_assert` per record against clang's size and alignment and one per field against its
offset, the layout law checked at compile time where it is claimed
(`docs/implementation_order.md` P2.1). A union and a bitfield fail closed until their rows
(P4.2, P4.1); a record clang lays out unnaturally fails closed unless the sidecar lists it
under `marshal` (section 4, marshal-only records). Globals follow (`var`, `var private` for a C
`static`, the initializer inline and under `unsafe(...)` when it takes an address; an unsafe
operation inside a global initializer wraps itself, one `unsafe(...)` per operation, since no
annotation covers a global), then `[init] def private c2das_init_globals`, then the functions.
das orders global initialization, so an initializer stays inline only while every global whose
address it takes has an explicit initializer and precedes it (`probes/test_globals.das`); an
address of a zero-initialized or later global moves the whole initializer into
`c2das_init_globals` as an assignment, which also holds the stores of a sparsely filled array
(`docs/lowering-examples.md` "Globals & initializers"). A function's value (`@@f`, from a decay
or from `&f`; C `main` is `@@c_main`) and a literal's address need no order. A null function
pointer is `default<function<...>>`, since das takes no `null` for a function value
(`probes/test_globals.das`). A function is `def name(p : T; ...) : ret` with `private` for a C
`static`; a parameter the body writes is declared `p_in` with `var p = p_in` as the first
statement, the callee copy C's by-value rule needs, since a das parameter is a reference; a
store that reaches the parameter through `.f` or an array's `[i]` is a write to it, while one
that crosses `->`, `*p` or a pointer's `[i]` writes what it points at and makes the parameter
`var`, the one spelling whose pointee stays writable (F3); a pointer parameter copied into a
pointer local or variable (`int *it = a`) is `var` for the same reason, since the copy of a
`let` parameter carries a const pointee. A body that used an unsafe operation (pointer
arithmetic, `deref`, `addr`, a `reinterpret`, a string literal) gets `[c_function]`. C `main`
becomes `c_main` and the module ends with `[export] def main : int { return c_main() }`, whose
`return` is the CLI's exit-code contract (`docs/probe-findings.md` F1). A C name that is a das
keyword takes the `_c_` prefix.

An enum is `enum Name { items }` with das's default `int` base, emitted before the records, an
item stating `= v` only where C's count-from-the-previous rule would not give its value, a
value past INT_MAX wrapped to the negative `int` of the same bits and INT_MIN as `-2147483647 -
1` (das reads `-2147483648` as a negated out-of-range constant; `probes/test_enums.das`), and
an unnamed enum named `anon_<slot>` like a record. An enumerator reaches the text as
`Name.ITEM` and the emitter keeps it symbolic where das can take the enum: a conversion into
its own enum (`t = MT_SHOTGUN`, an initializer slot, an argument), a literal whose value an
enumerator has (`(E) 0` is `E.ZERO`), `==`/`!=` between two values of one enum, which das
compares directly, and a ternary of two values of one enum whose arms hoist nothing (an arm
with a hoisted statement takes `emit_cond`'s if-chain). C's conversions between the enum and
those sites are looked through only while they keep the value: its promotion, and a widening
that keeps its sign; a narrowing or a sign change (`(unsigned) e` of an enum with a negative
enumerator) stops the look-through, since C compares the converted values. Where C reads the
enum as an integer the value goes through `int(e)`, bit-exact for every 32-bit type - a
relational operator, an index, arithmetic, a `printf` argument - the workhorse cast following
when C computes in another type (`uint(int(e))`), and through `uint(int(e))` before a 64-bit or
floating target when the enum's underlying type is unsigned, where `int(e)` would read a value
past INT_MAX as a sign. An enumerator C types `unsigned int` (one of its enum exceeds INT_MAX)
is spelled `uint(int(E.X))`. A conversion into an enum from anything else is
`enum_from_int(type<E>, i)` over the `int` value, which `++`, `+= 1` and `t = t + 1` all take
(`t = enum_from_int(type<E>, int(t) + 1)`); a compound assignment computes in the type clang
gave its right side, except a shift, which computes in the promoted left side, `uint` for an
unsigned-underlying enum (and for `unsigned w >>= n`), with an unsigned count. An enum's truth
is `int(e) != 0`; its zero is the enumerator of value zero when it has one, else
`enum_from_int(type<E>, 0)`, since das rejects `default<E>` for an enum without a zero
enumerator (`probes/test_process.das`; aggregates and globals of such an enum still zero,
`probes/test_enums.das`). A dimension the declarator spells by an enum constant stays
`[int(E.COUNT)]`, which das folds (`probes/test_enums.das`). A member is `a.f`, and `p.f` for
`p->f` and `(*p).f` alike, which das reads through a pointer without `deref` or unsafe; a
record initializer is `S(f = v, ...)` naming the filled slots. An array is `T[2][3]` with the
dimensions in C's order and `T? [N]` for an array of pointers, since `?[` lexes as the
safe-index operator; its initializer is one `fixed_array` holding every element, the unwritten
ones as zero literals, except an array past 32 elements the source fills sparsely, which is the
bare declaration followed by one store per written element (at module init for a global); a
`char[N]` from a string literal is `cstr_array("...", N)`. A subscript of an array is the das
index, range-checked (the documents' safety oracle); a subscript of a pointer is `deref(p +
i)`; a row pointer is `T[N]?` and reads as `deref(row)[i]`; decay is `addr(a[0])`. A function
pointer is a das function value, `function<(a0 : T; ...) : R>` with the parameters named by
position, a function's name decays to `@@name`, and a call through a pointer, `fp(...)` or
`(*fp)(...)`, is `invoke(fp, ...)`. A pointer difference is `int64(p - q)`, in elements as C
counts them; a pointer relation goes through `intptr`; `malloc`, `calloc`, `realloc`, `free`
and the `mem*` family are the CRT's through `crt`, with C's implicit `void *` conversions as
explicit `reinterpret`. `[c_function]` lands only on a body with an unsafe operation, and the
emitter counts those bodies against all the unit defines: the port-progress metric `main.das`
reports; `sizeof` and `offsetof` are `T(typeinfo sizeof(type<S>))` and `T(typeinfo
offsetof<f>(type<S>))`, never clang's constants, with the cast to the C result type. A string
literal in a pointer context stays a das literal, `reinterpret<uint8?>("...")`, which is a
NUL-terminated interned byte array (`probes/test_strings.das`); the empty literal is the one
exception, since das's `""` is a null pointer (`docs/probe-findings.md` F10): it is
`addr(c2das_empty[0])`, a one-byte private array the module declares right after its requires,
before any global whose initializer takes the address. A `char[N]` initialized from a literal
is `cstr_array("...", N)`, the empty literal included. A literal indexed in place
(`"abcdef"[2]`) is read through its pointer, `deref(p + i)`; a literal under `sizeof` is its
array type. A call to a libc function the C program declares resolves through two tables:
`C_RUNTIME_CALLS`, the functions a `c_runtime` piece lowers (`printf`, `sprintf`, `snprintf`,
`exit`, `abort`) by the module that holds the piece, and `CRT_CALLS`, the functions the `crt`
module binds under their C names (the memory, string.h, ctype, conversion, time and random
families of `dasCRuntime/ARCHITECTURE.md`), spelled `crt::name`; a function in neither fails
closed. A `size_t` result is `uint64`, so an index or a count it feeds carries the cast C gives
it. Expressions carry the C-IR casts: `IntegralCast` and the floating casts are the workhorse
cast, `IntegralToBoolean` is `x != 0` (`!= null` for a pointer), `BooleanToSignedIntegral` is
`b ? 1 : 0`, a comparison or `!` is spelled as the das bool it is and becomes `? 1 : 0` only
where C reads it as an int. Literals carry their suffix from the C-IR type (`u`, `l`, `ul`,
`lf`, `f`), small integers wrap in a cast. A compound assignment whose operand types differ
expands to `lhs = T_lhs(T_rhs(lhs) op rhs)`, which is C's small-int rule (`b = int8(int(b) +
1)`). Statement-ification happens at emission: an assignment, a step or a call met inside an
expression is hoisted into the statements before the current one (`let _t0 = x` then `x++` for
a postfix step), left to right; a comma is two statements; `&&` and `||` with a hoisted right
side become a flag and an `if`; a ternary whose arm carries hoisted statements becomes `var _tN
: T` and an `if`/`else`, while a ternary of pure arms stays inline since das `?:` evaluates
only the taken arm (F18). Loops follow the documents: `while` is `while`, with a side-effecting
condition spelled `while (true)` plus the test and `break`; `do` is the `_first` flag; `for` is
a bare block holding the initializer and one of three loops: `while (cond) { body }` when there
is no increment, `while (cond) { { body } finally { inc } }` when the body never leaves the
loop (no `break` at its level, no `return`, no `goto`), since `finally` runs on `continue` and
on every pass but also on `break`, and the `_f` increment-first flag otherwise; `if` chains
spell `elif` when the nested condition is pure. The split is measured:
`benchmarks/bench_for_shapes.das` times one body under the three spellings, and under the
interpreter the `finally` form costs 10.6 ns per iteration against the flag's 14.2 and the
native `range` loop's 4.9 (the O1 rewrite's target), while the JIT compiles all three alike.
Compound literals, a string literal outside a pointer or `char[N]` context (where the empty one
has no das spelling either, F10) and a call to an external function in neither call table are
errors until their lowering lands (`docs/implementation_order.md`, P2 onward).

A marshal-only record - one the sidecar lists under `marshal`, by tag or typedef name - lives
in C memory as bytes at clang's offsets and as a value is the naturally laid out das struct of
its fields, which carries no layout assertion (`docs/lowering-examples.md` "Packed structs").
Beside the struct the emitter writes `read_T(bytes, ofs)`, `write_T(bytes, ofs, v)` and a
`read_T_f`/`write_T_f` pair per field, each a `crt::memcpy` of the field's C size at its
offset, so no alignment is assumed and the value side is a plain struct copy. A pointer to
such a record is `uint8?`: `p->f`, `(*p).f` and `p[i].f` read through `read_T_f`, a store or
step into them writes through `write_T_f` around the read, `*p` is `read_T(p, 0)`, `*p = v` is
`write_T(p, 0, v)`, `sizeof` is clang's size as a literal, and a pointer step, `p + n`, `p[i]`,
`p - q` scale by that size. A packed record the sidecar does not list, the address of a
marshal-only value, an array of the record and a record or array-of-records field inside one
fail closed.

Output is assembled as an array of lines joined once (`docs/probe-findings.md` F19); the
text then goes through the formatter, so spacing is the formatter's and indentation is the
emitter's, four spaces per depth.
