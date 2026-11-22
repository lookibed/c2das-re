# converter Architecture - Dumper A's tags defined again

Companion to `ARCHITECTURE.md` in this folder, continuing section 3 of `ARCHITECTURE_DUMPER.md`.

### A struct or union tag defined again in a block {#shared-tags}

C lets a block define a tag again (`struct T { int y; }` inside a block of a function, beside a
file-scope `struct T`), which hides the outer definition until the block ends. The JSON dump
spells both types `struct T`, so its spelling alone cannot tell them apart; libclang can.

- **Naming.** The libclang pass registers every definition. The first definition of a tag
  keeps the tag. Each later one takes the first numbered tag that no record, enum or typedef
  of the unit spells: `struct T` again is `struct T1`, or `struct T2` when the program has its
  own `T1`. Its das struct has that name. C nests a record defined inside another with the
  outer one's scope, so libclang's semantic parent of a nested record is the unit: the record
  is a file-scope one.
- **Declarations.** The walk opens a tag scope for each block. When it meets a block's
  definition of a tag defined more than once, the tag names that record from there to the end
  of the block. A spelled type (a variable's, a cast's, a `sizeof`'s, a typedef's) takes the
  innermost block's binding, else the file-scope definition. A tag that only blocks define,
  spelled outside them (a file-scope `struct S *h(void)`, a new incomplete type in C), fails
  closed.
- **Expressions.** An expression's type follows its operands, not the scope it stands in:
  `s1.x` inside a block that hides `s1`'s tag is the outer record's member. After a tag's
  second definition, the libclang pass notes the record each expression's type names (through
  pointers and arrays), keyed by the expression's first token, and the walk reads an
  expression's type through that note before the scopes. Two expressions that start at one
  token and name different records of the tag (`(s2.y, &s1)->x`) fail closed.
- **Fields.** A record's fields are read when its type is first reached. A file-scope record
  first reached inside a block (a pointer to it, its definition later in the file) reads its
  fields with the block scopes set aside, so they name the file-scope tags.

An enum tag defined again in a block fails closed: its constants bind by location, its type by
spelling.
