# compare/pp Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
holds the token oracles of Dumper C's preprocessor: of the pp-token lexer, `frontend/pp_lexer.das`
(`frontend/ARCHITECTURE.md` section 4), and of the directive layer, `frontend/pp_directives.das`
(`frontend/ARCHITECTURE_PP.md`), and of the macro expansion, `frontend/pp_expand.das`
(`frontend/ARCHITECTURE_EXPAND.md`), with the `#if` evaluator, `frontend/pp_eval.das`
(`frontend/ARCHITECTURE_EVAL.md`): one unit through clang and through the frontend, the two
token streams compared token by token; and the token oracle of the whole preprocessor over every
corpus, with gcc as the second reference (section 8). It starts clang and gcc, so it lives outside
`frontend/`, whose code starts no process (`frontend/ARCHITECTURE.md` section 2).

## 1. File charters

- `pp_oracle.das` - the module: a unit preprocessed by clang (`compare_unit`), clang's token dump
  read (`clang_tokens`, `clang_kind`), the lexer's tokens (`lexed_tokens`), the comparison
  (`compare_tokens`), the corpora (`corpus_units`), the list of reference failures
  (`reference_failures`, `reference_failure`, section 3), a set's run (`run_set`) and the command
  line's run (`OracleArgs`, `run_oracle`); and the directive oracle of section 4
  (`compare_unit_pp2`, `pp2_tokens`, `pragma_lines`, `pp2_differences`, `pp2_difference_class`,
  `pp2_class`, `run_set_pp2`, `run_pp2`), which with `expand` is the expansion oracle of section 5
  (`OracleUnit`, `oracle_units`, `list_units`, `ORACLE_EPOCH`); and `write_features`, the
  regeneration of section 6.
- `pp_macros.das` - the expansion record's oracle of section 7: a unit through Dumper A and the
  record (`compare_unit_pp5`), the text normalizations (`pp5_normalized`, `pp5_macro_text_agrees`),
  a set's run and line (`run_set_pp5`, `describe_pp5_totals`), the `fixtures` corpus
  (`pp5_corpus_units`) and the command line's run and exit code (`run_pp5`, `pp5_exit_code`).
- `pp_features.das` - the feature-query tables of `frontend/predefined/` generated from the pinned
  clang (section 6): the operands read from clang's headers (`feature_candidates`), each asked of
  clang (`generate_features`), under the dialect's dumper flags (`dialect_flags`). The clang it runs
  and its flags are Dumper A's (`default_clang`, `dumper_frontend_flags`, `DUMPER_FLAGS` of
  `converter/dumper_a.das`): the oracle preprocesses as the converter does.
- `pp_token_oracle.das` - the token oracle of section 8: the corpora and sets (`Pp6Corpus`,
  `pp6_corpus`, `pp6_set`), gcc's flags and answer (`gcc_flags`, `pinned_gcc`, `gcc_answer`), the
  classes and the lists (`refusal_class`, `pp6_class`, `pp_answer`, `Pp6Lists`, `count_pp6`,
  `Pp6Totals`, `pp6_exit_code`),
  a corpus's run (`run_set_pp6`) and the command line's (`run_pp6`, `run_pp6_main`).
