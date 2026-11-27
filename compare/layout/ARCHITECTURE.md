# compare/layout Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
holds the layout oracle of Dumper C's record layout, `frontend/c_layout.das`
(`frontend/ARCHITECTURE_LAYOUT.md`): every record a unit defines, described to the module, laid
out by it, and compared with clang's layout of the same record. It starts clang and uses libclang,
so it lives outside `frontend/`, whose code does neither (`frontend/ARCHITECTURE.md` section 2).

## 1. File charters

- `layout_oracle.das` - the module: clang's text AST dump read for the records' attributes
  (`dump_records`), libclang's records (`clang_records`), the two matched (`match_records`), a
  record described (`describe_record`) and compared (`layout_differences`), a unit's run
  (`compare_layout_unit`), the corpora (`layout_corpus`) and the command line's run (`LayoutArgs`,
  `run_layout_oracle`). The clang it runs and its flags are Dumper A's (`default_clang`,
  `dumper_frontend_flags` of `converter/dumper_a.das`) for the dialect the run names.
- `run.das` - the command line's entry, from the repository root with `das`: `--corpus rules` (the
  fixtures), `--corpus c-testsuite`, `--corpus gcc-torture`, `--corpus lua`, `--corpus doom`,
  repeatable, `--root <folder>`, the folder holding the fetch trees (`suites/`, `lua/`, `doom/`;
  default the working directory), and `--dialect linux` (the default) or `--dialect msvc`, whose
  triple, predefined-macro table and own headers every unit is then read under. An unknown corpus,
  or one whose folder is missing, is an error and exit 1, never an empty set. It prints each
  differing record with its differences, each unit clang rejects, each undescribed record with its
  reason, a line per corpus with what it did not compare, and exits 0 when no record differs.
- `fixtures/rules.c` - one record per rule of `frontend/ARCHITECTURE_LAYOUT.md`, the records
  `frontend/tests/test_c_layout.das` quotes, read under both dialects. `fixtures/msvc/rules_msvc.c`
  - the msvc rules `rules.c` does not show (`frontend/ARCHITECTURE_LAYOUT_MSVC.md`), read under
  `msvc` alone, since `__declspec` needs its triple. `fixtures/probe_shapes.c` - the records
  `probes/test_layout.das` lays out through clang. `fixtures/macro_records.c` - three records one
  macro expansion defines. `fixtures/msvc/typedef_array.c` - a typedef of an array with `aligned`
  and an array of an aligned typedef, under `msvc`.
- The tests are `compare/tests/test_layout_oracle.das`.

## 2. What is compared

The oracle tests the layout rules, not a type builder. Dumper C cannot yet describe a record from C
source (the type builder of the plan's A.1 does that), so the description is built from clang's own
AST: each member's type size and alignment, bitfield width, flexible array and type class from
libclang (`clang_Type_getSizeOf`, `clang_Type_getAlignOf`, the canonical type's kind), and the
attributes libclang does not expose from `clang -Xclang -ast-dump` under the same flags: the
record's `PackedAttr`, `AlignedAttr` (its value, 16 for a bare `aligned`), `MSStructAttr` and the
`MaxFieldAlignmentAttr` that `#pragma pack` leaves on it (in bits), and each member's `PackedAttr`
and `AlignedAttr`. clang's answer is libclang's: the record's size and alignment and each field's
bit offset (`clang_Cursor_getOffsetOfField`). Under `msvc` a member's type requirement is described
too: a typedef with an `aligned` attribute (an `AlignedAttr` child of a typedef's declaration on the
way to the type, through arrays) requires the type's alignment, and the member then gets the
alignment of the type below its top-level typedefs alone (clang's `getUnqualifiedDesugaredType`): a
typedef of an array is laid out by the array, whose element keeps its own typedef's alignment; a member of a record
type, through arrays, requires that record's `required_align` as the module computes it, so the
records of a unit are laid out after every record their members' types are, a record found by its
definition, never by a forward declaration of its tag. An anonymous member is
the anonymous record libclang visits; its offset is that of a name it makes visible less that name's
offset inside it, as Dumper A finds it (`converter/ARCHITECTURE_DUMPER.md`).

libclang visits a record definition again under a declaration of its type, so the records are
taken once by their place, in libclang's order: the expansion file and offset with the spelling file
and offset, so the records one macro expansion defines are each their own (`fixtures/macro_records.c`);
the dump lists the definitions in the same order, clang's implicit records left out. A record is
matched to the next dump record of the same kind and member names within 16 places, else it is
counted as matching none; one whose libclang and dump member counts differ is undescribed. A record
met in an earlier unit of the corpus (a header's) is counted once while its description stays the
same; a unit whose defines or `#pragma pack` describe it otherwise compares it again, counted as
compared again.

Each record is one of: agreeing (size, alignment and every member's offset equal), differing (each
difference printed), refused by the module (its reason counted: a vector or 128-bit member,
`ms_struct`), or undescribed, with its reason: clang gives it no layout, an `_Alignas(type)` whose
value the dump does not state, an anonymous member that makes no name visible, a member whose record
has no layout of the module's, member counts that differ, or no dump record matching it; each is
printed with its reason. A unit libclang or clang rejects is a clang failure, printed and counted
apart. A corpus line ends with what was not compared (the units clang rejects, the undescribed
records), so its agreement is read against them. Only a difference fails the run.
