# converter Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The
folder is the daslang program that turns C into gen2 daslang: Dumper A, the C-IR model, the
emitter, the pipeline that chains them, and the tier runner the gate and the suites use. The
normative design is `docs/very-detailed-plan.md` (sections 4 and 5) and the expected output is
`docs/lowering-examples.md`; this document states only what the code here is.

## 1. File charters

- `cir.das` - the C-IR of `docs/c-ir-spec.md` as das values (`CirTu`, `CirType`, `CirDecl`,
  `CirStmt`, `CirExpr`, one struct per spec table), the canonical writer `write_cir`, the
  reader `read_cir`, the pinned `CAST_KINDS`, the two dialects. Nothing here knows clang or
  daslang syntax. A tree is owned through plain pointers and freed by one `delete` of its
  root: the generated finalizer recurses through pointer fields and arrays of pointers
  (`probes/test_delete.das`), so no hand-written walk frees a child.
- `dumper_a.das` - Dumper A: runs `clang -Xclang -ast-dump=json -fsyntax-only -target
  <triple>` on one file and normalizes the JSON into a `CirTu`. Fails closed: the first
  construct outside what it represents sets `Dumper.error` with `file:line:col`. Layout facts
  from dasClangBind join here when records enter the subset.
- `emit.das` - the emitter: `CirTu` in, gen2 text out, fails closed the same way. The
  lowering passes of the plan (type resolve and rename, promotion insertion,
  statement-ification, control flow) grow as their own files that transform a `CirTu`
  before emission; the emitter itself only spells nodes.
- `pipeline.das` - `convert(c_path, out_dir, target)`: dump, write the C-IR, read it back and
  rewrite it (the bytes must match), emit, format with `daslib/das_source_formatter`,
  compile-check with `compile_file`. Every artifact lands under `out_dir`.
- `tiers.das` - `run_tier(das_path, tier, work_dir, output[, module_dirs])`: the process exit
  code of the module under `interp`, `jit`, `exe` or `aot` (section 5); `module_dirs` are
  passed as `-load_module` to the interpreter and the JIT.
- `main.das` - the CLI (`daslib/clargs`): `c2das <file.c> [--out] [--target] [--run]`.
- `benchmarks/bench_for_shapes.das` - the loop-shape race behind section 4, run with
  `dastest -- --bench` under the interpreter and under `-jit`.
- `tests/test_lowerings.das` - the P1 fixtures under `tests/fixtures/p1_*.c`, each converted
  and run against the native build of the same file by the pinned clang (output and exit
  code), plus the lowering shapes the text must carry.
- `tests/test_pipeline.das` - the P0 gate: `tests/fixtures/ret42.c` converts, the C-IR and the
  das text hash to their golden values, and the module exits 42 under all four tiers.
  Fixtures under `tests/fixtures/` are C inputs, never das.

## 2. The C-IR bytes

`write_cir` is the one canonical spelling of the spec's section 8, and Dumper B must produce
these bytes for the byte-diff to mean anything: an object opens with `{` and a newline, every
member sits on its own line indented one space per depth as `"key": value`, members are
separated by `,` at the end of the line, the closing `}` sits at the parent's depth; an array
of scalars is one line `[1, 2, 3]`; an array of objects opens with `[` and a newline, holds
one object per line at the inner depth, and closes with `]` at the parent's depth; an empty
array is `[]`; keys follow the spec's table order; `null` spells an absent optional node; a
string is JSON-escaped by `write_json`; the file ends with one LF. The reader accepts any
JSON spelling; the pipeline proves the pair by rewriting what it read and comparing. One
node is this repository's addition to the spec's table: `offsetof` with `of_t` and `field`
(the record type and the field index), since the lowering spells `offsetof` as
`typeinfo offsetof` and the spec has no node for it (`docs/probe-findings.md` F20). The other
addition is `dims` on a `global`, a `decl` statement and a record field: one `{enum_t, item}`
per array dimension of the declarator, outermost first, the item empty for a dimension not
spelled as one enum constant, the member absent when none is, since the lowering keeps the
constant as the dimension and the spec's `count` is the folded integer (F21). The spelling is
a fact about the declarator, not the type, so the type table interns `T[6]` once however the
source wrote it. An `enum` type carries `"signed": false` when clang gave it an unsigned
underlying type (F22); the member is absent for a signed one, which is every enum of the
`msvc` dialect.

