# frontend Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`.

**Never weaken `REVIEW.das` - fix what it flags instead.**

**A diff that makes a `.das` file under this folder require a module that has no `<name>.das`
beside that file, other than a daslib module and `crt`, reads that module's source: a module that
requires `cbind`, or names `popen`, `popen_binary`, `popen_timeout`, `popen_argv`,
`popen_argv_pipe`, `spawn_process`, `spawn_argv`, `with_process`, `run_and_capture`,
`executable_on_path` or `system`, is never required here - do the work in das
instead.** `REVIEW.das` follows only a `require` that names a file.

**A diff that adds a file under this folder adds a `.das`, a `.h` or a `.md` file, or a `.defs`
table under `predefined/`, and writes
every module dependency as a line `require <module>` or `require <module> public` - never an
`include`, and never a `require` of another form.** `REVIEW.das` reads no other file and can name
the module of no other line, so it reports both.

**A diff to `pp_lexer.das` never makes a token allocate - `tests/test_pp_lexer.das`'s allocation
test is never loosened - and runs the oracle (`das compare/pp/run.das -- --corpus frontend --corpus
c-testsuite`, and `--raw compare/pp/fixtures/edge_tokens.c compare/pp/fixtures/bom_tokens.c`) with its difference
count stated.**
A rule change that still passes the unit tests can split or merge a token clang lexes otherwise.

**A diff to `pp_directives.das` runs the directive oracle (`das compare/pp/run.das -- --pp2
--corpus pp2 --corpus frontend`) and states its class counts, and adds a case to
`tests/test_pp_directives.das` for each directive behaviour it changes.** Clang's `-E` output is
the reference for what a directive leaves in the stream; the unit tests hold the diagnostics and
ledgers no token stream shows.

**A diff to `pp_directives.das` never drops a `#pragma` without a ledger entry or a diagnostic,
and never expands a macro outside the hooks PP.3 and PP.4 fill (`ARCHITECTURE_PP.md` sections 8
and 11).** A pragma lost there never reaches the C-IR's ledger, and an expansion here would be a
second expander beside PP.3's.

**A diff to `c_tokens.das` or `c_parser.das` never makes a token or a node allocate on its own -
the allocation tests of `tests/test_c_tokens.das` and `tests/test_c_parse_expr.das` are never
loosened.**

**A diff that makes `c_tokens.das` or `c_parser.das` reject an input ends it with one error at a
token's place, `file:line:col: ...`: a construct it does not take as `<construct> is not parsed`,
malformed input as `expected <what>, got <token>` - never a tree built past the error, a guess, or
a panic. Each new error message has a test with its exact text and place.**

**A diff that adds a loop to `c_parser.das` makes each turn consume a token or end at the first
error; one that adds a recursion a run of tokens can repeat makes it open a nesting level
(`enter`), so the bound of `ARCHITECTURE_PARSER.md` section 19 holds; one that adds frames between
two levels re-measures that section's bytes per level and keeps `tests/test_c_parse_expr.das`'s
costliest form at the bound.** Malformed input must end, and deep input must end in a refusal, not
a stack overflow.
