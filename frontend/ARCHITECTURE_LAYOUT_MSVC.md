# frontend Architecture - the msvc record layout

Companion to `ARCHITECTURE_LAYOUT.md` in this folder. Under the `msvc` dialect `c_layout.das` lays a
record out as clang does for `x86_64-pc-windows-msvc`, whose C records follow clang's Microsoft
record layout builder: the rules below, each held by `tests/test_c_layout.das` on a record of
`compare/layout/fixtures/rules.c` or `compare/layout/fixtures/msvc/rules_msvc.c` with clang 22's
numbers, and compared with clang over the corpora by `compare/layout/` under `--dialect msvc`. The
sizes of the LLP64 data model (`long` 4 bytes, `long double` 8 bytes aligned to 8) are facts of the
types, which the caller passes; the interface and the refusals are section 50's.

## 54. Members and the required alignment {#c-layout-msvc-members}

A member's alignment starts at its type's, is capped by `#pragma pack(n)`, drops to 1 under
`packed`, and is then raised to what the member requires. `packed` on the record acts as
`#pragma pack(1)`. A member requires the alignment of its own `aligned(N)` or `__declspec(align(N))`
(one attribute in clang) and the alignment its type requires: a typedef's `aligned` value, and a
record's `required_align`. A record's `required_align` is the largest of its own `aligned` and its
plain members' requirements, never a bitfield's, and no pack lowers it: `struct Declspec` aligned
to 16 is placed at 16 in a record under `#pragma pack(1)`, and so is any record holding it.

The type's alignment the caller passes is that of the type below its typedefs: msvc lays a member
of type `int_a1` (`typedef int int_a1 __attribute__((aligned(1)))`) out as an `int` at 4 and keeps
the typedef's 1 as a requirement (`required_align`), while an array of `int_a1` has the element's
alignment, 1. Under `linux` the alignment is the typedef's (section 51), and `required_align` is
not read.

A plain member sits at its alignment past the end of the last member, and a union's at 0. The
record's alignment is the largest of its plain members' and its bitfields' alignments (a union's
bitfields excepted) and its required alignment.

## 55. Bitfields {#c-layout-msvc-bitfields}

A bitfield of nonzero width goes into the unit of the bitfield before it when that bitfield has
nonzero width, their declared types have one size, and its bits fit in what the unit has left;
otherwise it opens a new unit of its type's size at its alignment, past the end. So
`struct { char a : 3; int b : 5; char c : 2; }` is three units, 12 bytes. An unnamed bitfield is
laid out and aligns the record like a named one. A bitfield's own `aligned` raises its alignment
and is no requirement. A zero-width bitfield directly after a bitfield of nonzero width moves the
end to its type's alignment and raises the record's alignment; after anything else it does
nothing. In a union every bitfield is at 0 and the union is at least its type's size, and a
bitfield's alignment does not count for the union's.

## 56. The record's size {#c-layout-msvc-record}

The size is the end of the last member rounded up to the members' alignment, then rounded to the
record's alignment capped by the pack, but never below its required alignment:
`#pragma pack(1) struct __attribute__((aligned(8))) { char a; int b; }` is 8 bytes. A record that
ends at 0 bytes (no member, or zero-width bitfields alone) is 4 bytes, or its alignment when it
requires 4 or more. A flexible array member adds no bytes, its element's alignment placing it.
A `#pragma pack` above 8 is ignored by msvc; since no member's own alignment is above 8 without a
requirement, which no pack lowers, it changes no layout and is taken as given.
