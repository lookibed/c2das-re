# frontend Architecture - the C parser

Companion to `ARCHITECTURE.md` in this folder; section numbers are unique across the family. It
describes Dumper C's parser: the C tokens it reads, the tree it builds, and how it decides what it
reads. The parser reads expressions, type names and declarations; it has no entry for a
statement, a record or enum body, or a function definition.

## 14. The C tokens {#c-tokens}

`c_tokens.das` turns the pp-tokens of section 4 into C tokens (C11 5.1.1.2, translation phase 7).
Its input today is a preprocessed unit, the text `clang -E` prints. `c_tokens_open` takes the bytes
and opens the pp-lexer on them; `c_tokens_read` reads every token into `unit.toks`, an array of
small plain structs, and ends it with one EOF token. A token is its kind (`CTok`), its symbol, its
byte range in the lexer's working buffer, and its place: a file id, a line and a column.

Nothing is allocated per token. The token array grows by doubling. A keyword is found by its
symbol: `c_tokens_open` interns every keyword spelling in the lexer's interner once and records
each one's kind in `kind_of_sym`, an array indexed by symbol, so an identifier's kind costs one
index. A symbol the array does not know yet is read once, on its first token: a universal
character name in it that C11 6.4.3p2 forbids (one naming a character below U+00A0 other than
`$`, `@` and a backquote, a surrogate, or a code point past U+10FFFF) is an error,
`invalid universal character name in '<spelling>'`, so no keyword is spelled through a UCN;
otherwise the symbol is recorded as an identifier, the array growing by doubling. The keyword table
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
no file keeps the file. A file name with a string prefix (`L"w.h"`) is an error. The file name is
interned as the bytes between its quotes, so a file a marker names again has its first id; file 0 is the unit's own name. Any other directive (`#pragma`
among them) is an error naming it. The first error ends the read and `unit.err` holds it as
`file:line:col: what`.

The token view reads the pp-lexer itself, not the directive layer of section 5, so it reads the
line markers of a preprocessed unit with its own reader and shares nothing with the directive
layer's `#line` (section 10): it takes the name's bytes as written, escapes included, and no flag.

## 15. The tree {#c-ast}

`c_ast.das` holds the tree: every node of a unit in one array, `CNodeRec`, a small plain struct.
A node refers to its children by index and holds no heap object. Its fields `op`, `a`, `b`, `c`
and `d` have the roles `NODE_FORMS` gives its kind: a child node, a list, a symbol, a token, a
token kind, an integer, or a token range. A list is its first node, the rest chained through
`next`. `tok`, the index of the node's first token, places every node: the token holds the file,
line and column.

`c_dump` writes a tree as one line, `(<name> <fields>)`: a missing node is `-`, a list is `[...]`,
a symbol and a token are their spelling, and an attribute is its bytes as written. The roles drive
the dump, so a new node kind needs only its row in `NODE_FORMS`. With `places`, each name carries
`@line:col`. The tests compare trees through this text. The dump keeps its own stack of steps, a
node or a piece of text each, so a tree of any depth costs no recursion: a flat sum of n terms is a
left chain n nodes deep, though parsing it costs no recursion either (section 18).

## 16. The typedef-name table {#c-typedef-table}

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
type specifier came before it, so in `(long T)` the `T` is no type: it is left for the declarator,
where a type name has no place for it.

## 17. Type names and declarators {#c-type-names}

A type name (C11 6.7.7) is a list of specifiers and qualifiers and an abstract declarator. The
specifiers are the builtin type keywords, the qualifiers (`_Atomic` as a qualifier), `struct`,
`union` and `enum` with a tag and the attributes after the keyword, a typedef name, `typeof` of a
type name or an expression, `_Alignas`, and `__attribute__((...))`. An attribute is kept whole: its
node spans its tokens to the `)` that balances the first `(`, and nothing reads its content yet.

The parser checks the type specifiers of a list as it reads them, by C11 6.7.2p2: each one is a
bit of a set (a second `long` its own bit; a typedef name, a tag and `typeof` one bit for all), and
the set must stay inside one of the largest sets that combine, `SPEC_SETS`: `void`; `char` with
`signed` or `unsigned`; `short`, `int` and either sign; `long`, `long`, `int` and either sign;
`float` with `_Complex`; `long`, `double` and `_Complex`; `_Bool`; a typedef name, a tag or
`typeof` alone. A specifier already in the set, or one that takes the set outside them all, is an
error at its token, `expected a type specifier that combines with those before it` (`(int int)`,
`(short double)`, `(T int)`, `(int struct S)`). `_Complex` alone stays, as GNU C takes it. A list
with no type specifier at all (`(const)`, `(_Alignas(8))`, a parameter `register x`) is refused,
`a specifier list with no type specifier is not parsed`: C99 has no implicit `int`. So no
combination check is left for the type pass.

A declarator is parsed in one of three modes: named, abstract, or either, which a parameter takes.
`*` with its qualifiers and attributes wraps the declarator after it; then a name, or a
parenthesised declarator, then any `[...]` and `(...)` suffixes. In the abstract modes a `(` opens a
nested declarator when the first token past any attributes after it is `*`, `(` or `[`, or, for a
parameter, an identifier no typedef binds; otherwise it opens a parameter list. A `[...]` holds
`static`, qualifiers, a size or `*`. A parameter list holds parameter declarations, whose one
storage class may be `register`, each with the attributes after its declarator, and `...`. In a
named declarator an identifier no typedef binds right after the `(` opens an old-style identifier
list instead (C11 6.7.6.3p3): its names are `ident_param` nodes and the function declarator's flag
is 2.

