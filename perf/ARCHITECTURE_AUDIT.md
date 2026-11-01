# perf Architecture - the interpreter audit on Lua

Companion to `ARCHITECTURE.md` in this folder, whose contract and kernel shape bind it. The
audit finds what makes converted Lua slow under the interpreter, one construct at a time: each
construct of the converted VM sits alone in a small kernel, and the kernel's module is timed as
the converter writes it and as the spelling a fix would write, so the two times give that
construct's own cost. The audit changes no converter output: a construct that costs is a ledger
row for a fix.

## 1. File charters

- `kernels/audit/<name>.c` - one kernel per construct family, in the kernel shape of
  `ARCHITECTURE.md` section 1 (a `volatile` static read on every call, no `main`, no
  `#include`, no expected result), each modelled on the Lua function its first comment names.
  The inner loop's input depends on the outer loop's counter, so clang cannot hoist the work
  out of the rep loop. The folder is no kernel list `c_file_ids` reads for `run.das`, the
  readability metric or `compare/`.
- `audit_constructs.das` - the constructs (`constructs()`): each its kernel, the name of its
  alternative spelling, the text whose occurrences count its sites in Lua, and the rewrite of
  the converted module into the alternative spelling; `site_counts`, the sites per hot module.
  A rewrite fails, naming the text it did not find, when the converter's output no longer holds
  that text, so a stale rewrite is an error cell, never a silent no-op.
- `audit_tables.das` - the construct table and the whole-benchmark table of a capture, and
  `BENCHES`, the four Lua benchmarks with the argument each runs with here. It measures nothing
  and reads no file.
- `audit_lua.das` - the driver: every kernel measured (section 2), the sites counted, the
  benchmarks timed, the capture written to `audit_linux.json` (or `--out`) and both tables
  printed; `--table` renders a stored capture, `--filter` names kernels, `--no-benches` leaves
  the benchmarks out, `--lua-work` names the folder `lua/run.das` converted Lua into.
- `audit_linux.json` - the committed capture: the machine, the versions, the Rust translator's
  commit, per kernel the native cell, the `converted` interpreter and JIT cells, one entry per
  alternative spelling with its two cells, and the Rust entry; the sites; the benchmarks.
- `tests/test_audit.das` - the rewrites on small texts, every rewrite applied to its kernel's
  real conversion, the site count, both tables over a fixture capture, and the driver as a child
  process: `-?`, one sample of `sizeof_scale`, `--table`.

## 2. The method

Each kernel is composed by the dasProfile method (`perf_compose.das`'s
`composed_method_source`: the steady clock, the `volatile` sink, the 0.5 s budget), because the
Rust translator lowers `clock_gettime` but refuses `clock`. The native build of that program is
the oracle; our conversion (`linux`, single file, so the layout plays no part) runs under the
interpreter and the JIT; each construct's rewrite of the same module runs under both; every
cell is perf's (`perf_measure.das`: each sample its own process, the median, the result checked
against native), with a 120 s sample limit. A construct's cost is the converted time over the
rewritten time on one tier. Under the JIT a rewrite that drops a `volatile` lets LLVM move the
kernel's work out of the budget loop; a rewritten cell under a tenth of native is shown as
`SUSPECT`, a different program, not a cost.

`[c_function]` is no construct here: the annotation wraps the body in `unsafe` before inference
and leaves no runtime form (`c_runtime/ARCHITECTURE.md`), so a module without it is the same
program; the call it sits on is the construct (`small_call`, the call inlined by hand).

The Rust side is the same composed program through `compare/rust_translator.das`'s
`translate_file` (`--libc std --strict`, `-DC2DAS_NATIVE`), timed under the interpreter only:
the translator drops a file-scope `volatile`, so its JIT cells measure what the optimizer leaves
(`compare/ARCHITECTURE.md` section 8). A translation it refuses is `refused` with its error.

A construct's sites are the occurrences of its text in the scc layout's fragments of the four
modules the benchmarks spend their time in (`lvm`, `ltable`, `lgc`, `ldo`), counted in the text,
not at run time: a count says how often the construct is written, not how often it runs, so a
site count beside a cost is a weight for choosing fixes, not a measured share of a benchmark.

The benchmarks run whole, each sample its own process timed by the wall clock after one
unmeasured run that fills the module cache, so a cell holds the program's load as well as its
work: the native build `lua/work/lua_native`, and the converted interpreter under daslang's
interpreter in the scc and in the source layouts. The source layout over the scc layout is the
cost of the calls the source layout late-binds through `lua_link.das` and nothing else, since
the two layouts hold the same functions. A benchmark's factor over native and a construct's
sites in the same modules correlate; they prove nothing about each other.
