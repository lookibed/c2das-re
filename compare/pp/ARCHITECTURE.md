# compare/pp Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
holds the token oracles of Dumper C's preprocessor: of the pp-token lexer, `frontend/pp_lexer.das`
(`frontend/ARCHITECTURE.md` section 4), and of the directive layer, `frontend/pp_directives.das`
(`frontend/ARCHITECTURE_PP.md`): one unit through clang and through the frontend, the two token
streams compared token by token. It starts clang, so it lives outside `frontend/`, whose
code starts no process (`frontend/ARCHITECTURE.md` section 2). The full preprocessor oracle of
the plan's PP.6 grows from it.

## 1. File charters

- `pp_oracle.das` - the module: a unit preprocessed by clang (`compare_unit`), clang's token dump
  read (`clang_tokens`, `clang_kind`), the lexer's tokens (`lexed_tokens`), the comparison
  (`compare_tokens`), the corpora (`corpus_units`), the list of reference failures
  (`reference_failures`, `reference_failure`, section 3), a set's run (`run_set`) and the command
  line's run (`OracleArgs`, `run_oracle`); and the directive oracle of section 4
  (`compare_unit_pp2`, `pp2_tokens`, `pragma_lines`, `pp2_class`, `run_set_pp2`, `run_pp2`). The clang it runs
  and its flags are Dumper A's (`default_clang`, `dumper_frontend_flags`, `DUMPER_FLAGS` of
  `converter/dumper_a.das`): the oracle preprocesses as the converter does.
- `run.das` - the command line's entry, its arguments parsed into `run_oracle`; from the repository
  root with `das`: `--corpus frontend` (every
  header of `frontend/include/`), `--corpus c-testsuite` (the fetched single-exec suite), `--corpus gcc-torture` (the fetched
  `execute` folder's own units), `--corpus pp2` (the directive fixtures), units
  named after the flags, `--raw`, `--pp2` (section 4), `--show N`, `--work <folder>` (default `compare/work/pp`, under
  the gitignored `compare/work/`). It prints each unit that differs with its first differences, a
  line per set and the total; exit 0 when no unit differs.
- `fixtures/edge_tokens.c` - the edge cases of `frontend/pp_lexer.das` as one unit with no
  directive: pp-numbers, UCNs, prefixes, every punctuator and digraph, `::`, raw strings, OTHER
  characters, splices, comments. `fixtures/bom_tokens.c` - a byte order mark and leading blanks,
  compared raw.
- `fixtures/pp2/` - the directive oracle's units (`*.c`) and the headers they include: include
  guards in both spellings, a file that is no guard, `#pragma once`, `#line` and a line marker,
  nested conditionals with directives in skipped groups, pragmas and the null directive. None uses
  a macro.
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
is dropped. None of the three counts is a difference: the exit code follows the differences alone.

## 4. The directive oracle {#pp2}

`--pp2` compares `frontend/pp_directives.das` with clang: a unit is preprocessed by `clang -E -P`
under the flags of section 2 and its output token-dumped as there, and PP.2 reads the unit itself
through the `fio` provider with the same macros and include path (`pp2_setup`: the `linux`
table's entries, the own headers' folder, canonical). `-P` output has lines and columns of its
own, so a token is compared by its kind, its spelling and `at_bol` only. Clang prints each pragma
it keeps as a `#pragma` line of its output, which its token dump takes as a pragma, not tokens;
PP.2 keeps a pragma in its ledgers, not its stream. So the oracle counts the `#pragma` lines of
the `-E` output (`pragma_lines`) against PP.2's pragma and pack entries.

PP.2 expands no macro and evaluates only the simplest `#if`, so a unit is classed (`pp2_class`):
clean when the streams, the pragma counts and PP.2's errors all agree; needs PP.3 when the first
difference comes at or after PP.2's first token naming a defined macro, or an `#include` or
`#line` is left to PP.3's expansion; needs PP.4 when it comes at or after the first `#if` left to
PP.4; and differs otherwise - a difference before either, a pragma count apart, or an error of
PP.2's own. Only a unit that differs fails the run; a unit clang refuses is a reference failure, listed or
unlisted as section 3 counts it, in this mode too.
