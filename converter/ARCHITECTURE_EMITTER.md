# converter Architecture - the emitter

Companion to `ARCHITECTURE.md` in this folder; section numbers are unique across the family.

## 4. What the emitter spells

The module opens with the generated banner, `options gen2`, `options indenting = 4`, `options
solid_context` (globals and functions reached by index, never looked up by name per JIT access, F80;
`--no-solid-context` or the sidecar's `solid_context: false` drops it, for code another context runs
or a patch reloads), `options stack` and a `require c_runtime/<name>` per piece the body reached.
Every module carries the options, the link module too; a `.das.inc` fragment none, being text its
module includes. The stack is the sidecar's `stack`, else 8388608, C's 8 MiB on linux: das's context
stack is 16 KiB (`probes/test_process.das`), which a record parameter's copy on entry or an alloca
arena outgrows, and a recursion multiplies.
Records come first: `struct Name` with adjacent fields of one type on one line, an unnamed
record named `anon_<slot>`, in declaration order, after an empty `struct Name {}` per record the
unit declares and never defines (an opaque handle, reached through pointers alone, since clang
refuses its `sizeof` and a dereference; das reads `struct Name;` as the same empty struct, no
forward declaration, `probes/test_structs.das`); then `[init] def private c2das_layout_check`,
one `static_assert` per record against clang's size and alignment and one per field against its
offset, the layout law checked at compile time where it is claimed
(`docs/implementation_order.md` P2.1); a record holding bitfields asserts its das alignment,
which can be below clang's (F5), and each unit's offset; a union asserts its storage at 0
(`ARCHITECTURE_EMITTER_AGGREGATES.md`, Unions). A record clang lays out unnaturally fails closed unless the sidecar lists
it under `marshal` (`ARCHITECTURE_EMITTER_AGGREGATES.md`, marshal-only records). Globals follow (`var`, `var private` for a C
`static`, the initializer inline and under `unsafe(...)` when it takes an address; an unsafe
operation inside a global initializer wraps itself, one `unsafe(...)` per operation, since no
annotation covers a global), then `[init] def private c2das_init_globals`, then the functions.
das orders global initialization, so an initializer stays inline only while every global whose
address it takes has an explicit initializer and precedes it (`probes/test_globals.das`); an
address of a zero-initialized or later global moves the whole initializer into
`c2das_init_globals` as an assignment, which also holds the stores of a sparsely filled
array (`docs/lowering-examples.md` "Globals & initializers"), and so does one das reads as an
initialization loop (`ARCHITECTURE_EMITTER_AGGREGATES.md`, Initialization loops). A module reaching the printf or
the scanf family puts `[init] def private c2das_dialect` (`c_long_bits`, the dialect's `long`
width) before every other `[init]`, so no initializer that formats runs ahead of it. A function's value (`@@f`, from a decay
or from `&f`; C `main` is `@@c_main`) and a literal's address need no textual order. A null function
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
place (`probes/test_param_constness.das`). A K&R definition's parameter arrives at the
promoted type clang's function type gives it (`int (int, int)` for `int a; char b;`), so it is
`b_in : int` and the body opens with C's conversion on entry, `let b = uint8(b_in)` (`var` when
the body writes it, `b_in != 0` for `_Bool`, `enum_from_int` for an enum), in both parameter
write modes (`docs/probe-findings.md` F55). That is the default parameter write mode,
`in-place`; under `copy` (`--param-writes copy` or the sidecar's `param_writes`, section 1 of
`ARCHITECTURE.md`) each such parameter is copied on entry the way a record is, `n_in` the
parameter and `var n = n_in` the body's first statement, under the same free-name rule, and
the parameter keeps the mode it has when the body never writes it: a scalar or a function
value `let`, a data pointer `var`, since a `var` local copied from a `let` pointer parameter
still reads its pointee as const (`probes/test_param_constness.das`). The interpreter writes a
local faster than an argument slot (`perf/ARCHITECTURE.md` section 2, the `interp-copy` lane).
A `va_list` parameter is the caller's cursor and stays in place in both modes; a parameter
the body only reads, and a record's copy, are the same in both, and nothing else differs
between them (`converter/tests/fixtures/p4_param_writes.c`). A function type's positions follow the parameter
rule, so every function of one C type fits one das type (F34); a function pointer position is
never `var`, since a function value has no pointee. A temporary the emitter hoists holding a
pointer (an initializer list's item, an alloca's address, a stepped pointer's old value) is
`var` for the same reason as a parameter. A body that uses an unsafe operation (pointer
arithmetic, `deref`, `addr`, a `reinterpret`, a string literal) gets `[c_function]`. Under `--checks off` or the sidecar's `checks: "off"` every converted function also carries `unsafe_deref` and `hint(unsafe_range_check)`, after `c_function` (by intent not the marshal accessors, the `[init]` functions or the link module's late-bind wrappers, whose bodies hold no checked dereference and index only in range loops), and a line under the module's banner says so: no null or range check under the interpreter, the JIT and the exe, the AOT host keeping its range checks, so a wrong C program reads its neighbor or dies by SIGSEGV instead of panicking (`docs/probe-findings.md` F84); the default `safe` keeps every check. C `main`
becomes `c_main` and the module ends with `[export] def main : int { return c_main() }`, whose
`return` is the CLI's exit-code contract (`docs/probe-findings.md` F1). `int main(int argc, char
**argv)` is `c_main(argc : int; var argv : uint8??)`; the wrapper calls `c_runtime_init("<stem>")`
(`c_runtime/c_args`: `argv` built once in C-allocator memory, `argv[0]` the source's stem, a
native build's name on every tier), then returns `c_main(c_argc(), c_argv())` (F56); a unit's
function named like one of these four takes the next free name (`c_argc1`), and so does a
function the program defines named like a libc one c_runtime maps (h264bsd's own `malloc` is
`malloc1`), since its calls would be ambiguous with the mapped one and das's builtin of the name;
C's calls of the name bind to it, as the link binds them to the program's definition. A `main` taking
`envp` or other parameters, and a `static` one, fail closed. A C name that is a das
keyword or a name of a das builtin type (every token of the gen2 lexer a C identifier can spell:
`include`, `fixed_array`, the vector types `int2` to `ushort8` and `byte3`, `DAS_KEYWORDS`), or that starts with `__`, which das reserves (glibc's `__tm_gmtoff`), takes the `_c_`
prefix; a program that also names an object, function, parameter or local `_c_<name>` fails closed
with both names, since the two would be one das name. A local that hides one of an enclosing block or a parameter
takes the first numbered name the function leaves free (`i1`), and so does every reference C
resolves to it, since das refuses a local that shadows another (`docs/probe-findings.md` F42);
`emit_tu` renames over the C-IR in place before anything reads a name, a `for`'s declarations
scoped to the whole `for`. A local the lowering declares outside its C block, one of a block a
goto enters (which loses its braces) or one a lowered switch carries (below), also takes a free
name when a global or another local of the function spells its own, since das would otherwise
bind the global's later reads, or a later block's local, to it (`int g = 3;` in a flattened
block beside a global `g` is `g1`; `converter/tests/fixtures/p4_scope_fidelity.c`). A temporary (`_tN`) skips every name the function spells, a C local
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
bare declaration followed by one store per written element (at module init for a global). A subscript of an array is the das
index, range-checked (the documents' safety oracle); a subscript of a pointer is `deref(p +
i)`; an index of a small integer type widens to `int`, since das indexes by `int`, `int64`,
`uint` and `uint64` alone and C does not promote a subscript (F43); `&a[k]` of an array whose
index can reach the length is `addr(a[0]) + end_index(k, N)` (`c_runtime/c_bounds`, which
panics past `N` with das's own range-check wording), and a constant `N` is `addr(a[0]) + N`,
since C may form the address one past the end and das range-checks `addr(a[N])` (F45); a
constant below the length keeps `addr(a[k])`, and so does a constant past it, whose range
check stands for C's undefined behaviour, while a literal past `int64` counts as no constant.
In a global initializer the decay and the sum each wrap themselves, `unsafe(unsafe(addr(a[0]))
+ k)` (F48). A reference C makes before the definition that gives its array a length (`extern int a[];`, the definition later in the unit or in another unit) keeps clang's type of unknown length in the C-IR and takes the type of the global its name binds to before anything is spelled (`complete_extern_arrays`), so it indexes and decays the definition's storage, and its address `&a` (`int (*)[]`) converts to a sized row pointer or an element pointer as C converts it, the conversion spelling the target type; a declarator of a pointer to an array of unknown length (`int (*p)[] = &a;`) fails closed; one no unit defines fails closed naming it; a row pointer is `T[N]?` and reads as `deref(row)[i]`; decay is `addr(a[0])`. A function
pointer is a das function value, `function<(a0 : T; ...) : R>` with the parameters named by
position, a function's name decays to `@@name`, and a call through a pointer, `fp(...)` or
`(*fp)(...)`, is `invoke(fp, ...)` (`ARCHITECTURE_EMITTER_AGGREGATES.md`, Function pointers). A pointer difference is `int64(p - q)`, in elements as C
counts them, the subtrahend parenthesized as the right operand of `-` (`top - 1 - (base + a)`); a pointer less a count whose pointer is no load of an object (a decay, a sum, a cast, a call) is the sum with the negated count, `addr(b[0]) + 10 + -(n)` (`-int64(n)` for an unsigned one), since das subtracts from a pointer variable only (F59); a sum with the count on the left, `n + p`, is commuted, `p + n`, since das adds a count to a pointer only; a pointer relation goes through `intptr`, and so does `==` or `!=` between two
data pointers, since das compares only pointers of one constness and a `let` pointer's pointee
is const (F44), while a null constant on either side compares with `null`; `malloc`, `calloc`, `realloc`, `free`
and the `mem*` family are the CRT's through `crt`, with C's implicit `void *` conversions as
explicit `reinterpret`. `[c_function]` lands only on a body with an unsafe operation, and the
emitter counts those bodies against all the unit defines: the port-progress metric `main.das`
reports; `sizeof` and `offsetof` are `T(typeinfo sizeof(type<S>))` and `T(typeinfo
offsetof<f>(type<S>))`, never clang's constants, with the cast to the C result type (a
marshal-only record's `offsetof` is clang's offset, `T(5)`, as its `sizeof` is clang's size); the
offset idiom, a member chain from a null pointer constant cast to a record pointer under `&` and
a cast to an integer (`(int)(long long)&((T *)0)->f[i]`), is that offset as an integer, never a
load through null: `int(int64(int64(typeinfo offsetof<f>(type<T>)) + int64(i) * int64(typeinfo
sizeof(type<E>))))`, a marshal record's terms clang's literals folded where constant, and any
other member of a null pointer constant (a read, its address as a pointer, a pointer field
indexed) fails closed; and
`_Alignof` is `T(typeinfo alignof(type<S>))` where das aligns the type as clang does and
clang's value `T(4)` where das aligns it lower (a record whose bitfield units align below
clang's, F5), for a marshal-only record and for a `va_list` (`docs/probe-findings.md` F54). A string
literal in a pointer context stays a das literal, `reinterpret<uint8?>("...")`, which is a
NUL-terminated interned byte array (`probes/test_strings.das`), an interior NUL spelled `\x00`,
which das keeps with the bytes after it; the empty literal is the one
exception, since das's `""` is a null pointer (`docs/probe-findings.md` F10): it is
`addr(c2das_empty[0])`, a one-byte private array the module declares right after its requires,
before any global whose initializer takes the address. A `char[N]` initialized from a literal
is `cstr_array("...", N)`, the empty literal included, and so is a row of a `char` matrix or a
record's `char[N]` field (`fixed_array(cstr_array("1234", 4), cstr_array("5678", 4))`, a row
the list leaves out the zero literal), a literal longer than `N` keeping its first `N` bytes,
as clang initializes the array; one with an interior NUL is the row of its bytes,
`fixed_array(uint8(97), uint8(0), ...)`, since `cstr_array` reads its literal as a das string,
which ends at the first NUL; a `signed char` one fails closed, and one in braces filling the whole array (`{ "ab" }`) is the dumper's plain literal. A literal
indexed in place (`"abcdef"[2]`) is read through its pointer, `deref(p + i)`; a literal under `sizeof` is its
array type. A call to a libc function the C program declares resolves through two tables:
`C_RUNTIME_CALLS`, the functions a `c_runtime` piece lowers (`printf`, `sprintf`, `snprintf`,
`vprintf`, `vsprintf`, `vsnprintf`, `fprintf`, `vfprintf`, `sscanf`, `vsscanf`, `exit`, `abort`, `signal`, `qsort`, `bsearch`; `<math.h>`'s surface das math covers, `floor` as `math::floor` and `fabs` as `math::abs`, as `docs/stdlib-examples.md` "math.h" rules; glibc's `__errno_location`, which `errno` expands to, as `crt::c_errno_location`),
one row each naming the module that holds the piece and the das name, and `CRT_CALLS`, the
functions the `crt` module binds under their C names (the memory, string.h, ctype, conversion,
libm exotica, time, locale, stdio and random families of `dasCRuntime/ARCHITECTURE.md`), spelled
`crt::name`, which take every pointer `let` (`strcpy`'s, `memcpy`'s and `memset`'s destination
included), since a C++ binding's parameter carries no das constness; a function in neither fails
closed. A library call takes a pointer to a record among its fixed arguments as `void?`
(`crt::getc(reinterpret<void?>(f))`) and gives one back through `reinterpret<T?>`
(`reinterpret<tm?>(crt::gmtime(addr(t)))`); `jmp_buf` and `va_list` are the protocol's own. A libc
object the program reads is its crt accessor through `CRT_OBJECTS` (`stdout` is
`reinterpret<_IO_FILE?>(crt::c_stdout())`, and the accessor's `void?` as it is where a library call
takes it), decided by declaration: a name a parameter, a local or a program global binds is the
program's own (`unshadow_locals` marks each reference a parameter or local binds). Where the
dialect's `long` is 32 bits (`msvc`), a fixed argument of C type `long` or `unsigned long` to a
`crt::` function is widened (`int64(off)`) and such a result narrowed (`int(crt::clock())`),
since crt binds C's `long` as 64 bits; a result C ranges at the dialect's `long` never wraps:
`strtol`, `strtoul`, `atol` and `ftell` call crt's 32-bit forms (`crt::c_strtol32(...)`,
`LONG32_CALLS`), which clamp with ERANGE as a 32-bit CRT does (`dasCRuntime/ARCHITECTURE.md`
section 3). A program calling `setvbuf` requires `c_runtime/c_exit`, whose
`[finalize]` flushes every stream while a buffer the program handed it, das memory, still lives. A `void *` among a call's trailing arguments travels as `reinterpret<uint8?>(p)`, since
daslang meets a tuple holding `void?` after two tuples of other pointers with two generic
instances (`docs/probe-findings.md` F61); the list holds every pointer as `void?` either way. A caller's `var` pointer reaches a piece's
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
(`let _t3 = g[0]`), since a second `_` in a nested block would shadow the first (F42). A step,
a compound store and an assignment whose value C reads spell their target more than once (read
and written, `x = x op v`, a marshal record's reader and writer), so they pin it first: the
pointer the target goes through, its index or a record value, whichever has an effect, is
evaluated once, into a temporary unless its text already is one (a variable's own name, `i` of
`++i` or `p` of `p = q`, changes under a call later in the statement), and every spelling of
the target reads that (`var _t0 = next()` then `deref(_t0)++`; `let _t0 = pick(1)` then
`deref(p + _t0).bf = uint(int(deref(p + _t0).bf) + 5)`; `let _t1 = arr[_t0].a` then
`arr[_t0].a++` for `arr[k++].a++`). An assignment read as a value is its target read after the
store through the same temporaries, so `if ((*p++ = *q++))` tests what the store wrote, a
bitfield's truncation included; a plain `=` statement spells its target once and pins nothing.
The pins live while the statement that needs them is spelled (`em.hoisted`); a comma
is two statements; `&&` and `||` with a hoisted right
side become a flag and an `if`; a ternary whose arm carries hoisted statements becomes `var _tN
: T` and an `if`/`else`, while a ternary of pure arms stays inline since das `?:` evaluates
only the taken arm (F18). das types `?:` by its first arm and takes no `null` there for a pointer,
so a null first arm of a pointer conditional is `default<T?>` (`probes/test_pointers.das`); a null
in any other position with a pointer type (a second arm, an argument, a return, a store, an
initializer) is `null`. A `void` ternary evaluated for its effects (an expression statement, a
comma's left side, a cast to `void`: the `(e) ? (void) 0 : fail()` of an assert) is an
`if`/`else` of its arms' statements, an arm with no effect left out (`if (!(e))` when it is the
first), and fails closed where its value is read, since das has no `void` variable. The loops (the range loop of a canonical counting `for`, the trailing increment, the `finally`
block and the flag), `x = x op y` as `x op= y`, C's wrapping signed sum and the volatile access
are in `ARCHITECTURE_EMITTER_LOOPS.md`; `if` chains spell `elif` when the nested condition is pure.
A string literal outside a pointer or `char[N]` context (where the empty one has no das spelling
either, F10) fails closed.

Marshal-only records are in `ARCHITECTURE_EMITTER_AGGREGATES.md`.

The switch ladder and the labels (`switch`, `goto`, a goto into another case) are in
`ARCHITECTURE_EMITTER_CONTROL.md`.

`alloca(n)` is a bump on a per-function arena (`docs/stdlib-examples.md` "alloca"): a function
whose body calls it opens with `var _c_astack : uint8[limit]` and `var _c_aoff = 0`, each site
hoists a guard that panics past the limit (das's `assert` is a debug check, so the guard is a
panic), takes `addr(_c_astack[_c_aoff])` as its value and advances the offset rounded to 16,
so allocations in a loop accumulate to the function's exit as C's do and a longjmp past the
frame frees them with it. Every alloca goes through the arena, a constant size included, since
a fixed array hoisted inside a loop body would die with the iteration (F24). The limit is the
sidecar's `alloca_limit`, 65536 by default, which the module's 8 MiB stack holds. A `__builtin_` name whose libc twin the call
tables carry is that twin (the shim list), so `__builtin_alloca`, `__builtin_memcpy` and
`__builtin_abort` lower like their plain names; `__builtin_expect(e, c)` is `e`, and `__builtin_huge_val()` (`HUGE_VAL`) the constant `crt::HUGE_VAL`.
`__builtin_constant_p(e)` never reaches the emitter from Dumper A: the dumper writes clang's
answer as an integer literal (`ARCHITECTURE_DUMPER.md` "`__builtin_constant_p`"). The bit builtins
(`ffs`, `ctz`, `clz`, `popcount`, `parity`, `clrsb`, each with its `l` and `ll` spellings),
`bswap16/32/64`, `signbit`, `unreachable` and `prefetch` are calls of the
`c_runtime/c_builtins` piece, the `l` and `ll` spellings reaching the overload of the operand's
width through the argument's type; `__builtin_trap` is `c_abort`.

Output is assembled as an array of lines joined once (`docs/probe-findings.md` F19); the
text then goes through the formatter, so spacing is the formatter's and indentation is the
emitter's, four spaces per depth.

The aggregates, function pointers and variadics (bitfields, unions, compound literals, flexible
array members, function pointers, `[variadic]` definitions and the `va_list` cursor) are in
`ARCHITECTURE_EMITTER_AGGREGATES.md`.

### setjmp / longjmp {#setjmp-general}

A `jmp_buf` is `CJmpBuf` (`c_runtime/setjmp`), its decay `addr(buf)` (or the pointer a `*p` read it
through), and `longjmp` is `c_longjmp`. A record holding one (Lua's `struct lua_longjmp`) keeps
clang's offsets and size through a padding field after it (`converter/ARCHITECTURE.md` section 2,
the relaxed search). A setjmp site is an `if` whose condition is `setjmp(buf)` tested against zero,
below casts, `!` and `== 0` / `!= 0`. With both branches it is the contained site of
`docs/lowering-examples.md` "setjmp / longjmp": the first run is the `try`, the longjmp return the
`recover`, which rethrows a longjmp to another buffer or a genuine panic (a null `c_jmp_target`) and
clears its own. With one branch, the first run's, and a tail calling nothing, it is flat: `try`, an
empty `recover`, then the tail once: no longjmp from the tail reaches the buffer. Other
single-branch sites are the trampoline: `_sj_runN`/`_sj_valN`, a `while` that reruns the branch,
under `if (_sj_val != 0)` (or `== 0` for `!setjmp`), and the rest of the block as its tail once per
longjmp caught, the `recover` storing `buf.val` into `_sj_val`; such a block cannot end in a return
das reads, so the function gets its trailing zero. The general form is a block's statement that
reads the value only where ISO C 7.13.1.1 allows it (`setjmp(buf);`, `r = setjmp(buf);`,
`int r = setjmp(buf);`, `return setjmp(buf);`, a `switch` or an `if` on it, on `!setjmp(buf)` or on
it compared with an integer constant), through implicit conversions: it opens the tail, setjmp read
as `_sj_valN` (0 on the first run, longjmp's value on a rerun), which reruns the statement, so
nothing in it is read before the call. A branch or a tail that leaves an enclosing loop, a site off
a block's statement level, a second setjmp, another effect or read (`x = g + setjmp(buf)`,
`a[i++] = setjmp(buf)`) and a `setjmp` read any other way fail closed. The lowering is exact in the
interpreter; under the JIT a `return` in a `try` or `recover` arm leaves only the arm
(`docs/probe-findings.md` F75), so a trampoline's tail or a flat branch that returns runs on there.
