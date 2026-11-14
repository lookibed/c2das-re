# compare Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture doc:
`ARCHITECTURE.md`. Planned work: `docs/implementation_order.md` (sec. P8).

**A diff that adds a number to a comparison table (a count, a time, a ratio, a readability total)
writes it from the capture the table's generator reads, never by hand.** A hand-typed number goes
stale with the next capture.

**A diff to the block of `docs/rust-comparison.md` between `<!-- compare:begin -->` and
`<!-- compare:end -->` is the output of `compare/run.das --readme` over the committed capture,
never a hand edit.** The next `--readme` run overwrites a hand edit without a trace.

**A diff that runs the Rust translator on an input records every input it does not pass as one of
`refused` (the translator failed), `compile` (daslang rejected the output), `exit` (the run exited
otherwise than the oracle), `output` (the run printed otherwise than the oracle), `timeout`,
`native` (a csmith seed's native reference failed), `crash` (a worker ended without a verdict)
or `skipped` (a lane the harness cannot run, its reason recorded), never drops it.** A dropped
input inflates the Rust side's pass rate.

**A diff that adds a time or ratio of this repository's output to the perf comparison takes it
from the run that timed the Rust side, never from a capture under `perf/` (`results_linux.json`,
`results_method_linux.json`).** Two runs on different days time two states of the machine.

**A diff to the perf comparison keeps every kernel and every lane in the capture: a lane without a
cell is an `{"error": ...}` entry, a refused translation a `refused` entry - never drop either.** A
dropped lane hides a side's failure from the table.

**A diff to `tests/` never builds the Rust translator (no `cargo`, no `scripts/build_c2das_rust.sh`
from the repo root) and never runs the binary `rust_binary` names; it runs a stand-in script the
test writes instead.**

**A test that runs `run.das --lua` passes `--lua-from` and `--out`, both naming a scratch folder the
test writes, never Lua's release or `results_linux.json`.** Without them the run reads the fetched
release, which a clean checkout lacks, and rewrites the committed capture.

**Never commit a file under `work/` (a translation, a compilation database, a run's scratch) -
write it there and keep `/compare/work/` in `.gitignore` (repo root) instead.**

**A diff to the suites comparison never writes a file under `suites/` (a csmith program, a
build, a verdict) - write it under `work/<suite>/<id>/` instead.**

**A table or report a diff adds never sets the numbers of two boxes side by side as a ratio.**
`perf/ARCHITECTURE.md` section 5 states the box a capture records.

**A speedup a diff claims is the branch against main before it, measured on one box in one run.**
`perf/ARCHITECTURE.md` section 5 states that a number carries its box.

**A diff that adds a table rendered from a capture labels its provenance line with
`perf/boxes.das`'s `capture_label`.** `perf/ARCHITECTURE.md` section 5 states the label.
