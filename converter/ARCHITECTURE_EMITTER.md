# converter Architecture - the emitter

Companion to `ARCHITECTURE.md` in this folder; section numbers are unique across the family.

## 4. What the emitter spells

The module opens with the generated banner, `options gen2`, `options indenting = 4`, `options
stack` and one `require c_runtime/<name>` per piece the body reached (`printf`, `c_exit`,
`c_function`). The stack is the sidecar's `stack`, else 8388608, C's 8 MiB default on linux:
das's own context stack is 16 KiB (`probes/test_process.das`), which a record parameter's copy
on entry or an alloca arena outgrows, and a recursion multiplies.
Records come first: `struct Name` with adjacent fields of one type on one line, an unnamed
record named `anon_<slot>`, in declaration order; then `[init] def private c2das_layout_check`,
one `static_assert` per record against clang's size and alignment and one per field against its
offset, the layout law checked at compile time where it is claimed
(`docs/implementation_order.md` P2.1); a record holding bitfields asserts its das alignment,
which can be below clang's (F5), and each unit's offset; a union asserts its storage at 0
(`ARCHITECTURE_EMITTER_AGGREGATES.md`, Unions). A record clang lays out unnaturally fails closed unless the sidecar lists
it under `marshal` (section 4, marshal-only records). Globals follow (`var`, `var private` for a C
`static`, the initializer inline and under `unsafe(...)` when it takes an address; an unsafe
operation inside a global initializer wraps itself, one `unsafe(...)` per operation, since no
annotation covers a global), then `[init] def private c2das_init_globals`, then the functions.
das orders global initialization, so an initializer stays inline only while every global whose
address it takes has an explicit initializer and precedes it (`probes/test_globals.das`); an
address of a zero-initialized or later global moves the whole initializer into
`c2das_init_globals` as an assignment, which also holds the stores of a sparsely filled
array (`docs/lowering-examples.md` "Globals & initializers"). A module reaching the printf or
the scanf family puts `[init] def private c2das_dialect` (`c_long_bits`, the dialect's `long`
width) before every other `[init]`, so no initializer that formats runs ahead of it. A function's value (`@@f`, from a decay
or from `&f`; C `main` is `@@c_main`) and a literal's address need no order. A null function
pointer is `default<function<...>>`, since das takes no `null` for a function value
(`probes/test_globals.das`). A function is `def name(p : T; ...) : ret` with `private` for a C
`static`. Every data pointer parameter is `var`, and so is every record parameter whose type
holds a data pointer in a field or an array at any depth (F3). das reads every pointer reached
through a `let` parameter as a const pointee, which no `var` parameter, `var` local, returned
pointer or record copy takes (`probes/test_param_constness.das`), and the emitter never spells
C's `const`. So the one rule carries a caller's pointer to any callee that writes through it,
by a call, through `?:`, a sum, `*pp`, `->`, a record's field or a function value. A record
holding no pointer stays `let`: nothing reached through it is a pointer, and a `var` record
parameter the body never writes is a LINT014 finding, which a pointer-holding record escapes
because its copy into `var s` is a `var` slot. A record parameter, `let` or `var`, is a
reference to the caller's object in das, so the function copies it on entry, `s_in` the
parameter and `var s = s_in` its first statement, C's by-value copy, which a write the callee
makes to the caller's object through another pointer during the call does not reach
(`converter/tests/fixtures/p4_pointer_policy.c`, `alias_plain` and `alias_ptr`, F50); the
copy's parameter takes `s_in`, else `s_in1` and up, whichever no parameter, local or name the
body reads already spells. das passes a scalar, a pointer and a function value by value, so a
parameter of those the body assigns, steps or takes the address of is `var` and written in
place (`probes/test_param_constness.das`). A function type's positions follow the parameter
rule, so every function of one C type fits one das type (F34); a function pointer position is
never `var`, since a function value has no pointee. A temporary the emitter hoists holding a
pointer (an initializer list's item, an alloca's address, a stepped pointer's old value) is
`var` for the same reason as a parameter. A body that used an unsafe operation (pointer
arithmetic, `deref`, `addr`, a `reinterpret`, a string literal) gets `[c_function]`. C `main`
becomes `c_main` and the module ends with `[export] def main : int { return c_main() }`, whose
`return` is the CLI's exit-code contract (`docs/probe-findings.md` F1). A C name that is a das
keyword takes the `_c_` prefix. A local that hides one of an enclosing block or a parameter
takes the first numbered name the function leaves free (`i1`), and so does every reference C
resolves to it, since das refuses a local that shadows another (`docs/probe-findings.md` F42);
`emit_tu` renames over the C-IR in place before anything reads a name, a `for`'s declarations
scoped to the whole `for`. A temporary (`_tN`) skips every name the function spells, a C local
`_t0` included.

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
unsigned-underlying enum (and for `unsigned w >>= n`) and `int` for a `_Bool`. A shift's count, compound or not, takes
the spelling of the left side (`int(right)`, a literal its suffix), since das shifts a value
only by a count of its own type while C promotes the count apart (F40). An enum's truth
is `int(e) != 0`; its zero is the enumerator of value zero when it has one, else
`enum_from_int(type<E>, 0)`, since das rejects `default<E>` for an enum without a zero
enumerator (`probes/test_process.das`; aggregates and globals of such an enum still zero,
`probes/test_enums.das`). A dimension the declarator spells by an enum constant stays
`[int(E.COUNT)]`, which das folds (`probes/test_enums.das`). A member is `a.f`, and `p.f` for
`p->f` and `(*p).f` alike, which das reads through a pointer without `deref` or unsafe; a
record initializer is `S(f = v, ...)` naming the filled slots. An array is `T[2][3]` with the
dimensions in C's order and `T? [N]` for an array of pointers, since `?[` lexes as the
safe-index operator; its initializer is one `fixed_array` holding every element, the unwritten
ones as zero literals (`fixed_array<T?>` for an array of pointers, since an all-null literal is
a `void?` array no pointer array takes, F41), except an array past 32 elements the source fills sparsely, which is the
bare declaration followed by one store per written element (at module init for a global); a
`char[N]` from a string literal is `cstr_array("...", N)`. A subscript of an array is the das
index, range-checked (the documents' safety oracle); a subscript of a pointer is `deref(p +
i)`; an index of a small integer type widens to `int`, since das indexes by `int`, `int64`,
`uint` and `uint64` alone and C does not promote a subscript (F43); `&a[k]` of an array whose
index can reach the length is `addr(a[0]) + end_index(k, N)` (`c_runtime/c_bounds`, which
panics past `N` with das's own range-check wording), and a constant `N` is `addr(a[0]) + N`,
since C may form the address one past the end and das range-checks `addr(a[N])` (F45); a
constant below the length keeps `addr(a[k])`, and so does a constant past it, whose range
check stands for C's undefined behaviour, while a literal past `int64` counts as no constant.
In a global initializer the decay and the sum each wrap themselves, `unsafe(unsafe(addr(a[0]))
+ k)` (F48). An array of unknown length (`extern int a[];`) fails closed; a row pointer is `T[N]?` and reads as `deref(row)[i]`; decay is `addr(a[0])`. A function
pointer is a das function value, `function<(a0 : T; ...) : R>` with the parameters named by
position, a function's name decays to `@@name`, and a call through a pointer, `fp(...)` or
`(*fp)(...)`, is `invoke(fp, ...)` (`ARCHITECTURE_EMITTER_AGGREGATES.md`, Function pointers). A pointer difference is `int64(p - q)`, in elements as C
counts them; a pointer relation goes through `intptr`, and so does `==` or `!=` between two
data pointers, since das compares only pointers of one constness and a `let` pointer's pointee
is const (F44), while a null constant on either side compares with `null`; `malloc`, `calloc`, `realloc`, `free`
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
`vprintf`, `vsprintf`, `vsnprintf`, `sscanf`, `vsscanf`, `exit`, `abort`, `qsort`, `bsearch`),
one row each naming the module that holds the piece and the das name, and `CRT_CALLS`, the
functions the `crt` module binds under their C names (the memory, string.h, ctype, conversion, time and random families of
`dasCRuntime/ARCHITECTURE.md`), spelled `crt::name`, which take every pointer `let` (`strcpy`'s,
`memcpy`'s and `memset`'s destination included), since a C++ binding's parameter carries no das
constness; a function in neither fails closed. A caller's `var` pointer reaches a piece's
pointer argument as it reaches a converted function's. A `size_t` result is `uint64`, so an index or a count it feeds carries the cast C gives
it. Expressions carry the C-IR casts: `IntegralCast` and the floating casts are the workhorse
cast, `IntegralToBoolean` is `x != 0` (`!= null` for a pointer), `BooleanToSignedIntegral` is
`b ? 1 : 0`, a comparison or `!` is spelled as the das bool it is and becomes `? 1 : 0` only
where C reads it as an int. Every expression of C type `_Bool` is a das `bool`: a truth test
takes it as it is (`if (b)`), a number is `b ? 1 : 0` wherever the emitter reads one (a cast,
an index, a pointer step, an operand of arithmetic), a store, an argument, an initializer and a
`return` keep the truth when their own C type is `_Bool`, and `b op= v` computes in the
promoted type and stores the truth of the result, `b = (int(b ? 1 : 0) + 1) != 0`; a `_Bool`
step fails closed. Literals carry their suffix from the C-IR type (`u`, `l`, `ul`,
`lf`, `f`), small integers wrap in a cast. A compound assignment whose operand types differ
expands to `lhs = T_lhs(T_rhs(lhs) op rhs)`, which is C's small-int rule (`b = int8(int(b) +
1)`). Statement-ification happens at emission: an assignment, a step or a call met inside an
expression is hoisted into the statements before the current one (`let _t0 = x` then `x++` for
a postfix step), left to right; an expression whose value C discards binds a fresh temporary
(`let _t3 = g[0]`), since a second `_` in a nested block would shadow the first (F42); a comma
is two statements; `&&` and `||` with a hoisted right
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

A `switch` follows the three-tier ladder of `docs/lowering-examples.md`. Its body is read as
groups, one run of labels and the statements under them; a statement before the first label
or a label below the switch's own level (Duff's device, P3.3) fails closed, a nested switch's
labels being its own. The condition is evaluated once into `_condN` (numbered per switch
within a function), the enum below C's promotion when there is one, so a case compares as
`_cond == E.X` (`int(_cond) == v` for a value no enumerator has) and otherwise against a
literal in the condition's type. The if-chain holds when no group falls into the next (each
ends in `break`, `return`, `goto` or `continue`, a trailing block looked through) and every
`break` that leaves the switch is that tail - a `break` inside a nested loop or switch is that
construct's own; the tail `break` is dropped, the groups become `if`/`elif` and the default
group `else`, wherever it stood. Otherwise the matched-flag loop: `while (true)` holding
`var _flagN = false`, one `_flag ||= _cond == v` per label and `_flag ||= !(every case value)`
for `default`, each group's statements under `if (_flag)`, a trailing `break`; C `break` is
das's. A C `continue` under such a loop would restart the switch, so it spells
`_contN = true` and `break`, with `if (_contN) { continue }` after the loop - itself through
the same translation when the switch sits in an outer flag loop; a real loop body resets the
translation. Computed goto (O6) is the optimization tier's.

A C label is `label N:  // name`, numbered per function in order of appearance, and a goto
is `goto label N` (`docs/lowering-examples.md` "goto / labels"); das resolves a label lexically
upward, so a goto reaches a label in its own block or an enclosing one, and a goto into a
deeper block has every bare block between them (a block that is its parent's statement)
emitted without braces, so the label lands in a scope the goto sees; an `if`, loop or switch
body on that way is Duff's device (P3.3) and fails closed. A goto over a declaration skips its
initializer, which is C's rule too (`probes/test_goto.das`).

A `jmp_buf` is `CJmpBuf` (`c_runtime/setjmp`), its decay `addr(buf)` (or the pointer a `*p`
read it through), and `longjmp` is `c_longjmp`. A setjmp site is an `if` whose condition is
`setjmp(buf)` tested against zero, below casts, `!` and `== 0` / `!= 0`. With both branches it
is the contained site of `docs/lowering-examples.md` "setjmp / longjmp": the first run is the
`try`, the longjmp return the `recover`, which rethrows a longjmp to another buffer or a
genuine panic (a null `c_jmp_target`) and clears its own. With one branch, met in a block's
statement walk, it is the trampoline: `_sj_runN`/`_sj_valN`, a `while` that reruns the
branch, under `if (_sj_val != 0)` (or `== 0` for `!setjmp`), and the rest of the block as its
tail once per longjmp caught, the `recover` storing `buf.val` into `_sj_val`; such a block
cannot end in a return das reads, so the function gets its trailing zero. A tail that leaves
an enclosing loop, a site that is not an `if` at a block's statement level and a `setjmp`
whose value is read any other way fail closed.

`alloca(n)` is a bump on a per-function arena (`docs/stdlib-examples.md` "alloca"): a function
whose body calls it opens with `var _c_astack : uint8[limit]` and `var _c_aoff = 0`, each site
hoists a guard that panics past the limit (das's `assert` is a debug check, so the guard is a
panic), takes `addr(_c_astack[_c_aoff])` as its value and advances the offset rounded to 16,
so allocations in a loop accumulate to the function's exit as C's do and a longjmp past the
frame frees them with it. Every alloca goes through the arena, a constant size included, since
a fixed array hoisted inside a loop body would die with the iteration (F24). The limit is the
sidecar's `alloca_limit`, 65536 by default, which the module's 8 MiB stack holds. A `__builtin_` name whose libc twin the call
tables carry is that twin (the shim list), so `__builtin_alloca`, `__builtin_memcpy` and
`__builtin_abort` lower like their plain names.

Output is assembled as an array of lines joined once (`docs/probe-findings.md` F19); the
text then goes through the formatter, so spacing is the formatter's and indentation is the
emitter's, four spaces per depth.

The aggregates, function pointers and variadics (bitfields, unions, function pointers,
`[variadic]` definitions and the `va_list` cursor) are in `ARCHITECTURE_EMITTER_AGGREGATES.md`.
