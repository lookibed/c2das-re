# converter Architecture - the C source's spelling the emitter carries

Companion to `ARCHITECTURE.md` in this folder, continuing section 4 of `ARCHITECTURE_EMITTER.md`.

### Character literals {#character-literals}

A C character literal is an integer to clang, so Dumper A marks the `int_lit` its
`CharacterLiteral` becomes, and the `case` whose label is one under clang's wrappers, with
`"char": true`, an optional field `cir.das` writes after the kind's members and before `macro`
(absent otherwise; the spec's section 6 does not list it, and Dumper B does not write it). The
emitter spells a marked value of das type `int` as the das character literal, which is an `int`
too: `'%'`, `'{'`, the named escapes `'\0' '\a' '\b' '\t' '\n' '\v' '\f' '\r' '\\' '\''`, and
`'\xHH'` for any other byte, since das reads C's escape set (`docs/probe-findings.md` F94): `*p !=
'\0'` is `int(deref(p)) != '\0'`, and C's octal `'\033'` is `'\x1b'`. A negative value (a
`'\xff'` under signed `char`) or one past a byte (a multi-character constant) stays its number,
and so does a marked value of another das type (a `u'x'`, a `char16_t`).
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
emitted counts: a statement a macro spells stands at its expansion site and carries that line's
comments, while a statement of a fragment the function's body includes (`ljumptab.h` in Lua's
`lvm.c`) lies in the fragment's file and carries nothing. An unterminated literal (an apostrophe
in `#if 0` prose) ends at its line's end, and a backslash-newline inside a literal is a line, so
no later comment moves off its line. Above a function's `def` go the comment lines right above
its header (lines holding a comment and no code), above the specifiers' own line in the GNU style
(`static int` alone above the name, a line ending in an identifier or `*`); the comments
between functions elsewhere, of globals, types and directives, and after a function's last
statement, are not carried.

### Constant names {#constant-names}

A node of a function body that carries a `macro` (`ARCHITECTURE_DUMPER.md`, "Macro names") and
is a numeric constant (literals, enumerators, `sizeof` and `alignof` under arithmetic, bitwise
and numeric conversions) is spelled by the macro's name, through the `_c_` rule for a das
keyword (`match` is `_c_match`); a name a builtin module holds a global of (`math`'s `PI`,
found through `program_for_each_registered_module`) keeps its value. The module holds `let private NAME = <value>` for each name
in first-use order, after its globals (in a cluster's own module, before its `include`s): the
value is the das text of the first use, and a use whose text differs (the macro redefined, or
expanded at another type) keeps its value. A constant whose body names other constants is
spelled over their names (`let private POS_B = POS_A + SIZE_A`), each declared before it, since
its value's text names them first; daslang folds a `let` over other `let`s' names, and a
conversion of one, to the constant before simulation (`probes/test_globals.das`,
`test_compound_let_folds`), so a name costs nothing at run time. A shift count C promotes apart
from its left side keeps a name in a conversion (`~0u << uint(SIZE_A)`) where a bare literal
takes the left side's suffix. A global's initializer keeps the value, as does a spelling that
does not go through `emit_expr` (a case label, a loop's step).

### Plain blocks and dead returns {#plain-blocks}

A C block that is a statement of its own, a case arm's trailing block or a `for`'s scope block is
spelled in braces and then loses them when its own level holds no `var`, `let` or `label` line
(`unbrace_plain`): its statements stand one level out. A block that declares keeps its braces, since
the name's scope ends with it, and so does one holding a label, which the goto lowering places
(`ARCHITECTURE_EMITTER_CONTROL.md`, Labels and goto); a block of multi-line entries keeps them too.
A function whose C body does not end in a `return` gets a zero `return` after it, unless the das
text's last statement already returns on every path by das's own rule (`text_returns`,
`docs/probe-findings.md` F101): a `return`, an `if` chain with an `else` whose arms each return, a
bare block that returns, or a `while (true)` whose body returns and which no `break` of its own can
leave (a `break` right after a `return` or a `break` of the same level is dead; a `goto` anywhere in
the body counts as leaving). Under that rule the dropped `return` is unreachable, and das accepts
the function without it.

### Parentheses {#parentheses}

Clang keeps the C source's parentheses as a `ParenExpr`; Dumper A marks the expression inside it
`"paren": true`, an optional field `cir.das` writes beside `char` (absent otherwise; Dumper B does not
write it). A pair the source text spells is marked whatever it holds; a pair from a macro's body only
around a shift or a bitwise operator (`((t) | ((v) << 4))`), where a reader misreads the precedence
against the neighbours, not around an argument, a unary or a comparison (`((o) == (t))`), which the
expansion repeats at every use. The emitter carries the mark on the expression's `Em`, and `wrap`
parenthesizes a marked operand that is no primary even where das's precedence needs no parentheses
(`1 << (b - 1)`, `a + (b * c)`). Where no operator takes the expression as an operand (a right-hand
side, an argument, a condition) it stands bare, and a marked lone name or call is never wrapped.

### Literal suffixes {#literal-suffixes}

A C integer literal the source converts to another arithmetic type (clang's `IntegralCast` or
`IntegralToFloating` over the literal, as `long x = 0;` or `f(1)` for a `size_t` parameter) is the
das literal of that type where das spells one with a suffix and the value is in the type's range:
`0l` and `-1l` for `int64`, `1ul` for `uint64`, `240u` for `uint`, `7u8` for `uint8`, `10.0lf` for
`double` and `1.0f` for `float`. A negative value takes no unsigned suffix, and a type without one
(`int8`, `int16`, `uint16`) keeps the conversion `int16(5)`, as does a named constant (`int64(FRACBITS)`)
and a character literal (`uint8('a')`). A negative literal is a unary minus, so it binds as one.
