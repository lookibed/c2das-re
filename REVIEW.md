# c2das-re Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`. Planned work: `docs/implementation_order.md`.

A file or entry of these kinds, wherever the diff puts it, also answers to that folder's
checklist: an `addExtern` CRT binding - `dasCRuntime/`; a das implementation of a libc function,
or an annotation macro, that converted programs require - `c_runtime/`; a benchmark kernel -
`perf/`; a suite's `skip.txt` or `expected_pass.txt` - `suites/`; a suite's pin in
`VERSIONS.md` - `suites/`.

**A diff whose code disagrees with a `docs/` design file under `--target msvc` or `--target
linux` changes the code to match, or adds a `docs/probe-findings.md` row for the disagreement,
in the same change.** A design file is any file under `docs/` that does not record findings or
planned work.

**A diff that changes code so it no longer does what a `docs/probe-findings.md` row's `Consumer`
cell says it does updates that cell in the same change.**

**A diff that adds a row to `docs/probe-findings.md` adds, or names in the row, the probe under
`probes/` or the fixture under `converter/tests/fixtures/` that shows what the row records, in
the same change.**

**A diff that makes the converter emit, or `c_runtime/` use, a daslang form that no probe under
`probes/` compiles and asserts the result of adds that probe in the same change.** A form is an
operator or builtin-module function at its argument types, a cast or `reinterpret` between two
types, a literal, a statement shape, or a declaration of a type.

**Never commit converted output - a test that compares against it records its hash.**

**A diff that closes a `docs/implementation_order.md` item (its commit subject starts with the
item's id) adds a kernel under `perf/kernels/` for every C construct whose conversion it
changes, or names in its commit message the kernel that already uses that construct.** A C
construct is a kind of declaration, parameter, operator, call or statement.

**A diff that closes a `docs/implementation_order.md` item (its commit subject starts with the
item's id) re-records `perf/results_linux.json` from a `scripts/run_perf.sh` run with no
`--filter` and no `--samples`, in the same change.**

**A diff that closes a `docs/implementation_order.md` item (its commit subject starts with the
item's id) puts in its commit message the `--report` output of the `scripts/run_perf.sh` run
that re-recorded `perf/results_linux.json`, with the fix or a reason for every `FLAG` and every
`SUSPECT` line in it; each reason names a command a reviewer can rerun to confirm it.**

**A diff that changes `run_exe`, `run_aot`, `aot_link_command` or `native_module_sources` in
`converter/tiers.das` beyond comments re-records `perf/results_linux.json` from a
`scripts/run_perf.sh` run with no `--filter` and no `--samples`, in the same change.**

**A diff that changes a `.das` file under `converter/` outside `converter/tests/` and
`converter/benchmarks/`, an annotation macro under `c_runtime/c_runtime/`, a suite's pin in
`VERSIONS.md`, what `csmith_program` (`suites/csmith/generate.das`) writes for a seed, the C
text of a kernel under `perf/kernels/`, or the prologue or epilogue `perf/perf_compose.das` puts
around a kernel, beyond comments, re-records `metrics/readability_linux.json` with
`scripts/run_readability.sh --update` in the same change and puts the table that run prints in
its commit message.**

**A diff that adds a choice for one C project that the converter cannot derive from the C
source puts it in that project's `.c2das` sidecar, never in converter code.**

**A diff that chooses between a converted form that runs faster under the interpreter and a
more idiomatic one, where no single form gives both, emits the idiomatic form by default and
the faster one under an opt-in converter flag that the `.c2das` sidecar can also set, and
covers each form with a test preflight runs, a column of its own in the perf report and a key
in the readability capture, in the same change.** The ruling of 2026-10-20 in
`docs/very-detailed-plan.md`, decision "Speed vs idiomatic output".

**A diff that adds C code under GPL-2 keeps it under `doom/` (repo root); C code anywhere else ships
under a permissive license.**

**A diff that makes this repository need a daScript module, configure flag, libclang version
or ast-grep version that `VERSIONS.md` does not record records it there and makes
`scripts/verify_daslang.sh` check it, in the same change.**

**Never edit a vendored skill - a file `scripts/sync_daslang_skills.sh` lists as vendored, or
anything under `skills/daslang/` - fix it in daScript and re-run the script.**

**A diff that adds a skill written for this repository puts it under `skills/internal/`.**
