# frontend Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`.

**Never weaken `REVIEW.das` - fix what it flags instead.**

**A diff that makes a `.das` file under this folder require a module that has no `<name>.das`
beside that file, other than a daslib module, reads that module's source: a module that
requires `cbind`, or names `popen`, `popen_binary`, `popen_timeout`, `popen_argv`,
`popen_argv_pipe`, `spawn_process`, `spawn_argv`, `with_process`, `run_and_capture`,
`executable_on_path` or `system`, is never required here - do the work in das
instead.** `REVIEW.das` follows only a `require` that names a file.

**A diff to a `.das` file under this folder, outside the own headers' tests (`include/tests/`),
never requires a native module - `crt`, `c_runtime` or one of its modules - directly or through
what it requires; the frontend needs none, and a floating constant or anything else the C library
would compute is computed in das.** Dumper C runs inside a daslang compile and in a web page,
where no native module loads; `REVIEW.das` reports such a `require`. The exception, `include/tests/`, is the header set's test code, which compiles converted programs against the C runtime, not Dumper C.

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

**A diff to `pp_directives.das` that reads a token from the lexer passes it through `consumed` -
`fetch` and `next_on_line` do - when the directive layer takes it (`ARCHITECTURE_PP.md#pp-diags`).**
A token taken past it leaves its lexer diagnostics unmarked, so a bad byte in `#if 0` refuses a
valid unit, and a poisoned name in it unreported.

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

**A diff to `pp_expand.das` keeps rescanning on the context model (`ARCHITECTURE_EXPAND.md`
section 30): a macro is disabled by the context of its replacement and a name read then is
painted - never a set of macros carried on each token (a Prosser hide set).** Per-token hide
sets differ from clang and gcc on deferred recursion and grow without bound on Boost.PP.

**A diff to `pp_expand.das` runs the expansion oracle (`das compare/pp/run.das -- --pp3 --corpus
pp3`, and the corpus lists it touches) and states its class counts, and adds a case to
`tests/test_pp_expand.das` for each expansion rule it changes.** The fixtures hold clang's
answer; the unit tests hold the diagnostics and the call record no token stream shows.

**A diff to `pp_expand.das` never allocates per token read or pasted, nor per call: tokens go in
reused buffers, spellings - a builtin's value and a `_Pragma` operand among them - in the pools,
and the call record grows geometrically; `tests/test_pp_expand.das`'s allocation tests are never
loosened.** A string or an array made per token grows the das heap
with the size of the expansion, which a macro library makes millions of tokens long.

**A diff to `pp_eval.das` keeps every value 64 bits and a signedness, folded by C11 6.10.1p4's
rule - an unsigned operand makes the operation unsigned - and computes on the `uint64` bits, never
on a narrower type or a signed das operation that can overflow; it adds a case pinned against
clang to `tests/test_pp_eval.das` for each rule it changes, and runs `das compare/pp/run.das --
--pp4 --corpus pp4 --corpus pp3 --corpus frontend` with its class counts stated.** The sign of a
converted operand is the trap every hand-written evaluator falls into (`L'\0' - 1 > 0`), and a das
`int64` overflow or `INT64_MIN / -1` is undefined behaviour in the evaluator itself.

**`predefined/*_features.defs` is generated from the pinned clang, never edited by hand: a change
to it is the output of `das compare/pp/run.das -- --features` (`ARCHITECTURE_EVAL.md#pp-eval-features`).**
A hand-written answer is a guess about clang that no oracle can see, since the query's answer
changes which group a unit reads.

**A diff to `pp_record.das` or to the record in `pp_expand.das` keeps every reader allocation-free
for a token, a call and an argument - a text goes into the caller's buffer, a place or a copy is
read in place, and a view in place is given only of bytes that live for the whole unit - and never
loosens `tests/test_pp_expand.das`'s `test_record_readers_allocate_nothing`; the diff's author
runs the record's oracle (`das compare/pp/run.das -- --pp5 --corpus fixtures --list
compare/pp/fixtures/pp5/lua.txt`) and states the counts in the pull request.** Dumper C reads
the record once per token of a unit while the unit is still read, so a view into a pool that grows
dangles; and Dumper A's marks are the only outside check of what the record says.

**A macro fact Dumper C writes into the C-IR - a site, an argument's text, a copy, a `macros`
entry - is read from the expansion record (`ARCHITECTURE_EXPAND.md#pp-record`), never derived
again by matching spellings or re-reading a `#define`.** A second derivation would be a second
answer to the question the record already answers exactly, the way Dumper A has to match.

