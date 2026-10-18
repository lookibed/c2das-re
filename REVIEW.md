# c2das-re Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`. Planned work: `docs/implementation_order.md`.

A file of these kinds, wherever the diff puts it, also answers to that folder's checklist: an
`addExtern` CRT binding - `dasCRuntime/`; a das implementation of a libc function, or an
annotation macro, that converted programs require - `c_runtime/`; a benchmark kernel -
`perf/`; a suite's `skip.txt` or `expected_pass.txt` - `suites/`.

**A diff whose code disagrees with a design document under `docs/` - a file that specifies what
the converter does, which a file recording findings or planned work (`probe-findings.md`,
`implementation_order.md`, `sidequest.md`) does not - under any dialect the converter's
`--target` flag selects, changes the code to match or adds a row for the disagreement to
`docs/probe-findings.md` in the same change.**

**A diff that adds a row to `docs/probe-findings.md` adds the probe under `probes/` or the
fixture under `converter/tests/fixtures/` that shows the disagreement.**

**A diff that makes the converter emit, or `c_runtime/` use, a kind of daslang expression or
declaration that no probe under `probes/` compiles and checks adds that probe in the same
change.**

**Never commit converted output - a test that compares against it records its hash.**

**A diff that adds a choice for one C project that the converter cannot derive from the C
source puts it in that project's `.c2das` sidecar, never in converter code.**

**A diff that adds C code under GPL-2 keeps it under `doom/`; C code anywhere else ships
under a permissive license.**

**A diff that makes this repository need a daScript module, configure flag, libclang version
or ast-grep version that `VERSIONS.md` does not record records it there and makes
`scripts/verify_daslang.sh` check it, in the same change.**

**Never edit a skill under `skills/` outside `skills/internal/` - fix it in daScript and run
`scripts/sync_daslang_skills.sh`.**

**A diff that adds a skill written for this repository puts it under `skills/internal/`.**
