# compare/types Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder holds
the oracle of Dumper C's type table, `frontend/c_types.das` (`frontend/ARCHITECTURE_TYPES.md`): one
unit dumped by Dumper A and read by the builder under one dialect, the two type tables compared
entry by entry. It starts clang, so it lives outside `frontend/`, whose code starts no process
(`frontend/ARCHITECTURE.md` section 2).

## 1. File charters

- `types_compare.das` - the module: the structural name of a table entry (`type_name`,
  `table_names`, `has_aggregate`), Dumper A's declaration order rebuilt from its declarations
  (`declaration_order`, section 3), the entries only its expressions reach (`expression_only`), the
  declaration comparison (`declaration_difference`), the builder's table from `clang -E` text
  (`builder_table`), one unit compared (`compare_types`, `first_difference`), a run's counts
  (`TypesTotals`, `count_types`, `describe_types_totals`), the c-testsuite corpus
  (`c_testsuite_units`) and the command line's run (`TypesArgs`, `run_types`). The clang it runs and
  its flags are Dumper A's (`default_clang`, `dumper_frontend_flags`).
- `run.das` - the command line's entry; from the repository root with `das`: `--c-testsuite` (the
  fetched single-exec suite; a suite not fetched is an error and exit 1), units named after the
  flags, `--dialect linux|msvc` (repeatable, both by default), `--work <folder>` (default
  `compare/work/types`, under the gitignored `compare/work/`). It prints each unit that is not an
  agreement, a line per dialect and the total; exit 0 when no scalar-only unit differs or is
  refused and Dumper A failed on none, 1 otherwise and when no unit is named.
- `fixtures/` - `decl_order.c`, declarations whose expressions bring no type first (the whole tables
  agree); `redeclared.c`, types a declaration interns that no rebuilt declaration names (a block
  typedef's type under a name with an entry, a redeclaration's array); `expr_first.c`, an expression
  type used before a declaration uses it (only the declaration orders agree); `aggregate.c`, a
  record the builder refuses; `refused.c`, a scalar-only unit the builder refuses; `walk_bodies.c`,
  declarations in branches, a loop body and an old-style parameter list that no expression's type
  names; `expr_only.c`, a type only an expression names; `header.c`, an own header's typedef.
- The tests are `compare/tests/test_types_compare.das`.

## 2. What is compared {#compared}

A unit is dumped by Dumper A (`dump_tu`, with no sidecar input) under the dialect, and preprocessed
by `clang -E` under the same flags (`dumper_frontend_flags`) into `<work>/<unit>.<dialect>.i`, line
markers kept: the builder takes a declaration in a file under the own headers' folder for a
library one (`frontend/ARCHITECTURE_TYPES.md` section 28). The parser reads that text with the
dialect's predeclared names, and the builder builds the table.

Two tables are compared by the structural name of each entry (`type_name`): an integer by its
spelling, width and sign, a float by its spelling and width, a pointer, an array, a function and a
typedef through the names of their parts, a record or an enum by its kind and name. A name is the
same for one type in either table, whatever index the parts have.

A unit is classed per dialect: Dumper A failed (nothing compared); with aggregates, when Dumper A's
table holds a record, a union or an enum, which the builder refuses until the Aggregates phase (a
builder that types such a unit is printed); else scalar-only, where the builder's refusal or the
parser's is printed and counted, and its table is compared twice: whole, against Dumper A's table,
and by declarations, against Dumper A's declaration order (section 3). The builder builds no
expression type yet, so a scalar-only unit agrees when the declaration orders are equal; the whole
table agrees too where no expression brings a type before a declaration does. A unit whose
declaration orders differ prints the first differing entry, each side's name there.

## 3. Dumper A's declaration order {#declaration-order}

Dumper A's table interleaves expression types with declaration types
(`frontend/ARCHITECTURE_TYPES.md` section 27). `declaration_order` rebuilds the order Dumper A's
walk reaches the declaration types alone, from its `decls`: each declaration's type, a function's
parameter types, then its body's `decl` statements in source order, statements under statements
depth-first; each type's parts before it, as section 24 of that document states. Dumper A pushes a
static it hoists from a body, and a block declaration of a function no declaration named before,
into `decls` ahead of the function, and leaves a `null` statement in the body: each declaration
ahead of a function with a body, in its file and placed after the function's own place, is one of
those. The walk reaches it in the body before the first statement placed after it (at the end of the
body when none is), where Dumper A interned its type.

The rebuilt order holds only the types a declaration in `decls` names, and some declarations
intern a type no declaration names: a block typedef of a name that has a `typedef` entry already
(the entry is shared by name, so the declaration names the first typedef), an array type a
redeclaration's composite replaced. `declaration_extras` finds those two kinds in Dumper A's unit:
an array of unknown size whose completed form is a global's type, and, when a typedef name is
declared more than once, every entry the rebuilt order does not hold. The declaration comparison
(`declaration_difference`) then takes every entry of Dumper A's table as a declaration's unless only
expression nodes reach it (`expression_only`: the types its expressions name, with their parts,
less the rebuilt order's); a declaration entry that is neither rebuilt nor of those two kinds is a
gap of the rebuilt walk and a difference, so a walk that skips a branch, a loop body or an
old-style parameter list fails (`fixtures/walk_bodies.c`). The builder's table must hold exactly the
declaration entries - no entry Dumper A's declarations do not intern, none of them missing - with
the rebuilt ones in the rebuilt order and each other one where Dumper A's table puts it among them
(after the longest run of rebuilt entries from the first that Dumper A interned before it), so a
builder that drops, adds or moves an entry never counts as agreeing.

