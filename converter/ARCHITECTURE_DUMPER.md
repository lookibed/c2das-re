# converter Architecture - Dumper A

Companion to `ARCHITECTURE.md` in this folder; section numbers are unique across the family.

## 3. Dumper A's subset

### The program's files {#file-policy}

A C program is its main file and every file under the main file's directory, subdirectories
included, except clang's resource directory and the directories clang searches for `<...>` under
the target (its `-v` list), which stay external wherever they lie (a main file in `/root` holds
the default `/root/libclang`): a header beside the `.c` (or under a folder of it) declares the program's records,
typedefs, enums, prototypes, objects and static functions, and they convert with the file. Every
other file is external, a system header's above all: its records stay out of the C-IR, and a
reference to one of its functions or objects binds by name (`strlen`, `stderr`). Paths compare
canonical (`get_full_file_name`, symbolic links and `..` resolved, memoized per spelling), so
`#include "../dir/x.h"` back into the folder is the program's too. The rule is one test,
`in_program`, applied in both passes: the libclang walk keeps a cursor whose expansion file passes
it, the JSON walk a top-level declaration whose location's file does. The rule draws the
boundary per translation unit, so a program whose headers live outside the folder of its C files
needs them copied beside those files; Lua's sources and headers share one folder. An external record the program reaches a member of, declares a
variable or a record field of, or names under `sizeof` as a type or an operand's (`sizeof *p`)
(`struct tm`, `struct lconv`, `mbstate_t`) is laid out with the program's records: the libclang pass registers its definition from the system header, and every external
record it holds by value, an anonymous one nested in it included, and the walk anchors it where it first interns it, so it converts and is
layout-checked under its C tag; one the program reaches only through pointers (`FILE`) stays
opaque.

clang writes a location's `file` and `line` only where they differ from the last location it
wrote, over every location of the dump in print order: a node's `loc` (a macro-produced one as
its `spellingLoc`, then its `expansionLoc`), its `range.begin` and `range.end`, then its
children (`array_filler` before `inner`); the `file` of an `includedFrom` is no part of that
state. Before the walk `complete_locs` replays that order over the whole dump and writes every
omitted `file` and `line` back, so each valid location names its own file and line; a node's
location is its `loc`, else its `range.begin`, the expansion site for a macro-produced one, and
an invalid location (`{}`) takes the last valid one's.

