# frontend Architecture - expressions and conversions

Companion to `ARCHITECTURE.md` in this folder; section numbers are unique across the family. It
describes `c_exprs.das`, which types the parser's expressions as C-IR expression nodes with every
conversion clang makes, `c_floats.das`, which computes floating constants, and the parts of
`c_ir.das` that place expressions in the unit: initializers, statements and the order their types
enter the table. Dumper A writes what clang's tree holds (`converter/dumper_a.das`, `dump_expr`),
so each rule here states what clang's semantic analysis puts in that tree.

## 29. Nodes {#c-exprs-nodes}

`c_expr` turns a parser expression into a C-IR node (`docs/c-ir-spec.md` section 6) whose `t` is
a pool type (`ARCHITECTURE_TYPES.md` section 24), qualified as clang types the node: a reference
has its declaration's type, a subscript and a dereference the pointer's target type. The node
carries no conversion at its top; the context that uses it adds them (sections 30 to 33). The
nodes: literals (section 34), a reference to a variable or function in scope (`CIr.ids`, bound by
the walk: a variable from its declaration on, so its own initializer sees it), `un`, `bin`,
`assign` with its operator, `cond`, `comma`, `call`, `index` (the base as the source writes it),
`cast` for an explicit cast, and `sizeof_v` with Dumper A's size of the type (a scalar its width, a
pointer and a function the pointer width, `long double` its 64 bits, an array its count of
elements). Parentheses set `paren`; `__extension__` is its operand. A reference, a subscript and a
dereference of a volatile-qualified type set `vol`.

A reference to a function an old-style definition defined has the type `R ()`, as clang's reference
does, while its calls convert by the definition's promoted parameters (section 33); a declaration
with no prototype keeps the type and prototype of an earlier one of the name (clang's composite
type). The builtin functions typed are `__builtin_expect` and `__builtin_abort` (`BUILTIN_FUNCTIONS`),
only as callees: a reference has the type clang gives a builtin, `<builtin fn type>`
(`c_builtin_fn_type`, in the table `void (...)`, keyed apart), and its decay is to a pointer to its
prototype, `long (long, long)` and `void (void)`.

Refused, at the construct's place: an identifier no variable or function in scope names (an enum
constant among them, until the Aggregates phase), a builtin other than as a callee, GNU's `?:` with
no middle operand, a member access, `va_arg`, `offsetof`, `__func__`, a compound literal, `_Alignof`,
a statement expression other than a statement block (section 35), an operator on a pointer C does
not define, a dereference, subscript or call of a value of the wrong type, a cast or a conditional
of types clang refuses.

## 30. Casts {#c-exprs-casts}

A conversion is a `cast` node over its operand, typed by the result. `c_implicit` adds an implicit
one as clang's `ImpCastExprToType` does: none when the operand has the result type already (the
same pool type, qualifiers included), and when the operand is itself an implicit cast of the same
kind, that cast is retyped instead of wrapped, so a promotion and the integer conversion after it
are one `IntegralCast`, while a promotion before an `IntegralToFloating` stays its own cast.

