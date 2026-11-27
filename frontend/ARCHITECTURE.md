# frontend Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
holds the part of the converter that reads C with no clang behind it. Today that is the libc
header set under `include/`, the only libc Dumper A's clang reads (`-nostdinc` and this folder,
`converter/ARCHITECTURE_DUMPER.md` section 3), the macro definitions of section 3, which the
sidecar reader and Dumper A read, the first stages of Dumper C's preprocessor - the pp-token
lexer of section 4 and the directive layer of `ARCHITECTURE_PP.md` (sections 5 to 13: directives,
`#include`, the macro table, the ledgers) - and the first part of Dumper C's parser, which reads the
C tokens of a preprocessed unit, its expressions, type names, declarations, records, enums,
statements and function definitions (`ARCHITECTURE_PARSER.md`, sections 14 to 22, and
`ARCHITECTURE_STATEMENTS.md`, section 23), the type
table built from the parser's tree (`ARCHITECTURE_TYPES.md`, sections 24 to 28), and the
expressions with their conversions and the unit's C-IR walk (`ARCHITECTURE_EXPRS.md`, sections 29
to 36), with the names and places it gives (`ARCHITECTURE_NAMES.md`, sections 37 to 39), its
records, unions and enums (`ARCHITECTURE_RECORDS.md`, sections 41 to 47), and
the byte diff of two dumpers' C-IR (`ARCHITECTURE_DIFF.md`, section 40), and the record layout of
`ARCHITECTURE_LAYOUT.md` and `ARCHITECTURE_LAYOUT_MSVC.md` (sections 50 to 56). No converter pass
calls the preprocessor, the parser, the C-IR builder or the layout yet.

## 1. File charters

- `include/` - the own libc header set and its test (`include/ARCHITECTURE.md`). Never a `.das`
  module a converter pass requires.
- `c_defines.das` - the parser of a macro definition entry and the reader of a predefined-macro
  table (section 3), and where this folder's data lies: `predefined_path` and `own_include_dir`.
  The one `.das` module here a converter pass requires.
- `predefined/linux.defs`, `predefined/msvc.defs` - the predefined-macro table of each dialect.
- `pp_lexer.das` - the preprocessing-token lexer (section 4): translation phases 1 and 2, the
  pp-token rules, the placing of a token in its original file. Requires dasFlex's `flex/flex_macro`.
- `pp_directives.das` - the directive layer over the lexer (`ARCHITECTURE_PP.md`): the file
  providers, the `#include` stack and search, include guards, `#line`, the conditionals, the macro
  table, the pragma and pack ledgers, and the hook PP.4's `#if` evaluator fills. It expands no
  macro.
- `tests/test_pp_directives.das` - every directive over in-memory files, the predefined-macro table,
  and the own headers read through `fio`. The comparison with clang is `compare/pp/`'s `--pp2`.
- `c_tokens.das` - the C tokens of a preprocessed unit over the pp-lexer: keywords by symbol,
  pp-numbers classified, line markers read (`ARCHITECTURE_PARSER.md` section 14).
- `c_ast.das` - the tree in one node array and its one-line dump (section 15). No parsing.
- `c_parser.das` - the recursive-descent parser: the typedef-name table, type names and
  declarators, expressions, the errors and the nesting bound, declarations, records and enums,
  function definitions and the unit, statements (sections 16 to 23).
  One module, since the grammar's parts call each other.
- `c_types.das` - the C-IR type table of a unit (`ARCHITECTURE_TYPES.md`): the pool of types met,
  qualified ones apart, each use interning a type into `CirTu.types`, the specifiers, declarators
  and initializer-sized arrays, the typedef and tag scopes, a record's and an enum's entry with its
  layout. It writes `converter/cir.das`'s structures and requires no other converter module than
  `bit_units.das`, through `c_layout.das`.
