# frontend Architecture - directives and includes

Companion to `ARCHITECTURE.md` in this folder; section numbers are unique across the family.

## 5. The directive layer {#pp-directives}

`pp_directives.das` reads a translation unit as the pp-token lexer of section 4 hands out its
tokens, does every directive, and hands out the tokens of the active groups: `pp_start` opens the
main file, `pp_next_token` reads the next token into `pp.tok` and answers false at the end. No
macro is expanded: a token naming a macro is handed out as it is, for PP.3's expansion to replace.
A `#` that starts a line (`at_bol`) starts a directive, and the directive is read token by token
to the next token at the start of a line, which stays the lexer's current token and is marked
`pending` for the next read. So no line is ever materialized; a directive that needs its tokens
later (`#if`, `#pragma`, `#error`) copies them into `pp.line`, each a `PpHeld` whose spelling is
copied into the `pp.line_text` byte pool.

`pp.tok` is a `PpOutToken`: the lexer's `PpToken`, placed in its physical file, and beside it the
presumed line and file name `#line` gives it (`pline`, `pname`, an index of `pp.names`). PP.5's
expansion record extends this struct with the expansion place and the macro call. Directive
diagnostics (`pp.diags`) carry the physical place and the presumed one; the lexer's own
diagnostics stay in `pp.lx.diags`. An error never stops the preprocessor: `#error`, a missing
file and a malformed directive are recorded, and reading goes on, as clang reports every error of
a unit.

In a skipped group only the conditionals count: `#if`, `#ifdef` and `#ifndef` open a nested
conditional with no group to take, `#elif`, `#else` and `#endif` move or close one, and every
other line - a directive or not - is read and dropped. A conditional (`PpCond`) is `active` while
its current group is read and `taken` once a group was; a conditional opened inside a skipped
group starts taken, so none of its groups is read. Each file closes its own conditionals: one
still open at the end of its file is an error there, and an `#endif` cannot close an includer's.
The tokens after the directive name of `#ifdef`, `#ifndef`, `#else`, `#endif`, `#undef`, `#line`
and `#include` past what the directive takes are a warning and dropped. An unknown directive name
(`#ident` and `#assert` among them) is an error; a `#` alone on its line is the null directive; a
number after `#` is a GNU line marker, read as `#line` (section 10).

## 6. Starting a unit and the file provider {#pp-start}

A file is read through a `PpFileProvider`, a class with `exists(path)` and `read(path, bytes)`:
`PpFioProvider` reads the file system with `fio`, and `PpMemoryProvider` serves texts from a
table, so the tests need no files. No provider starts a process (section 2).

`pp_start` takes the provider, the main file, the predefined entries and the include path. The
entries (`parse_define`'s, in the order of section 3: the dialect table, then the sidecar's
`defines`) become the text of a buffer named `<built-in>`, one `#define` a line, which is read
before the main file's first line, as clang reads its predefines buffer. So the table's macros go
through the one `#define` path, and a macro defined there reports `<built-in>` as its file.

## 7. File identity {#pp-files}

