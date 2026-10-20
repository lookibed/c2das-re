# c2das-re Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`. Planned work: `docs/implementation_order.md`.

A file of these kinds, wherever the diff puts it, also answers to that folder's checklist: an
`addExtern` CRT binding - `dasCRuntime/`; a das implementation of a libc function, or an
annotation macro, that converted programs require - `c_runtime/`; a benchmark kernel - `perf/`; a
suite's `skip.txt` or `expected_pass.txt` - `suites/`; a suite's pin in `VERSIONS.md` -
`suites/`.

**A diff whose code disagrees with a `docs/` design file - one that is not a ledger of findings
or planned work (`probe-findings.md`, `implementation_order.md`, `sidequest.md`) - under any
`--target` dialect, changes the code to match or adds a `docs/probe-findings.md` row for the
disagreement, in the same change.**

**A diff that adds a row to `docs/probe-findings.md` adds the probe under `probes/` or the
fixture under `converter/tests/fixtures/` that shows what the row records.**

**A diff that makes the converter emit, or `c_runtime/` use, a daslang form that no probe under
`probes/` compiles and asserts the result of adds that probe in the same change.** A form is an
operator or builtin-module function at its argument types, a cast or `reinterpret` between two
types, a literal, a statement shape, or a declaration of a type.

**Never commit converted output - a test that compares against it records its hash.**

**A diff that closes a ledger item of `docs/implementation_order.md` (its commit subject starts
with the item's id) and changes what the converter emits adds a kernel under `perf/kernels/`
using the C constructs whose conversion it changes, or names in its commit message the kernel
that already uses them.**

**A diff that closes a `docs/implementation_order.md` item (its commit subject starts with the
item's id) re-records `perf/results_linux.json` from a `scripts/run_perf.sh` run with no `--filter` and no `--samples`
in the same change, and puts that run's `--report` output in its commit message with the reason
or the fix for every `FLAG` and every `SUSPECT` line it prints.**

**A diff that changes the command `run_exe` or `run_aot` in `converter/tiers.das` builds its
executable with re-records `perf/results_linux.json` from a `scripts/run_perf.sh` run with no
`--filter` and no `--samples` in the same change.**

**A diff that adds a choice for one C project that the converter cannot derive from the C
source puts it in that project's `.c2das` sidecar, never in converter code.**

**A diff that adds C code under GPL-2 keeps it under `doom/`; C code anywhere else ships
under a permissive license.**

**A diff that makes this repository need a daScript module, configure flag, libclang version
or ast-grep version that `VERSIONS.md` does not record records it there and makes
`scripts/verify_daslang.sh` check it, in the same change.**

**Never edit a vendored skill - a file `scripts/sync_daslang_skills.sh` lists as vendored, or
anything under `skills/daslang/` - fix it in daScript and re-run the script.**

**A diff that adds a skill written for this repository puts it under `skills/internal/`.**
