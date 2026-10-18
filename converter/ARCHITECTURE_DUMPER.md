# converter Architecture - Dumper A

Companion to `ARCHITECTURE.md` in this folder; section numbers are unique across the family.

## 3. Dumper A's subset

The dumper walks `TranslationUnitDecl.inner`, skipping `isImplicit` nodes (clang's builtin
typedefs and `_GUID`) and every declaration whose location is another file (a header's).
Locations come from `loc`, else `range.begin`; clang omits `file` and `line` when they repeat
the previous node's, so the dumper carries the last seen values forward in tree order, starting
from the main file. Types are interned by a structural key (`int:32:true:int`, `ptr:3`,
`func:0:1,2:false`) in first-use order, which is the spec's order. Type spellings come from
`desugaredQualType` when clang gives one, else `qualType`, with `const`, `volatile`, `restrict`
and `__attribute__` text stripped: the C99 scalar names, `_Bool`, `T *`, `T[N]` (the first
bracket is the outer dimension: `T[2][3]` is two `T[3]`), `T (*)[N]` pointers to arrays, `R (P,
...)` function types (`R *(P)` when the return is a pointer, which clang writes without a
space), `R (*)(P)` pointers to functions, `R (**)(P)` pointers to those and `R (*[N])(P)`
arrays of them. A builtin typedef in a builtin's prototype (`__size_t`, `__ptrdiff_t`) has no
cursor and is the dialect's pointer-wide integer. Widths follow the selected dialect (`msvc`:
int 32, long 32, long long 64; `linux`: long 64); plain `char` is unsigned in both
(`docs/probe-findings.md` F17), which the dumper enforces with `-funsigned-char`. The dump
desugars only the top level of a spelling, so a typedef name inside `P_t *` or `P_t (P_t, int)`
resolves through the canonical spelling libclang gives the typedef. Records come from a
libclang pass over the same file under the same flags, run before the JSON walk: every `struct`
and `union` definition of the main file, nested ones included, with clang's size, alignment and
field offsets, keyed by the canonical spelling the JSON desugars to (`struct X`, `struct
thinker_t` for a typedef-named anonymous record, which libclang spells bare and the pass
re-tags) and by its location, which is how a `RecordDecl` of the walk finds its layout. A
record is interned in its own slot before its fields, so a self-referential pointer resolves;
`packed` is set when clang's offsets are not the natural layout das would compute, and a record
libclang never saw defined has size -1. A typedef is a `typedef` type and a `typedefdecl`
anchor, nothing more. A file-scope `static` gets the TU-qualified name `<stem>__<name>` (a stem
that starts with a digit, as the c-testsuite's do, takes a leading underscore, since `00099__f`
is not a name) and a local `static` is hoisted into `decls` as `<fn>_<name>` with `from_func`;
references use the hoisted name. Tentative definitions of one object merge into the declaration
carrying the initializer.

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
An enumerator reached through a macro has no main-file cursor and fails closed
(`docs/implementation_order.md`, the P2.4 ledger). A `SwitchStmt` is a `switch` with its
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
which the lowering spells as the protocol's `CJmpBuf`. A `__builtin_*` reference has no
prototype in the dump (`<builtin fn type>`), so it is a variadic function type read only
through its decay, which clang spells `BuiltinFnToFnPtr` and the dumper as the pinned
`FunctionToPointerDecay` (F23); the emitter resolves the callee by name. Anything else is an
error naming the node kind and its location: compound literals are the next row.
