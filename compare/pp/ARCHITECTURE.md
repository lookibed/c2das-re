# compare/pp Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
holds the token oracles of Dumper C's preprocessor: of the pp-token lexer, `frontend/pp_lexer.das`
(`frontend/ARCHITECTURE.md` section 4), and of the directive layer, `frontend/pp_directives.das`
(`frontend/ARCHITECTURE_PP.md`), and of the macro expansion, `frontend/pp_expand.das`
(`frontend/ARCHITECTURE_EXPAND.md`), with the `#if` evaluator, `frontend/pp_eval.das`
(`frontend/ARCHITECTURE_EVAL.md`): one unit through clang and through the frontend, the two
token streams compared token by token. It starts clang, so it lives outside `frontend/`, whose
code starts no process (`frontend/ARCHITECTURE.md` section 2). The full preprocessor oracle of
the plan's PP.6 grows from it.

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
- `pp_features.das` - the feature-query tables of `frontend/predefined/` generated from the pinned
  clang (section 6): the operands read from clang's headers (`feature_candidates`), each asked of
  clang (`generate_features`), under the dialect's dumper flags (`dialect_flags`). The clang it runs
  and its flags are Dumper A's (`default_clang`, `dumper_frontend_flags`, `DUMPER_FLAGS` of
  `converter/dumper_a.das`): the oracle preprocesses as the converter does.
- `run.das` - the command line's entry, its arguments parsed into `run_oracle`; from the repository
  root with `das`: `--corpus frontend` (every
  header of `frontend/include/`), `--corpus c-testsuite` (the fetched single-exec suite), `--corpus gcc-torture` (the fetched
  `execute` folder's own units), `--corpus pp2` and `--corpus pp3` (the directive and expansion
  fixtures), `--list <file>` (a corpus list, section 5), units named after the flags, `--raw`,
  `--pp2` (section 4), `--pp3` and `--pp4` (section 5), `--corpus pp4`, `--features` (section 6),
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
- `reference_failures.txt` - the units the reference cannot preprocess, each with its reason
  (section 3).
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
(`pragma_places`), an entry's the tokens PP.2 handed out before it (`emitted`).

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
no difference waits for PP.4. PP.2 alone reads an `#if` or `#line` that names a macro otherwise than
clang, which expands it: past the first such line (`Preprocessor.unexpanded`, `pp3_from`) every
difference ending there and every error met there needs PP.3, so a unit whose condition tests a
macro's value is classed as waiting for PP.3, not as PP.2's own defect. A unit's class (`pp2_class`) is the latest its differences wait for,
raised to needs PP.3 by a place left to PP.3 with no difference; it differs when one difference
differs, when the preprocessor has an error of its own - one naming PP.3 is not -, when the pragma
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
entries, `-x <lang>` to clang alone; any other flag makes the unit a reference failure. The PP.6
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
