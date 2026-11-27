# frontend Architecture - the type table

Companion to `ARCHITECTURE.md` in this folder; section numbers are unique across the family. It
describes `c_types.das`, which types the parser's specifiers and declarators and keeps a unit's
C-IR type table (`docs/c-ir-spec.md` sections 2 and 3, `CirTu.types` of `converter/cir.das`), and
the walk of `c_ir.das` that fills the table in Dumper A's order, so that it equals Dumper A's entry
for entry. The expressions the walk types are `ARCHITECTURE_EXPRS.md`'s.

## 24. What Dumper A's table is {#c-types-order}

Dumper A interns a type while it walks clang's JSON dump (`converter/dumper_a.das`,
`converter/ARCHITECTURE_DUMPER.md` section 3): each node's type is read from its spelling, the
desugared one where clang gives it, with every qualifier dropped and every typedef name inside it
resolved to its canonical type. So a table entry is never a typedef's target by name: `typedef`
entries are added by the typedef declarations alone, and an entry's parts are always resolved
types. Reading a spelling interns a type's parts before the type: a pointer's target, an array's
element, a function's result and then each parameter left to right. An entry is keyed by its
structure - an integer by width, sign and spelling, `float` by width, `double` and `long double`
apart, a pointer, an array and a function by the indices of their parts, a typedef by its name -
and is interned once, at its first use.

The builder states a type once, in its pool (`CTypes.pool`), by the same structural keys over pool
indices, typedef names resolved, and uses it (`c_types_use`): the parts not yet in the table first,
in that order, then the type. A qualified type is a pool entry of its own (`c_qualified`, keyed by
its qualifier bits and its unqualified entry; an array's qualifiers on its element, C11 6.7.3p9),
since a conversion depends on qualifiers (`ARCHITECTURE_EXPRS.md` section 33); its use is its
unqualified type's table entry, as Dumper A drops every qualifier. A function type's parameters
are unqualified. Computing a type adds to the pool
only; the table grows by uses, in the order Dumper A's walk reaches the same declarations:

- the external declarations in order, those of the own libc headers adding nothing (section 28);
- a typedef declaration: its type, then its `typedef` entry, keyed by the name, so a second
  typedef of one name - another block's, of another type - adds its type and shares the entry;
- a variable declaration: its type, then its initializer's expression types
  (`ARCHITECTURE_EXPRS.md` section 35);
- a function declaration: its type, then each parameter's adjusted type, which the function's type
  holds already; a definition then its body;
- a body: its statements depth-first in source order, each expression where it stands
  (`ARCHITECTURE_EXPRS.md` section 35), each declaration in it as at file scope -
  `static` and `extern` locals alike - except that a block declaration of a function whose name a
  declaration before it declared (the unit's, or the own headers') adds nothing, as clang links it
  to that declaration;
- an old-style definition: its type as clang gives it, `R (P...)` with each parameter's adjusted
  type from its declaration in the list under the default argument promotions (`char` and `short`
  are `int`, `float` is `double`), then each parameter's adjusted type itself, in the identifier
  list's order.

`(void)` and `()` are one type, `R` with no parameter and not variadic. A typedef name keeps the
pool type it names for its scope: a block's bindings end with the block (`for` opens one too).

## 25. Specifiers {#c-types-specifiers}

The builtin type keywords of a specifier list form a set (a second `long` its own bit), which the
parser has already checked to combine (`ARCHITECTURE_PARSER.md` section 17). `int` and `signed`
fold into the set they qualify; each set is one type spelled as clang spells it, every width the
dialect's (`CirTarget`): `char` (signed as the target says: unsigned under both dialects, as Dumper
A passes `-funsigned-char`), `signed char`, `unsigned char`, `short`, `unsigned short`, `int`,
`unsigned int`, `long`, `unsigned long`, `long long`, `unsigned long long`, `_Bool` (8 bits,
unsigned), `float`, `double`, `long double` (64 bits under both dialects), `void`. Qualifiers,
storage classes and function specifiers give no type. A typedef name gives the pool type it is
bound to, and `typeof` of a type name that type name's type. Under the msvc dialect `size_t`,
which clang declares there before the unit, is `unsigned long long`.

Records, unions and enums are the Aggregates phase: the builder refuses them where they stand,
and its keys (by structure, a typedef by name) take them as further kinds. It refuses, with the
place of the construct, `file:line:col: <construct> is not typed yet`: a struct, union or enum type,
`_Complex`, `_Atomic`, `typeof` of an expression, `_Alignas`, an attribute naming `mode`,
`vector_size` or `ext_vector_type` (in the specifiers, on a pointer, around a parenthesised
declarator, after a declarator or a parameter), and a typedef name it has no type for - one clang
predeclares (`__builtin_va_list`, `__builtin_ms_va_list`, `__NSConstantString`) or an own header's
typedef it does not type, whose own refusal follows the message.

## 26. Declarators {#c-types-declarators}

A declarator is read inside-out over its tree (`ARCHITECTURE_PARSER.md` section 17): a pointer
points at what is built so far, an array holds it, a function returns it with its parameters'
types. A parameter's type is adjusted (C11 6.7.6.3p7-8): an array, an array of unknown size and a
function at the end of its declarator are pointers to the element and to the function, and a
typedef of an array or function type used with no declarator of its own adjusts the same way. The
array is then never used, as clang's parameter types are the adjusted ones.

An array's size is an integer constant expression (C11 6.6) from 0 to 2^31 - 1, evaluated by the
unit's one evaluator: `CTypes.fold`, which the walk sets to `c_exprs.das`'s `c_fold_node`
(`ARCHITECTURE_EXPRS.md` section 32), so array sizes, index designators and `case` labels fold
alike. Any other size - a variable one, which the spec leaves out of scope - is refused, and so is
`[*]` under a declarator. An array with no size is count -1 unless its initializer sizes it (section 27).

## 27. Initializers and expression types {#c-types-arrays}

An unsized array that has an initializer takes its count from it: a run of string literals gives
its bytes - each escape one byte, a universal character name its UTF-8 bytes, the NUL included -
and so does one braced alone for a character array; an initializer list gives one past the last
position its items fill, each item the position after the one before, an index designator `[k]`
(an integer constant expression) moving it to `k`; for an array of arrays each item is braced or a string
literal. A prefixed (wide or UTF) string literal, any other designator (a range, a nested one, a
non-constant index), an elided brace in an array of arrays and any other initializer of an unsized
array are refused.


## 28. The own libc headers {#c-types-library}

Dumper A dumps no declaration outside the program (its file policy), so the own headers' types
enter the table only where the unit uses them. The builder reads `clang -E` text, whose line
markers name each declaration's file: a declaration in a file whose name starts with the folder the
builder is opened with (`c_types_open`'s `library_dir`) adds no type. Its typedef names are bound to
their pool types, or, for one the builder refuses, to the refusal, which a use in the unit reports;
its function names count as declared for the block rule of section 24.
