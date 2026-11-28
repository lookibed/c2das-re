# frontend Architecture - the `#if` evaluator

Companion to `ARCHITECTURE.md` in this folder; section numbers are unique across the family
(`ARCHITECTURE.md` holds sections 1 to 4, `ARCHITECTURE_PP.md` 5 to 13, 53 and 54,
`ARCHITECTURE_PARSER.md` 14 to 22, `ARCHITECTURE_STATEMENTS.md` 23, `ARCHITECTURE_TYPES.md` 24 to
28, `ARCHITECTURE_EXPAND.md` 29 to 37, `ARCHITECTURE_EXPRS.md` 38 to 45).

## 46. The evaluator {#pp-eval}

`pp_eval.das` evaluates the expression of an `#if` or `#elif` line after PP.3 expanded it
(`ARCHITECTURE_EXPAND.md` section 33), as clang 22's `PPExpressions.cpp` does under the dumper's
flags. It sits below the directive layer: it knows no `Preprocessor`, reads the line as
`PpEvalToken`s (kind, symbol, a byte range of `PpEval.text`) that the hook of
`ARCHITECTURE_PP.md` section 11 copies in, and asks the directive layer through one block for
what only that layer knows - whether a name is defined, whether a query name is still the
builtin, and whether `__has_include`, `__has_include_next` or `__has_embed` find their file.

A value is 64 bits and a signedness (`PpValue`): intmax_t or uintmax_t, both 64 bits on every
dialect here (C11 6.10.1p4). The bits are a `uint64` whatever the signedness, so every addition,
subtraction, multiplication and negation wraps as two's complement with no undefined behaviour in
the evaluator itself; the signedness decides comparison, division, the right shift and the
diagnostics.

`pp_eval_condition` answers a value and `failed`. An error fails the condition: the group is
skipped, as clang skips it, and the diagnostics stand in `PpEval.diags` at the line's token they
name (-1: the directive). Some errors leave the value standing, as in clang: tokens after a whole
expression ("expected end of line in preprocessor expression", so `#if 1)` and `#if 1, 2` take
their group), a plain octal escape out of its type's range, which keeps the escape's low bits, a
`z` suffix (section 49), and an error inside a query's parentheses (section 50). Warnings -
overflow, a negative value converted to unsigned, a multi-character constant - never change the
value.

## 47. The grammar {#pp-eval-grammar}

An operand is an integer or character constant, a name, `defined`, a query, a unary `+`, `-`,
`~` or `!` with its operand, or a parenthesized expression; any other token there is "invalid
token at start of a preprocessor expression", and the end of the line "expected value in
expression" (an `#if` with no expression included, and a `)` where an operand stands). The binary
operators fold by clang's precedence climb, `:` 1, comma 2, `?:` 3, `||` 4, `&&` 5, `|` 6, `^` 7,
`&` 8, equality 9, relational 10, shifts 11, additive 12, multiplicative 13. The line's top level
starts at `?:`, so a comma or a `:` there ends the expression and is the trailing-token error
above; inside parentheses and in the middle operand of `?:` the comma is an operator whose value
is its right operand, and inside parentheses a `:` no `?` took is "':' without preceding '?'".
`?:` is right associative. A token that is no binary operator after an operand is "token is not a valid binary
operator in a preprocessor subexpression", and after a name that is no macro a `(` is "function-like
macro 'X' is not defined".

The right operand of `&&` after a false left one, of `||` after a true one, and the arm of `?:`
not chosen are dead: they are parsed and typed, but a division by zero in them is no error and an
overflow no warning, as clang's `ValueLive`.

## 48. Arithmetic and the conversions {#pp-eval-arith}

Before `* / % + - < > <= >= == != & ^ |` the usual arithmetic conversions run: when either
operand is unsigned both are, a negative signed operand becoming its 2^64 complement with
clang's warning "left side of operator converted from negative value to unsigned: -1 to
18446744073709551615". This is the sign trap of glibc's `bits/wchar.h`: `L'\0' - 1 > 0` is false
because `L'\0'` is a signed `wchar_t` here and nothing in it is unsigned, while `0u - 1 > 0` and
`-1 > 0u` are true. `?:` takes the unsigned type when either arm is unsigned, its condition aside;
the shifts, `&&`, `||` and the comma convert nothing. A comparison, `!`, `&&`, `||` and `defined`
give a signed 0 or 1.