An `offsetof` joins its libclang cursor (the type and the member, which the dump does not carry)
by that key too, and every `offsetof` of one macro expansion shares it: the expansion site, and
stddef.h's `__builtin_offsetof` as the spelling. The dump gives no location of the member, so the
n-th node of a key takes the n-th cursor, which holds while both walks meet them in source order
(lua's `udatamemoffset`, two in one `?:`). Where they can disagree the conversion fails closed
unless the key's `offsetof`s are alike: one in an initializer list, whose designators reorder the
dump's, and a key the two walks count apart once the dump is walked, one in an array dimension or
a designator's index, which the dump keeps only in a type or drops.

The dumper walks `TranslationUnitDecl.inner`, skipping `isImplicit` nodes (clang's builtin
typedefs and `_GUID`) and every declaration of an external file. Types are interned by a structural key (`int:32:true:int`, `ptr:3`,
`func:0:1,2:false`) in first-use order, which is the spec's order. Type spellings come from
`desugaredQualType` when clang gives one, else `qualType`, with `const`, `volatile`, `restrict`
and `__attribute__` text stripped (a `volatile` the node's own type carries at the top level,
`volatile int`, `int *volatile` or `int (*volatile)(char *)` but not `volatile int *` or
`void (*)(int *volatile)`, marks a `ref`, `member`, `index` or `un deref` node `vol` instead,
`is_volatile_spelling`: the qualifiers after the last `*` of the innermost declarator group, a
parenthesis whose text starts with `*`, before any bounds, clang's `(unnamed at f:l:c)` name of
an anonymous record no group; a function type is never volatile, its qualifier being its return
value's): the C99 scalar names, `_Bool`, `T *`, `T[N]` (the first
bracket is the outer dimension: `T[2][3]` is two `T[3]`), `T (*)[N]` pointers to arrays, `R (P,
...)` function types (`R *(P)` when the return is a pointer, which clang writes without a
space), `R (*)(P)` pointers to functions, `R (**)(P)` pointers to those and `R (*[N])(P)`
arrays of them, the `(*` read as the pointer only outside every parenthesis (a function whose
parameter is a function pointer, `void (void (*)(int), int)`, is a function type) and a `const`
on the pointer (`R (* const)(P)`, a member read through a const record) dropped, since das
spells none. clang spells every constant dimension as its count, so a dimension it leaves as an
expression (`int[n]`) is a variable-length array, which fails closed naming it; a local's error
spells the declaration (`int a[n]`). A VLA parameter is no array: clang decays it to a pointer. A builtin typedef in a builtin's prototype (`__size_t`, `__ptrdiff_t`) has no
cursor and is the dialect's pointer-wide integer. Widths follow the selected dialect (`msvc`:
int 32, long 32, long long 64; `linux`: long 64); plain `char` is unsigned in both
(`docs/probe-findings.md` F17), which the dumper enforces with `-funsigned-char`. Both
passes also define `__NO_CTYPE`: glibc's `<ctype.h>` otherwise spells `isalpha(c)` as a macro
indexing its locale table through `__ctype_b_loc()` and an enum of a system header, and with
it each is the function the crt module binds. The dump
desugars only the top level of a spelling, so a typedef name inside `P_t *` or `P_t (P_t, int)`
resolves through the canonical spelling libclang gives the typedef. Records come from a
libclang pass over the same file under the same flags and the pinned clang's resource directory
(`clang -print-resource-dir`; libclang finds none of its own, and without it `stddef.h` and the
`size_t` a libc prototype spells are missing; an error the pass reports fails the dump with its
text, since a missing header leaves records and typedefs out), run before the JSON walk: every `struct`
and `union` definition of the program, nested ones included, with clang's size, alignment and
field offsets, keyed by the canonical spelling the JSON desugars to (`struct X`, `struct
thinker_t` for a typedef-named anonymous record, which libclang spells bare and the pass
re-tags) and by its location, which is how a `RecordDecl` of the walk finds its layout. A
record is interned in its own slot before its fields, so a self-referential pointer resolves;
`packed` is set when clang's offsets are not the natural layout das would compute (the law of
`ARCHITECTURE.md` section 2, `bit_units.das`), and a record libclang never saw defined has size
-1. A record with bitfields can be natural with an alignment below clang's (under the `linux`
dialect `struct { unsigned a : 3; int b : 5; short e; }` is a `uint8` unit and `e` at 2, size
4, align 2 against clang's 4, `docs/probe-findings.md` F5), so a record holding one is placed
by that smaller alignment. Every field, an unnamed bitfield included (`"name": ""`), is a C-IR
field; clang's record initializer has no child for an unnamed bitfield, so the dumper maps the
n-th child to the n-th field that is not one. An anonymous member (a struct or union member
with no declarator) is a field named `""` that is no bitfield, of the anonymous record's type:
libclang visits that record but never the implicit field, so the pass adds the field where the
record stands, at the offset `clang_Type_getOffsetOf` gives a name the member makes visible
(through nested anonymous members) less that name's offset inside it; a member that makes no
name visible (`struct { int : 4; }`) fails closed, since libclang offers no other way to its
offset. Both the dump and libclang can scope such a record by its owner (`union
S::(anonymous at f:l:c)`, nested `union N::(anonymous struct)::(anonymous at f:l:c)`), so a
record spelling is keyed with the scope dropped. A typedef is a `typedef` type and a `typedefdecl`
anchor, nothing more. A file-scope `static` gets the TU-qualified name `<stem>__<name>` (a stem
that starts with a digit, as the c-testsuite's do, takes a leading underscore, since `00099__f`
is not a name) and a local `static` is hoisted into `decls` as `<fn>_<name>` with `from_func`
(`<fn>_<name>1` and up past another hoisted static, a file-scope name the dump declares, a system
header's included, and a parameter or local of the function). A file-scope `static` declared
again without `static` keeps its internal linkage (C11 6.2.2p4). A reference binds by the
declaration id clang resolved it to (`referencedDecl.id`), never by its spelling, so a local
that hides a static, or a later block's local named like an earlier block's static, keeps its
own binding (`docs/probe-findings.md` F47); an id outside the program (a libc function,
`stderr`) binds by its file-scope name. A block-scope `extern` declares nothing: its id binds to
the declaration its `previousDecl` names, and it fails closed with no file-scope declaration
before it, or when a local of the function spells the same name, since a non-static global and
that local share the C-IR name and the reference would bind to the local. Tentative definitions of one object merge into the declaration
carrying the initializer.

Declarations: `FunctionDecl` with `ParmVarDecl` and a `CompoundStmt` body, `VarDecl`.
Statements: compound, `DeclStmt` (one `decl` per variable), expression statements,
`if`, `while`, `do`, `for` (its five slots, an absent one spelled `{}`), `break`,
`continue`, `return`, the null statement. Expressions: integer, character, floating (as a
hex-float through the CRT) and string literals (C escapes decoded, the NUL appended),
`DeclRefExpr`, every pinned cast, the unary, binary, compound-assignment, conditional and
comma operators, calls, subscripts, `sizeof` and `_Alignof` (clang's `alignof`, with clang's
alignment of the type as its value, the `AlignedAttr` value when a typedef's `aligned` attribute
sets it, its own or one down its chain, which the interned type has lost; an aligned typedef as
an array's element, or one with no value, and GNU `__alignof` fail closed), `MemberExpr` (the field by index into the
record's fields, `arrow` kept; a member named `""` is the anonymous member whose record is the
node's type), `InitListExpr` of a record or an array (clang's semantic form,
one child per field or element, an `ImplicitValueInitExpr` left to the positional zero;
an array with a trailing run of zeros lists its filler first under `array_filler`, then the
elements up to the last one written) or of a union (at most one child, the member it
initializes named under `field`: one item at that member's index, none for `{}`, and a member
`field` names `""` fails closed), `CompoundLiteralExpr` (the `compound_lit` node over its
list; a scalar's list, `(int){5}`, holds its one value at position 0, none for `(int){}`),
`ConstantExpr` (clang's wrapper of a constant item in a file-scope initializer, its child's
value) and `OffsetOfExpr`,
whose components the dump omits: the dumper reads `T, f` from the macro's own text at its
`expansionLoc`, in whichever file of the program that is (F20). A location with an `expansionLoc` is that location.

The libclang pass and the JSON walk meet on one key: the canonical file and byte offset of a
node's expansion location and of its spelling location (`clang_getExpansionLocation`,
`clang_getSpellingLocation`; the JSON `expansionLoc` and `spellingLoc` of a macro-produced node,
its flat `loc` for both otherwise), since every node one macro expansion produces shares the
expansion offset and two files of the program share offsets. The JSON always carries `offset`,
and `complete_locs` gives it the file; a buffer that is no file (`<scratch space>`, a pasted
token's) is the empty file on both sides. Two records one expansion still makes
indistinguishable (one key, or one `(anonymous at f:l:c)` spelling, which is the expansion
location) fail closed when the second is registered; the same record met twice (a block-scoped
record under its statement and its variable's type) is recognized by `clang_hashCursor`. Every record, enum, enumerator reference
and dimensioned declarator the pass records is keyed that way; the location carry (`loc_of`)
serves the C-IR's `loc` alone.

Enums come from the same libclang pass as records: every `enum` definition of the program,
nested and block-scoped ones included, with the enumerator values as C reads them
(`clang_getEnumConstantDeclUnsignedValue` for an unsigned underlying type, which the linux
dialect gives an enum without a negative enumerator; past INT_MAX such a value is possible) and
the width and signedness of the integer type clang chose, keyed by spelling (`enum color`, `enum
mobjtype_t` for a typedef-named anonymous enum, re-tagged the way a record is) and by offset,
which is how an `EnumDecl` of the walk finds its entry and pushes its `enumdef` anchor; a forward
declaration (`enum E;`, no enumerators) adds nothing, and a nested `EnumDecl` or `RecordDecl`
that is not a definition (`struct S { enum K *p; }`) is not registered. An enum whose width is
not the dialect's `int` fails closed, and so does a spelling two block-scoped enums of one tag
share, since the dump resolves types by spelling alone; an enum the walk never anchored (one
defined inside a `sizeof` or cast operand) fails closed at the end of the dump. The pass also
records, per declarator whose array dimensions the source spells by enum constants, the constant
of each dimension (`clang_getCursorReferenced` on the size expression, a lone `DeclRefExpr` to an
`EnumConstantDecl`; any other expression keeps the bare count), and the `VarDecl` or `FieldDecl`
at that offset gets its `dims`, a constant kept only when its value is the dimension's count,
since two declarators of one macro expansion share an offset. A `DeclRefExpr` to an
`EnumConstantDecl` resolves by its offset too, since C scopes let two enums of one file spell one
constant name: the `enum_ref` carries the enum the constant belongs to, and the node's type is
what clang gave the reference (`int`, or `unsigned int` for an enum with a value past INT_MAX).
An enumerator a macro body spells resolves the same way: each token of the expansion has its own
spelling offset, so `#define BOTH (A + B)` keys `A` and `B` apart. A `SwitchStmt` is a `switch` with its
condition and body; clang nests each case's statement under its `CaseStmt`, and shared labels one
under the other, which the dumper flattens into `case` and `default` marker statements followed
by the statement, wherever in the body they sit (Duff's device keeps its nesting). A case value
is folded here, since the JSON writes a `ConstantExpr` without its value: literals, characters,
the arithmetic and bitwise operators, parentheses, casts and enumerators; a GNU case range (`case
1 ... 3`) fails closed. A function's labels are read before its body (a `GotoStmt` names its
label by declaration id, and the label may follow the goto): a `LabelStmt` is a `label` marker
followed by its statement, flattened like a case, a `GotoStmt` is a `goto` naming the label, and
an `IndirectGotoStmt` (a computed goto through a label address) is outside the dialect.
Every type spelling that carries `__jmp_buf_tag` (glibc's `jmp_buf`, `struct
__jmp_buf_tag[1]`; its decay and a pointer to it, `struct __jmp_buf_tag *`; a pointer to the
array, `(*)[1]`) is the one opaque record `jmp_buf` of one `int` field, or a pointer to it,
which the lowering spells as the protocol's `CJmpBuf`; a main-file definition of `struct
__jmp_buf_tag` (a file that includes no header declares glibc's tag itself) adds no record. A `va_list` is known by its declaration, since
msvc's desugaring to `char *` loses it and a program's own `typedef char *va_list` desugars
alike: a typedef is one when its chain of typedefs reaches clang's implicit `__builtin_va_list`
declaration, which the `va_list` and `__gnuc_va_list` of clang's `stdarg.h` do. The JSON walk
follows a node type's `typeAliasDeclId` to the typedef declarations that reach it (collected
in tree order before the walk); the libclang pass follows a typedef's and a record field's
declared type through `clang_getTypeDeclaration`, so a field of a pointer to a `va_list` fails
closed. Under `linux` the spellings `struct __va_list_tag[1]` and `struct __va_list_tag *` are
one too, the decayed parameter having lost its alias. A spelling with no declaration beside it
(a function type's parameters, `va_list *`) is read by its words: a typedef name every typedef
of that name reaching the builtin is a `va_list`, a name some typedefs give a `va_list` and
others another type fails closed, and `struct va_list` is a C record. Such a spelling is the
opaque record `va_list` of `ARCHITECTURE.md` section 2 (`struct __va_list_tag[1]`, a name, and
msvc's builtins' `__builtin_va_list &`), linux's `struct __va_list_tag *` a pointer to it; a
function type naming one among its parameters parses as usual, a pointer to one or an array of
them (`va_list *`, `va_list[2]`) fails closed, and so does a spelling the dumper does not know.
A `VAArgExpr` is the `va_arg` node. A `__builtin_*` reference has no
prototype in the dump (`<builtin fn type>`), so it is a variadic function type read only
through its decay, which clang spells `BuiltinFnToFnPtr` and the dumper as the pinned
`FunctionToPointerDecay` (F23); the emitter resolves the callee by name. Anything else is an
error naming the node kind and its location.

### Attributes and asm {#attributes-and-asm}

The C-IR carries no attribute, so every attribute a program declaration carries, at any depth (a
function's, a local's, a field's, a statement's), is judged against two deliberate lists before
the declaration is dumped (`check_attributes`). The dropped list holds the attributes that change
nothing a das run observes: inlining and optimizer hints (`noinline`, `always_inline`, `hot`,
`cold`, `const`, `pure`, `leaf`, `nothrow`, `malloc`, `alloc_size`), diagnostics (`unused`,
`used`, `format`, `nonnull`, `returns_nonnull`, `warn_unused_result`, `deprecated`, `nodebug`,
`no_instrument_function`, `fallthrough`), a symbol's `visibility` or `section`, `gnu_inline`
(a definition the unit uses either way), `_Noreturn` and `[[noreturn]]`
(GNU `noreturn` is part of the function type, not an attribute node), `mode` (clang has already
given the declaration the type the mode names, `typedef int DI __attribute__((mode(DI)))` dumping
as `long`; a vector mode leaves a vector type, which fails closed as a type), `weak` on a name the
unit defines (a function with a body, a variable that is not `extern` or has an initializer), and
`may_alias`, since das has no strict-aliasing rule for it to relax. `noclone`, `noipa`,
`optimize`, `externally_visible` and `scalar_storage_order` reach no node: clang ignores them, so the dump cannot tell
a test it changed. The read list holds `aligned` (the typedef pass above, the record layout
check) and `packed` with `#pragma pack` (clang's record layout, which the layout law places or
the sidecar marshals, `ARCHITECTURE.md` section 2). Any other attribute (`cleanup`,
`constructor`, `destructor`, `transparent_union`, `alias`, `weak` on a name the unit never
defines) fails the conversion naming it; one clang wrote itself (`implicit`) or carried from an
earlier declaration (`inherited`) was judged where it was written or belongs to the library.

A statement that carries attributes (`AttributedStmt`: `__attribute__((fallthrough));`,
`[[fallthrough]];`) is its statement, the attributes judged with the declaration around it.

A `GCCAsmStmt` has neither its template nor its constraints in the dump, so the libclang pass
reads each asm statement as clang parsed it (`clang_Cursor_getGCCAssemblyTemplate`, the operand
counts, `goto`; a template a macro argument gives is the argument's) and keys it like an enum
reference (`register_asm`). An asm with an empty template, no operand and no `goto`, at most a
clobber list (`asm("")`, `asm volatile("" ::: "memory")`), is a compiler barrier and the empty
statement, since it orders nothing a das run observes; any other fails closed naming why: template
text is machine code, an operand a register binding, `asm goto` a jump from machine code. A
file-scope asm fails closed as machine code outside any function.

### `__builtin_constant_p` {#builtin-constant-p}

A `__builtin_constant_p(e)` call is the `int_lit` of clang's answer, so its argument is neither
dumped nor evaluated (`i++` stays unstepped, `f()` uncalled). The answer is the pinned clang's
at -O0, which is its constant evaluator's and not GCC's (a `const int` local, `(1, 2)`, `1 ? 2 :
x`, `0 && x` and `"hi"[0]` are constants; `1 / 0`, `"hi" + 1`, an address and a variable are
not): the libclang pass evaluates every call (`clang_Cursor_Evaluate`) and keys the answer like
an enum reference, a result its value. Where the evaluator gives none, the -O0 build answers
`llvm.is_constant` over the value its code generator emits for the argument, which is 0 (none
is 0) except across a comma operator, whose right operand the generator emits on its own
(`(x, 5)` answers 1), and over a nested call the evaluator cannot fold
(`__builtin_constant_p(__builtin_constant_p(x))` answers 1): both fail closed
(`probes/test_toolchain.das`), `(x, x)` with them. So does a key two calls share with different
answers (one macro expansion spelling both from one token, a nested expansion placing two calls
at one spelling and one expansion site included: a refusal, never a wrong value), and a call the
pass never saw.