- `c_records.das` - struct, union and enum definitions built into types, a tag's use bound to its
  definition, the walk that interns and anchors them, `dims` (`ARCHITECTURE_RECORDS.md`).
  `tests/test_c_records.das` - the table order, anchors, tag uses, library records, enums under
  both dialects, promotions, member access, `dims`, layout attributes, every refusal with its place.
- `c_exprs.das` - expressions as C-IR nodes with every conversion clang makes, the integer
  constant folder, the identifier scopes (`ARCHITECTURE_EXPRS.md` sections 29 to 35).
- `c_floats.das` - floating constants as Dumper A writes them, in das alone: big-integer rounding
  and the `%a` print (section 36).
- `c_ir.das` - the unit's C-IR: the walk over declarations, definitions and bodies in Dumper A's
  order, initializers, statements, the own headers' declarations, the names
  (`ARCHITECTURE_TYPES.md` sections 24 and 28, `ARCHITECTURE_EXPRS.md` sections 33 and 35,
  `ARCHITECTURE_NAMES.md`).
- `diff.das` - the byte diff of two C-IR texts, the macro fields and the producer set aside
  (`ARCHITECTURE_DIFF.md`). `tests/test_diff.das` - equal, macro-only and producer-only differences
  agree, any other reported at its line, a text the reader refuses named.
- `tests/test_c_exprs.das` - per conversion group its exact cast stream, the literals under both
  dialects, `sizeof`, initializers, every statement form, the table order, every refusal with its
  place. `tests/test_c_floats.das` - the hard floating constants against clang and the C library.
- `tests/test_c_types.das` - per type form its entry and spelling under both dialects, a unit's
  order through every statement form, typedefs, adjusted parameters, old-style definitions,
  unsized arrays, the own headers' declarations, and every refusal with its place. The comparison
  with Dumper A is `compare/types/`.
- `tests/test_c_parse_decl.das` - every declaration specifier, declarator and init-declarator form
  as a dumped tree, the typedef table's scope cases, the refusals and malformed declarations, the
  declarator nesting bound, and the allocation probe over the preprocessed own headers.
- `tests/test_c_parse_unit.das` - every record, enum, definition and file-scope form as a dumped
  tree, the tag and enumerator scopes, the old-style declaration list, a body's scope, the
  refusals and malformed input, the nesting bound of the record forms, and a whole unit of headers
  and a program with its allocation probe.
- `tests/test_c_parse_stmt.das` - every statement and GNU statement form as a dumped tree, the
  block and `for` scopes, the refusals and malformed statements, the nesting bound of the statement
  forms, and a unit with real bodies with its allocation probe.
- `c_layout.das` - the record layout of a dialect (`ARCHITECTURE_LAYOUT.md`, the `msvc` rules in
  `ARCHITECTURE_LAYOUT_MSVC.md`): a record's size, alignment and member bit offsets from a
  description of its members, and the record written into a C-IR type with the `packed` verdict of
  `converter/bit_units.das`, which it requires. It reads no C text: the type builder describes the
  record.
- `tests/test_c_layout.das` - every layout rule of both dialects with clang's numbers for a record
  of `compare/layout/fixtures/rules.c` or `fixtures/msvc/rules_msvc.c`, every refusal with its
  message, and the C-IR write with its `packed` verdicts. The comparison with clang over the
  corpora is `compare/layout/`.
- `tests/_preprocessed_headers.das` - the own headers as `clang -E` prints them, the text the
  parser tests read.
- `tests/test_c_tokens.das`, `tests/test_c_parse_expr.das` - every token class, keyword family and
  line-marker case; every expression and type-name form as a dumped tree, the ambiguities, every
  refusal and malformed input with its message, the nesting bound, and the allocation probes.
- `tests/test_pp_lexer.das` - every token class and edge case of section 4, the placing through
  splices, interning, and the no-allocation probe over a real header. The clang comparison lives
  outside this folder: `compare/pp/` (section 2).
- `tests/test_c_defines.das` - the parser and the reader, and that each table reads clean.
- `tests/_own_header_names.das` - `header_names`, the headers of `include/` as a program includes
  them, for the header tests of `include/tests/` and of `converter/tests/` (repo root); a `require`
  path cannot spell the folder `include`, a daslang keyword, so the helper is here.
