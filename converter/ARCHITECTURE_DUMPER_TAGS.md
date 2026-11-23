# converter Architecture - Dumper A's tags defined again and GNU type keywords

Companion to `ARCHITECTURE.md` in this folder, continuing section 3 of `ARCHITECTURE_DUMPER.md`.

### A struct or union tag defined again in a block {#shared-tags}

C lets a block define a tag again (`struct T { int y; }` inside a block of a function, beside a
file-scope `struct T`), which hides the outer definition until the block ends. The JSON dump
spells both types `struct T`, so its spelling alone cannot tell them apart; libclang can.

- **Naming.** The libclang pass registers every definition. The first definition of a tag
  keeps the tag. Each later one takes the first numbered tag that no record, enum, typedef,
  function or variable of the unit spells (das spells a record's constructor as a call of its
  name): `struct T` again is `struct T1`, or `struct T2` when the program has its own `T1`.
  Its das struct has that name. C scopes a record nested inside another with the outer one,
  and libclang's semantic parent of a nested record is then the unit: it is a file-scope
  record.
- **Units.** The free-name set is per unit. The link merges records of several units by
  spelling (`ARCHITECTURE_LINK.md`): two units' `T1` with one layout and the same field names
  are one das struct, and any difference, field names included, fails the link, naming both
  definitions (`converter/tests/test_link.das`, `numbered_tag_fields`).
- **Declarations.** The walk opens a tag scope for each compound statement and for each `for`
  statement (its declarations through its body). When it meets a definition of a tag defined
  more than once, the tag names that record from the definition to the end of the enclosing
  compound statement or `for` statement. A spelled type (a variable's, a cast's, a `sizeof`'s,
  a typedef's) takes the innermost binding, else the file-scope definition. A tag that only
  blocks define, spelled outside them (a file-scope `struct S *h(void)`, a new incomplete type
  in C), fails closed.
- **Expressions.** An expression's type follows its operands, not the scope it stands in:
  `s1.x` inside a block that hides `s1`'s tag is the outer record's member. When the file
  defines a tag more than once, a second libclang walk notes the record each expression's type
  names (through pointers and arrays), keyed by the expression's first token, and the walk reads
  an expression's type from that note alone. An expression with no note at its first token, or
  with two notes of one tag there (`(s2.y, &s1)->x`), fails closed.
- **Fields.** A record's fields are read when its type is first reached. A file-scope record
  first reached inside a block (a pointer to it, its definition later in the file) reads its
  fields past the block scopes and past any expression's note, so they name the file-scope tags.
- **Refused declarations.** A block's `struct T;`, or a first `struct T *p` there, declares a
  new incomplete type, and so does a tag defined in a parameter list, which the dump's spelling
  would read as a definition elsewhere. `struct T;` alone fails closed when the file defines the
  tag; the other two fail closed when the file defines it more than once. A first `struct W *b`
  of a tag defined once is that definition, as before (W's one file-scope definition later).

An enum tag defined again in a block fails closed: its constants bind by location, its type by
spelling.

### GNU `typeof` and `__alignof__`

clang resolves a `typeof`, and the dump desugars the whole spelling of a type (`typeof (x)` beside
`int`), but spells one under a declarator by its operand (`typeof (x) *`, `typeof (big)
(typeof(int))`). The libclang pass notes the canonical spelling of every `typeof` under the type of
a declaration, a cast and a compound literal, through pointers, arrays and function types, keyed
by clang's spelling of the `typeof` (`register_typeof`); once the program spells one, a second
walk notes those of every file of the unit (`note_typeofs`), since a header's declaration gives a
program expression its type. The type reader puts the canonical spelling in the place of each
`typeof (...)` before it reads the text (`without_typeof`). A spelling resolves only when every
place that spells it names one type: two that name different types (`typeof (x)` in two functions
whose `x` differ) fail closed, and so does one under a declarator in the operand of `sizeof`,
`_Alignof` or `va_arg`, where libclang gives the pass no type and another scope's declaration
could answer for it (a whole `typeof` there is desugared by the dump). A `typeof` of a function,
an array or a pointer to one under a declarator, whose type no text in its place spells, fails
closed too. A name that only holds the word
(`my_typeof_t`, C23's `typeof_unqual`) is no `typeof`.

GNU `__alignof__` (clang's trait `__alignof`) is the preferred alignment, and of an expression
naming a declaration the declaration's own (`__alignof__(f)` of a function declared
`aligned(256)`), neither of which the interned type tells: its value is the fold of clang's
evaluator over the node (`register_trait_value`, keyed like a `__builtin_constant_p` call). It is
an `alignof_v` with that value, so the emitter spells das's alignment of the type where the two
agree and the value elsewhere (a function's, an aligned declaration's). Two in one macro expansion
spelled from one token that clang values apart fail closed.
