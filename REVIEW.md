# c2das-re Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`. Planned work: `docs/implementation_order.md`.

A file or entry of these kinds, wherever the diff puts it, also answers to that folder's
checklist: an `addExtern` CRT binding - `dasCRuntime/`; a das implementation of a libc function,
or an annotation macro, that converted programs require - `c_runtime/`; a benchmark kernel -
`perf/kernels/`; a suite's `skip.txt` or `expected_pass.txt` - `suites/`; a suite's pin or the
`gcc:` line in `VERSIONS.md` - `suites/`; the `lua:` line in `VERSIONS.md` - `lua/`.

**A diff whose code disagrees with a `docs/` design file under `--target msvc` or `--target
linux` changes the code to match, or records the disagreement in `docs/probe-findings.md` as a
new row or as a clause in an existing row, in the same pull request.** A design file is any file
under `docs/` that does not record findings or planned work.

**A `docs/probe-findings.md` row or clause that records a disagreement between code and a
design file names, in that row's `Document line` cell, the passage the code contradicts.**

**A diff that changes code so it no longer does what a `docs/probe-findings.md` row's `Consumer`
cell says it does updates that cell in the same pull request.**

**A diff that adds a row, or a clause to an existing row, in `docs/probe-findings.md` adds, or
names in that row, the probe under `probes/` or the fixture under `converter/tests/fixtures/`
that shows what the added row or clause records, in the same pull request.**

**A diff that makes the converter emit, or `c_runtime/` use, a daslang form that no probe under
`probes/` compiles and asserts the result of adds that probe in the same pull request.** A form is an
operator or builtin-module function at its argument types, a cast or `reinterpret` between two
types, a literal, a statement shape, or a declaration of a type.

**Never commit converted output - a test that compares against it records its hash.**

**A diff that marks a row of `docs/implementation_order.md` done - a `Done` or `Landed` sentence
in the row - lists in the pull request body every C construct the item newly converts or converts
differently, each with the kernel under `perf/kernels/` or the ports program under `ports/` that
uses it.** A C construct is a kind of declaration, parameter, operator, call or statement.

**A diff that marks a row of `docs/implementation_order.md` done - a `Done` or `Landed` sentence
in the row - re-records `perf/results_linux.json` from a `scripts/run_perf.sh` run with no
`--filter` and no `--samples`, in the same pull request.**

**A diff that marks a row of `docs/implementation_order.md` done - a `Done` or `Landed` sentence
in the row - carries in the pull request body the `--report` output of its `scripts/run_perf.sh`
run, with the fix or a reason for every `FLAG` and every `SUSPECT` line.** Each reason names a
command a reviewer can rerun to confirm it.

**A pull request body that says in a sentence that the diff made a lane faster or slower shows, in
that body and in this order: the reference pass, the profile, and the predictions.** A lane is the
interpreter, JIT, AOT or exe; a table the body carries as tool output is not such a sentence. The
reference pass is how the Rust translator's
output and daslang's options, JIT and AOT flags treat the same C construct. The profile is a
`perf/sampler` profile of the native C build and of that lane, listing the top functions by self
time with each one's share and its lane-to-native ratio. The predictions put beside every measured
number the value predicted for it before the run, in the item's ledger row committed before the run
or in the dated predictions file the body names. A claim missing any of these is a
MAJOR finding, fixed by adding the missing part, not by dropping or weakening the claim.

**A diff that changes, beyond comments, the readability run's input - the C source or the id list
of a suite whose `expected_pass.txt` feeds the run, a kernel under `perf/kernels/`, or a Lua
program `lua/sources.das` lists - or a `.das` file under `converter/` outside `converter/tests/`
and `converter/benchmarks/`, or an annotation macro under `c_runtime/c_runtime/`, runs
`scripts/run_readability.sh --update` and says in the pull request body that the run was made and
whether it re-recorded `metrics/readability_linux.json` or left it unchanged.**

**A diff that adds C code under GPL-2 keeps it under a `doom/` folder at the repo root, created by
the first such diff; C code anywhere else ships under a permissive license.**

**A diff that makes any tool or test in the repository need something not in this repository - a
tool, a library, a daScript module or build flag, or a version of any of them - records it in
`VERSIONS.md` and makes a script refuse a mismatch with it, in the same pull request.**

**A diff that adds a skill written for this repository puts it under `skills/internal/`.**
