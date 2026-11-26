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
  (`compare_tokens`), the corpora (`corpus_units`) and a set's run (`run_set`). The clang it runs
  and its flags are Dumper A's (`default_clang`, `dumper_frontend_flags`, `DUMPER_FLAGS` of
  `converter/dumper_a.das`): the oracle preprocesses as the converter does.
- `run.das` - the command line, from the repository root with `das`: `--corpus frontend` (every
  header of `frontend/include/`), `--corpus c-testsuite` (the fetched single-exec suite), units
  named after the flags, `--raw`, `--show N`, `--work <folder>` (default `compare/work/pp`, under
  the gitignored `compare/work/`). It prints each unit that differs with its first differences, a
  line per set and the total; exit 0 when no unit differs.
- `fixtures/edge_tokens.c` - the edge cases of `frontend/pp_lexer.das` as one unit with no
  directive: pp-numbers, UCNs, prefixes, digraphs, OTHER characters, splices, comments.
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
`[StartOfLine]` past the file's first byte: clang sets `[LeadingSpace]` only when the byte before
the token is no newline, while the lexer's `has_space`, as C's whitespace, counts the newline too.
A difference is a position where any of these differ, plus each token one side has past the
other's end. A unit clang refuses (a header the own set lacks) is a clang failure, counted apart
and never a difference.
