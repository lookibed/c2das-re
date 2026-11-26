# frontend Architecture - the C parser

Companion to `ARCHITECTURE.md` in this folder; section numbers are unique across the family. It
describes Dumper C's parser: the C tokens it reads, the tree it builds, and how it decides what it
reads.

## 5. The C tokens {#c-tokens}

`c_tokens.das` turns the pp-tokens of section 4 into C tokens (C11 5.1.1.2, translation phase 7).
Its input today is a preprocessed unit, the text `clang -E` prints. `c_tokens_open` takes the bytes
and opens the pp-lexer on them; `c_tokens_read` reads every token into `unit.toks`, an array of
small plain structs, and ends it with one EOF token. A token is its kind (`CTok`), its symbol, its
byte range in the lexer's working buffer, and its place: a file id, a line and a column.

Nothing is allocated per token. The token array grows by doubling. A keyword is found by its
symbol: `c_tokens_open` interns every keyword spelling in the lexer's interner once and records
each one's kind in `keyword_of`, an array indexed by symbol, so an identifier's kind costs one
index. A symbol interned later is past the array's end and is an identifier. The keyword table
`KEYWORDS` holds every spelling clang takes as a keyword under gnu17: the C99 and C11 keywords and
the GNU alternates (`__const`, `__inline__`, `__restrict`, `__signed__`, `__volatile__`,
`__attribute`, `asm`, `__typeof__`, `__alignof__`...), each alternate with its standard keyword's
kind. It also holds the words the parser refuses by name (`_Generic`, `__int128`, `__real__`...),
so a refusal names the construct instead of a stray identifier. `__builtin_va_arg`,
`__builtin_offsetof` and `__builtin_types_compatible_p` are keywords because they take a type
name. Every other `__builtin_*` name is an identifier and its use is a call.

A pp-number becomes an integer or a floating constant by its bytes, read in place (C11 6.4.4.1,
6.4.4.2): a decimal, octal, hexadecimal or GNU binary integer with `u` and `l`, `ll` (one case)
in either order; a decimal floating constant with a `.` or an exponent; a hexadecimal one with its
`p` exponent, which is required; a floating suffix `f` or `l` in either case. A pp-number that is
neither is an error, `invalid numeric constant '<spelling>'`; so is an imaginary suffix. Its value
is not computed here. A punctuator keeps the kind `PpTok` gives it, so a digraph has the kind of
the punctuator it spells. A character constant and a string literal stay one token each; adjacent
string literals are joined by the parser. `#` and `##` outside a line marker, `::`, a pp-token of kind
OTHER and an unterminated comment are errors.

A `#` that starts a line opens a line marker, `# <line> "<file>" <flags>` as `clang -E` writes it,
or `#line <line> "<file>"`. The lines after it are placed at that line, in that file; a marker with
no file keeps the file. The file name is interned as the bytes between its quotes, so a file a
marker names again has its first id; file 0 is the unit's own name. Any other directive (`#pragma`
among them) is an error naming it. The first error ends the read and `unit.err` holds it as
`file:line:col: what`.