## 3. Dumper A's subset

The dumper walks `TranslationUnitDecl.inner`, skipping `isImplicit` nodes (clang's builtin
typedefs and `_GUID`) and every declaration whose location is another file (a header's).
Locations come from `loc`, else `range.begin`; clang omits `file` and `line` when they
repeat the previous node's, so the dumper carries the last seen values forward in tree
order, starting from the main file. Types are interned by a structural key
(`int:32:true:int`, `ptr:3`, `func:0:1,2:false`) in first-use order, which is the spec's
order. Type spellings come from `desugaredQualType` when clang gives one, else `qualType`,
with `const`, `volatile`, `restrict` and `__attribute__` text stripped: the C99 scalar names,
`_Bool`, `T *`, `T[N]` (the first bracket is the outer dimension: `T[2][3]` is two `T[3]`),
`T (*)[N]` pointers to arrays, `R (P, ...)` function types (`R *(P)` when the return is a
pointer, which clang writes without a space), `R (*)(P)` pointers to functions, `R (**)(P)`
pointers to those and `R (*[N])(P)` arrays of them. A builtin typedef in a builtin's
prototype (`__size_t`, `__ptrdiff_t`) has no cursor and is the dialect's pointer-wide
integer.
Widths follow the selected dialect (`msvc`: int 32, long 32, long long 64; `linux`: long
64); plain `char` is unsigned in both (`docs/probe-findings.md` F17), which the dumper
enforces with `-funsigned-char`. The dump desugars only the top level of a spelling, so a
typedef name inside `P_t *` or `P_t (P_t, int)` resolves through the canonical spelling
libclang gives the typedef. Records come from a libclang pass over the same file under the
same flags, run before the JSON walk: every `struct` and `union` definition of the main
file, nested ones included, with clang's size, alignment and field offsets, keyed by the
canonical spelling the JSON desugars to (`struct X`, `struct thinker_t` for a typedef-named
anonymous record, which libclang spells bare and the pass re-tags) and by its location, which
is how a `RecordDecl` of the walk finds its layout. A record is interned in its own slot
before its fields, so a self-referential pointer resolves; `packed` is set when clang's
offsets are not the natural layout das would compute, and a record libclang never saw
defined has size -1. A typedef is a `typedef` type and a `typedefdecl` anchor, nothing more. A file-scope `static` gets the TU-qualified name
`<stem>__<name>` (a stem that starts with a digit, as the c-testsuite's do, takes a leading
underscore, since `00099__f` is not a name) and a local `static` is hoisted into `decls` as
`<fn>_<name>` with `from_func`; references use the hoisted name. Tentative definitions of one object merge
into the declaration carrying the initializer.

Declarations: `FunctionDecl` with `ParmVarDecl` and a `CompoundStmt` body, `VarDecl`.
Statements: compound, `DeclStmt` (one `decl` per variable), expression statements,
`if`, `while`, `do`, `for` (its five slots, an absent one spelled `{}`), `break`,
`continue`, `return`, the null statement. Expressions: integer, character, floating (as a
hex-float through the CRT) and string literals (C escapes decoded, the NUL appended),
`DeclRefExpr`, every pinned cast, the unary, binary, compound-assignment, conditional and
comma operators, calls, subscripts, `sizeof`, `MemberExpr` (the field by index into the
record's fields, `arrow` kept), `InitListExpr` of a record or an array (clang's semantic form,
one child per field or element, an `ImplicitValueInitExpr` left to the positional zero;
an array with a trailing run of zeros lists its filler first under `array_filler`, then the
elements up to the last one written) and `OffsetOfExpr`,
whose components the dump omits: the dumper reads `T, f` from the macro's own text at its
`expansionLoc` (F20). A location with an `expansionLoc` is that location.

The libclang pass and the JSON walk meet on one key: the byte offset of a node's expansion
location (`clang_getExpansionLocation`; the JSON `loc`, or its `expansionLoc`, always carries
`offset`, where clang omits a `line` that repeats the last one it printed, its last-line state
also moving on a `range.end` the dumper never sees). Every record, enum, enumerator reference
and dimensioned declarator the pass records is keyed that way; the location carry (`loc_of`)
serves the C-IR's `loc` alone.

Enums come from the same libclang pass as records: every `enum` definition of the main file,
nested and block-scoped ones included, with the enumerator values as C reads them
(`clang_getEnumConstantDeclUnsignedValue` for an unsigned underlying type, which the linux
dialect gives an enum without a negative enumerator; past INT_MAX such a value is possible)
and the width and signedness of the integer type clang chose, keyed by spelling (`enum color`,
`enum mobjtype_t` for a typedef-named anonymous enum, re-tagged the way a record is) and by
offset, which is how an `EnumDecl` of the walk finds its entry and pushes its `enumdef` anchor;
a forward declaration (`enum E;`, no enumerators) adds nothing, and a nested `EnumDecl` or
`RecordDecl` that is not a definition (`struct S { enum K *p; }`) is not registered. An enum
whose width is not the dialect's `int` fails closed, and so does a spelling two block-scoped
enums of one tag share, since the dump resolves types by spelling alone; an enum the walk
never anchored (one defined inside a `sizeof` or cast operand) fails closed at the end of the
dump. The pass also records, per declarator whose array dimensions the source spells by enum
constants, the constant of each dimension (`clang_getCursorReferenced` on the size expression,
a lone `DeclRefExpr` to an `EnumConstantDecl`; any other expression keeps the bare count),
and the `VarDecl` or `FieldDecl` at that offset gets its `dims`, a constant kept only when its
value is the dimension's count, since two declarators of one macro expansion share an offset.
A `DeclRefExpr` to an `EnumConstantDecl` resolves by its offset too, since C scopes let two
enums of one file spell one constant name: the `enum_ref` carries the enum the constant belongs
to, and the node's type is what clang gave the reference (`int`, or `unsigned int` for an enum
with a value past INT_MAX). An enumerator reached through a macro has no main-file cursor and
fails closed (`docs/implementation_order.md`, the P2.4 ledger). Anything else is an error
naming the node kind and its location: compound literals, `goto`, `switch` are the next
phases' rows.

