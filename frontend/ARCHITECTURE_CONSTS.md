# frontend Architecture - constants

Companion to `ARCHITECTURE.md` in this folder: `c_consts.das`, the constant forms of Dumper C's
C-IR builder beside the integer folder `c_fold` (`ARCHITECTURE_EXPRS.md` section 41), sections
73 to 77. Each form is written as Dumper A writes it: Dumper A reads clang's evaluated value
where clang's JSON holds none (`converter/dumper_a.das`'s `register_trait_value`,
`register_constant_p`, `register_offsetof`), so each rule here states what clang's evaluator
gives. Where the builder cannot be certain of clang's answer it refuses; it never guesses a
value. `tests/test_c_consts.das` holds each form and refusal.

## 73. The forms {#c-consts-forms}

`c_constant_expr` types the nodes `c_expr` hands it through `CTypes.constant_expr`:

- `__builtin_offsetof(T, m)` is Dumper A's `offsetof` node: typed `size_t`, `of_t` the record `T`
  names unqualified (a typedef resolved), `field` the index of its direct member `m`. The byte
  offset from the record's layout rides in `trait_v` for `c_fold` (an array size, a `case`) and is
  cleared when `c_exprs_use` interns the node, since Dumper A's node holds none. A member path
  (`a.b`, `a[i]`) and a member an anonymous member holds are refused, as Dumper A does not lower
  them; a type other than a complete struct or union, a member the record lacks and a bit-field
  are invalid C.
- `__builtin_types_compatible_p(T, U)` is the `int` literal of clang's answer: the two types
  compatible once their own qualifiers are dropped (`c_composite`), an array's element keeping
  its own. The operands add pool types only, as Dumper A dumps neither. A function type with no
  parameter anywhere in either type is refused: the pool keeps `()` and `(void)` as one type.
- GNU `typeof (e)` is the type of `e` with no conversion and its qualifiers kept
  (`c_expr_type`, through `CTypes.expr_type`).
- `__builtin_constant_p` (section 75); `_Alignof` and `__alignof__` (section 74).

## 74. Alignments {#c-consts-alignof}

Both are Dumper A's `alignof_v`: typed `size_t`, the value in `trait_v`, `of_t` the operand type,
an operand expression's types interned after the node's as `sizeof_v`'s are. `_Alignof` is the
type's alignment as Dumper A computes it from the C-IR type (`c_type_align`). GNU `__alignof__`
is clang's preferred alignment, which is that same value on both dialects but for linux's
`long double`, x87's type, 16. `_Alignof` of linux's `long double` (or an array of it) is
refused: clang's 16 is not the 8 Dumper A computes from the C-IR's 64-bit type.

clang gives an expression that names a declaration the declaration's own alignment, which an
`aligned` attribute or `_Alignas` raises and a packed record lowers; the pool's types hold
neither. So a member operand is refused, and when the unit spells `aligned` or `_Alignas`
anywhere, so is any other expression operand and a type name whose specifiers name a typedef or
a `typeof`. A function designator under `__alignof__` is the largest `aligned(N)` its file-scope
declarations before the use spell, refused when none does or when a declaration spells an
`aligned` its specifier and attribute lists do not show; under `_Alignof` it is refused (Dumper
A gives a function no alignment). A type without an alignment - `void`, a function, an array of
unknown size, an incomplete record - is refused.

## 75. `__builtin_constant_p` {#c-consts-constant-p}

Dumper A writes clang's answer as an `int` literal and never dumps the argument. The pinned
clang's `-O0` answer is its evaluator's fold of the call: 1 when the argument, converted to a
value (an array and a function decay), is an integer, floating or pointer value the evaluator
folds - a null or integer-cast pointer and a pointer to a string literal's first character
included - and 0 otherwise, an aggregate always. Where the evaluator gives no answer and the
argument holds a comma operator or another such call, the answer is the code generator's, which
Dumper A refuses; the builder refuses any argument holding a comma, another such call, a
compound literal or a statement expression.

The builder's verdict on the argument walks it as clang's evaluator does. It folds literals,
enumerators, `sizeof`, `_Alignof` and `offsetof`, the arithmetic and bitwise operators, a signed
overflow, a shift past the width and a NaN included, and the casts between arithmetic types. It
follows `&&`, `||` and `?:` past a deciding left operand. It finds no value in a read of a
variable that is not const, a call, an assignment or an increment, an integer division by zero,
or the address of an object or a function (the evaluator holds an address, not a constant
value). A read of a const object (whose initializer clang may fold), a dereference, a builtin's
call, a negative shift count and an address used as anything but a pointer or a pointer-wide
integer have answers the builder cannot give: refused. `compare/types/fixtures/constants.c`
holds the pinned clang's answers.

## 76. Static initializers {#c-consts-statics}

A file-scope object's and a block's `static` object's initializer must be a constant (C11 6.7.9p4),
else clang rejects the unit. `c_static_initializer` walks each item of the initializer with the
evaluator of section 75 and takes an arithmetic constant, a string literal, a null or integer-cast
pointer, and an address constant: the address of an object of static storage or a function, a
member of one, an element at a constant index, a pointer step from one, a string literal stepped,
a file-scope compound literal whose items are constants (a block's is automatic), and an address
as an integer of the pointer's width. A read of a variable, a call, an effect, an integer division
by zero and the address of a parameter or an automatic object (`CId.automatic`) are invalid C;
what the builder cannot decide - a const object's value, an address narrowed - is refused.

## 77. A `case` value {#c-consts-case}

A `case` label's value is clang's (`c_fold`). Dumper A does not read clang's: it folds the
label's expression itself (`fold_constant`), through every cast, each step in 64 signed bits,
and dumps no unit where it meets anything but literals, enumerators, the unary operators and
the arithmetic, shift and bitwise binary operators. `c_case_value` runs that fold beside
clang's and refuses a label the two fold apart - a narrowing cast (`(signed char)255`), an
overflow of a narrower type (`1 << 31`), unsigned 64-bit arithmetic, a literal past 63 bits -
since writing Dumper A's value would be wrong C and clang's is not Dumper A's C-IR.
