# frontend Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
holds the part of the converter that reads C with no clang behind it. Today that is the libc
header set under `include/`; no converter code reads it: Dumper A resolves `<...>` in clang's own
system directories (`converter/ARCHITECTURE_DUMPER.md` section 3).

## 1. File charters

- `include/` - the own libc header set and its test (`include/ARCHITECTURE.md`). Never a `.das`
  module a converter pass requires.
- `REVIEW.das` - the mechanical gate of section 2, over every `.das` file under this folder.
- `tests/test_review_gate.das` - the gate's findings on stand-in files, one per ban.

## 2. No clang, no child process

A `.das` file under this folder runs where no clang is installed and no process may start: inside
a daslang compile, and in a web page. So it requires no `cbind`, the libclang binding of daScript's
`dasClangBind`, whose submodules are `cbind/<name>`; and it calls none of the daslang functions
that start a process: `popen`, `popen_binary`, `popen_timeout`, `popen_argv`, `popen_argv_pipe`,
`run_and_capture` (all of `fio`) and `system` (of `fio` and of `crt`).

The ban holds for what a file pulls in as well. `REVIEW.das` reads each `.das` file under the
folder line by line, a comment line aside, and follows every `require` that names a file: a path
ending in `.das`, or a module whose `<name>.das` sits beside the requiring file. It reports a
`require` of `cbind` and a call of one of the seven functions with the file and line, and for a
file outside this folder the file here that reaches it. A module that a module folder or daslib
resolves (`strings`, `daslib/fio`, `crt`) has no file beside the requirer and is not followed.
`include/tests/test_headers.das` requires `converter/emit.das` for the emitter's libc tables, and
the gate walks that file and the converter modules it requires.
