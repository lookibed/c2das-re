# converter Architecture - the C source's spelling the emitter carries

Companion to `ARCHITECTURE.md` in this folder, continuing section 4 of `ARCHITECTURE_EMITTER.md`.

### Character literals {#character-literals}

A C character literal is an integer to clang, so Dumper A marks the `int_lit` its
`CharacterLiteral` becomes, and the `case` whose label is one under clang's wrappers, with
`"char": true`, an optional field `cir.das` writes after the kind's members and before `macro`
(absent otherwise; the spec's section 6 does not list it, and Dumper B does not write it). The
emitter spells a marked value of das type `int` as the das character literal, which is an `int`
too: `'%'`, `'{'`, the escapes
`'\n' '\t' '\r' '\b' '\f' '\\' '\''`, the same spelling the C had for these. das reads no `\0`,
`\a`, `\v`, octal or hex escape, so any other value stays its number (`*p != '\0'` is
`int(deref(p)) != 0`), and so does a marked value of another das type (a `u'x'`, a `char16_t`).
A conversion of the literal is a cast around it (a `char` slot's `uint8('\'')`). A case label's
mark is per switch, so a number labelling the same value in another switch stays a number.

### Comments {#comments}

The C comments are absent from clang's AST, so the emitter reads them from the C text a
statement's location names (`c_comments`, once per file): per line, the comment's text with its
whitespace collapsed and the `*` and `/` decoration at either end dropped, a block comment's
lines each their own, a `//` or `/*` inside a string or a character literal no comment. A
statement other than a block or a label carries, as `//` lines above it, the comments of the
lines after the last one carried up to its own: a comment on its own line lands above the next
statement, one after code above the statement of that line. Only the file of the function being
emitted counts, so a statement a header's macro spells carries nothing. Above a function's `def`
go the comment lines right above its header (lines holding a comment and no code); the comments
between functions elsewhere, of globals, types and directives, and after a function's last
statement, are not carried.