- `run.das` - the command line's entry, its arguments parsed into `run_oracle`; from the repository
  root with `das`: `--corpus frontend` (every
  header of `frontend/include/`), `--corpus c-testsuite` (the fetched single-exec suite), `--corpus gcc-torture` (the fetched
  `execute` folder's own units), `--corpus pp2` and `--corpus pp3` (the directive and expansion
  fixtures), `--list <file>` (a corpus list, section 5), units named after the flags, `--raw`,
  `--pp2` (section 4), `--pp3` and `--pp4` (section 5), `--corpus pp4`, `--features` (section 6),
  `--pp5` (section 7) with `--corpus fixtures` (the converter's test units), `--pp6` with
  `--fast` or `--full` (section 8),
  `--show N`, `--work <folder>` (default `compare/work/pp`, under
  the gitignored `compare/work/`). An unknown corpus, or one whose folder is missing - a suite not
  fetched - or a corpus list that is missing, is an error and exit 1, never an empty set. It prints each unit that differs with its
  first differences, a line per set and the total; exit 0 when no unit differs.
- `fixtures/edge_tokens.c` - the edge cases of `frontend/pp_lexer.das` as one unit with no
  directive: pp-numbers, UCNs, prefixes, every punctuator and digraph, `::`, raw strings, OTHER
  characters, splices, comments. `fixtures/bom_tokens.c` - a byte order mark and leading blanks,
  compared raw.
- `fixtures/pp2/` - the directive oracle's units (`*.c`) and the headers they include: include
  guards in both spellings, a file that is no guard, `#pragma once`, `#line` and a line marker,
  nested conditionals with directives in skipped groups, pragmas and the null directive, `#import`,
  `#ident` and `#sccs`. None uses a macro.
- `fixtures/pp3/` - the expansion oracle's units: the examples of C11 6.10.3.3 to 6.10.3.5 and
  6.10.9, rescanning and deferred recursion, the GNU variadics, `#` and `##`, the builtins under
  `SOURCE_DATE_EPOCH`, macros in `#include`, `#line` and `#if` lines, and `_Pragma` - its operand
  expanded, in arguments done at the rescan, in an `#if` line - with the names of disabled macros
  read in arguments, a directive before a call's `(`, `__VA_OPT__` in a macro that is not variadic
  and a final `\` stringified (`pragma_args.c`); `vers2.h` and `builtins.h` are headers they
  include.
- `fixtures/pp4/` - the whole preprocessor's units, the `#if` evaluator's cases as clang reads
  them: the sign trap of glibc's `bits/wchar.h` and its unsigned twins, arithmetic, constants,
  short-circuiting, `#elif` chains and nesting, `__COUNTER__` in a condition, `__has_include` by
  name and by macro, each feature query, `defined` of builtin names; and an include guard a macro
  produces, which is none (`guard_macro.c`, `guard_macro.h` the header it includes twice).
- `fixtures/pp5/lua.txt` - a corpus list of Lua's units under the defines of `lua/lua.c2das`, for
  `--pp5`: the program where Dumper A marks the most expansions.
- `fixtures/pp5/copies.c` - a unit for `--pp5` whose calls end in an argument copy and are
  followed by source tokens and by another call, where a copy left on the next token shows.
- `reference_failures.txt` - the units the reference cannot preprocess, each with its reason
  (section 3). `implementation_defined.txt` - the units clang and gcc disagree on, each with
  their first difference and the preprocessor's; `known_differences.txt` - the units of a corpus
  list where the preprocessor differs and gcc agrees with clang, each with its cause (section 8).
- `corpus/` - the corpus lists of section 8's preprocessor-loading inputs, paths from the
  repository root; `fetch.sh` fetches the outside ones into `compare/pp/fetch/` (gitignored) at
  their `VERSIONS.md` pins. `fixtures/pp6/` - the inputs of those lists written here: the C11
  6.10.3.5 examples and macro tricks (`std/`), the hide-set tests (`hideset/`, `hideset2/`), the
  macro libraries' units (`macrolibs/`), and `impl_line.c`, a unit clang and gcc disagree on.
- The tests are `compare/tests/test_pp_oracle.das`.

## 2. What is compared {#flags}

A unit is preprocessed by `clang -E -P` under Dumper A's flags for the `linux` dialect (its
triple, `-undef` and the predefined-macro table as `-D`, `-funsigned-char`, `-nostdinc` and the own
headers), into `<work>/<unit>.i`. Clang then lexes that output under `-dump-tokens` with the triple,
`-undef` and the same flags, so no macro is left to expand, and the pp lexer lexes the same file.
With `--raw` both read the unit itself, which then has no directive: clang's tokens are its
lexer's, so line splices, comments and a byte order mark reach both sides, which `-E` output
never carries.

A token is compared by its kind (clang's mapped to the lexer's `PpTok`: every keyword and
`identifier` an IDENTIFIER, every literal class to CHAR_CONSTANT or STRING_LITERAL, `unknown` to
OTHER), its spelling (clang's clean one, splices removed, as the lexer's `pp_spelling`), its line,
its column, `at_bol` against `[StartOfLine]`, and `has_space` against `[LeadingSpace]` or
`[StartOfLine]` past the first line: clang sets `[LeadingSpace]` only for blanks or a comment on
the token's own line, while the lexer's `has_space` counts the newline as skipped text too
(`frontend/ARCHITECTURE.md#pp-flags`). On the first line no newline precedes a token, so there
`[LeadingSpace]` alone decides, and a byte order mark before the first token is no space on
either side.

The two streams are walked together by position. A token both place at one line and column is
one difference when its kind, spelling or a flag differs; a token only one side places there is
one difference, and the walk moves on past it on that side alone, so a token one side splits in two
costs its own differences and the tokens after it still compare. Each token one side has past the
other's end is one more. A unit clang refuses (a header the own set lacks) is a clang failure,
counted apart and never a difference.

## 3. Reference failures {#reference-failures}

