# compare/pp Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
holds the token oracle of Dumper C's pp-token lexer, `frontend/pp_lexer.das`
(`frontend/ARCHITECTURE.md` section 4): one unit through clang and through the lexer, the two
token streams compared token by token. It starts clang, so it lives outside `frontend/`, whose
code starts no process (`frontend/ARCHITECTURE.md` section 2). The full preprocessor oracle of
the plan's PP.6 grows from it.

## 1. File charters

- `pp_oracle.das` - the module: a unit preprocessed by clang (`compare_unit`), clang's token dump
  read (`clang_tokens`, `clang_kind`), the lexer's tokens (`lexed_tokens`), the comparison
  (`compare_tokens`), the corpora (`corpus_units`), a set's run (`run_set`) and the command line's
  run (`OracleArgs`, `run_oracle`). The clang it runs
  and its flags are Dumper A's (`default_clang`, `dumper_frontend_flags`, `DUMPER_FLAGS` of
  `converter/dumper_a.das`): the oracle preprocesses as the converter does.
- `run.das` - the command line's entry, its arguments parsed into `run_oracle`; from the repository
  root with `das`: `--corpus frontend` (every
  header of `frontend/include/`), `--corpus c-testsuite` (the fetched single-exec suite), units
  named after the flags, `--raw`, `--show N`, `--work <folder>` (default `compare/work/pp`, under
  the gitignored `compare/work/`). It prints each unit that differs with its first differences, a
  line per set and the total; exit 0 when no unit differs.
- `fixtures/edge_tokens.c` - the edge cases of `frontend/pp_lexer.das` as one unit with no
  directive: pp-numbers, UCNs, prefixes, every punctuator and digraph, `::`, raw strings, OTHER
  characters, splices, comments. `fixtures/bom_tokens.c` - a byte order mark and leading blanks,
  compared raw.
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