## 18. Expressions {#c-expressions}

Expressions follow C11 6.5 by recursive descent, but for the binary operators from `*` to `||`:
those ten left-associative levels go by operator precedence over two explicit stacks in the parser
(`operators`, `operands`), so `binary` is a loop. An operator waits on the stack until one that
binds no tighter follows it; then it takes the two operands on top. A binary expression of any
shape and length costs no recursion, and a nested one shares the stacks above the outer one's
base. `?:` and the assignments bind to the right; the comma operator is a binary node of its own
operator. A cast is tried before a unary expression: `(` and a type name make a cast, or a
compound literal when `{` follows the `)`. Where a unary expression stands (the operand of `++`,
`--` and `sizeof`) a `(` and a type name can only open a compound literal, so the `{` is required
there. An argument list takes no trailing comma: `f(a,)` is `expected an expression`.
`sizeof`, `_Alignof` and `__alignof__` take a parenthesised type name, a compound literal or a
unary expression; the alignment nodes keep which keyword was spelled. A compound literal's
initializer list holds positional items, `.member` and `[index]` designators, GNU `[first ...
last]` ranges and nested lists.

The GNU forms are nodes of their own: `a ?: b` is a conditional with no middle operand,
`__extension__` wraps its operand, `__builtin_va_arg(e, T)`, `__builtin_offsetof(T, designators)`
and `__builtin_types_compatible_p(T, U)` keep their type names, and `__func__`, `__FUNCTION__` and
`__PRETTY_FUNCTION__` are one node kind. A node starts at its first token; a binary node at its
left operand's.

## 19. Errors and the nesting bound {#c-parser-errors}

The parser stops at the first error: `failed` is set, `err` holds `file:line:col: what` at the
token where it stopped, and the cursor moves to the EOF token, so every loop ends. Malformed input
reads `expected <what>, got '<token>'` (`got end of input` at the end). A construct the parser does
not take reads `<construct> is not parsed`: a statement expression, a label address `&&label`,
`_Generic`, a struct, union or enum body, `__int128`, `_Atomic(T)`, `_Imaginary`, `__auto_type`,
`__real__`, `__imag__`, `__label__`, and the old GNU designator `member:`. Every loop either
consumes a token or stops.

Recursion is bounded so that deep input ends in a located refusal, never in a stack overflow,
which ends the daslang context. A level is opened by each assignment expression, constant
expression, `?:` arm after the `:`, prefix operator, cast, compound literal where a unary expression
stands, initializer list, type name, parameter list, and a declarator's `*` or parentheses; every
cycle of the parser's calls passes one of them. The 257th level is refused as `nesting deeper than
256 levels`. An expression in 255 parentheses is 256 levels.

The bound comes from the stack. Under the interpreter a level costs the frames between two
openings, measured by the deepest input of each form that fits a 1 MiB stack: 80 bytes for a cast,
an assignment, a `?:` arm or a `*`; 112 for a brace; 160 for a prefix operator; 320 for a parameter
list or a `typeof`; 529 for a call; 593 for a parenthesis or a subscript; and 658, the most, for a
`__builtin_offsetof` designator's index. The declarator forms cost less: 80 bytes for a pointer or a
parenthesised declarator, 112 for a parameter list with a pointer declarator in it, 417 for a
parameter list alone, 353 for a `typeof` in a declaration, 278 for a `sizeof` of an array type in
an array size. 256 levels of the costliest form take about 165 KiB. The
parser therefore runs on a context stack of at least 256 KiB (`options stack = 262144`), which
leaves a third of it for the caller. A context's stack is the `options stack` of the program that
made it, 16 KiB when none is given (daslang's default): a test's context takes its test file's
option; a macro runs at compile time in the macro context of its own module, sized by that
module's option, never by the module being compiled. So the module whose macro or program runs the
parser states the option; on the default 16 KiB 24 parentheses fit.

## 20. Declarations {#c-declarations}

`c_declaration` reads one declaration and its `;` (C11 6.7): any `__extension__`s (the node's
flag is 1 after one), the declaration specifiers, then the init-declarators. `_Static_assert` with
a condition and an optional message is a declaration of its own. A declaration may declare
nothing (`int;`), as clang takes it.

The specifiers of a declaration take storage classes and function specifiers. C11 6.7.1p2 allows
one storage class, and `_Thread_local` (`__thread`) beside `static` or `extern` only; a storage
class that breaks that rule is `expected a storage class that combines with those before it` at its
token. A repeated one stays, as clang takes it with a warning. The type specifiers follow
section 17, and a declaration with no type specifier is refused.

An init-declarator is a named declarator, a GNU asm label `__asm__("name")`, then attributes; the
attributes written before a later declarator of the list join them. Each name is bound in the
innermost scope right after its init-declarator, before its initializer: as a typedef name when the
specifiers hold `typedef`, else as an ordinary identifier. So `int T = T;` reads its own `T`, and in
`int x = sizeof(T), T = 1;` the first `T` is still the type. A typedef takes no initializer. A
typedef name declared again as the same typedef stays a typedef name. `__builtin_va_list` is a
typedef name before the first token, as clang declares it.

A declarator followed by `{` is a function definition, and an old-style identifier list outside one
is invalid C (C11 6.7.6.3p3); `c_declaration` refuses both at their token, so the entry for
definitions owns them. The table's scope functions (`c_scope_open`, `c_scope_close`) are public: a
block, which the statement parser opens, and the tests that stand in for it use them.
