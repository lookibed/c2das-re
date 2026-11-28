# frontend Architecture - the C parser

Companion to `ARCHITECTURE.md` in this folder; section numbers are unique across the family. It
describes Dumper C's parser: the C tokens it reads, the tree it builds, and how it decides what it
reads. The parser reads expressions, type names, declarations with their record and enum bodies,
function definitions and whole units; its statements are `ARCHITECTURE_STATEMENTS.md`.

## 14. The C tokens {#c-tokens}

`c_tokens.das` turns the tokens the preprocessor hands out into C tokens (C11 5.1.1.2, translation
phase 7). The unit holds a `Preprocessor` (`ARCHITECTURE_PP.md`) read with `pp_next_token`: over a
preprocessed unit, the text `clang -E` prints (`c_tokens_open`: `pp_start` over one file in memory),
or over C source with macro expansion (`c_tokens_expand_open`: `pp_expand_start` over a file
provider). `c_tokens_read` reads every token into `unit.toks`, small plain structs, then one EOF.
A token is its kind (`CTok`), its symbol, where its spelling lies, and its presumed place: a file name id
(an index of the preprocessor's `names`: 0 the unit's own name, 1 the predefined macros' buffer,
then each name a file, `#line` or a line marker gives), a line and a column. A token of the source
stands at its own place; a token an expansion makes, a macro body's or an argument's, stands at the
outermost macro name of its call, line and column, as clang's expansion location does, and is
marked `expanded`. The end of a unit whose last token an expansion made stands after the call's
`)`, the main file's lexer's last token.

The spelling is kept where the preprocessor keeps it (`PpSpelled`): a file's working buffer, the
macro body pool or a symbol, all valid for the unit's life, read through `pp_span_of`. A pasted or
stringified token's spelling lies in the expansion's pool, which the next `pp_next_token` may
clear, so it is copied into the unit's own `pool` as it is read. `c_span` gives a token's bytes,
`c_spelling` a string of them, and `c_range_text` the text of a run of tokens: the bytes between
its ends as written when the tokens cover them - each read from one file, none an expansion's, with
nothing but blanks between, so no directive, skipped group, comment or dropped argument - else the
spellings with a blank between each two.

