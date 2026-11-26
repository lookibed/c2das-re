# frontend Architecture - the C parser

Companion to `ARCHITECTURE.md` in this folder; section numbers are unique across the family. It
describes Dumper C's parser: the C tokens it reads, the tree it builds, and how it decides what it
reads. The parser reads expressions and type names; it has no entry for a declaration or a
statement.

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

## 6. The tree {#c-ast}

`c_ast.das` holds the tree: every node of a unit in one array, `CNodeRec`, a small plain struct.
A node refers to its children by index and holds no heap object. Its fields `op`, `a`, `b`, `c`
and `d` have the roles `NODE_FORMS` gives its kind: a child node, a list, a symbol, a token, a
token kind, an integer, or a token range. A list is its first node, the rest chained through
`next`. `tok`, the index of the node's first token, places every node: the token holds the file,
line and column.

`c_dump` writes a tree as one line, `(<name> <fields>)`: a missing node is `-`, a list is `[...]`,
a symbol and a token are their spelling, and an attribute is its bytes as written. The roles drive
the dump, so a new node kind needs only its row in `NODE_FORMS`. With `places`, each name carries
`@line:col`. The tests compare trees through this text.

## 7. The typedef-name table {#c-typedef-table}

An identifier in C is a type name or an ordinary name, and only the declarations in scope say
which. The parser asks `c_is_typedef`, one index into an array that holds every symbol's binding
now (`CBinding`). A scope keeps an undo log: `c_declare` pushes the binding it replaces, and
`c_scope_close` restores the log back to the scope's mark. A lookup costs no search, and a scope's
end costs one step per name it bound. A function prototype's parameter list is a scope: a
parameter's name binds as ordinary in the rest of the list only.

The table decides each ambiguity at the token where it arises. A `(` opens a cast, a compound
literal or a `sizeof`/`_Alignof` type operand when the token after it starts a type name: a type
keyword or qualifier, a tag keyword, `typeof`, `_Alignas`, an attribute, a refused type word, or an
identifier bound as a typedef. In a list of specifiers an identifier is a typedef name only while no
type specifier came before it, so in `(long T)` the `T` is no type.

## 8. Type names and declarators {#c-type-names}

A type name (C11 6.7.7) is a list of specifiers and qualifiers and an abstract declarator. The
specifiers are the builtin type keywords, the qualifiers (`_Atomic` as a qualifier), `struct`,
`union` and `enum` with a tag and the attributes after the keyword, a typedef name, `typeof` of a
type name or an expression, `_Alignas`, and `__attribute__((...))`. An attribute is kept whole: its
node spans its tokens to the `)` that balances the first `(`, and nothing reads its content yet.

A declarator is parsed in one of three modes: named, abstract, or either, which a parameter takes.
`*` with its qualifiers and attributes wraps the declarator after it; then a name, or a
parenthesised declarator, then any `[...]` and `(...)` suffixes. In the abstract modes a `(` opens a
nested declarator when the first token past any attributes after it is `*`, `(` or `[`, or, for a
parameter, an identifier no typedef binds; otherwise it opens a parameter list. A `[...]` holds
`static`, qualifiers, a size or `*`. A parameter list holds parameter declarations, whose
specifiers may hold storage classes, and `...`.

## 9. Expressions {#c-expressions}

Expressions follow C11 6.5 by recursive descent. The binary operators from `*` to `||` go by
precedence climbing over ten levels, each left-associative; `?:` and the assignments bind to the
right; the comma operator is a binary node of its own operator. A cast is tried before a unary
expression: `(` and a type name make a cast, or a compound literal when `{` follows the `)`.
`sizeof`, `_Alignof` and `__alignof__` take a parenthesised type name, a compound literal or a
unary expression; the alignment nodes keep which keyword was spelled. A compound literal's
initializer list holds positional items, `.member` and `[index]` designators, GNU `[first ...
last]` ranges and nested lists.

The GNU forms are nodes of their own: `a ?: b` is a conditional with no middle operand,
`__extension__` wraps its operand, `__builtin_va_arg(e, T)`, `__builtin_offsetof(T, designators)`
and `__builtin_types_compatible_p(T, U)` keep their type names, and `__func__`, `__FUNCTION__` and
`__PRETTY_FUNCTION__` are one node kind. A node starts at its first token; a binary node at its
left operand's.

## 10. Errors and the nesting bound {#c-parser-errors}

The parser stops at the first error: `failed` is set, `err` holds `file:line:col: what` at the
token where it stopped, and the cursor moves to the EOF token, so every loop ends. Malformed input
reads `expected <what>, got '<token>'` (`got end of input` at the end). A construct the parser does
not take reads `<construct> is not parsed`: a statement expression, a label address `&&label`,
`_Generic`, a struct, union or enum body, `__int128`, `_Atomic(T)`, `_Imaginary`, `__auto_type`,
`__real__`, `__imag__`, `__label__`, and the old GNU designator `member:`. Every loop either
consumes a token or stops.

Recursion is bounded: an assignment expression, a `?:` arm after the `:`, a prefix operator, a
cast, an initializer list, a type name, a parameter list and a declarator's `*` or parentheses each
open one level, and the 257th level is refused as `nesting deeper than 256 levels`. An expression
in 255 parentheses is 256 levels. At the bound the interpreter's recursion takes up to about
160 KiB of the context's stack, so a program that parses runs with `options stack = 262144` or more;
without the bound, input nested deep enough ends the context with a stack overflow instead of a
located error.