## 4. What the emitter spells

The module opens with the generated banner, `options gen2`, `options indenting = 4` and one
`require c_runtime/<name>` per piece the body reached (`printf`, `c_exit`, `c_function`).
Records come first: `struct Name` with adjacent fields of one type on one line, an unnamed
record named `anon_<slot>`, in declaration order; then `[init] def private
c2das_layout_check`, one `static_assert` per record against clang's size and alignment and
one per field against its offset, the layout law checked at compile time where it is claimed
(`docs/implementation_order.md` P2.1). A union, a bitfield and a record clang lays out
unnaturally fail closed until their rows (P4.2, P4.1, P2.7). Globals follow (`var`, `var
private` for a C `static`, the initializer inline and under `unsafe(...)` when it takes an
address; an unsafe operation inside a global initializer wraps itself, one `unsafe(...)` per
operation, since no annotation covers a global), then `[init] def private
c2das_init_globals`, then the functions. das orders global initialization, so an initializer
stays inline only while every global whose address it takes has an explicit initializer and
precedes it (`probes/test_globals.das`); an address of a zero-initialized or later global
moves the whole initializer into `c2das_init_globals` as an assignment, which also holds the
stores of a sparsely filled array (`docs/lowering-examples.md` "Globals & initializers"). A
function's value (`@@f`, from a decay or from `&f`; C `main` is `@@c_main`) and a literal's
address need no order. A null function pointer is `default<function<...>>`, since das takes
no `null` for a function value (`probes/test_globals.das`). A function is
`def name(p : T; ...) : ret` with `private` for a C `static`; a parameter the body writes
is declared `p_in` with `var p = p_in` as the first statement, the callee copy C's by-value
rule needs, since a das parameter is a reference; a store that reaches the parameter through
`.f` or an array's `[i]` is a write to it, while one that crosses `->`, `*p` or a pointer's
`[i]` writes what it points at and makes the parameter `var`, the one spelling whose pointee
stays writable (F3); a pointer parameter copied into a pointer local or variable (`int *it =
a`) is `var` for the same reason, since the copy of a `let` parameter carries a const pointee. A body that used an unsafe operation
(pointer arithmetic, `deref`, `addr`, a `reinterpret`, a string literal) gets
`[c_function]`. C `main` becomes `c_main` and the module ends with
`[export] def main : int { return c_main() }`, whose `return` is the CLI's exit-code
contract (`docs/probe-findings.md` F1). A C name that is a das keyword takes the `_c_`
prefix.

