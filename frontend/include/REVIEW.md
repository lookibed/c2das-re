# frontend/include Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`.

**Never weaken `tests/test_headers.das` or the scanner `tests/_header_scan.das` - fix the header
they flag instead.**

**A diff that adds a name to `GLIBC_ALIASES`, `STDOUT_HELPERS` or `DIRECTIVE_PIECES` in
`tests/test_headers.das` states in `ARCHITECTURE.md` section 2 why that name has no prototype, in
the same change.**

**A diff that adds a base type to `BASE_TYPES` in `tests/_header_scan.das` maps it to the das type
the `crt` module binds a value of that C type as, and to `UNBOUND` only when no `crt` function
takes or returns it.**

**A diff that adds a macro whose expansion calls a function or a `__builtin_` name adds it only
when `converter/emit.das` (repo root) maps the called name - a macro over a name nothing lowers is
a defect.**

**A diff that adds a macro, a typedef or a record with no bound function behind it names in the
pull request the suite test or converted project that uses it.** A header grows on demand.

**A diff that adds or changes a macro value, a typedef or a record gives it glibc's value, type
and layout on linux x86_64 under both dialects, spelling a 64-bit integer type `__INT64_TYPE__`.**
The `crt` module binds the host libc.

**A diff that adds a name to `PREDEFINED` in `tests/test_headers.das` adds it to the table of
`ARCHITECTURE.md` section 5, with its value under each dialect, in the same change.**

**A diff to a header reports in the pull request the result of compiling every header alone and
all headers together with the pinned clang under both dialect triples: `-nostdinc -I
frontend/include -fsyntax-only -std=c99 -funsigned-char -Wall -Wextra -pedantic`, no diagnostic.**
