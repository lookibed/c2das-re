# frontend Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`.

**Never weaken `REVIEW.das` - fix what it flags instead.**

**A diff that makes a `.das` file under this folder require a module that has no `<name>.das`
beside that file, other than a daslib module and `crt`, reads that module's source: a module that
requires `cbind`, or names `popen`, `popen_binary`, `popen_timeout`, `popen_argv`,
`popen_argv_pipe`, `spawn_process`, `spawn_argv`, `with_process`, `run_and_capture`,
`executable_on_path` or `system`, is never required here - do the work in das
instead.** `REVIEW.das` follows only a `require` that names a file.

**A diff that adds a file under this folder adds a `.das`, a `.h` or a `.md` file, or a `.defs`
table under `predefined/`, and writes
every module dependency as a line `require <module>` or `require <module> public` - never an
`include`, and never a `require` of another form.** `REVIEW.das` reads no other file and can name
the module of no other line, so it reports both.