An enum is `enum Name { items }` with das's default `int` base, emitted before the records, an
item stating `= v` only where C's count-from-the-previous rule would not give its value, a
value past INT_MAX wrapped to the negative `int` of the same bits and INT_MIN as
`-2147483647 - 1` (das reads `-2147483648` as a negated out-of-range constant;
`probes/test_enums.das`), and an unnamed enum named `anon_<slot>` like a record. An enumerator
reaches the text as `Name.ITEM` and the emitter keeps it symbolic where das can take the enum:
a conversion into its own enum (`t = MT_SHOTGUN`, an initializer slot, an argument), a literal
whose value an enumerator has (`(E) 0` is `E.ZERO`), `==`/`!=` between two values of one enum,
which das compares directly, and a ternary of two values of one enum whose arms hoist nothing
(an arm with a hoisted statement takes `emit_cond`'s if-chain). C's conversions between the
enum and those sites are looked through only while they keep the value: its promotion, and a
widening that keeps its sign; a narrowing or a sign change (`(unsigned) e` of an enum with a
negative enumerator) stops the look-through, since C compares the converted values. Where C
reads the enum as an integer the value goes through `int(e)`, bit-exact for every 32-bit type
- a relational operator, an index, arithmetic, a `printf` argument - the workhorse cast
following when C computes in another type (`uint(int(e))`), and through `uint(int(e))` before
a 64-bit or floating target when the enum's underlying type is unsigned, where `int(e)` would
read a value past INT_MAX as a sign. An enumerator C types `unsigned int` (one of its enum
exceeds INT_MAX) is spelled `uint(int(E.X))`. A conversion into an enum from anything else is
`enum_from_int(type<E>, i)` over the `int` value, which `++`, `+= 1` and `t = t + 1` all take
(`t = enum_from_int(type<E>, int(t) + 1)`); a compound assignment computes in the type clang
gave its right side, except a shift, which computes in the promoted left side, `uint` for an
unsigned-underlying enum (and for `unsigned w >>= n`), with an unsigned count. An enum's truth
is `int(e) != 0`; its zero is the enumerator of value zero when it has one, else
`enum_from_int(type<E>, 0)`, since das rejects `default<E>` for an enum without a zero
enumerator (`probes/test_process.das`; aggregates and globals of such an enum still zero,
`probes/test_enums.das`). A dimension the declarator spells by an enum constant stays
`[int(E.COUNT)]`, which das folds (`probes/test_enums.das`). A member is
`a.f`, and `p.f` for `p->f` and `(*p).f` alike, which das reads through a
pointer without `deref` or unsafe; a record initializer is `S(f = v, ...)` naming the filled
slots. An array is `T[2][3]` with the dimensions in C's order and `T? [N]` for an array of
pointers, since `?[` lexes as the safe-index operator; its initializer is one `fixed_array`
holding every element, the unwritten ones as zero literals, except an array past 32
elements the source fills sparsely, which is the bare declaration followed by one store per
written element (at module init for a global); a `char[N]` from a string literal is
`cstr_array("...", N)`. A subscript of an array is the das index, range-checked (the
documents' safety oracle); a subscript of a pointer is `deref(p + i)`; a row pointer is
`T[N]?` and reads as `deref(row)[i]`; decay is `addr(a[0])`. A function pointer is a das
function value, `function<(a0 : T; ...) : R>` with the parameters named by position, a
function's name decays to `@@name`, and a call through a pointer, `fp(...)` or `(*fp)(...)`,
is `invoke(fp, ...)`. A pointer difference is `int64(p - q)`, in elements as C counts
them; a pointer relation goes through `intptr`; `malloc`, `calloc`, `realloc`, `free` and
the `mem*` family are the CRT's through `crt`, with C's implicit `void *` conversions as
explicit `reinterpret`. `[c_function]` lands only on a body with an unsafe operation, and
the emitter counts those bodies against all the unit defines: the port-progress metric
`main.das` reports; `sizeof` and `offsetof` are `T(typeinfo sizeof(type<S>))` and
`T(typeinfo offsetof<f>(type<S>))`, never clang's constants, with the cast to the C result
type. A string literal in a pointer context stays a das literal, `reinterpret<uint8?>("...")`,
which is a NUL-terminated interned byte array (`probes/test_strings.das`); the empty literal
is the one exception, since das's `""` is a null pointer (`docs/probe-findings.md` F10): it
is `addr(c2das_empty[0])`, a one-byte private array the module declares right after its
requires, before any global whose initializer takes the address. A `char[N]` initialized from
a literal is `cstr_array("...", N)`, the empty literal included. A literal indexed in place
(`"abcdef"[2]`) is read through its pointer, `deref(p + i)`; a literal under `sizeof` is its
array type. A call to a libc function the C program declares resolves through two tables:
`C_RUNTIME_CALLS`, the functions a `c_runtime` piece lowers (`printf`, `sprintf`, `snprintf`,
`exit`, `abort`) by the module that holds the piece, and `CRT_CALLS`, the functions the `crt`
module binds under their C names (the memory, string.h, ctype, conversion, time and random
families of `dasCRuntime/ARCHITECTURE.md`), spelled `crt::name`; a function in neither fails
closed. A `size_t` result is `uint64`, so an index or a count it feeds carries the cast C
gives it. Expressions carry the C-IR casts: `IntegralCast` and the floating casts are the workhorse
cast, `IntegralToBoolean` is `x != 0` (`!= null` for a pointer), `BooleanToSignedIntegral`
is `b ? 1 : 0`, a comparison or `!` is spelled as the das bool it is and becomes `? 1 : 0`
only where C reads it as an int. Literals carry their suffix from the C-IR type (`u`, `l`,
`ul`, `lf`, `f`), small integers wrap in a cast. A compound assignment whose operand types
differ expands to `lhs = T_lhs(T_rhs(lhs) op rhs)`, which is C's small-int rule
(`b = int8(int(b) + 1)`). Statement-ification happens at emission: an assignment, a step
or a call met inside an expression is hoisted into the statements before the current one
(`let _t0 = x` then `x++` for a postfix step), left to right; a comma is two statements;
`&&` and `||` with a hoisted right side become a flag and an `if`; a ternary whose arm
carries hoisted statements becomes `var _tN : T` and an `if`/`else`, while a ternary of
pure arms stays inline since das `?:` evaluates only the taken arm (F18). Loops follow the
documents: `while` is `while`, with a side-effecting condition spelled `while (true)` plus
the test and `break`; `do` is the `_first` flag; `for` is a bare block holding the
initializer and one of three loops: `while (cond) { body }` when there is no increment,
`while (cond) { { body } finally { inc } }` when the body never leaves the loop (no `break`
at its level, no `return`, no `goto`), since `finally` runs on `continue` and on every pass
but also on `break`, and the `_f` increment-first flag otherwise; `if` chains spell `elif`
when the nested condition is pure. The split is measured: `benchmarks/bench_for_shapes.das`
times one body under the three spellings, and under the interpreter the `finally` form costs
10.6 ns per iteration against the flag's 14.2 and the native `range` loop's 4.9 (the O1
rewrite's target), while the JIT compiles all three alike. Function pointers, compound literals,
string literals outside a pointer or `char[N]` context (the empty literal included, F10) and
calls to external functions without a `c_runtime` mapping are errors until their lowering
lands (`docs/implementation_order.md`, P2 onward).

Output is assembled as an array of lines joined once (`docs/probe-findings.md` F19); the
text then goes through the formatter, so spacing is the formatter's and indentation is the
emitter's, four spaces per depth.

## 5. The four tiers

`interp` runs `daslang <module>`, `jit` runs `daslang -jit <module>`, `exe` runs
`daslang -exe <module> -output <work>/<stem>_exe` and executes the binary (the JIT names it
`.exe` on every platform), `aot` runs `daslang utils/aot/main.das -- -ctx <module> <work>/ctx/`
and compiles the generated context with a seven-line C host (`<stem>_create`, `<stem>_main`,
`<stem>_destroy` from the generated header) against the static runtime: `liblibDaScript.a`,
`liblibDaScript_runtime.a`, `liblibUriParser.a`, with the checkout's ABI flags (no RTTI,
`DAS_FUSION=2`, `SIZE_OF_VOID_P=8`). The AOT tier links no C++ module yet; when converted code
requires `crt`, its static archive joins the link. The interpreter and JIT tiers take the
module folders to load from the caller (`suites/c_testsuite/run.das` passes both). The exit code is the program's own on every tier, which is why the wrapper
returns from `main`.

## 6. Exception ledger

Empty.