`c_rvalue` makes a node a value (C11 6.3.2.1), the conversion every context below starts with: a
function decays (`FunctionToPointerDecay`), an array lvalue decays to a pointer to its element,
qualifiers kept (`ArrayToPointerDecay`, a string literal's too), any other lvalue is read
(`LValueToRValue`, its type unqualified). A reference to an object, a string literal, a subscript
and a dereference of an object pointer are the lvalues. No conversion reaches the operand of `&`,
`sizeof`, `++` and `--`, or an assignment's left operand.

## 31. Operand conversions {#c-exprs-operands}

`c_promote` is clang's usual unary conversions: a value, then an integer narrower than `int`
converted to `int` (C11 6.3.1.1p2; `float` stays `float`). `c_arith` is the usual arithmetic
conversions (6.3.1.8): both operands promoted, then the one not of the common type converted to it:
the wider floating type; else the higher rank of one sign; an unsigned operand of rank at least the
signed one's; a signed type wider than the unsigned one; else the unsigned type of the signed one's
rank. Rank follows the spelling (`long` above `int` at one width, `long long` above `long`).

- `*`, `/`, `%`, `+`, `-`, `&`, `|`, `^` and the relational and equality operators on arithmetic
  operands: the usual arithmetic conversions; a comparison is `int`.
- `<<` and `>>`: each operand promoted alone; the result the left one's type.
- `&&` and `||`: each operand promoted; `int`.
- Unary `-`, `+`, `~`: the operand promoted. `!`: the operand a value only (clang does not promote
  it), `int`. `*`: the operand a value. `++`, `--`, `&`: none.
- A comparison with a pointer: both values; an integer operand converted to the other's pointer
  type, `NullToPointer` for a null pointer constant (`IntegralToPointer` else); two pointers of
  different pool types, the right one converted to the left one's type by `BitCast`, the left one
  when only it is a null pointer constant (as clang's `checkCompareOperands` does).
- Pointer arithmetic: the pointer a value, the integer promoted; the result the pointer's type;
  the difference of two pointers the dialect's `ptrdiff_t` (`long`, msvc's `long long`).
- `?:`: the condition promoted; arithmetic arms by the usual arithmetic conversions; else both
  values, two `void` arms `void`, a null pointer constant converted to the other arm's pointer type
  (`NullToPointer`, also over an explicit `(void *)0`), a pointer to `void` taking the other arm by
  `BitCast`, two other pointers of different types both made `void *` by `BitCast`.
- `,`: both operands values; the right one's type. A `switch` controlling expression is promoted.

## 32. Constants {#c-exprs-constants}

`c_fold` evaluates an integer constant expression (C11 6.6) over typed nodes: integer and character
literals, integer casts, `sizeof`, the unary, binary, logical and conditional operators, each step
held in its node's type (wrapped to the width, unsigned arithmetic for unsigned operands).
`c_fold_node` types a parser expression and folds it: the unit's one evaluator, for a `case`
label (its `v`; a GNU range is refused), an index designator, and through `CTypes.fold` an array
size (`ARCHITECTURE_TYPES.md` section 26). A typed size expression adds pool types only, as Dumper
A's table holds the folded array type and no node of its size. A null
pointer constant (`c_is_null`, 6.3.2.3p3) is an integer constant expression of value 0, or an
explicit cast of one to `void *`.

## 33. Conversions to a slot's type {#c-exprs-slots}

`c_assigned` converts as by assignment (6.5.16.1, clang's copy initialization) to the slot's type
unqualified: the operand a value, then arithmetic to arithmetic by the pair's kind (`IntegralCast`,
`IntegralToFloating`, `FloatingToIntegral`, `FloatingCast`, `IntegralToBoolean`,
`FloatingToBoolean`); to a pointer `NullToPointer` from a null pointer constant, `IntegralToPointer`
from another integer, `NoOp` from a pointer whose type differs only in qualifiers (`char *` to
`const char *`), `BitCast` from any other pointer; a pointer to `_Bool` `PointerToBoolean`, to
another integer `PointerToIntegral`. A literal is converted, never retyped (`char c = 1` is an
`IntegralCast` over `1`). The slots:

- a scalar initializer, braced or not, and a list's items, each to its element type at its position
  (an index designator sets it; the items in position order, a later one for a position replacing
  an earlier one, as clang's semantic form holds them); a character array's string literal, braced
  or not, is typed as the array itself (`char s[10] = "ab"` gives the literal `char[10]`), as clang
  does; an array of arrays with elided braces is refused;
- an assignment's right operand to the left one's type; a compound assignment's right operand
  promoted and converted to the computation type, the usual arithmetic conversions of the promoted
  left type and it (no node on the left operand), a shift's and a pointer's promoted alone;
- a `return` value to the function's result type (a `void` function's value only made a value);
- a call's arguments: within a prototype's parameters each to its parameter's type; past them, or
  when the callee has no prototype, by the default argument promotions (6.5.2.2p6: promoted, `float`
  to `double`); a call by name of a function an old-style definition defined converts its arguments
  to that definition's parameter types promoted, as clang does.

An explicit cast takes its operand as a value (to `void` too) and its kind from the two types:
`NoOp` when they differ in qualifiers at most, the arithmetic kinds as above, `ToVoid`,
`NullToPointer` for a null pointer constant integer to a pointer, `IntegralToPointer`,
`PointerToIntegral`, `PointerToBoolean`, `BitCast` between other pointers.

## 34. Literals {#c-exprs-literals}

An integer literal takes the first type of its list that holds its value (6.4.4.1): decimal with no
suffix `int`, `long`, `long long`; octal or hex with no suffix the signed and unsigned types of each
rank in turn; `u`, `l`, `ll` and their combinations their own lists; the widths the dialect's. Its
`v` is the decimal value. Under msvc an `ll` literal without `u` past `long long` is a `long long`
of the wrapped value, as clang's MSVC compatibility types it (`0xc000000080000000LL` is
-4611686016279904256). A character constant is an `int` of the one byte it holds, read as plain
`char` (unsigned under both dialects); with `L` the dialect's `wchar_t` (`int`, msvc's
`unsigned short`), with `u` `unsigned short`, with `U` `unsigned int`, of the one character it holds,
or of its one octal or hexadecimal escape's value, a code unit and not a byte (`L'\400'` is 256; a
value past `INT_MAX` refused); both set `is_char`. A string literal is `char[N]` of its bytes, escapes decoded, a universal
character name as its UTF-8 bytes, adjacent literals joined, the NUL appended; a prefixed one is
refused. A floating constant is `float` with `f`, `long double` with `l`, else `double`, its `v` by
section 36.

