# converter Architecture - Dumper A's tags defined again

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
  are one das struct, and any difference fails the link, naming both definitions.
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
  new incomplete type, and so does a tag defined in a parameter list; each fails closed when the
  file defines the tag elsewhere, since the dump's spelling would read it as that definition.

An enum tag defined again in a block fails closed: its constants bind by location, its type by
spelling.