- `REVIEW.das` - the mechanical gate of section 2, over every `.das` file under this folder.
- `tests/test_review_gate.das` - the gate's findings on stand-in files, one per ban.
  `tests/test_frontend_gate.das` (repo root) runs the gate itself, on this tree and on a stand-in
  root: a test that starts a process cannot live under this folder.

## 2. No clang, no child process

A `.das` file under this folder runs where no clang is installed and no process may start: inside
a daslang compile, and in a web page. So it requires no `cbind`, the libclang binding of daScript's
`dasClangBind`, whose submodules are `cbind/<name>`; and it names none of the daslang functions
that start a process: `popen`, `popen_binary`, `popen_timeout`, `popen_argv`, `popen_argv_pipe`,
`spawn_process`, `spawn_argv`, `with_process`, `run_and_capture`, `executable_on_path` (all of
`fio`; the last probes `PATH` through a shell) and `system` (of `fio` and of `crt`).

Nor does it require a native module: `crt`, the C runtime, or `c_runtime` and its modules, which
need it. Dumper C computes in das what the C library would (`ARCHITECTURE_EXPRS.md`'s floating
constants). The own headers' tests under `include/tests/` are the one exception: they compile
converted programs against the C runtime and are no part of Dumper C.

The ban holds for what a file pulls in as well. `REVIEW.das` reads each `.das` file under the
folder with its comments and the characters of its string and character literals blanked (the code
inside a string's `{...}` stays: it runs), and reports, each with the file and line:

- any of those names as a whole identifier, called or not: `x |> system`, `system (x)` and
  `@@system` are findings like `system(x)`, and so is a local or a field of such a name, which is
  renamed;
- a line that holds the word `require` and the word `cbind` anywhere; and a line that holds
  `require` and is not `require <module>` or `require <module> public`, `<module>` spelled in
  letters, digits, `_`, `.`, `/` and `-`, since the gate cannot name the module of any other form;
- a `require` of `crt`, of `c_runtime` or of one of its modules, outside `include/tests/`;
- the word `include`: the gate follows no text include, so a file here has none.

It follows every `require` that names a file, a path ending in `.das` or a module whose
`<name>.das` sits beside the requiring file, and names for a finding outside this folder the file
here that reaches it. Under the folder itself a file is a `.das` file, which is checked, or a `.h`
or `.md` file or a `.defs` table of `predefined/`, which hold no daslang; any other file (`.inc`,
`.das.inc`, a `.defs` elsewhere) is a finding, since daslang can load it as source and the gate
does not read it. A module that a module folder or daslib
resolves (`strings`, `daslib/fio`, `crt`, dasFlex's `flex/...`) has no file beside the requirer and
is not followed; dasFlex's `flex/` modules name no spawner and require no `cbind`.
`include/tests/test_headers.das` requires `converter/emit.das` for the emitter's libc tables, and
the gate walks that file and the converter modules it requires.

## 3. Macro definitions and the predefined-macro tables

A C program is preprocessed under macro definitions set before its first line, in this order: the
dialect's predefined macros, then the sidecar's `defines`; a later definition of a name replaces an
earlier one. Each is an entry `NAME`, `NAME=value` or `NAME(params)=value`, `NAME` alone meaning
`NAME=1` as `-DNAME` does, and `parse_define` of `c_defines.das` is the one parser of an entry: the
sidecar reader accepts a `defines` string by it, and the table reader a line.

A table is text, one entry a line as written, in a fixed order; an empty line and a line starting
with `#` are skipped. `read_predefined` refuses, naming the file and the line, a line that is no
entry (a blank at either end included) and a name a line above defines, and refuses a file that is
missing or holds no entry. `predefined_path` names a dialect's table and `own_include_dir` the
header set, both beside the module, so the converter finds them from wherever it runs.

The tables are every macro a frontend that reads them defines before the first line: Dumper A
runs clang under `-undef` and passes the entries as `-D` (`converter/ARCHITECTURE_DUMPER_MACROS.md`),
so both dumpers preprocess one input. They hold no name the preprocessor itself answers, which
`clang -E -dM` does not list and `-undef` does not drop: `__FILE__`, `__LINE__`, `__COUNTER__`,
`__DATE__`, `__TIME__`, `__FLT_EVAL_METHOD__`, `__has_include` and its kin. Their content follows
one rule: **a table never disagrees with clang.** Every entry has the
value the pinned clang predefines for that name under the dialect's triple with `-funsigned-char`
and no `-std` (so the language is clang's default, gnu17: `__STDC_VERSION__` is `201710L`), and
every name clang predefines there is an entry unless a class below excludes it. The one entry
clang does not define is `__STDC_NO_VLA__=1` (C11 6.10.8.3; `CONVERTER_ENTRIES`), the converter's own statement that it
lowers no variable-length array, so a program testing it (wasm3's `M3_HAS_VLA`) takes its
fixed-size path. The names `-undef` leaves defined (`__STDC__` under the `linux` triple only,
`__STDC_HOSTED__`, `__STDC_VERSION__`, `__STDC_UTF_16__`, `__STDC_UTF_32__`, the three
`__STDC_EMBED_` names) are entries with clang's values, so the tables state them for a reader
that is not clang. `converter/tests/test_predefined.das` holds the rule against clang, and
`include/tests/test_headers.das` holds every name the own headers read
(`include/ARCHITECTURE.md` section 5) to be an entry of both tables.

The `linux` table states the GNU dialect as clang states it under that triple: `__GNUC__=4`,
`__GNUC_MINOR__=2`, `__GNUC_PATCHLEVEL__=1`. The dialect is GNU C (gnu17, the builtins, the
attributes, case ranges), and a program that guards a layout attribute or a builtin by `__GNUC__`
(doomgeneric's `PACKEDATTR`) keeps the meaning a GNU compiler gives it; without the names it loses
`packed` with no error. `__clang__` is no entry, so a program's clang-only arm is never taken. The
`msvc` table has none of the three: clang defines no `__GNUC__` under that triple.

In the tables: the language's `__STDC` names, the platform (`__linux__`, `__unix__`, `__ELF__`,
`__x86_64__`; `_WIN32`, `_WIN64`, `_M_X64`), the data model and byte order, every size, width,
limit and type name (`__SIZEOF_INT__`, `__INT_MAX__`, `__SIZE_TYPE__`, `__SIZEOF_INT128__`), the
constant and format macros of the fixed-width types, and the floating-point parameters.

Excluded, by what the name states, each class a list of names and prefixes in the test:

| Class | Names | Why no entry |
|---|---|---|
| compiler identity and version | `__GNUC_STDC_INLINE__`, `__GXX_ABI_VERSION`, `__VERSION__`, `__clang__`, `__clang_*`, `__llvm__`, `_MSC_VER`, `_MSC_FULL_VER`, `_MSC_BUILD`, `_MSC_EXTENSIONS`, `_MSVC_*`, `_CRT_USE_BUILTIN_OFFSETOF`, `__CONSTANT_CFSTRINGS__`, `__PRAGMA_REDEFINE_EXTNAME`, `__GCC_ASM_FLAG_OUTPUTS__`, `__GCC_HAVE_DWARF2_CFI_ASM` | the input is read by two frontends and neither is clang, GCC or MSVC; a program that asks for one of these takes its other arm under both |
| code generation | `__NO_INLINE__`, `__NO_MATH_INLINES`, `__PIC__`, `__PIE__`, `__pic__`, `__pie__`, `__code_model_*`, `_M_FP_*`, `__REGISTER_PREFIX__`, `__USER_LABEL_PREFIX__`, `__GCC_CONSTRUCTIVE_SIZE`, `__GCC_DESTRUCTIVE_SIZE` | no machine code, symbol or cache line of clang's exists in a converted program |
| CPU features | `__SSE*`, `__MMX__`, `__FXSR__`, `__k8`, `__k8__`, `__tune_*`, `__SEG_*`, `__seg_*` | no intrinsic header is in the own set, and no intrinsic or segment is lowered |
| atomics | `__ATOMIC_*`, `__GCC_ATOMIC_*`, `__CLANG_ATOMIC_*`, `__GCC_HAVE_SYNC_COMPARE_AND_SWAP_*`, `__MEMORY_SCOPE_*` | a converted program has one thread, and the own set has no `<stdatomic.h>` |
| other languages | `__OBJC_*`, `__OPENCL_*` | the input is C |

## 4. The pp-token lexer {#pp-lexer}

`pp_lexer.das` turns one file's bytes into C11 preprocessing tokens (6.4), one at a time: `pp_open`
takes the bytes and a file id, `pp_next` reads the next token into `lx.tok` and answers false at the
end, and `pp_next_header_name` reads one token with a header name allowed, for the token after
`#include`. Nothing is materialized past the current token, so a directive line is read as tokens
as they come. A token is its kind (`PpTok`), the file id, its byte offset and length in the file as
read, its line and byte column (both from 1), `has_space`, `at_bol` and, for an identifier, its
symbol. Its bytes are read on request: `pp_spelling` builds the string, `pp_spelling_is` compares
in place.

The scanner is dasFlex's: `[flex(flags = true)]` builds the automaton when the module compiles and
gives the two flags; dasFlex is fetched at its `VERSIONS.md` pin into `fetch/dasFlex/` and loaded
as a module folder, never copied here. Nothing allocates per token. An identifier's rule interns
its bytes in the lexer's interner, which builds a name's string only when `pp_symbol_text` asks;
a token is fields of the lexer, rewritten by each `pp_next`. A name is one symbol for the whole life of
the lexer: `pp_open` on the next file keeps the interner, so the same name in two files has the same
symbol, and the file id is the caller's. A name spelled with a UCN and the same name in UTF-8 are
two symbols: the interner compares bytes.

### Translation phases 1 and 2 {#pp-phases}

`pp_open` skips a UTF-8 byte order mark at offset 0, as clang and gcc do: the first token keeps its
byte offset and column (4) and has no space. It replaces no trigraph, as clang does by default
under gnu17. A lone `\r` (no `\n` after it) is a newline to clang, in the line count and wherever a
newline ends a token, so `pp_open` turns it into `\n`, one byte for one. It removes every line
splice - a backslash, any blanks, then `\n`, `\r\n` or a lone `\r`; the blanks are clang's and gcc's
extension - before the scanner runs, since a scanner rule that skipped one would set `has_space`
and one that matched across it would need it in every pattern. A file with neither is lexed in
its own bytes: `pp_open` takes the array over (`<-`), and one byte of spare capacity
(`pp_read_file` leaves it) holds the scanner's end zero without a reallocation. A file with either
is copied once into a working buffer, and a table records, per removed splice, the file offset of
its backslash, the buffer offset where the bytes after it start and their offset in the file.

A token is placed back through that table: the splices before its first byte give its file offset
(the buffer offset plus their removed bytes) and its line (the buffer line plus their count, each
splice removing one newline); its column is the buffer column, or, when a splice lies on the same
buffer line before it, the distance from the byte after that splice's newline. The splices before
its last byte give its end, so a token split by a splice (`in\` newline `t`) is one token at the
offset of `i`, its length counting the splice. A token whose first byte comes right after a splice
starts at that splice's backslash, where clang places it. The table is walked forward with the tokens, so
placing costs no search; a file without splices pays a field copy per token.

### The rules {#pp-tokens}

The rule list is C11 6.4's pp-token grammar with clang's choices where the standard leaves one:

- an identifier takes ASCII letters, digits, `_`, `$`, UCNs and the UTF-8 code points of C11
  Annex D (D.2's not first), clang's C11 table; every identifier is IDENTIFIER, keywords included;
- a pp-number (6.4.8) is a digit or a dot and a digit, then digits, letters, `_`, dots, UCNs,
  Annex D code points and an exponent sign after `e`, `E`, `p` or `P`: `1..2`, `.5e`, `12abc` and
  `1é` are one token each, `1$` is `1` then `$`;
- a character constant takes the prefixes `L`, `u`, `U` (`u8'c'` is `u8` then `'c'` before C23)
  and one character at least, a string literal those prefixes and `u8`; a backslash escapes any
  one character, as clang lexes an unknown escape; an unterminated literal is one OTHER token to
  the end of its line, a backslash ending the file included, and `''` is one OTHER token, as in
  clang;
- a raw string literal, `R"delim(...)delim"` with the string prefixes, is one STRING_LITERAL, a
  newline inside it included: clang 22 takes it under gnu17. Its end repeats the delimiter, which
  no regular expression can match, so the `R"` rule's action reads the delimiter (up to 16
  printable ASCII bytes but a blank, `(`, `)` and `\`) and scans the bytes for `)delim"`. As in
  clang, a malformed delimiter makes the token OTHER through the next `"`, and a raw string nothing
  closes is OTHER to the end of the file;
- every punctuator of 6.4.6, `#` and `##` among them, and `::`, which clang 22 lexes as one token
  under gnu17, the longest first; the six digraphs, which clang takes under gnu17, have the kind of
  the punctuator they spell and keep their spelling;
- a header name only in `pp_next_header_name`'s condition, which ends with its token;
- a NUL byte is whitespace, as clang takes it;
- any other code point is one OTHER token (6.4p3), and a byte that starts no UTF-8 character is
  one too, with a diagnostic (`lx.diags`) at its file offset. dasFlex's `.` checks a lead byte and
  its count of continuation bytes, which is wider than valid UTF-8: it admits a surrogate
  (`ED A0..BF`), an overlong form (`E0 80..9F`, `F0 80..8F`) and a code point past U+10FFFF
  (`F4 90..BF`). The `.` rule's action checks the second byte after such a lead and cuts the token
  back to the lead, so each byte of the sequence is an OTHER token with a diagnostic, as clang
  splits it;
- an unterminated block comment ends the file with a diagnostic at its `/*`.

Two of clang's choices stay unfollowed. The identifier rule takes any UCN whole, so a UCN naming
a code point outside Annex D (`a\u00A0b`), or an Annex D.2 one (a combining mark) first
(`\u0301x`), is part of an identifier here, while clang makes that UCN an OTHER token of its own.
A line splice inside a raw string is removed here, while clang keeps the raw string's bytes as
written: the spelling differs, the token does not.

### The token flags across comments {#pp-flags}

`has_space` is set when any skipped text - whitespace, a newline or a comment - lies between a
token and the one before it: it is dasFlex's flag, the token's start against the previous token's
end. Clang's `LeadingSpace` differs after a newline, which clang does not count: a token first on
its line has `StartOfLine` and no `LeadingSpace` unless blanks precede it on that line. The oracle
maps the one onto the other (`compare/pp/ARCHITECTURE.md#flags`). `at_bol` is set for the first
token of a file and a token a newline separates from the previous one. A block comment is one space
(phase 3), so a newline inside it does not set `at_bol`: `x /*` newline `*/ # y` holds no directive
in clang or gcc. The `/*` rule's action skips the comment itself, scanning the bytes for `*/`, and
moves dasFlex's `prev_end_line` by the lines the comment spans, so the next token's line is
compared with the comment's last line. A comment opening after a newline still leaves the next
token at the start of its line, as the space it stands for would. The action leaves the start
condition alone, so a comment before a header name keeps `pp_next_header_name`'s condition; with no
`*/` it moves to the end of the file and stops the scanner as failed (dasFlex's `failed` and
`err`), its token still the `/*`, which `pp_next` places for the diagnostic.
