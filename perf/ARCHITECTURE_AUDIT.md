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
  A loop-carried accumulator, or an inner input that depends on the outer loop's counter, keeps
  clang from hoisting the work out of the rep loop. The folder is no kernel list `c_file_ids` reads for `run.das`, the
  readability metric or `compare/`.
- `audit_constructs.das` - the constructs (`constructs()`): each its kernel, the name of its
  alternative spelling, the text whose occurrences count its sites in Lua, and the rewrite of
  the converted module into the alternative spelling; `site_counts`, the sites per hot module.
  A rewrite fails, naming the text it did not find, when the converter's output no longer holds
  that text, so a stale rewrite is an error cell, never a silent no-op.
- `audit_tables.das` - the construct table and the whole-benchmark table of a capture, and
  `BENCHES`, the startup row and the four Lua benchmarks with the argument each runs with here. It measures nothing
  and reads no file.
- `audit_lua.das` - the driver: every kernel measured (section 2), the sites counted, the
  benchmarks timed, the capture written to `audit_linux.json` (or `--out`) and both tables
  printed; `--table` renders a stored capture, `--filter` names kernels, `--no-benches` leaves
  the benchmarks out, `--benches-only` times the benchmarks alone into the stored capture,
  `--lua-work` names the folder `lua/run.das` converted Lua into.
- `audit_linux.json` - the committed capture, a one-off: it is re-recorded by hand when a kernel
  or a rewrite changes, and the `results_linux.json` rules of `REVIEW.md` (the `--report` text,
  the `FLAG` lines, the re-record duty) do not apply to it. It holds the machine, the versions,
  the Rust translator's commit, per kernel the native cell, the `converted` interpreter and JIT
  cells, one entry per alternative spelling with its two cells, and the Rust entry; the sites;
  the benchmarks.
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
interpreter in the scc and in the source layouts. The startup row (`-e "print(1)"`) times the
load alone; a benchmark's net time is its time less the startup row's in the same lane, and the
net factors are what the table compares, since the warm module cache still leaves the two
layouts' load seconds apart. The source layout's net time over the scc layout's is the cost of
the calls the source layout late-binds through `lua_link.das`, since the two layouts hold the
same functions. A benchmark's factor over native and a construct's
sites in the same modules correlate; they prove nothing about each other.

## 3. What the capture says

The committed capture is from the Ryzen 7 7435HS, while other jobs shared the machine, five
samples per kernel lane. Six constructs cost under the interpreter, each measured as the converted
time over the rewrite's: the `_flag` switch chain 2.08x (419x native as converted; the Rust
translation's computed `goto` dispatch runs the same kernel at 23.9x native), the wrap casts
`int64(uint64(a) op uint64(b))` 2.10x, the `int64(x != 0 ? 1 : 0) != 0` test 1.58x, `addr((p +
i).f)` on a stack slot 1.53x, `c_volatile_load` 1.32x, and `try`/`recover` itself 1.25x, of which
the `while (_sj_run)` trampoline 1.13x; the union member through `reinterpret<GCUnion?>` costs 1.17x
and `enum_from_int` 1.12x. Five cost nothing measurable (0.93x to 1.02x): `addr(deref(p + i))`,
the macro mask arithmetic (daslang folds the constants), a small call against its body inlined,
the redundant `uint8` cast of a byte read, and `typeinfo sizeof`. Under the JIT every construct but
`try`/`recover` (5.43x) costs within 16 percent (the small call 1.16x); the `c_volatile_load` JIT
cell is `SUSPECT` and left out. The `wrap_cast` kernel's values stay under 2^28, so its rewrite
matching native shows no wrap semantics: the plain operators' wrap on overflow is daslang's
defined signed arithmetic, which a probe should pin before the fix lands. The whole benchmarks run the source layout's
late-bound calls at 0.95x to 1.00x of the scc layout's net time, so the slots cost nothing
measurable there, while the scc layout loads in 4.21 s against 0.80 s. Each whole-run sample
resolves to 0.1 s on every lane (about 5 percent of a 4 s net time). The native benchmark runs
end within a few ticks, under the 1.0 s net floor, so no net factor over native is shown.
