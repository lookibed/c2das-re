# frontend Architecture - the record layout

Companion to `ARCHITECTURE.md` in this folder. `c_layout.das` computes a C record's layout the
way clang lays it out for the dialect's triple, from a description of the record that Dumper C's
type builder makes; it reads no C text and no type table of its own. The `linux` dialect is the
System V x86-64 rule set clang follows for `x86_64-unknown-linux-gnu` (the Itanium record layout
builder in C mode); the same rules hold for macOS and wasm64, which the `linux` dialect also
stands for. The `msvc` dialect's rules are `ARCHITECTURE_LAYOUT_MSVC.md`'s. All numbers come from
clang 22: `tests/test_c_layout.das` holds every rule below on a record of
`compare/layout/fixtures/rules.c`, and `compare/layout/` compares the rules with clang on every
record of the suites and the projects.

## 50. The interface and what is refused {#c-layout-record}

`c_record_layout` takes a `CLayoutRecord`: the dialect (a predefined-macro table's name), struct
or union, the record's `packed` and `aligned(N)` (the largest of its `aligned` attributes, 0 for
none; a bare `aligned` is the target's largest alignment, 16, which the caller resolves), the
`#pragma pack` value in force at the definition (0 for none; the pack ledger of
`ARCHITECTURE_PP.md` section 13 holds it), `ms_struct`, and the members in declaration order. A
`CLayoutMember` is its name (`""` for an unnamed bitfield and for an anonymous member), the size
and alignment of its type in bytes, whether it is a bitfield and its width, whether it is a
flexible array member, its own `packed` and largest `aligned(N)` or `_Alignas`, the alignment its
type requires (`required_align`, read under `msvc` alone), its type class, and its place. The
type's size and alignment are the caller's: a scalar's by the dialect, an array's by its element,
a nested record's by that record's own layout, a typedef's `aligned` included under `linux`, which
can lower an alignment as clang lets a typedef do (under `msvc` the type's below its typedefs,
`ARCHITECTURE_LAYOUT_MSVC.md` section 54). A bitfield's size and
alignment are those of its declared type, which is its storage unit; a flexible array member's
alignment is its element's.

The answer is a `CRecordLayout`: the size and alignment in bytes, under `msvc` the record's
required alignment (`required_align`, what a member of its type requires), and each member's
offset in bits from the record's first byte. An anonymous member gets an offset like any member;
the members it makes visible are the nested record's own. The bitfield storage units are not part
of the answer:
the C-IR carries each bitfield's bit offset and width, and the emitter derives the units
(`converter/bit_units.das`).

The layout fails closed. `failed` and `err` (`file:line:col: what`, the member's place when it has
one, else the record's) are set, and no number is, for:

- a dialect with no table;
- `ms_struct`, which switches a `linux` record to clang's own variant of the msvc rules, under
  either dialect;
- a member of a vector type or a 128-bit integer type, which the C-IR has no type for;
- a description no C record has: an alignment, `aligned` or `#pragma pack` value that is no power
  of two, a member of incomplete type, a flexible array member that is not the last member or is
  a bitfield, a bitfield wider than its type or of negative width, and a named bitfield of width
  0;
- a member of 2^60 bytes or more, and a record its members would bring to 2^60 bytes (clang's
  limit: it refuses such a record), checked before any size is counted in bits, so no bit offset
  overflows; the check adds the most padding a member's largest alignment can add, so a record
  within that much of the limit is refused too.

## 51. Members {#c-layout-members}

A member that is no bitfield is placed at the first offset past the previous member's end that
is a multiple of its alignment. Its alignment is its type's, or 1 when the member or the record
is `packed`; its own `aligned(N)` raises that and never lowers it, so `packed` and `aligned(2)`
together give 2; `#pragma pack(n)` then caps it at `n`, an `aligned` member included. A union
places every member at 0 and is as large as its largest member. A flexible array member adds no
bytes, but its alignment places it and counts for the record's. The record's alignment is the
largest of its members' alignments and its own `aligned(N)`, which `#pragma pack` does not cap.
The size is the end of the last member, rounded up to that alignment; a struct with no member is 0
bytes, as GNU C has it. `long double` is 16 bytes aligned to 16, a fact of the type, which the
caller passes.

## 52. Bitfields {#c-layout-bitfields}

A bitfield starts at the first bit the previous member left unused: after a bitfield, inside its
last byte; after any other member, at its end. It moves up to the next multiple of its alignment
when it is of width 0, or when it would cross a boundary of its declared type's unit (its offset
modulo the alignment plus its width is past the type's size in bits); a `_Bool` bitfield has a
unit of one byte. A bitfield with its own `aligned(N)` moves to that alignment besides. Under
`#pragma pack(n)` no bitfield of nonzero width moves for a unit, its alignment is capped at `n`,
and its own `aligned(N)` still places it when `N` is at most `n`. A `packed` bitfield (by its own
attribute or the record's) has an alignment of one bit: it never moves for a unit and adds nothing
to the record's alignment, except under `#pragma pack`, where its alignment is its type's capped
at `n`. A zero-width bitfield keeps its type's alignment under `packed` and `#pragma pack`.

A named bitfield's alignment counts for the record's; an unnamed one's never does, of any width,
so `struct { char a; int : 0; char b; }` is 5 bytes aligned to 1. The record ends at the byte
holding its last bit, rounded to its alignment. In a union every bitfield starts at bit 0 and
takes its width rounded up to bytes.

## 53. The C-IR record and its `packed` verdict {#c-layout-cir}

`c_layout_into_cir` writes a layout into a C-IR record type whose fields the caller has built,
one per member in the same order, as Dumper A does (`converter/ARCHITECTURE_DUMPER.md`): the size
and alignment, each field's `bit_off` and its byte `off` (`bit_off` divided by 8, for a bitfield
too), and `packed`. The `packed` verdict is the layout law of `converter/bit_units.das`, called,
not restated: the record is `packed` when das's natural layout of its fields, through bitfield
units, does not give these offsets and this size. The law reads nested records from the same type
table, so the caller lays a record out after every record it holds by value, and before anything
measures it in the `LayoutMemo` it passes. A record of more bytes than an `int` counts bits is
refused, since a C-IR bit offset is an `int`.
