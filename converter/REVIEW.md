# converter Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
docs: `ARCHITECTURE.md`, `ARCHITECTURE_DUMPER.md`, `ARCHITECTURE_EMITTER.md`,
`ARCHITECTURE_EMITTER_AGGREGATES.md`, `ARCHITECTURE_EMITTER_CONTROL.md`, `ARCHITECTURE_EMITTER_LOOPS.md`, `ARCHITECTURE_LINK.md`, `ARCHITECTURE_LAYOUT.md`. Planned work: `docs/implementation_order.md`.

**A diff that changes `run_exe`, `run_aot`, `aot_link_command` or `native_module_sources` in
`tiers.das`, or `default_clang` in `dumper_a.das`, beyond comments re-records
`perf/results_linux.json` (repo root) from a `scripts/run_perf.sh` run with no `--filter` and no
`--samples`, in the same change.**

**A diff that adds a choice for one C project that the converter cannot derive from the C
source puts it in that project's `.c2das` sidecar, never in converter code.**

**A diff that makes the converter emit a form that runs faster under the interpreter in place
of a more idiomatic one, where no single form is both, keeps the idiomatic form as the default
and emits the faster one only under a converter option the `.c2das` sidecar can also set.**

**A diff that adds a converter option, or a value of one, that changes converted text covers
each value with a test under `tests/`, a lane in `perf/results_linux.json` (repo root) and its
keys in `metrics/readability_linux.json` (repo root), in the same change.**