Some corpus units `clang -E` itself cannot preprocess under the dumper's flags, by a decision made
elsewhere: a header the own set leaves out (`<sys/mman.h>` for gcc-torture's `loop-2f.c` and
`loop-2g.c`), or a quoted include of a `gcc.dg` file the sparse gcc-torture fetch does not hold.
Nothing on the lexer's side can be compared for them. `reference_failures.txt` lists them, one line
per unit: the end of its path (`gcc.c-torture/execute/loop-2f.c`), a tab, the reason. `run_set`
(and `run_set_pp2`, both through `reference_failure`) counts a failing unit the list names as a listed reference failure, with that reason, and any
other failing unit as an unlisted one, with clang's error, so a new failure shows up apart from the
known ones. A listed unit that preprocesses after all is counted and printed too, so a stale line
is dropped. None of the three counts is a difference. The lexer's run exits by the differences
alone; the directive and expansion oracles (sections 4 and 5) fail closed: an unlisted reference
failure fails their run, a listed one does not, so the units the reference cannot read stay the
ones the list names and a new failure is never passed over as a reference problem.

## 4. The directive oracle {#pp2}

`--pp2` compares `frontend/pp_directives.das` with clang: a unit is preprocessed by `clang -E -P`
under the flags of section 2 and its output token-dumped as there, and PP.2 reads the unit itself
through the `fio` provider with the same macros and include path (`pp2_setup`: the `linux`
table's entries, the own headers' folder, canonical). `-P` output has lines and columns of its
own, so a token is compared by its kind, its spelling and `at_bol` only. Clang prints each pragma
it keeps, and each `#ident` or `#sccs`, as a `#pragma` or `#ident` line of its output, which its
token dump takes as a directive, not tokens; PP.2 keeps them in its ledgers, not its stream. So
the oracle counts those lines of the `-E` output (`pragma_lines`) against PP.2's pragma and pack
entries, and places each: a line's place is the count of clang's tokens on the lines before it
(`pragma_places`), an entry's the tokens PP.2 handed out before it (`emitted`). Clang prints a
`#pragma GCC warning` or `GCC error` too, which PP.2 raises as a diagnostic and keeps in no ledger
(`frontend/ARCHITECTURE_PP.md#pp-poison`), so such a line is not counted: its kind is the whole
word `warning` or `error`, ended by the line or a blank, as clang's `-E` prints the line with one
blank between its tokens - `GCC warningfoo` is a pragma PP.2 keeps.

A macro clang expands shifts every later token, so the two streams are aligned, not compared
position by position: `pp2_differences` takes Myers' shortest edit script by kind, spelling and
`at_bol`, and a difference is each run between matched tokens. Past 2000 edits the search gives
up and the rest of the streams is one difference. Every difference is classed
(`pp2_difference_class`), so one past a macro is still seen:

- needs PP.3 when PP.2's side names a macro PP.2 defined there, or one of clang's builtin macros
  (`__LINE__`, `__FILE__`, `_Pragma`, the `__has_*` family), or an `#include` or `#line` was
  left to PP.3's expansion at a place it spans;
- differs otherwise: a difference before every macro use, or whose tokens are no macro's, is
  PP.2's own.

Every `#if` is decided by PP.4's evaluator, PP.2 alone included (its macros then are names worth
0, as `frontend/ARCHITECTURE_PP.md` section 11 states), with the `linux` feature table loaded, so
no difference waits for PP.4. PP.2 alone reads a conditional that tests a macro's value otherwise
than clang, which expands it: such a conditional is undecided (`frontend/ARCHITECTURE_PP.md` section
11), and a difference whose PP.2 side stands in a group it chose (`Pp2Token.undecided`) or whose
span holds the place of its line (`undecided_at`, `Preprocessor.unexpanded`) needs PP.3, and so
does an error marked undecided. A difference wholly before the line - its last PP.2 token among
them, handed out before the line was read - or past its `#endif`, and an error raised there, stay
the preprocessor's own. A unit's class (`pp2_class`) is the latest its differences wait for,
raised to needs PP.3 by a place left to PP.3 with no difference; it differs when one difference
differs, when the preprocessor has an error of its own - one naming PP.3 is not; a lexer diagnostic
met outside a skipped group is one, as clang's compile reports it, though its `-E` passes an
invalid byte through; one in a skipped group is none, as clang reads nothing there, and nor is a
bad byte on a directive's line, which clang does not diagnose, and one in a group an undecided
conditional chose, skipped or read, needs PP.3, as an undecided error does
(`frontend/ARCHITECTURE_PP.md#pp-diags`) -, when the pragma
counts disagree with nothing left to PP.3 to explain them (clang has more: `_Pragma` in an
expansion), or when the streams
are equal and a pragma stands at another place than clang's. Each unit not clean prints its count
of differences of each class, every difference that differs and `--show` of each other class.
A unit that differs fails the run; a unit clang refuses is a reference failure, listed or
unlisted as section 3 counts it, and an unlisted one fails the run too.

