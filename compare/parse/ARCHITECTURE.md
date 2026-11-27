# compare/parse Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
holds the parse oracle of Dumper C's parser (`frontend/c_parser.das`,
`frontend/ARCHITECTURE_PARSER.md`): one unit preprocessed by clang, its declarations, record and
enum bodies and function bodies as clang's tree holds them and as the parser reads them, both
reduced to one line form and compared line by line. It starts clang, so it lives outside `frontend/`, whose code starts no process
(`frontend/ARCHITECTURE.md` section 2). It compares what the AST alone fixes; what clang decides by
the meaning of the program is left to it (section 3).

## 1. File charters

- `clang_side.das` - clang's side: the presumed places of a preprocessed text (`presumed_map`,
  `place_of`, section 2), clang's type spellings (`clang_type`), an expression of clang's JSON tree
  in the form (`clang_expression`), a record or enum body's lines, a statement's lines
  (`clang_statement`), and a unit's file-scope declarations (`clang_unit`, one `ClangTop` each: its
  lines, the names it binds). It reads no parser state.
- `parser_side.das` - the parser's side: the unit through the parser's entry (`parse_unit`,
  section 4), a declaration's lines (`parser_lines`) with its bodies' and a definition's statements
  (`statement_lines`), an expression in the form (`parser_expression`), and the types spelled as
  clang spells them (`base_spelling`, `spell_type`, `integer_value`). It reads the parser's public
  API and its public fields only.
- `parse_oracle.das` - the comparison (`lines_match`, `compare_texts`, section 5), a unit through
  clang (`clang_dump`, `compare_unit`), the totals of a set (`ParseTotals`, `run_set`), the corpora
  (`corpus_units`) and the command line's run (`ParseOracleArgs`, `run_parse_oracle`).
- `run.das` - the command line's entry, from the repository root with `das`: `--corpus fixtures`
  (the units of `fixtures/`), `--corpus frontend` (every header of `frontend/include/` as a unit),
  `--corpus c-testsuite` (the fetched single-exec suite), units named after the flags, `--quiet`
  (only the units that are not the same), `--dump` (both sides' lines of every unit), `--define
  <macro>` (a `-D` added to every unit's preprocessing, a program's own sidecar macros), `--work
  <folder>` (default `compare/work/parse`, under the gitignored `compare/work/`), `--show N` (the
  differences printed per unit). An unknown corpus, or one whose folder is missing, is an error and
  exit 1, never an empty set. Exit 0 when the parser refused no unit and every difference has a
  named cause. It states the context stack the parser needs (`options
  stack`, `frontend/ARCHITECTURE_PARSER.md` section 19) and room for the reductions' recursion.
- `fixtures/` - a unit per construct family, each with the verdict the tests expect:
  `expressions.c` (every expression form, as file-scope initializers), `types.c` (type names,
  declarators, storage classes), `typedefs.c` (the typedef table's effect), `static_assert.c`,
  `bodies.c` (record and enum bodies, definitions, every statement), `edges.c` (precedence,
  postfix chains, type names in odd places, GNU forms), `wildcards.c` (a `?` for one part of a
  type), `oldstyle.c` (old-style definitions), `param_bodies.c` (tag bodies inside declarators,
  some not compared), `forward.c` (tags declared with no body), all `same`; `semantic.c` (a clang
  semantic difference, `differs`); `builtin.c` (library builtins, `differs` by a named cause only);
  `causes.c` (a builtin and a merged redeclaration, `differs` by named causes only);
  `refused.c` (`construct refused`); `pragma.c` (`parser refused`); `clang_refuses.c` (`clang
  refused`).
- The tests are `compare/tests/test_parse_oracle.das`.

## 2. Places {#places}

The unit is `clang -E` output with its line markers, and both sides read that one text. A place is
a file, a line and a column, as the line markers present them. The parser's side takes the place of
a node's first token from its token (`frontend/ARCHITECTURE_PARSER.md` section 14). Clang's JSON
writes each location's byte offset into the text, and drops a file or line equal to the last one
written, so the clang side does not read clang's lines: `presumed_map` reads the line markers of
the text itself (`# <line> "<file>" <flags>` and `#line <line> "<file>"`, the file as the bytes
between the quotes) and `place_of` turns an offset into a place, the column a byte column. So a
place is compared from two readings of the markers, the parser's and the oracle's own.

## 3. The form and what is compared {#compared}

Each entity a declaration declares is one line, at file scope and in a block alike. A typedef is `(typedef
<name>@<line>:<col> "<type>")`; any other declarator is `(decl <name>@<line>:<col> "<type>"
<flags> [<parameter names>] = <initializer>)`. A `_Static_assert` is `(static_assert@<line>:<col>
<condition> <message>)`. A tag declared with no body by a declaration of its own (`struct S;`, at
file scope, in a block or in a record) is `(tag <keyword> <tag>@<place>)`; a tag a declaration
names with no body (`struct S *p;`) has no line of its own: clang lists it beside that
declaration, its place inside the declaration's range (`tag_of_neighbour`). The type is spelled as
clang spells it. The flags are the storage class
(`static`, `extern`), `thread_local` and `inline`. The parameter names, each `-` when unnamed, stand
for a declarator that applies a function to its name and has parameters. A line `(file <name>)`
opens each run of lines in one file.

