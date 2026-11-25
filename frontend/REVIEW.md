# frontend Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`.

**Never weaken `REVIEW.das` - fix what it flags instead.**

**A diff that makes a `.das` file under this folder require a module that has no `<name>.das`
beside that file, other than a daslib module and `crt`, reads that module's source: a module that
requires `cbind`, or names `popen`, `popen_binary`, `popen_timeout`, `popen_argv`,
`popen_argv_pipe`, `run_and_capture` or `system`, is never required here - do the work in das
instead.** `REVIEW.das` follows only a `require` that names a file.