Nothing is allocated per token. The token array and the pool grow by doubling; what a directive
costs (a line marker's name, say) is the preprocessor's. Each open starts a new preprocessor and
hands it the interner of the last one, so a name keeps its symbol from unit to unit. A keyword is
found by its symbol: each open interns every keyword spelling in the interner once and records
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
string literals are joined by the parser. A `::`, which the pp-lexer reads as one token, is two
`:` tokens, as clang reads it in C17, the second a column on (at the macro name for an expansion's);
`unit.splits` records each, so `c_token_index` maps a pragma's `emitted` count to a token. A `#`, a
`##` and a pp-token of kind OTHER are errors.

Directives are the preprocessor's: a line marker, `#line`, `#pragma` and every other directive
are done there, and a `#` or `##` the preprocessor hands out is a stray token. A pragma the
preprocessor records (`pp.pragmas`, `pp.packs`) is refused at its place, `the pragma '#pragma
<text>' is not parsed`, unless the C-IR may pass it by (`PASSED_PRAGMAS`): a `GCC diagnostic`,
`clang diagnostic`, `message` or `GCC warning` pragma and `#ident` change no C-IR. `pack` is refused
until the record layout reads `pp.packs`; `#pragma GCC error "<text>"` is the error it asks for.

The first error ends the read, `file:line:col: what` in `unit.err`: a token's, a pragma's, the
preprocessor's (`pp.diags`, a warning being none) or the lexer's (`pp.lx.diags`, placed in its own
file by that file's `#line` state, else its path). Of those one read meets the first in reading
order wins: in one file the earlier place, an unterminated call or conditional (placed at its start)
counted at the file's end; across files the one recorded first.

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
`union` and `enum` with a tag, a body and their attributes (section 21), a typedef name, `typeof` of a
type name or an expression, `_Alignas`, and `__attribute__((...))`. An attribute is kept whole: its
node spans its tokens to the `)` that balances the first `(`, and nothing reads its content yet.

The parser checks the type specifiers of a list as it reads them, by C11 6.7.2p2: each one is a
bit of a set (a second `long` its own bit; a typedef name, a tag and `typeof` one bit for all), and
the set must stay inside one of the largest sets that combine, `SPEC_SETS`: `void`; `char` with
`signed` or `unsigned`; `short`, `int` and either sign; `long`, `long`, `int` and either sign;
each integer set with GNU's `_Complex` too; `float` with `_Complex`; `long`, `double` and
`_Complex`; `_Bool`; a typedef name, a tag or
`typeof` alone. A specifier already in the set, or one that takes the set outside them all, is an
error at its token, `expected a type specifier that combines with those before it` (`(int int)`,
`(short double)`, `(T int)`, `(int struct S)`, `(_Complex _Bool)`). `_Complex` alone stays, as
clang takes it for `_Complex double`. A list
with no type specifier at all (`(const)`, `(_Alignas(8))`, a parameter `register x`) is refused,
`a specifier list with no type specifier is not parsed`: C99 has no implicit `int`. So no
combination check is left for the type pass.

A declarator is parsed in one of three modes: named, abstract, or either, which a parameter takes.
`*` with its qualifiers and attributes wraps the declarator after it; then a name, or a
parenthesised declarator, then any `[...]` and `(...)` suffixes. In the abstract modes a `(` opens a
nested declarator when the first token past any attributes after it is `*`, `(` or `[`, or, for a
parameter, an identifier no typedef binds; otherwise it opens a parameter list. A `[...]` holds
`static` once, qualifiers, a size or `*`; `static` needs a size. As clang takes them (C11 6.7.6.2p1,
6.7.6.3p7), a qualifier or `static` stands only in a parameter's outermost array, `[*]` only in a
parameter's array at any level, and each array declarator keeps its `[` (the node's `d`) to place
the refusal of either elsewhere. A parameter list holds parameter declarations, whose one storage
class may be `register`, each with the attributes after its declarator, and `...` after one of
them: C23 takes `...` alone, gnu17 does not. In a
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
not take reads `<construct> is not parsed`: a label address `&&label`, a computed goto `goto *`,
`asm goto`, a nested function definition,
`_Generic`, `__int128`, `_Atomic(T)`, `_Imaginary`, `__auto_type`,
`__real__`, `__imag__`, `__label__`, and the old GNU designator `member:`. Every loop either
consumes a token or stops.

Recursion is bounded so that deep input ends in a located refusal, never in a stack overflow,
which ends the daslang context. A level is opened by each assignment expression, constant
expression, `?:` arm after the `:`, prefix operator, cast, compound literal where a unary expression
stands, initializer list, type name, parameter list, record or enum body, compound statement,
the statement of a selection or iteration statement, and a declarator's `*` or parentheses; every
cycle of the parser's calls passes one of them. The 257th level is refused as `nesting deeper than
256 levels`. An expression in 255 parentheses is 256 levels.

The bound comes from the stack. Under the interpreter a level costs the frames between two
openings, measured by the deepest input of each form that fits a 1 MiB stack: 80 bytes for a cast,
an assignment, a `?:` arm or a `*`; 112 for a brace; 160 for a prefix operator; 320 for a parameter
list or a `typeof`; 529 for a call; 593 for a parenthesis or a subscript; and 658, the most, for a
`__builtin_offsetof` designator's index. The declarator forms cost less: 80 bytes for a pointer or a
parenthesised declarator, 112 for a parameter list with a pointer declarator in it, 417 for a
parameter list alone, 353 for a `typeof` in a declaration, 278 for a `sizeof` of an array type in
an array size. The record forms: 561 bytes for a record body in a member of a record body, and 449
for a record body in a parameter list of a member's function declarator, whose cycle holds two
levels open, the body and the parameter list. The statement forms: 224 bytes for a block in a block
(a label before it costs nothing), 337 for an `if` statement's body, 305 for a `while`'s, 320 for a
`for`'s, and 409 for a statement expression in a statement expression, whose cycle holds two
levels open, the block and the assignment expression. 256 levels of the costliest form take about 165 KiB. The
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

An init-declarator is a named declarator, a GNU asm label `__asm__("name")` of unprefixed string
literals (clang takes no wide or Unicode one there), then attributes; the
attributes written before a later declarator of the list join them. Each name is bound in the
innermost scope right after its init-declarator, before its initializer: as a typedef name when the
specifiers hold `typedef`, else as an ordinary identifier. So `int T = T;` reads its own `T`, and in
`int x = sizeof(T), T = 1;` the first `T` is still the type. A typedef takes no initializer. A
typedef name declared again as the same typedef stays a typedef name. Before the first token the
table holds the typedef names clang declares in every C unit of the dialect's triples:
`__builtin_va_list`, `__builtin_ms_va_list`, `__NSConstantString`, `__int128_t` and
`__uint128_t`, and under msvc `size_t` (the `msvc` of `c_parser_open_text` and
`c_parser_open_source`). The two 128-bit names name a refused type, so a use of either is refused there, `the __int128 type is not parsed`.

`c_declaration` reads a declaration in a block. A function definition has no place there, so its
`{` is `expected ';'`; an old-style identifier list outside a definition is invalid C (C11
6.7.6.3p3) and refused at its first name. The table's scope functions (`c_scope_open`,
`c_scope_close`) are public: a block, which the statement parser opens, and the tests that stand
in for it use them.

## 21. Records and enums {#c-records}

A `struct`, `union` or `enum` specifier is the keyword, attributes, a tag, then a body in braces
and the attributes after it; it has a tag or a body at least, and its node keeps whether it has a
body, so `struct S {}`, which clang takes, differs from `struct S`. Attributes between the tag and
the `{` are an error, as in clang. A body opens a nesting level (section 19).

A record body holds member declarations: `__extension__`s, specifiers and qualifiers with no
storage class, then member declarators, each a declarator, a bit-field width or both, with the
attributes written before a later one and after each. A member declaration with no declarator is
an anonymous member, `struct { int a; };` or the `int;` clang warns on alike; a member declaration
of attributes alone, `__attribute__((packed));`, is one too, as clang takes it. A member declarator
holds no old-style identifier list. A `;` alone and
`_Static_assert` stand among the members. A flexible array member is an array declarator with no
size, and a member's array takes no qualifier, `static` or `[*]` (section 17); the parser checks no rule on members beyond the grammar (C11 6.7.2.1: a flexible array
last, a width's value, a bit-field's type), which the checker owns.

An enum body holds enumerators: a name, its attributes, then an optional `=` and constant
expression; a trailing comma stays, an empty body is an error. An enumerator is an ordinary
identifier from the end of its own definition on (C11 6.2.1p7), so it shadows a typedef name, and
in `enum { T = sizeof(T) }` the operand still names the type.

Neither a tag nor a member enters the typedef table: tags and members have name spaces of their
own, which no ambiguity of the grammar reads. So a tag spelled like a typedef name leaves it a
type, and a member may share a typedef's name. A record body opens no scope, so an enumerator
declared in a member's enum binds in the scope around the record, and one declared in a parameter
list ends with the prototype's scope. Which declaration a tag names is the checker's question.

## 22. Function definitions and the unit {#c-definitions}

`c_unit` reads a unit to its end as a list of external declarations (C11 6.9). At file scope a
`;` alone, after `__extension__`s too, declares nothing and makes no node; a declaration of
attributes alone (`__attribute__((unused));`) is a declaration with no declarator, as clang takes
it; a file-scope asm is refused, `a file-scope asm is not parsed`, as Dumper A fails it closed.

The first declarator of a file-scope declaration starts a function definition when it declares a
function through its own function declarator, that declarator holds the only identifier list,
there is no asm label and no `typedef`, and a `{` follows, or, after an identifier list, anything
but `;`, `,` or `=`. Otherwise its `{` is `expected ';'`, as for `int a, f(void) {}`, a pointer
to a function, or an asm label, which clang rejects on a definition. Attributes after the
declarator stay, as clang takes them. A definition's own parameters take no `[*]` at any level, as
clang requires a bound there; a prototype inside one may.

The function's name is bound as an ordinary identifier around the definition. Then a scope opens
for the parameters. After an identifier list, the old-style declaration list follows: each
declaration takes `register` alone as its storage class, no initializer and no asm label, an array
in it a qualifier or `static` as a parameter's but no `[*]`; it declares at least one name
(`expected a declaration of a parameter`, a tag or enum body alone included), and names of
the identifier list, each once (`expected a name of the identifier list`, `expected a parameter
declared once`); a typedef name in it is a type as anywhere. A name the list leaves untyped is an
error at the body's `{`, since clang under gnu17 refuses the implicit `int`. Each identifier
names its declarator (the `ident_param` node's `b`).

A prototype's scope is kept as it closes: the function declarator's node holds the run of
bindings the scope made (`c` and `d` into `prototype_bindings`), the parameters and every
enumerator a parameter's type declared. `c_parameters_declare` makes them again in the innermost
scope, so a body reads `typedef char T; int f(enum { T = 1 } x) { return sizeof(T); }` with `T` the
enumerator, as clang does. An identifier list opens no prototype scope: its names are bound by the declaration
list, in the definition's scope.

The body is a compound statement (`ARCHITECTURE_STATEMENTS.md` section 23) read in the scope the
definition opens, which `c_parameters_declare` fills with the definition's own prototype scope: a
parameter or an enumerator of a parameter's type shadows a typedef name in the body, and the name
is a type again after it.