Signed `+`, `-`, `*` and unary `-` wrap and warn "integer overflow in preprocessor expression"
when the true result leaves intmax_t; `INT64_MIN / -1` is that overflow and gives `INT64_MIN`,
`INT64_MIN % -1` gives 0, and `/` or `%` by zero is the error "division by zero in preprocessor
expression" or "remainder by zero in preprocessor expression" - in a dead operand it is 0 of the converted type, so `(0 ? 0/0u : -1) < 0` is false. A shift keeps its left operand's type. `<<` by a count of 64 or more (a negative
count is one, read as unsigned) gives 0 and warns; otherwise it warns when a set bit, or a signed
value's sign, is shifted out. `>>` takes the count's low 32 bits as clang's `getLimitedValue`
cast does; 64 or more shifts by 63 and warns; a signed value shifts arithmetically.

## 49. Constants {#pp-eval-literals}

An integer constant is a pp-number read as clang's `NumericLiteralParser`: decimal, octal after
`0` or `0o` (C2y's prefix, before an octal digit), hex after `0x`, and binary after `0b` before a
0 or 1, which clang takes under gnu17. A `.` or an exponent (`e` in decimal or octal, `p` in hex)
makes it a floating constant, the error "floating point literal in preprocessor expression", or
"exponent has no digits" when no digit follows the exponent and its sign; so does an imaginary
`i` or `j` suffix. The suffix is `u` with one of `l` or `ll` in either case (`lL` not), `z`
(size_t), or `wb` or `WB` (`_BitInt`), the `u` before or after; under the Microsoft extensions
clang turns on for its MSVC targets (`PpEvalTarget.ms_extensions`), `i8`, `i16`, `i32`, `i64` or
`i128` may end it, after a `u` alone. Anything else is "invalid suffix '...' on integer
constant"; an 8 or 9 in an octal constant, a 2 to 9 in a binary one, and a letter `a` to `f`
other than an exponent after any constant but a hex one is "invalid digit '...' in <base>
constant". `wb` is clang's warning "'_BitInt' suffix for literals is a C23 extension"; `z` is its
error "'size_t' suffix for literals is a C++23 feature" with the value standing. `u` makes the
constant unsigned, and so does a value with bit 63 set, a decimal one with clang's warning when
its value is live; a
value past 64 bits is the error "integer literal is too large to be represented in any integer
type" and keeps its low 64 bits. C17 has no digit separator: `1'000` lexes as `1` and an
unterminated character constant.

A character constant is read as clang's `CharLiteralParser`: the simple escapes and GNU's `\e`,
octal of up to three digits, hex of any length, `\u` and `\U`, the delimited `\x{...}`,
`\o{...}` and `\u{...}` clang takes as an extension, an unknown escape being its character with a
warning; a named `\N{...}` is not read and fails the condition (section 52). A hex or delimited
octal escape past its type fails the condition ("hex escape sequence out of range", "octal ..."),
a plain octal one keeps its low bits with that error. A UCN fails it for a surrogate or a value past 0x10FFFF
("invalid universal character"), a control character, or a basic character other than `$`, `@`
and `` ` ``, as C11 6.4.3 and clang refuse them. A plain constant's character is one byte, and a
UTF-8 code point past ASCII or a UCN past 0x7F in it fails the condition ("character too large
for enclosing character literal type"); an `L`, `u` or `U` constant takes the code point, and one
past its type fails too.
More than one character in a plain constant is a multi-character constant: each character's low
byte shifted in, 32 bits kept (`'ab'` is 0x6162), the type `int`; in a wide one it is an error.
The value is then the type's: a plain character is 8 bits, extended by the sign of `char`
(unsigned under the dialects' `-funsigned-char`, so `'\377'` is 255 and `'\0' - 1 > 0` is true),
and its intmax_t is unsigned when `char` is; `L` is `wchar_t`, 32-bit signed under `linux` and
16-bit unsigned under `msvc`; `u` and `U` are unsigned; a multi-character constant is `int`, its
intmax_t unsigned when `char` is, as clang types it. The four facts come from the dialect's
predefined entries when `pp_start` reads them (`pp_eval_target`: `__CHAR_UNSIGNED__`,
`__WCHAR_UNSIGNED__`, `__WCHAR_WIDTH__`, `__INT_WIDTH__`).

## 50. Names, `defined` and the queries {#pp-eval-queries}

A name left after expansion is 0, `true` and `false` among them (C has no such keywords); clang's
`-Wundef` warning is off under the dumper's flags. `defined X` and `defined ( X )` are 1 for a
macro and for a builtin name the expansion answers (`__FILE__`, `__LINE__`, `__COUNTER__`, the
`__has_*` family; `pp_is_defined`), which `#ifdef`, `#ifndef`, `#elifdef` and `#elifndef` ask too,
so `#ifdef __has_include` takes its group as in clang; an `#undef` of a builtin removes it from
both. `__has_cpp_attribute` is C++'s alone: clang under C has no such builtin, so it is a name and
`__has_cpp_attribute(x)` the function-like error.

`__has_include` and `__has_include_next` take `( "name" )` or `( < ... > )`, the angled form left
unexpanded by PP.3 and joined as `#include` joins it, or a macro that expands to either; the
directive layer searches as for `#include` and `#include_next` (`ARCHITECTURE_PP.md` section 8)
and answers 1 when a file is found. `__has_embed` takes the same operand and answers 0 for no
file, 2 for an empty one and 1 for another, clang's `__STDC_EMBED_*` values; its parameters are
not read and fail the condition. Its file is looked up as clang's `LookupEmbedFile` looks it up,
never through the include path: an absolute name as it stands, a `"..."` one also from the
working directory and the includer's directory, and the `--embed-dir` folders, which the dumper
does not pass, so an angled relative name answers 0. An empty name in any of the three is clang's
error "empty filename", at the `)` of `__has_include` and at the name of `__has_embed`, answering
0 with the condition standing.

Every other query - `__has_builtin`, `__has_constexpr_builtin`, `__has_feature`,
`__has_extension`, `__has_attribute`, `__has_c_attribute`, `__has_declspec_attribute`,
`__has_warning`, `__is_identifier`, `__is_target_arch`, `__is_target_vendor`, `__is_target_os`,
`__is_target_environment` - takes one parenthesized name (`__has_c_attribute` also
`scope::name`, `__has_warning` a string literal) and answers what the dialect's table says
(section 51), 0 for a name it does not list and 1 for `__is_identifier`; `__building_module` is
always 0. `__foo__` (four characters or more) is read as `foo` in a feature or attribute name, and
the scopes `__gnu__` and `_Clang` as `gnu` and `clang`, as clang normalizes them; a target query's
name is lower-cased, as clang's triple parser reads it. An error past a feature query's `(` -
no name, a token after it, a comma, nested parentheses - is reported and the query skipped to its
closing `)`, answering for the name read (0 for none); a wrong token in place of an include
query's name or `)` answers 0 and is consumed. Either way the condition stands, as clang's. Clang expands the operand of the attribute queries and `__has_include` only; PP.3
leaves the others' operand as written (`ARCHITECTURE_EXPAND.md` section 33), so
`__is_target_os(linux)` asks for `linux` though the table defines `linux` as 1.

## 51. The feature tables {#pp-eval-features}

`predefined/<dialect>_features.defs` holds each query's answers under that dialect, as the
pinned clang gives them: a line `<query> <operand> <value>`, every answer that is not the query's
default (0; 1 for `__is_identifier`). The operands are clang's own lists - the builtin tables with
the `__builtin_*`, `__is_*` and `__has_*` keywords and the `__is_target_*` names `__has_builtin`
also answers, the attribute spellings (bare and under `gnu::` and `clang::`), the feature list,
the warning groups, the keywords, and the triple parser's names and aliases for the target
queries, of the SDK's `include/clang/Basic/` - each asked of clang under the dialect's
dumper flags (`compare/pp/ARCHITECTURE.md#features`). A predefined-macro entry cannot carry them:
a warning group and a scoped attribute are no identifier, so `parse_define` reads no such line,
and the table has its own reader, `parse_features`. `read_features` loads a table; the caller
puts it in `pp.eval.features` after starting a unit, as it chose the dialect's macros. Dumper A takes
its answers from clang itself, so the tables are regenerated with the same pinned clang, which the
regenerate-and-diff test of `compare/tests/test_pp_oracle.das` enforces.

## 52. Known differences from clang

The queries are evaluated in `#if` and `#elif` lines only: in the text of a unit PP.3 hands
`__has_builtin(x)` out as tokens, where clang expands it to its answer. `__is_target_variant_os`
and `__is_target_variant_environment` answer 0, as for a target with no variant. A diagnostic
with no token of its own (the line ended) stands at the line's last token; clang places it just
past that token. A named escape `\N{...}` fails the condition; clang resolves its name and takes it
in an `L`, `u` or `U` constant when the code point fits (`U'\N{GREEK SMALL LETTER ALPHA}'`). A
target query's name clang's triple parser reads by its prefix (`__is_target_os(linuxfoo)`) answers
0 unless the table lists it. `__has_warning` takes a name of any length and a single string
literal; clang warns for a name shorter than three characters and joins adjacent literals.