## 35. Order and statements {#c-exprs-order}

Dumper A interns a node's type before its operands' (`dump_expr_node` reads the node's type, then
dumps its children), left to right, and a `sizeof`'s operand type, or its operand expression's types,
after its own. `c_exprs_use` turns a typed expression's pool types into table indices in that order,
and the walk of `c_ir.das` calls it where Dumper A dumps the expression: a variable's initializer
right after the variable's type; in a body each statement's expressions in source order - an `if`'s
condition before its branches, a `while`'s before its body, a `do`'s after, a `for`'s initializer,
condition and step before its body, a `switch`'s controlling expression, a `return` value. A `case`
label's expression adds no type (Dumper A folds it from the tree).

The statements are Dumper A's shapes: a block's declarations as its statements (a local's `decl`,
a hoisted `static` a `null` with the static in `decls` as a global named `<function>_<name>` before
the function, an `extern` a `null`, a block function declaration nothing), `case`, `default` and a
label as markers followed by the statement under them, a `for`'s declaration as a compound
statement in `init_s`, an expression statement (and a `for`'s initializer and step, an `if`, `while`,
`do` or `for` condition) made a value, a GNU statement expression used as a statement - through
parentheses, `__extension__` and a cast to `void` - as its compound statement. The names are
`ARCHITECTURE_NAMES.md`'s.

## 36. Floating constants {#c-exprs-floats}

Dumper A writes a floating constant as clang's decimal text of its value read back by the C
library's `strtod` and printed by `%a`. `c_floats.das` does it in das alone, since the frontend
loads no native module (`ARCHITECTURE.md` section 2): the literal's exact value - a decimal one as a
big integer times a power of ten, a hex one as a big integer times a power of two - is rounded to
the nearest value of the type with ties to even, a value below the smallest normal keeping fewer
bits and one past the largest finite infinite (`c_float_value`). A `float` constant's value then
goes through clang's text of it, nine significant digits cut and rounded up when the first digit
cut is 5 or more, as LLVM's `APFloat::toString` does (`c_float_decimal`), read back as a double. A
double's seventeen digits read back to the same double, so it is printed as it is; a `long double`
constant is read as a double, the dialect's width (clang's own reading at 64 bits can differ in
its last bit where the decimal lies near a halfway point of the double). The print
(`c_hex_float`) is glibc's `%a` of a double: `0x1.<hex digits>p<exponent>` without trailing zero
digits, a subnormal `0x0.<hex digits>p-1022`, zero `0x0p+0`, infinity `inf`.