## 5. The expansion oracle {#pp3}

`--pp3` compares PP.3 over PP.2 with clang the way section 4 does: `clang -E -P` under the flags of
section 2, the streams aligned by kind, spelling and `at_bol`, the `#pragma` lines against the
ledgers, each difference classed, the reference list of section 3 applied. PP.3 hands out expanded
tokens, so no difference needs PP.3 (`Pp2Result.expanded`): every difference differs, and a unit
is clean or differs. `--pp4` is this oracle under PP.4's name, the evaluator being part of the
stream it compares; `--corpus pp4` is its fixture set. `at_bol` is comparable after expansion: clang's `-E` starts a printed
line where the token's own line starts one, the first token of a replacement takes the macro
name's, and the token after a pragma starts a line in both. Both sides run at `ORACLE_EPOCH`:
clang reads it from `SOURCE_DATE_EPOCH`, PP.3 from `pp_expand_start`, so `__DATE__`, `__TIME__`
and `__TIMESTAMP__` compare exactly.

A corpus list (`--list`, in either mode) names a unit a line, its path then its own flags:
`-I<dir>` goes to clang and before PP.2's include path, `-D<entry>` to clang and after the table's
entries, `-x <lang>` and `-std=<standard>` to clang alone (`split_unit_flags`); `-include <file>`
makes both read a wrapper in the work folder that includes each such file, then the unit by its
full path (`forced_include_unit`), as the preprocessor has no forced include; any other flag makes
the unit a reference failure. The PP.6
corpus lists are of this form. Two kinds of unit cannot compare by re-lexing clang's output, and
are reported, not mapped: a `#` that an empty macro leaves at a line start (clang prints `#
define X` as text, its token dump reads it as a directive), and a name spelled with a UCN, which
clang prints in UTF-8.

## 6. The feature tables {#features}

`--features` regenerates `frontend/predefined/<dialect>_features.defs` for every dialect
(`frontend/ARCHITECTURE_EVAL.md#pp-eval-features`). `feature_candidates` reads the operands each
query is asked of from the pinned SDK's `include/clang/Basic/` (`DAS_CLANG_INCLUDE`, else beside
the clang binary): the builtins of `Builtins.inc`, `BuiltinsX86.inc` and `BuiltinsX86_64.inc` (their
string tables and enumerators), the attribute spellings of `AttrHasAttributeImpl.inc`, bare and
under `gnu::` and `clang::` for `__has_c_attribute`, `Features.def`'s features and extensions, the
warning groups of `DiagnosticGroups.inc` as `-W<group>`, the keywords and traits of
`TokenKinds.def`, and a short list of target names. `generate_features` writes one unit a query,
a line `query(name)` a candidate, runs `clang -E -P` on it under the dialect's dumper flags
(`dumper_frontend_flags`, the flags the converter dumps under) and keeps every answer that is not
the query's default; an answer clang prints as `202003L` is stored as `202003`. A clang run that
fails or answers a line short is an error and nothing is written. A test of
`compare/tests/test_pp_oracle.das` regenerates both tables and fails when a committed one differs,
so a hand edit or a clang bump shows up.

## 7. The expansion record's oracle {#pp5}

`--pp5` holds the frontend's expansion record (`frontend/ARCHITECTURE_EXPAND.md#pp-record`) against
Dumper A's marks of function-like expansions (`converter/ARCHITECTURE_DUMPER_MACROS.md#fn-macros`),
the one other source of those facts: Dumper A finds them by matching spellings against libclang's
preprocessing record, the record knows them from the expansion. A unit is dumped by Dumper A
(`dump_tu`) and read by the expander under the same `linux` table, own headers and the unit's own
`-D` and `-I` flags (any other flag is an error of the unit); a unit Dumper A refuses is counted
apart.

