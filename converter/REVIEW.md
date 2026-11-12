# converter Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
docs: `ARCHITECTURE.md`, `ARCHITECTURE_DUMPER.md`, `ARCHITECTURE_DUMPER_MACROS.md`, `ARCHITECTURE_EMITTER.md`,
`ARCHITECTURE_EMITTER_AGGREGATES.md`, `ARCHITECTURE_EMITTER_CONTROL.md`,
`ARCHITECTURE_EMITTER_LOOPS.md`, `ARCHITECTURE_EMITTER_TEXT.md`, `ARCHITECTURE_EMITTER_MACROS.md`, `ARCHITECTURE_LINK.md`,
`ARCHITECTURE_LAYOUT.md`, `ARCHITECTURE_TIERS.md`. Planned work:
`docs/implementation_order.md`.

**A diff that changes `run_exe`, `run_aot`, `aot_link_command` or `native_module_sources` in
`tiers.das`, or `default_clang` in `dumper_a.das`, beyond comments re-records
`perf/results_linux.json` (repo root) from a `scripts/run_perf.sh` run with no `--filter` and no
`--samples`, in the same change.**

**A diff that adds a choice for one C project that the converter cannot derive from the C
source puts it in that project's `.c2das` sidecar, never in converter code.**

**A diff that makes the converter emit a form that runs faster under the interpreter in place
of a more idiomatic one, where no single form is both, keeps the idiomatic form as the default
and emits the faster one only under a converter option the `.c2das` sidecar can also set.**

**A diff that adds a converter option, or a new value of one that takes a fixed set of values,
covers each fixed value, and one setting of an open-valued option, with a test under `tests/`, in
the same change.** A converter option is a `main.das` flag or a `.c2das` key that changes
converted text.

**A diff that adds a converter option, or a new value of one that takes a fixed set of values,
adds a lane for each fixed value, and for one setting of an open-valued option, in the same
change: in `perf/results_linux.json` (repo root) for an option that changes one file's text, in a
lane `ports/publish.das` (repo root) captures for an option that changes a whole program's text.**

**A diff that adds a converter option, or a new value of one that takes a fixed set of values,
records `<suite>/<input>@<value>` entries in `metrics/readability_linux.json` (repo root) for each
fixed value, and for one setting of an open-valued option, in the same change.**

**A diff that adds a fixed-set converter option refuses any value outside the set, and a
diff that adds a `.c2das` key refuses an unknown key beside it, with an error naming the option or
key and the value - never a silent default.**

**A diff that adds a module name, or a name pattern, that the converter generates beyond one module
per C file refuses a C file whose module would take that name, with a test under `tests/`.**
