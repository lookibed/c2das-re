# frontend Architecture - records, unions and enums

Companion to `ARCHITECTURE.md` in this folder; section numbers are unique across the family. It
describes `c_records.das`, which builds a unit's struct, union and enum types, and what
`c_types.das`, `c_exprs.das` and `c_ir.das` do with them, so that the C-IR equals Dumper A's
(`converter/ARCHITECTURE_DUMPER.md` section 3, `docs/c-ir-spec.md` section 3). The layout of a
record is `ARCHITECTURE_LAYOUT.md`'s.

## 41. Tags and definitions {#c-records-definitions}

A struct, union or enum specifier with a body defines a type of its own identity (its pool entry's
`count`, which the C-IR writes for no record or enum): the tag names it in the scope the
definition stands in, a block's tag ending with the block. A specifier with no body names the
tag's type; a record tag no definition reached yet names a new incomplete record. Dumper A reads a
record's fields from clang's whole unit where its type is first reached, so a use before the one
file-scope definition of its tag (`typedef struct node node;` before `struct node { ... }`) takes
that definition (`c_tag_lookahead` finds each tag's one file-scope definition, the own headers'
included): the use marks it, and it is built once the declaration of the use is bound
(`c_tag_complete`), before a type is interned, a member read or a size taken; such a definition's members may
name a typedef the unit declares at file scope after the use (each typedef name's one file-scope
declaration is found with the definitions). A record never
defined is incomplete: its entry has size and alignment -1 and no field.

An enum named before its one file-scope definition (`typedef enum foo E;` first) takes it the same
way; any other enum named before its definition is refused. A tag defined again in another scope
(two blocks' `union D`, or a block's definition shadowing a file-scope one) names a record of its
own, which Dumper A names by the first `<tag><n>` from
1 that no record, enum, typedef, file-scope name or identifier in scope spells; an enum defined
again is refused, as Dumper A binds its constants by place. A definition is built where a
declaration, a member or the walk stands; one in a parameter list or a type name is refused, and
so are a tag defined again in its own scope and a tag of another kind. glibc's `struct
__jmp_buf_tag`, which Dumper A holds as the opaque `jmp_buf`, is refused, and with it `jmp_buf`. An
initializer list of a struct or union, and an array of records initialized with elided braces,
are refused: initializers of aggregates are A.3's. A record or enum with no tag that a typedef declares by its name alone
(`typedef struct { ... } Q;`) is named by it; any other with no tag is named "", and an enum with
no name is spelled `enum (unnamed at <file>:<line>:<col>)`, the place of its keyword, as clang
spells it. A definition in an own header is built where the header stands; one the builder refuses
there is refused where the unit names the tag.

## 42. The table order and the anchors {#c-records-order}

A record's table entry is interned before its fields' types, so a pointer to it among them
resolves; then each field's type in order, then the layout with its `packed` verdict
(`c_layout_into_cir`). An enum constant's value rides on its node while it is folded and is
cleared when the node is interned. The walk (`c_tag_definitions`) reaches a definition among a declaration's
specifiers: the definitions among its members first, each interned and anchored, then its own
entry and its `record` or `enumdef` declaration at its tag, its keyword when it has none. A
block's definition is anchored where the block stands, before its function's declaration. An own
header's record or enum is anchored where the unit first interns it, at the declaration or
statement being read; one never defined is anchored nowhere.

## 43. Members {#c-records-members}

A member declaration's specifiers give its type, each member declarator its declarator's type,
its name and its bit width (an integer constant expression from 0 to 64 over an integer or enum
type); a declaration with no declarator is an anonymous member, a field named "" of a record with
no tag, and any other declaration that declares no member is refused. An array of unknown size is
a flexible member. Each member is described to the layout by its type's size and alignment, its
bit width, its own `packed` and `aligned`, and under msvc the layout requirement of a record it
holds (through arrays); the layout refuses what it does not lay out, a member of incomplete type
among them.

## 44. Layout attributes {#c-records-attributes}

`packed` and `aligned(N)` (`__packed__`, `__aligned__`) on a record (after its keyword or its body)
and on a member (in its specifiers or after its declarator) reach the layout; `aligned` alone is
16, x86-64's largest alignment, and an `aligned` of other than an integer literal is refused, as is
an attribute that changes a type. `ms_struct` on a record is the layout's refusal. A `#pragma pack`
does not reach the builder: the C token reader refuses the directive.

## 45. Enums {#c-records-enums}

An enumerator's value is its integer constant expression's, the one before plus one where none is
written (0 for the first), and it is bound as it is read, so a later value folds an earlier one.
Under msvc an enum is an `int` and its values are wrapped into it; under linux it is `unsigned int`
when no value is negative, else `int`, and an enum no 32-bit type holds is refused. An enumerator is
an `int`, or under linux the enum's `unsigned int` when one of its values is past INT_MAX. A
reference to one is an `enum_ref` of its enum and name. An enum's value promotes to its type's
integer by an `IntegralCast`, and converts as an integer of that type. A pointer to an enum and
one to its integer type are compatible: in a conditional they make the integer's pointer.

## 46. Member access {#c-records-access}

`.` and `->` name a field of a complete struct or union: its own, or one an anonymous member makes
visible, each anonymous member on the way a `member` node of its own, `arrow` on the first access
alone. A member's type is its field's with the record's qualifiers; a `volatile` one, or an
array of volatile elements, marks the lvalue, a variable's and a subscript's alike. Every member is read as an lvalue, one of a call's
record result too, which clang materializes. A read of a bit-field narrower than `int` promotes to `int`
whatever its type's width, one as wide as `int` to `int` or, of an unsigned type, `unsigned int`,
and a wider one keeps its type, as clang promotes bit-fields; a compound
assignment to one computes in that promoted type.

## 47. Dims {#c-records-dims}

A declarator's `dims` (a global's, a local's, a field's) holds, per array level of its type from
the outermost, in the order the source spells the sizes, the enumerator a size names alone (its value
is that level's count; Dumper A checks it, since a macro expansion can give two declarators one
place, which Dumper C's own tokens never do), else enum 0 and no item; a declarator none of whose sizes names one has
none, as Dumper A records them.
