# frontend Architecture - the C parser's statements

Companion to `ARCHITECTURE.md` and `ARCHITECTURE_PARSER.md` in this folder; section numbers are
unique across the family. It describes how Dumper C's parser reads a statement: the function
bodies of `ARCHITECTURE_PARSER.md` section 22 and the statement expressions of its section 18.

## 23. Statements {#c-statements}

`c_statement` reads one statement (C11 6.8). A compound statement opens a scope and a nesting
level and holds declarations and statements in any order. Where a block item stands, it is a
declaration when its first token past any `__extension__`s is a storage class, a function
specifier, `_Static_assert` or a type name's first token (section 16), but an identifier followed by
`:`, which is a label even when it names a typedef, and attributes followed by `;`, which are a
null statement's (`__attribute__((fallthrough));`), unless an `__extension__` before them makes a
declaration of attributes alone, as clang takes it; attributes before anything else start a
declaration. An `__extension__` before an expression is the expression's (section 18). A function
definition in a block, a GNU nested function, is refused at its `{`.

A run of labels, `name:` with the attributes after it, `case` with a constant expression and a GNU
range's `... last`, and `default`, is read in a loop, each label the statement of the one before,
so a long run costs no recursion. As clang takes it, a label among a block's items may stand at the
block's end, its statement missing, or before a declaration; a label that is the body of `if`,
`while`, `for`, `do`, `switch` or a `case` takes a statement only (`if (1) l: int x;` is `expected
an expression`).

`if`, `switch`, `while`, `do` and `for` are each a scope, and each body is a scope and a nesting
level of its own (C11 6.8.4p3, 6.8.5p5), so a declaration in a `for`'s first clause or anywhere
in a body ends with the statement. A `for` declaration takes `auto` or `register` alone as its storage class
(C11 6.8.5p3); any other is `expected 'auto' or 'register' as a for declaration's storage class`. An `else` binds to the nearest `if`; a chain of `else if` is
read in a loop, so a long chain costs no recursion. `goto` takes a label name, `return` an
optional expression. A declaration where a body must stand is no statement: `if (x) int y;` is
`expected an expression`.

The GNU forms: a statement expression `({ ... })` is a primary expression holding a compound
statement, whose declarations end with it. An asm statement takes `volatile` and `inline`, each
once, a template, and up to three sections: outputs and inputs, each operand an optional `[name]`,
its constraint and its expression in parentheses, read as any expression, so an enumerator or a tag
declared in it binds where clang binds it; then clobbers, string literals. The template, the
constraints and the clobbers are unprefixed string literals, as an asm label's are (clang takes no
wide or Unicode one in an asm). The builder takes a compiler barrier as the empty statement and
refuses every other asm, as Dumper A does (`ARCHITECTURE_SUBSET.md` section 83). `::` is two `:` tokens (section 14), as C17 has no `::`.