A file is known by its path as the search built it, with `.` components and `name/..` pairs
removed (`normalized_path`): `"a.h"` and `"./a.h"` from one folder are one file, one `PpFile`,
one id. The id is the lexer's file id and the index of `pp.files`. A file keeps its quote
directory (its path's folder), the search folder it was found in, its `#pragma once` mark, its
include guard and how often it was entered. Two paths to one file through a link are two files:
the provider has no file identity to ask.

## 8. The include search {#pp-search}

`#include "name"` searches the includer's folder, then the include path in order; `#include
<name>` searches only the include path; an absolute name is itself. This is clang's order with
no `-iquote` folder: the quote folder is the current file's, never the folders of the files that
included it. `#include_next` searches the include path after the folder the current file was
found in; in the main file, or a file found by its quote folder or an absolute path, it searches
like `#include`, with clang's warning. A name found nowhere is an error naming every folder
searched, and the line after the directive is read.

`#include` reads its name with `pp_next_header_name`. A token that is no header name - a macro
naming the header - is left to PP.3: the directive's tokens are copied into `pp.line`, the
inclusion is recorded with `needs_expansion`, and an error names PP.3. `#line` whose number is a
name is left to PP.3 the same way.

Before a found file is opened, two checks skip it with no read: it said `#pragma once` and was
entered before, or its include guard (section 9) is a defined macro. Each `#include` of an active
group is a `PpInclusion` in `pp.inclusions`, with the file and the reason it was skipped, if it
was.

Opening a file suspends the current one: its lexer, with the token it stopped on, and its state
(the file id, the `#line` offset and name, the conditional depth it started at, its guard
progress) move into a `PpFrame` on `pp.frames`, and the one lexer opens the new file. The
interner moves back into the lexer at once, so a name has one symbol across every file; before a
file's bytes are freed at its end, the interner detaches from them. Nesting is clang's limit: the
main file and 199 included files open at once (`PP_MAX_INCLUDE_DEPTH`); the include past it is an
error and skipped.

## 9. Include guards {#pp-guards}

A file whose every token and directive lies inside one conditional opened by `#ifndef X`, `#if
!defined X` or `#if !defined(X)` - comments and blank lines aside - has the include guard `X`,
recorded on its `PpFile` at its end; a second `#include` of it is skipped unopened while `X` is
defined, as clang and gcc skip it. The file's progress is a state: at the start, inside the guard's
conditional, after its `#endif`, or no guard. A token, or a directive other than the guard's own
conditional ones, before the guard opens or after it closes ends the chance, and so does an
`#elif` or `#else` of the guard's conditional itself; a nested conditional inside the guard does
not. A file whose guard macro was `#undef`ed is read again.

## 10. `#line` {#pp-line}

`#line N` and `#line N "name"` make the line after the directive report line N, and the file
`name` when one is given, until the file ends; the file that included it keeps its own. The
offset `N - (the line of the directive's last token + 1)` is added to each later token's physical
line, so a block comment spanning lines inside the directive is not counted. N is a plain
digit sequence of at most 2147483647; the name's `\\` and `\"` are one character each. A GNU line
marker `# N "name" flags` does the same, its flags ignored.

## 11. The `#if` evaluator hook {#pp-if-hook}

`#if` and `#elif` copy their expression's tokens into `pp.line` and ask `eval_condition`, the one
place PP.4's evaluator goes. Until then it answers `0`, `1`, `defined X` and `defined(X)`, each
under any number of `!`; any other expression is an error naming PP.4 and false, so the group is
skipped. An `#elif` whose conditional already took a group evaluates nothing. `#ifdef`,
`#ifndef`, `#elifdef` and `#elifndef` ask the macro table now.

## 12. The macro table {#pp-macros}

`#define` stores a `PpMacro` in `pp.macros` and maps its name's symbol to it in `pp.macro_of`; an
`#undef` removes the mapping and leaves the definition, so a definition's index never changes for
PP.5 to record. The body is the definition's tokens, `count` of them in `pp.macro_body` from
`first`, each a `PpHeld` with its spelling in the `pp.macro_text` pool and its place, unexpanded.
A function-like macro is a name followed by `(` with no space; its parameters are symbols, and a
variadic one's last parameter is `__VA_ARGS__`, or the name of a GNU `name...`. The definition
is refused with an error for a missing or invalid name, `defined`, a malformed parameter list,
`##` at either end of the body, and a `#` in a function-like body before no parameter. A
redefinition that differs in parameters, spellings or the presence of whitespace between tokens
is a warning, and the new definition holds, as in clang.

`#pragma push_macro("X")` saves the current definition of `X`, none included, and
`#pragma pop_macro("X")` makes the last saved one current; neither is a ledger entry, as clang's
`-E` prints neither.

## 13. The pragma and pack ledgers {#pp-pragmas}

A `#pragma` is never dropped silently. `#pragma once` marks the file; `push_macro` and
`pop_macro` act on the macro table (section 12). `#pragma pack(...)` is a `PpPack` in
`pp.packs`: `pack(N)` sets, `pack()` resets to the target's default (0), `pack(push[, tag][,
N])` saves the current alignment, `pack(pop[, tag][, N])` restores the one saved last, or the one
saved with `tag` and every one after it, and `pack(show)` changes nothing; each entry keeps the
alignment in force after it (`current`) and the tokens handed out before it (`emitted`), which
places it among the declarations for the layout phase. N is 1, 2, 4, 8 or 16; any other form is a
warning and ignored. Every other pragma (`#pragma warning(...)`, `#pragma GCC ...`, `#pragma`
alone) is a `PpPragma` in `pp.pragmas`: its place, the tokens handed out before it, and its tokens
spelled with a blank where the source had space, for the C-IR's ledger.
