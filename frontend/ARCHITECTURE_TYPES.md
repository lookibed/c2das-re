# frontend Architecture - the type table

Companion to `ARCHITECTURE.md` in this folder; section numbers are unique across the family. It
describes `c_types.das`, which builds a unit's C-IR type table (`docs/c-ir-spec.md` sections 2
and 3, `CirTu.types` of `converter/cir.das`) from the parser's tree, so that the table equals
Dumper A's entry for entry.

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
indices, with qualifiers dropped and typedef names resolved, and uses it (`c_types_use`): the
parts not yet in the table first, in that order, then the type. Computing a type adds to the pool
only; the table grows by uses, in the order Dumper A's walk reaches the same declarations:

- the external declarations in order, those of the own libc headers adding nothing (section 28);
- a typedef declaration: its type, then its `typedef` entry, keyed by the name, so a second
  typedef of one name - another block's, of another type - adds its type and shares the entry;
- a variable declaration: its type (then its initializer's expression types, section 27);
- a function declaration: its type, then each parameter's adjusted type, which the function's type
  holds already; a definition then its body;
- a body: its statements depth-first in source order, each declaration in it as at file scope -
  `static` and `extern` locals alike - except that a block declaration of a function whose name a
  declaration before it declared (the unit's, or the own headers') adds nothing, as clang links it
  to that declaration;
- an old-style definition: its type as clang gives it, `R (P...)` with each parameter's type
  promoted (C11 6.5.2.2p6: an integer type narrower than `int` and `_Bool` to `int`, `float` to
  `double`), then each parameter's adjusted type from its declaration in the list, unpromoted, in
  the identifier list's order (`int` for a name the list does not declare); an attribute on such a
  declaration that changes a type is refused, as anywhere.

A declaration's specifiers name one type, resolved once before its declarators: a typedef name
one declarator binds does not change the type the next declarator starts from
(`typedef T T2, *T, T3;` makes `T3` the outer `T`).

`(void)` and `()` are one type, `R` with no parameter and not variadic, and so is a parameter
list of one typedef name of `void`. A typedef name keeps the
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
`vector_size` or `ext_vector_type` in either spelling (in the specifiers, on a pointer, around a
parenthesised declarator, after a declarator, a parameter, an old-style parameter's declaration
or an own header's typedef), `_Atomic` on a pointer or in an array parameter's brackets, and a
typedef name it has no type for - one clang
predeclares (`__builtin_va_list`, `__builtin_ms_va_list`, `__NSConstantString`) or an own header's
typedef it does not type, whose own refusal follows the message.

## 26. Declarators {#c-types-declarators}

A declarator is read inside-out over its tree (`ARCHITECTURE_PARSER.md` section 17): a pointer
points at what is built so far, an array holds it, a function returns it with its parameters'
types. A parameter's type is adjusted (C11 6.7.6.3p7-8): an array, an array of unknown size and a
function at the end of its declarator are pointers to the element and to the function, and a
typedef of an array or function type used with no declarator of its own adjusts the same way. The
array is then never used, as clang's parameter types are the adjusted ones.

An array's size is an integer literal, in parentheses or not, decimal, octal or hex with any suffix,
below 2^31; any other size - an integer constant expression, which waits for constant folding, or a
variable size, which the spec leaves out of scope - is refused, and so is `[*]` under a declarator.
An array with no size is count -1 unless its initializer sizes it (section 27) or it is a tentative
definition the unit's end completes.

## 27. Initializers and expression types {#c-types-arrays}

An unsized array that has an initializer takes its count from it: a run of string literals gives
its bytes - each escape one byte, a universal character name its UTF-8 bytes, the NUL included -
and so does one braced alone for a character array; an initializer list gives one past the last
position its items fill, each item the position after the one before, an index designator `[k]`
(an integer literal) moving it to `k`; for an array of arrays each item is braced or a string
literal. A position past 2^31 - 1 is refused. An array of unknown size that a typedef names
(`typedef char A[]; A a = "hello";`) is sized by the initializer the same way.

A file-scope declaration with no initializer and no `extern` is a tentative definition (C11
6.9.2): clang completes the last such definition of an array of unknown size to one element at the
unit's end, and Dumper A reads that type at the declaration. So the builder gives the declaration
`T[1]` when no later declaration of the name defines it, and keeps the size unknown when a later
one does (with a size, an initializer, or tentatively); a later `extern` declaration with no size
changes nothing, and one with a size is refused (the completion it makes waits for the Aggregates
phase). A prefixed (wide or UTF) string literal, any other designator (a range, a nested one, a
non-literal index), an elided brace in an array of arrays and any other initializer of an unsized
array are refused.

Expression types are not built yet (C.3). In Dumper A's table they interleave with the
declaration types: right after a variable's type come the types of its initializer's nodes
(literals, implicit and explicit casts, string literals' `char[N]` arrays, decays, `sizeof` and
compound-literal type names), and in a body each expression statement, condition, `return` value
and loop step adds its nodes' types where it stands among the declarations. Declarations inside an
expression (a statement expression's, a compound literal's or a cast's type name) are not walked.
So the table matches Dumper A's whole only for a unit whose expressions bring no type of their own
before its declarations do; `compare/types/` compares the declaration-derived order on its own.

## 28. The own libc headers {#c-types-library}

Dumper A dumps no declaration outside the program (its file policy), so the own headers' types
enter the table only where the unit uses them. The builder reads `clang -E` text, whose line
markers name each declaration's file: a declaration in a file whose name starts with the folder the
builder is opened with (`c_types_open`'s `library_dir`) adds no type. Its typedef names are bound to
their pool types, or, for one the builder refuses, to the refusal, which a use in the unit reports;
its function names count as declared for the block rule of section 24.

## 60. Redeclarations {#c-types-redeclarations}

clang gives a redeclaration of a name the composite of its type and the earlier one's (C11 6.2.7p4),
and Dumper A reads that type. The builder keeps, per name declared at file scope or with `extern`
(a function declaration in a block included), the pool type its last declaration has and whether
it had a prototype, and gives a redeclaration (a definition included):

- of a function with no prototype (`int f();`), after one with a prototype: the earlier type;
- of a function with a prototype, after one with none: its own type;
- of an array of unknown size, after one with a size: the earlier type; of an array with a size,
  after one of unknown size: its own;
- of the same type: that type.

A function the own headers declared and the unit declares again is held to the header's type the
same way, computed when the unit's declaration is met. Any other pair of different types - two
prototypes with different parameters, arrays of different sizes, a composite inside a pointer or a
parameter - is refused at the redeclaration, as its composite waits for the Aggregates phase's
machinery.

A unit's file-scope declaration of a C library function that clang knows as a builtin, with a type
clang does not merge (`int strlen(char *);`, c-testsuite 00025), makes Dumper A intern the
library's type (`unsigned long (char *)`) before the declaration's own (its
`note_library_redeclaration`). The builder holds no table of clang's library builtins, so it
interns the declaration's type alone, and `compare/types` reports such a unit as differing.

