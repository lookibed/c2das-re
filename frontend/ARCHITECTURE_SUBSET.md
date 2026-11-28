# frontend Architecture - the rest of Dumper A's subset

Companion to `ARCHITECTURE.md` in this folder: the forms of Dumper A's subset beside expressions,
records, initializers and constants, sections 79 to 87. Each is written as Dumper A writes it
(`converter/ARCHITECTURE_DUMPER.md`, sections "Statements" and "Attributes and asm", and
`converter/ARCHITECTURE.md` section 2 for the opaque records); what Dumper A refuses, or where the
builder cannot give clang's answer, is refused at its place.

## 79. Builtin functions {#c-subset-builtins}

A `__builtin_*` name is typed from `BUILTIN_FUNCTIONS` (`c_exprs.das`): a reference is clang's
`<builtin fn type>`, read only as a callee, and its decay is a pointer to the prototype the pinned
clang declares (`c_builtin_spelled` reads the spellings: `size_t` and `uint64` follow the dialect,
a pointee keeps its `const`; a pointer's own `restrict` is dropped, as no slot reads it), so each argument converts to its
parameter's type and a variadic one's extra arguments take the default argument promotions. The
builtins clang checks itself (`__builtin_signbit`, the `add`, `sub` and `mul` overflow builtins)
have the prototype `()`: their arguments are made values and take no other conversion, as clang
leaves them. `__builtin_choose_expr(c, a, b)` is the operand the folded `c` chooses; the other one
is typed and dropped. A builtin the table lacks stays an unknown identifier.

## 80. `va_list` and `va_arg` {#c-subset-va}

clang's `__builtin_va_list` is one opaque record named `va_list`, one field `words` of `unsigned
long long[N]`: under linux `N` is 3 (24 bytes) and the type is clang's `struct __va_list_tag[1]`,
an array of one record, so a variable of it decays where it is used and a parameter is a pointer
to the record; the table holds the array as the record itself (section 82). Under msvc `N` is 1
(8 bytes) and the type is the record, held whole: a call reads it (`LValueToRValue`). Its field
type enters the table before the record, as Dumper A builds the record from it.

`__builtin_va_start`, `__builtin_va_end` and `__builtin_va_copy` take their lists as linux's
decayed pointer and msvc's record as written (clang's builtins take it by reference there);
`va_start`'s last argument stands as written, no conversion on it. `va_arg(list, T)` is the
spec's `va_arg`: typed `T`, `arg_t` `T`, `list` decayed or read under linux, as written under
msvc. A `va_arg` of another type is refused, so is a builtin's list that is no `va_list` object.

## 81. glibc's `jmp_buf` {#c-subset-opaque}

The own `<setjmp.h>`'s `struct __jmp_buf_tag` is the opaque record `jmp_buf` of one `int`, 4
bytes, whatever members it spells (`c_make_opaque`); `jmp_buf`, an array of one, decays as an
array does and its size is the record's. Dumper A reads a type by its spelling, so every table
entry of a type that holds the record anywhere is the record itself, or a pointer to it when the
spelling ends in `*` or holds `(*)` (`opaque_spelling`): a function taking a `jmp_buf` is the
record, a pointer to such a function a pointer to it. Its definition in the unit adds no anchor,
and the record enters the table where a type names it, its field type first.

## 82. Opaque spellings in the table {#c-subset-spellings}

`c_types_use` asks `opaque_spelling` before it interns a pool type: the `jmp_buf` rule above, and
linux's `va_list` array of one record interned as the record. Every other type is interned by its
own parts. The pool keeps the C types, so conversions and calls follow C; only the table reads as
Dumper A spells.

## 83. The asm barrier {#c-subset-asm}

An asm statement with an empty template (adjacent empty literals included), no output and no
input, at most clobbers, is a compiler barrier: it orders nothing a das run observes, and it is
the empty statement. Template text is machine code and an operand a register binding: both are
refused; `asm goto` is refused by the parser.

## 84. The `mode` attribute {#c-subset-mode}

clang gives a declaration the type its `mode` names, so `c_mode_type` does: an integer or an enum
becomes the integer of the mode's width and its own sign - `QI` and `byte` a `signed char` or
`unsigned char`, `HI` a `short`, `SI` an `int`, `DI` and `word` the dialect's 64-bit `long` or
`long long` - read in the specifiers, a member's specifiers, or after a declarator that is a name
alone. Another mode (`TI`, a floating mode), another type (a pointer, a floating type, plain
`char`, `_Bool`), a mode after a derived declarator and one in an enum's own attribute list are
refused.

## 85. GNU case ranges {#c-subset-case-range}

`case lo ... hi:` folds both ends as a single label does (`ARCHITECTURE_CONSTS.md` section 77) and
holds them in the switch's promoted controlling type, as clang converts them; it is a `case` with
`hi`, a character range marked when both ends are characters. An empty range, `lo` above `hi`
there, labels nothing and adds no marker; its statement stays.

## 86. Library functions and the attribute lists {#c-subset-library}

A declaration with no prototype, neither `static` nor a definition, of a C library function clang
declares itself (`exit`, `strlen`,
the `mem` and `str` functions, `malloc`, `free`, `abs`) takes the library's prototype as its
composite type (`extern void exit();` is `void (int)`), and any declaration with no prototype
lists its composite type's parameters, unnamed, as Dumper A reads them off clang's type.

### Attributes {#c-subset-attributes}

`c_plain_attributes` takes the attributes Dumper A drops (inlining and optimizer hints,
diagnostics, `visibility`, `section`, `gnu_inline`, `noreturn`, `weak` on a name the unit defines,
`may_alias`, `mode`), reads (`aligned`, `packed`) or accepts as a plain call (`musttail`), and those
clang ignores (`noclone`, `noipa`, `optimize`, `externally_visible`, `scalar_storage_order`) and
the calling conventions (`stdcall`, `cdecl`, `fastcall`, `thiscall`, `vectorcall`, `ms_abi`), which
x86-64 ignores or Dumper A strips from a type; any
other, `ms_struct`, `cleanup`, `constructor` and `transparent_union` among them, is refused at
its name. A `weak` name the unit never defines (`note_weak`, checked at the unit's end) is
refused.

## 87. Function names {#c-subset-func-name}

`__func__` and `__FUNCTION__` are the string literal of the enclosing function's C name, typed
`const char[N]`. `__PRETTY_FUNCTION__`, whose text is clang's spelling of the signature, and a name
outside a function are refused.
