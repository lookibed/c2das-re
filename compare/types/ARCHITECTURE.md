# compare/types Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
holds the oracle of Dumper C's C-IR builder, `frontend/c_ir.das` with its type table and
expressions (`frontend/ARCHITECTURE_TYPES.md`, `frontend/ARCHITECTURE_EXPRS.md`): one unit dumped by
Dumper A and built by Dumper C under one dialect, the two type tables, the two units' declarations,
statements and expressions, their conversion censuses and their C-IR texts byte for byte compared. It starts clang, so it lives
outside `frontend/`, whose code starts no process (`frontend/ARCHITECTURE.md` section 2).

## 1. File charters

- `types_compare.das` - the module: the structural name of a table entry (`type_name`,
  `table_names`, `has_aggregate`), the first difference of two tables (`first_difference`), of two
  units' C-IR (`cir_difference`, `stmt_difference`, `expr_difference`) and of their conversion
  censuses (`census_difference`, over `metrics/conversion_census_count.das`), the builder's C-IR
  (`builder_tu`, through `converter/dumper_c.das`), one unit compared (`compare_types`, the byte
  diff `frontend/diff.das`'s), a run's counts (`TypesTotals`, `count_types`,
  `describe_types_totals`), the corpora (`c_testsuite_units`, `gcc_torture_units`), the ratchet
  (`ratchet_key`, `ratchet_keys`) and the command line's run (`TypesArgs`, `run_types`). The clang it runs and
  its flags are Dumper A's (`default_clang`, `dumper_frontend_flags`).
- `run.das` - the command line's entry; from the repository root with `das`: `--c-testsuite` (the
  fetched single-exec suite), `--gcc-torture` (the fetched execute units its `expected_pass.txt`
  lists, Dumper A's passing ids; a suite not fetched is an error and exit 1), units named after the
  flags, `--dialect linux|msvc` (repeatable, both by default), `--ratchet <file>` with
  `--update-ratchet` (section 3). It prints
  each unit that is not an agreement, a line per dialect and the total; with `--ratchet` exit 0
  when every listed unit stays byte-identical, else exit 0 when no unit differs or is
  refused and Dumper A failed on none; 1 otherwise and when no unit is named.
- `fixtures/` - `conversions.c`, every conversion group of the scalar world (all three comparisons
  agree); `redeclared.c`, types a declaration interns that no other declaration names (a block
  typedef's type under a name with an entry, a redeclaration's array; all three agree);
  `walk_bodies.c`, declarations in branches, a loop body and an old-style parameter list whose types
  no expression names; `expr_only.c`, a type only an expression names; `header.c`, an own header's
  typedef; `decl_order.c`, declarations whose expressions bring no type first; `expr_first.c`, an
  expression's type used before a declaration uses it; `differs.c`, a unit whose table, C-IR and
  census differ (clang gives `strlen` its builtin's `size_t` result); `aggregate.c`, a record whose initializer holds an `offsetof` (all
  four agree); `constants.c`, the constant forms of `frontend/ARCHITECTURE_CONSTS.md` with the
  pinned clang's `__builtin_constant_p` answers (all four agree); `aligned_record.c`, an aligned record byte for byte; `refused.c`, a scalar-only unit the builder refuses (a wide string literal).
- The tests are `compare/tests/test_types_compare.das`.

## 2. What is compared {#compared}

A unit is dumped by Dumper A (`dump_tu`, with no sidecar input) under the dialect, and built by
Dumper C (`dumper_c_tu` of `converter/dumper_c.das`: clang's preprocessing, the frontend's parser
and builder, which place every node by their own tokens) with no sidecar input either.

A unit is classed per dialect: Dumper A failed (nothing compared); with aggregates, when Dumper A's
table holds a record, a union or an enum; else scalar-only, and core when its table holds no array
either. Every unit Dumper A dumps is built by Dumper C: the builder's refusal or the parser's is
printed and counted, and four comparisons are made, each printing its first difference:

- the type tables, entry by entry by structural name (`type_name`): an integer by its spelling,
  width and sign, a float by its spelling and width, a pointer, an array, a function and a typedef
  through the names of their parts, a record or an enum by its kind and name;
- the C-IR, declaration by declaration in order: each declaration's kind, C name, type, linkage,
  hoisting function and parameter types, its initializer and its body; each statement's kind, type,
  value, label and expressions and the statements under it; each expression's every field the spec
  lists, a cast's kind and explicitness among them, every name (a declaration's, a parameter's, a
  local's, a reference's), types by structural name. Set aside: the places, and what the
  preprocessor alone knows - the macro fields and whether parentheses are the
  source's own or a macro body's (both keep a macro body's only around a shift or a bitwise
  operator, and the byte comparison checks them);
- the conversion census of `metrics/conversion_census_count.das` (`census_tu`) over both units,
  key by key: every count of every dimension (castKind, pair, context, rule, clause, chain,
  anomaly) equal, the plan's C.3 acceptance;
- the C-IR texts, `write_cir` of each, byte for byte after `cir_diff`'s normalization (the macro
  fields and the producer set aside, `frontend/ARCHITECTURE_DIFF.md`): places and parentheses
  included, the plan's C.6.

A unit agrees when all four are equal; one that differs in its bytes alone differs in places or
parentheses (`frontend/ARCHITECTURE_NAMES.md` section 88). Its printed line names its dialect and
class (`aggregate`, `core`), and the totals count the byte-identical units per class: with
aggregates, scalar-only, and core, the set the Core phase's acceptance names (a scalar-only unit
whose table holds no array type).

## 3. The ratchet

`--ratchet <file>` names a suite's list of byte-identical units (`suites/<suite>/dumper_c_identical.txt`),
one `<dialect> <id>` line each, `id` the file stem; a file that does not exist is an error. Only
the suite's units are keyed: a unit named on the command line is no suite's, its stem may be any
file's, so it is never checked against the list nor written to it. A run fails when a listed unit
it compares is not byte-identical, and reports a byte-identical one the list lacks; a run over a
whole suite (no unit named besides) also reports each listed unit the suite no longer holds.
`--update-ratchet` adds every byte-identical suite unit of the run to the list, sorted, keeps the
lines of units the run did not compare and, over a whole suite, drops those the suite no longer
holds. A list only grows otherwise: a run where a listed unit is no longer byte-identical writes
nothing and fails. The lists are written by this run alone, never by hand. Nothing runs the suite
ratchets on its own: the byte acceptance of a change that can move them runs them; the mechanism's
test is `compare/tests/test_types_compare.das`.
