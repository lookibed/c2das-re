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
'\0'` is `int(*p) != '\0'`, and C's octal `'\033'` is `'\x1b'`. A negative value (a
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

### Never-reassigned locals {#let-locals}

A local declared with an initializer that the function never assigns, steps or takes the address of
(`em.written`, collected over the whole body before it is spelled) is `let` when its das type is an
integer, a floating value or an enum: `let i1 : int64 = ivalue(v1)`. A `let` argument is what an
`[inline]` def's splice substitutes in place, where a `var` one binds a copy per site
(`docs/probe-findings.md` F104). A pointer, a record holding one and an array stay `var`: a `let`
pointer reads its pointee as const and passes to no `var` parameter (F3), and a record or an array
is written through its members, which the store-root walk does not see. A declaration without an
initializer, one filled by stores and one a lowered switch carries stay `var`.

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

### Same-type conversions {#same-type-conversions}

A C conversion between two integer or floating types das spells alike is no conversion: C's
`char` and `unsigned char` are both `uint8`, so `(unsigned char)s[i]` is `s[i]` and
`(unsigned)(unsigned char)s[i]` is `uint(s[i])`. An enum and a truth value keep their own routes
(`enum_to_integer`, `int_of`). A `sizeof` C reads as an `int` is das's `typeinfo sizeof(type<T>)`,
an `int` already, where the `size_t` value was `int(uint64(typeinfo sizeof(type<T>)))` (a
marshal-only record's size is its literal). A conversion that changes the das type stays, a
widening of a narrower one included (`uint64(uint(i))` zero-extends a negative `int`).

### Narrow equality {#narrow-equality}

C compares a `uint8`, `int8`, `uint16` or `int16` value promoted, and das's storage integers
compare only by `==` and `!=`, against a bare literal in their range or a value of their own type
(`docs/probe-findings.md` F106). So `==`/`!=` of such a value below conversions that keep its
every value (the promotion to `int`, then `unsigned` beside a `5u`) against an integer literal
in its range is the narrow compare, `ts.extra == 0`, `t.s == -128`, `*s == 'a'` (a character
literal stays one), on either side; two values of one storage type compare narrow too, `a.extra
== b.extra`. Each is exact, since the promotion keeps every value. A literal outside the range
(`int(t.extra) == -1`, never true), a named constant, two different storage types and an
ordering (das defines `<` on no storage type) keep C's promoted compare. The literal's value is
C's: a negated unsigned literal (`-1u`, UINT_MAX) is no negative value and keeps the promoted
compare, and so does a literal a conversion on its side changes (`(signed char)200` is -56), since
das would read the printed digits and compare them in range without an error. A literal past the
storage type's range is a das compile error, which catches only an out-of-range print.

### Enum conversions {#enum-conversions}

das converts an enum to every integer type directly with the bits `int(e)` gives (F106): C's
`(unsigned)e` is `uint(e)`, `(long long)e` is `int64(e)`, `(unsigned char)e` is `uint8(e)`, where
the value went through `int(e)` first. A 64-bit target of an enum whose underlying type is
unsigned (an enumerator past INT_MAX) takes `uint` first, `uint64(uint(m))`, since the direct
conversion would extend the stored high bit as a sign; a floating target takes the promoted
integer, `double(int(e))` and `double(uint(m))`, since das has no enum-to-float conversion.

### Long lines {#long-lines}

A line past `LINE_WIDTH` (160 bytes, the readability criterion's own bound) breaks where the
emitter marked the expression's structure as it spelled each node: after a list's `,` (a call's
arguments, a `fixed_array`'s elements, a record's fields), after `&&` and `||`, and after any
other binary operator. The marks are bytes the emitter writes into the expression's text
(`converter/line_wrap.das`), and `laid_out` chooses among them when the module's text is
assembled, dropping every mark of a line that fits. Of a line too long it breaks at the lowest
rank first, the shallowest parentheses and within them a list's commas, then `&&`/`||`, then the
other operators, filling each line with the parts that fit and indenting a continuation 8 spaces
past its statement (4 more per deeper break). A mark breaks only directly inside a `(`, where das
reads the next line as the same expression (a line opening with `+` or `-` outside parentheses is
a new statement, `$DASLANG_ROOT/CLAUDE.md`'s "fail silently" list), never inside a string or
character literal, a comment, a `[` or a `{`. A line no mark can shorten (a long string literal,
a top-level operator chain with no parentheses around it) stays as it is. The marks are the
AST's: no text is parsed to find where an expression may break.

### Dereferences and pointer steps {#pointer-steps}

A C dereference `*p` is das's `*p`, the node `deref(p)` is (`docs/probe-findings.md` F102: the two
spellings compile to the same nodes in the same order, no call among them). It is a unary operand:
das binds it below a member and an index as C does (`*s.p` is `*(s.p)`), so `wrap` parenthesizes
it under a postfix (`(*row)[2]`, `(*p).val`, `(*p)++`; das alone would read `*p++` as `(*p)++`
too, C as `*(p++)`), beside an operator when C parenthesized it (`(*p) != 0` for the value `if
((*d++ = *s++))` stored), and its own operand below a unary (`*(p - 1)`, but `**pp`). A step of a
pointer lvalue is das's own `p++` and `p--`, and a compound store of one is `p += n` and `p -= n`,
which das steps by the pointee's size for an `int`, `uint`, `int64` or `uint64` count on any
lvalue: a variable, a field, a field through a pointer, an element, a pointee, a `[c_union]` member
(F102). A byte pointer to a marshal-only record steps by the record's C size, `p += 24` and `p -=
n * 24`; a volatile pointer keeps its `c_volatile_store` of the sum.

### Truth values read as int {#truth-as-int}

A C truth value (a comparison, `&&`, `||`, `!`, a `_Bool`) is a das `bool`, and where C reads it as
an int (a store into an int, a `return`, an operand of arithmetic, a cast) it is `int_of(c)`:
`return int_of(line.dy > 0)`, `x += int_of(a < b)`. `int_of` is `c_runtime/int_of`'s call macro,
which expands in place to `c ? 1 : 0` once `c` is inferred, the same nodes the ternary spelled
before, no call under any tier. das has no `int(bool)`, and a macro named `int` would see every
`int(` of a module, so the name is the converter's own, reserved against a program's names.