Each site Dumper A marks (`fn_macro`) is keyed by the canonical file and byte offset of its
outermost call's name (`MacroIndex.site_places`), its macro's name, file and line, and each
argument's text; each call of the record by the same, through `outer`, `PpMacro` and
`pp_call_arg_text`. A site with no call of that key is a disagreement. The texts are compared after
`pp5_normalized`, which takes out only what the two spell differently - Dumper A slices the file,
splices (`\` and LF, or `\` and CR LF) and comments included, while the record joins the tokens of
an argument that is no stretch of a file: splices dropped, each comment and run of blanks one blank,
none at either end. Several sites can be one call: an argument the body uses twice holds one
expansion of a call it writes (`SQ(SQ(x))`), which Dumper A marks at each node.

Each argument copy Dumper A marks on a matched site (`macro_args`) must be a copy the record holds:
some token handed out whose chain holds that call and parameter (`pp_each_copy`). The other way,
for each argument of a matched call the record holds a copy of, a token of a file whose chain
names that argument must lie inside the argument's byte span when the argument is one stretch of
that file - a copy outside it (a stray copy) is a disagreement - and an argument Dumper A marks no
copy of is listed as one only the record copies: Dumper A marks a copy only on a whole node, so
such an argument is no disagreement, and is never counted as an agreement either.

Each entry of Dumper A's `macros` must be the record's definition at that file and line with the
same parameters, text (`pp_macro_text`) and uses (`pp_macro_uses`). The C-IR's text puts a blank
only between tokens the source separated, and a line splice is no separator, where Dumper A writes
a blank at each splice; `pp5_macro_text_agrees` takes Dumper A's text as the record's when the only
difference is such blanks, at most one per splice of the definition's lines. A use Dumper A gives
as -1 and the record counts is no disagreement, the record knowing what Dumper A does not follow (a
system header's macro, `MAX`), and is listed apart.

The record may mark more than Dumper A: the line counts the record's calls of the program's
markable macros - defined in and called from the files under the unit's folder, outside directive
lines - and how many of them have the key of some site of Dumper A, and lists the others (`--show`
of them per unit). A unit disagrees when a site, a copy or a macro disagrees; the run exits 1 when
one unit disagrees or one is in error, and when no unit was compared - every one refused by Dumper
A or in error - since such a run has checked nothing (`pp5_exit_code`).

## 8. The token oracle {#pp6}

`--pp6` is the expansion oracle of section 5 over every corpus, with `gcc -E` as a second
reference. `--fast` names the fixtures, the own headers and c-testsuite (`PP6_FAST`); `--full`
adds gcc-torture, every project's units - Lua under its sidecar's defines, PureDOOM's units and
host and chibicc's units under theirs, the Rust checkout's projects (each translation unit and its
bench twin under `clang_args` and both sides' defines) - and every list of `corpus/`: mcpp's
`n.*`, `e.*`, `i.*` and `u.*`, `gcc.dg/cpp` with `c-c++-common/cpp`, tcc's `tests/pp`, sqlite's
amalgamation and shell, the 6.10.3.5 examples, the hide-set tests and ten macro-library units.
csmith has no fixed input, so no csmith unit is in a corpus.

A unit the preprocessor reads as clang does is clean. One it does not is read once more by
`gcc-14 -E -P` under `gcc_flags` of clang's flags: every flag gcc spells the same is kept,
`-std=gnu17` (clang's default C, written out) is added unless a standard is named, and `-target`
with its triple, which gcc has no twin of, is dropped - the native gcc-14 is that target. gcc's
output is token-dumped by clang and aligned with clang's stream as PP's is, its `#pragma` lines
counted against clang's. When clang and gcc disagree, the unit is implementation-defined: the
standard leaves the answer open and the preprocessor following clang there or not is no defect.
When gcc agrees with clang, or refuses the unit, the unit differs. In a corpus list, a unit clang
refuses is no reference failure: the preprocessor must refuse it too (`refusal_class`), else it
differs, unless gcc accepts it, which makes it implementation-defined; one both refuse is counted
apart, as nothing was compared. The suites and projects are `strict`: there a unit must be clean,
and neither list excuses anything.

`implementation_defined.txt` has `reference_failures.txt`'s shape - a path suffix, a tab, the
first difference as clang and gcc give it and the preprocessor's (`pp_answer`) - and fails closed
like it (`count_pp6`): an implementation-defined unit it does not name fails the run, printed with
the line that names it. `known_differences.txt`, of the same shape with a cause, names the
preprocessor's own differences on the corpus lists, its debt: a unit that differs passes only when
named there. A unit either list names that is clean is printed so the line is dropped. The run prints each unit not
clean with the preprocessor's differences, its errors and gcc's answer, a line per corpus (clean,
refused by both, implementation-defined listed and unlisted, known differences, differ, reference
failures, listed units clean) and
the total; it exits 1 when a unit differs or a disagreement or a reference failure is unlisted
(`pp6_exit_code`). gcc runs only on a unit that is not clean, and a `gcc-14` whose
`-dumpfullversion` is not `VERSIONS.md`'s `gcc:` pin answers nothing there, so the unit differs.
Preflight runs `--fast` as its `pp-oracle` gate and `--full` as its `pp-oracle-full` lane.
