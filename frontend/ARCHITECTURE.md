# frontend Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
holds the part of the converter that reads C with no clang behind it. Today that is the libc
header set under `include/`, which no converter code reads (Dumper A resolves `<...>` in clang's
own system directories, `converter/ARCHITECTURE_DUMPER.md` section 3), and the macro definitions
of section 3, which the sidecar reader and Dumper A do read.

## 1. File charters

- `include/` - the own libc header set and its test (`include/ARCHITECTURE.md`). Never a `.das`
  module a converter pass requires.
- `c_defines.das` - the parser of a macro definition entry and the reader of a predefined-macro
  table (section 3). The one `.das` module here a converter pass requires.
- `predefined/linux.defs`, `predefined/msvc.defs` - the predefined-macro table of each dialect.
- `tests/test_c_defines.das` - the parser and the reader, and that each table reads clean.
- `REVIEW.das` - the mechanical gate of section 2, over every `.das` file under this folder.
- `tests/test_review_gate.das` - the gate's findings on stand-in files, one per ban.

## 2. No clang, no child process

A `.das` file under this folder runs where no clang is installed and no process may start: inside
a daslang compile, and in a web page. So it requires no `cbind`, the libclang binding of daScript's
`dasClangBind`, whose submodules are `cbind/<name>`; and it names none of the daslang functions
that start a process: `popen`, `popen_binary`, `popen_timeout`, `popen_argv`, `popen_argv_pipe`,
`run_and_capture` (all of `fio`) and `system` (of `fio` and of `crt`).

The ban holds for what a file pulls in as well. `REVIEW.das` reads each `.das` file under the
folder with its comments and the characters of its string and character literals blanked (the code
inside a string's `{...}` stays: it runs), and reports, each with the file and line:

- any of the seven names as a whole identifier, called or not: `x |> system`, `system (x)` and
  `@@system` are findings like `system(x)`, and so is a local or a field of such a name, which is
  renamed;
- a line that holds the word `require` and the word `cbind` anywhere; and a line that holds
  `require` and is not `require <module>` or `require <module> public`, `<module>` spelled in
  letters, digits, `_`, `.`, `/` and `-`, since the gate cannot name the module of any other form;
- the word `include`: the gate follows no text include, so a file here has none.

It follows every `require` that names a file, a path ending in `.das` or a module whose
`<name>.das` sits beside the requiring file, and names for a finding outside this folder the file
here that reaches it. Under the folder itself a file is a `.das` file, which is checked, or a `.h`
or `.md` file or a `.defs` table of `predefined/`, which hold no daslang; any other file (`.inc`,
`.das.inc`, a `.defs` elsewhere) is a finding, since daslang can load it as source and the gate
does not read it. A module that a module folder or daslib
resolves (`strings`, `daslib/fio`, `crt`) has no file beside the requirer and is not followed.
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
missing or holds no entry. `predefined_path` names a dialect's table beside the module, so the
converter finds it from wherever it runs.

The tables are the whole set of predefined macros: a compiler that reads them drops its own
(`clang -undef`, `converter/ARCHITECTURE_DUMPER_MACROS.md`), so both dumpers preprocess one
input. Their content follows one rule: **a table never disagrees with clang.** Every entry has the
value the pinned clang predefines for that name under the dialect's triple with `-funsigned-char`
and no `-std` (so the language is clang's default, gnu17: `__STDC_VERSION__` is `201710L`), and
every name clang predefines there is an entry unless a class below excludes it. The one entry
clang does not define is `__STDC_NO_VLA__=1` (C11 6.10.8.3), the converter's own statement that it
lowers no variable-length array, so a program testing it (wasm3's `M3_HAS_VLA`) takes its
fixed-size path. The names `-undef` leaves defined (`__STDC__` under the `linux` triple only,
`__STDC_HOSTED__`, `__STDC_VERSION__`, `__STDC_UTF_16__`, `__STDC_UTF_32__`, the three
`__STDC_EMBED_` names) are entries with clang's values, so the tables state them for a reader
that is not clang. `converter/tests/test_predefined.das` holds the rule against clang, and
`include/tests/test_headers.das` holds every name the own headers read
(`include/ARCHITECTURE.md` section 5) to be an entry of both tables.

In the tables: the language's `__STDC` names, the platform (`__linux__`, `__unix__`, `__ELF__`,
`__x86_64__`; `_WIN32`, `_WIN64`, `_M_X64`), the data model and byte order, every size, width,
limit and type name (`__SIZEOF_INT__`, `__INT_MAX__`, `__SIZE_TYPE__`, `__SIZEOF_INT128__`), the
constant and format macros of the fixed-width types, and the floating-point parameters.

Excluded, by what the name states, each class a list of names and prefixes in the test:

| Class | Names | Why no entry |
|---|---|---|
| compiler identity and version | `__GNUC__` and its parts, `__GNUC_STDC_INLINE__`, `__GXX_ABI_VERSION`, `__VERSION__`, `__clang__`, `__clang_*`, `__llvm__`, `_MSC_VER`, `_MSC_FULL_VER`, `_MSC_BUILD`, `_MSC_EXTENSIONS`, `_MSVC_*`, `_CRT_USE_BUILTIN_OFFSETOF`, `__CONSTANT_CFSTRINGS__`, `__PRAGMA_REDEFINE_EXTNAME`, `__GCC_ASM_FLAG_OUTPUTS__`, `__GCC_HAVE_DWARF2_CFI_ASM` | the input is read by two frontends and neither is GCC or MSVC; a program that asks takes its portable arm under both |
| code generation | `__NO_INLINE__`, `__NO_MATH_INLINES`, `__PIC__`, `__PIE__`, `__pic__`, `__pie__`, `__code_model_*`, `_M_FP_*`, `__REGISTER_PREFIX__`, `__USER_LABEL_PREFIX__`, `__GCC_CONSTRUCTIVE_SIZE`, `__GCC_DESTRUCTIVE_SIZE` | no machine code, symbol or cache line of clang's exists in a converted program |
| CPU features | `__SSE*`, `__MMX__`, `__FXSR__`, `__k8`, `__k8__`, `__tune_*`, `__SEG_*`, `__seg_*` | no intrinsic header is in the own set, and no intrinsic or segment is lowered |
| atomics | `__ATOMIC_*`, `__GCC_ATOMIC_*`, `__CLANG_ATOMIC_*`, `__GCC_HAVE_SYNC_COMPARE_AND_SWAP_*`, `__MEMORY_SCOPE_*` | a converted program has one thread, and the own set has no `<stdatomic.h>` |
| other languages | `__OBJC_*`, `__OPENCL_*` | the input is C |
