# compare/types Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
holds the oracle of Dumper C's C-IR builder, `frontend/c_ir.das` with its type table and
expressions (`frontend/ARCHITECTURE_TYPES.md`, `frontend/ARCHITECTURE_EXPRS.md`): one unit dumped by
Dumper A and built by Dumper C under one dialect, the two type tables, the two units' declarations,
statements and expressions, and their conversion censuses compared. It starts clang, so it lives
outside `frontend/`, whose code starts no process (`frontend/ARCHITECTURE.md` section 2).

## 1. File charters

- `types_compare.das` - the module: the structural name of a table entry (`type_name`,
  `table_names`, `has_aggregate`), the first difference of two tables (`first_difference`), of two
  units' C-IR (`cir_difference`, `stmt_difference`, `expr_difference`) and of their conversion
  censuses (`census_difference`, over `metrics/conversion_census_count.das`), the builder's C-IR
  from `clang -E` text (`builder_tu`), one unit compared (`compare_types`), a run's counts
  (`TypesTotals`, `count_types`, `describe_types_totals`), the c-testsuite corpus
  (`c_testsuite_units`) and the command line's run (`TypesArgs`, `run_types`). The clang it runs and
  its flags are Dumper A's (`default_clang`, `dumper_frontend_flags`).
- `run.das` - the command line's entry; from the repository root with `das`: `--c-testsuite` (the
  fetched single-exec suite; a suite not fetched is an error and exit 1), units named after the
  flags, `--dialect linux|msvc` (repeatable, both by default), `--work <folder>` (default
  `compare/work/types`, under the gitignored `compare/work/`). It prints each unit that is not an
  agreement, a line per dialect and the total; exit 0 when no scalar-only unit differs or is
  refused and Dumper A failed on none, 1 otherwise and when no unit is named.
- `fixtures/` - `conversions.c`, every conversion group of the scalar world (all three comparisons
  agree); `redeclared.c`, types a declaration interns that no other declaration names (a block
  typedef's type under a name with an entry, a redeclaration's array; all three agree); `aggregate.c`, a record the builder refuses; `refused.c`, a scalar-only unit the builder
  refuses.
- The tests are `compare/tests/test_types_compare.das`.

## 2. What is compared {#compared}

A unit is dumped by Dumper A (`dump_tu`, with no sidecar input) under the dialect, and preprocessed
by `clang -E` under the same flags (`dumper_frontend_flags`) into `<work>/<unit>.<dialect>.i`, line
markers kept: the builder takes a declaration in a file under the own headers' folder for a
library one (`frontend/ARCHITECTURE_TYPES.md` section 28). The parser reads that text with the
dialect's predeclared names, and `c_ir_unit` builds the C-IR.

A unit is classed per dialect: Dumper A failed (nothing compared); with aggregates, when Dumper A's
table holds a record, a union or an enum, which the builder refuses until the Aggregates phase (a
builder that builds such a unit is printed); else scalar-only, where the builder's refusal or the
parser's is printed and counted, and three comparisons are made, each printing its first
difference:

- the type tables, entry by entry by structural name (`type_name`): an integer by its spelling,
  width and sign, a float by its spelling and width, a pointer, an array, a function and a typedef
  through the names of their parts, a record or an enum by its kind and name;
- the C-IR, declaration by declaration in order: each declaration's kind, C name, type, linkage,
  hoisting function and parameter types, its initializer and its body; each statement's kind, type,
  value, label and expressions and the statements under it; each expression's every field the spec
  lists, a cast's kind and explicitness among them, types by structural name. Set aside: a
  declaration's and a reference's linkage name and a local's renamed name (C.4's renames), the
  places, and what the preprocessor alone knows - the macro fields and whether parentheses are the
  source's own or a macro body's (Dumper A keeps a macro body's only around a shift or a bitwise
  operator; `clang -E` text keeps no trace of a macro);
- the conversion census of `metrics/conversion_census_count.das` (`census_tu`) over both units,
  key by key: every count of every dimension (castKind, pair, context, rule, clause, chain,
  anomaly) equal, the plan's C.3 acceptance.

A scalar-only unit agrees when all three are equal.