A record or enum body is its tag's line, `(record struct <tag>@<place>)` or `(enum <tag>@<place>)`
(`-` for no tag, placed at the keyword), one line per member, `(field <name>@<place> "<type>")` with
` : <width>` for a bit-field (an unnamed one `-`, placed at its declaration's first token), or per
enumerator, `(enumerator <name>@<place> = <value>)` (`-` for none), then `(end)`. A body its members'
specifiers hold comes before the members it types, as clang nests it. The field clang makes for an
anonymous member, and the names it brings into the record, are clang's and not compared; the
member's own record body is.

A function definition is its declaration's line, then one `(param <name>@<place> "<type>")` per
parameter (`-` and no place for an unnamed one), with the type the parameter is declared with,
adjusted as a parameter, then its body as statements: one line per
statement in order, with its kind, place and expressions: `(compound@...)` closed by `(end)`,
`(expr@... <e>)`, `(null)` (unplaced: clang places it at its `;`, the parser at any attribute
before it), `(label@... <name>)`, `(case@... <value> <last>)` (`-` with no GNU range),
`(default@...)`, `(if@... <condition> else|-)`, `(switch@... <e>)`, `(while@... <e>)`, `(do@...
<condition>)`, `(for@... <first> <condition> <step>)` (`decl` for a declaration, whose lines follow,
`-` for a part left out), `(goto@... <label>)`, `(continue@...)`, `(break@...)`, `(return@... <e>)`,
`(asm@...)`; each statement under one follows it. A declaration in a block is its lines; a label at a
block's end has a `(null)` statement, as clang gives it one.

An old-style definition (`int f(a, b) char a; float b; {...}`) has the type clang gives it, its
parameters' types promoted (C11 6.5.2.2p6): the integer types below `int` and `_Bool` to `int`,
`float` to `double`, a qualifier of the parameter dropped; each parameter's line has the type its
declaration-list entry gives it, `int` for none. A typedef name or an enum promotes by a type
the tree does not hold (an enum's by its values), so its promoted type is `?`.

The parser spells a type from its specifiers and declarator. A builtin type takes its canonical
name (`long int signed` is `long`, `_Complex` alone is `_Complex double`), the qualifiers go
first in the order `const volatile restrict`, and `_Atomic` wraps the type it qualifies. The
declarator is spelled from the name out: a pointer and its qualifiers before the text, an array or
a function after it, the text in parentheses when an array or a function follows a pointer. A
parameter's outermost array or function type is adjusted to a pointer, as C11 6.7.6.3p7 and p8 say
and clang writes it. An array size is the value of an integer constant; any other size is `?`.

A `?` in a parser line stands for one part of a type, never the type around it (`lines_match`):
a run of clang's line with its parentheses and brackets balanced and none of `,`, `*`, `[`, `]`,
`)` or `"` outside them, so `int (?, int)` and `? *[3]` compare the return type, the other
parameter, the pointer and the array, and a `?` never stands for a pointer or a parameter beside
it; right after `[` it is an array's size, any text up to the closing `]`. The parser writes it
where the tree alone cannot spell clang's text, for that part alone: an array size that is no
integer constant (clang writes its value or its text), an array of no size that an initializer
completes, the operand of `typeof` (clang writes it as it prints it), a tag with no name (below),
and an old-style parameter's promoted type when it is a typedef name or an enum. A pointer
qualified `_Atomic` is spelled as clang spells it, `_Atomic(int *)`, its other qualifiers before
it and the outer parts around it.

An expression is a nested form named as `c_dump` names the nodes (`frontend/ARCHITECTURE_PARSER.md`
section 15), each with the place of its first token: an identifier with its name, an integer
constant with its value, the operator of a binary, assignment, unary or postfix node, a member and
its `.` or `->`, the type of a cast, a `sizeof` or `_Alignof` of a type, a compound literal and a
`va_arg`, and the keyword an alignment node keeps (`alignof` or `__alignof`).

Not compared, each for its reason:

- a tag body in a parameter of a function's own declarator (`int f(struct S { int a; } p);`), and
  any tag body in a declarator or a type name inside a function body: clang keeps the tag in the
  function or its scope and its JSON shows no node for it. The parser's side counts each one, by
  that reason, under `not compared` in the run's totals (`NOT_IN_PARAMETER`, `NOT_IN_BLOCK`). A
  tag body clang lists beside a declaration outside a function body is compared: in a nested
  declarator (`int (*fp)(struct P { int e; } q);`, a typedef's parameters, an array size) before
  the declaration's line, in an initializer's type name after it, in a record member's declarator
  before the field's line;
- the value of a floating constant, a character constant and a string literal: clang writes a
  value the parser does not compute;
- the inside of an initializer list: clang's tree holds its semantic form (members filled in,
  designators resolved), so a list is `(init_list@...)` on both sides;
- the designators of `__builtin_offsetof`: clang writes no path, so it is `(offsetof@...)`;
- attributes and an asm label: clang keeps them as attributes of the declaration, and strips none
  but the `__attribute__((...))` it writes into a type (`clang_type`);
- `_Alignas`, `__extension__` before a declaration, `_Noreturn`: no part of the type or the flags;
- the places of an unnamed parameter and of a declaration's first token: clang places them by its
  own rules;
- an asm statement's qualifiers, template and operands, which clang keeps as its own fields;
- the inside of a statement expression, `(stmt_expr@...)` on both sides;
- the attributes of a statement or a label;
- the implicit conversions clang inserts (`ImplicitCastExpr`, `ConstantExpr`): they are its
  semantics, and their one child stands for them; so does an anonymous member access clang adds.

A clang node the form has no name for is `(unknown <kind>@...)`, and a parser node the reduction
does not know is `(unknown <name>@...)`: either differs from the other side. Clang's
`__builtin_choose_expr` node is the parser's call of the builtin name, and both are written as the
call.

A difference that clang's semantics make stays a difference: the parser has no way to know it, and
the oracle does not hide it. Where clang's tree says why, the difference is counted under a named
cause (section 7). Other known ones, which the tree does not mark: a parameter of a function or
array typedef's type is adjusted to a pointer (`semantic.c`;
`va_list` is an array typedef); clang keeps the parentheses of an abstract declarator in an adjusted
parameter's type (`int ([4])` is `int (*)`); a typedef of `void` as the only parameter; an
attribute that changes a type (`mode`).

A tag with no name has a type clang names by its place and its owner (`struct (unnamed at ...)`,
`union S::(anonymous at ...)`, or the typedef name that names it), which the tree does not spell:
the parser writes `?` for it.

## 4. The unit entry {#unit}

`parse_unit` reads a unit with the parser's unit entry, `c_unit`. The parser stops at its first
error. A refusal of a construct it does not take (`<place>: <construct> is not parsed`) ends the unit
as `construct refused`, counted by the construct, which is no failure of the run; any other error -
malformed input, a token error, a directive the tokens refuse - is `parser refused`.

## 5. Verdicts {#verdicts}

A unit's verdict is the first of:

- `clang refused`: `clang -E` or the JSON dump fails, or the dump is no JSON; clang's first error
  line. Nothing is compared.
- `construct refused`: the parser refused a construct it does not take; its located message and
  the construct. Nothing is compared.
- `parser refused`: the parser stopped with an error that is no construct refusal; its located
  message.
- `differs`: a line where the parser's line does not match clang's, both kept with clang's named
  cause. The walk goes on past a pair of lines that name one entity, so each differing line is
  counted; a pair that names two entities, or a line past the other side's end (`(none)`), is the
  last difference, as the sides no longer align (`line_differences`).
- `same`: every line matches; the count of lines compared.

A set prints its units, each that differs with its first differences (`--show`), then its totals:
the units per verdict and how many of those that differ do so by named causes only, the lines
compared, the differing lines by cause (`unnamed` for none), and the refused constructs by name. The run fails on a unit the parser refused or one with a
difference no cause names.

## 6. The clang flags {#flags}

A unit is preprocessed by `clang -E` under Dumper A's flags for the `linux` dialect
(`dumper_frontend_flags` of `converter/dumper_a.das`: its triple, `-undef` and the predefined-macro
table as `-D`, `-funsigned-char`, `-w`, `-nostdinc` and the own headers), into `<work>/<unit>.i`,
line markers kept. Clang then dumps that output as JSON (`-Xclang -ast-dump=json -fsyntax-only`)
under the triple, `-undef` and `DUMPER_FLAGS`, so no macro is left to expand, and the parser reads
the same file.

## 7. Named causes {#causes}

A named cause explains one difference of one shape, and nothing else on the line. The clang side
marks a function declaration's line with the cause its tree states: `BuiltinAttr`, a library
function clang knows as a builtin, whose redeclaration has clang's own type, the builtin's merged
with the written one; or `previousDecl`, a function declared before, whose type is merged with the
earlier declaration's (that declaration's type rides on the line as `prior`). `explained_by`
accepts the cause for a differing line only when everything but the declaration's type is the same
on both sides - the name, the place, the flags, the parameter names and places, the initializer -
and the type differs in the cause's shape alone:

- a library builtin: the two types are the same once clang's own spellings are undone
  (`builtin_as_written`): `restrict` dropped from both, `__size_t` read as `size_t`, the decayed
  `struct __va_list_tag *` and `struct __jmp_buf_tag *` read as `va_list` and `jmp_buf`
  (`builtin.c`, `causes.c`);
- a redeclaration: clang's type is the earlier declaration's type as clang wrote it, so a
  definition `int m() {}` after `int m(void);` is `int (void)` (`semantic.c`, `causes.c`). A
  builtin's earlier declaration is clang's implicit one, so a builtin is held to its own shape.

Any other difference on such a line has no cause and counts as unnamed. A difference with a
cause is the only kind that lets the walk go on past its line, and its line names the same entity
on both sides, so a named cause never stops the comparison of the lines after it.

