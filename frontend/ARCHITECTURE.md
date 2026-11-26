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
  `tests/test_frontend_gate.das` (repo root) runs the gate itself, on this tree and on a stand-in
  root: a test that starts a process cannot live under this folder.

## 2. No clang, no child process

A `.das` file under this folder runs where no clang is installed and no process may start: inside
a daslang compile, and in a web page. So it requires no `cbind`, the libclang binding of daScript's
`dasClangBind`, whose submodules are `cbind/<name>`; and it names none of the daslang functions
that start a process: `popen`, `popen_binary`, `popen_timeout`, `popen_argv`, `popen_argv_pipe`,
`spawn_process`, `spawn_argv`, `with_process`, `run_and_capture`, `executable_on_path` (all of
`fio`; the last probes `PATH` through a shell) and `system` (of `fio` and of `crt`).

The ban holds for what a file pulls in as well. `REVIEW.das` reads each `.das` file under the
folder with its comments and the characters of its string and character literals blanked (the code
inside a string's `{...}` stays: it runs), and reports, each with the file and line:

- any of those names as a whole identifier, called or not: `x |> system`, `system (x)` and
  `@@system` are findings like `system(x)`, and so is a local or a field of such a name, which is
  renamed;
- a line that holds the word `require` and the word `cbind` anywhere; and a line that holds
  `require` and is not `require <module>` or `require <module> public`, `<module>` spelled in
  letters, digits, `_`, `.`, `/` and `-`, since the gate cannot name the module of any other form;
- the word `include`: the gate follows no text include, so a file here has none.

It follows every `require` that names a file, a path ending in `.das` or a module whose
`<name>.das` sits beside the requiring file, and names for a finding outside this folder the file
here that reaches it. Under the folder itself a file is a `.das` file, which is checked, or a `.h`
or `.md` file, which holds no daslang; any other file (`.inc`, `.das.inc`) is a finding, since
daslang can load it as source and the gate does not read it. A module that a module folder or daslib
resolves (`strings`, `daslib/fio`, `crt`) has no file beside the requirer and is not followed.
`include/tests/test_headers.das` requires `converter/emit.das` for the emitter's libc tables, and
the gate walks that file and the converter modules it requires.
