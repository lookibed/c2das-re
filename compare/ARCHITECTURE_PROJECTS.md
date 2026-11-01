# compare Architecture - the real projects

Companion to `ARCHITECTURE.md` in this folder: the real projects comparison.

## The projects {#projects}

`run.das --project <name>` runs one real project of the Rust repository's `tests/manual` through
both translators and writes its entry of the capture's `projects` section, keeping every other
project and section. A project is a row of `project_table` in `projects.das`, the facts of the
project's README in the Rust checkout (`$C2DAS_RUST`, else `/root/c2das`, read in place, never
copied or built): the translation unit and the bench unit relative to the project folder, the
include folders, the defines, the C standard and the native build's flags the README gives, the
fixture the program reads from its last argument, the output it must print (the README's text), the
translator options of the project's canonical case in the Rust repository's
`tests/canonical/cases.json`, and the C functions shown side by side. wasm3 is the first row:
`src/all_host.c` and `src/all_host_bench.c`, `-std=c11 -Iinclude -Iupstream/wasm3/source -Isrc`,
`-O2`, `fixtures/fib32.wasm`, the nine lines `bytes=62` to `count=7`, `--das-option "stack =
4194304"`, and `op_Call` (an op that ends in the dispatch to the next op) and `call_fib` (the host's
call of the module's `fib`).

Everything a run builds sits in `work/projects/<name>/`: `native/` (the pinned clang's builds of
both units), `ours/` and `ours_bench/` (our conversions), `rust/` and `rust_bench/` (the Rust
translations), and each side's lane builds. The run is capped by the command that starts it
(`prlimit --as=3221225472`), which every child process inherits.

The entry is `{rust_commit, rust_commit_error, daslang, date, samples, lanes, native, ours, rust,
speed, code, functions}`: `native` the native build's verdict, `ours` and `rust` each `{error,
lanes}` with the side's refusal and a verdict per lane of `lanes` (`interp`, `jit`, `exe`, `aot`),
`speed`, `code` and `functions` as below. The capture's `rust_commit` is the `HEAD` of the checkout
holding the binary (`ARCHITECTURE.md` section 2).

## The verdicts {#verdicts}

The native build runs the unit with the fixture; it is `pass` when it prints the expected output,
else `native` with the reason, and then every lane of both sides is `refused` with `no native
result`. Our side converts the unit under `linux` with a sidecar of the project's defines; the
converter takes no include folder, so a project whose unit includes from a folder other than its own
is refused at the first such `#include`. The Rust side translates it with `translate_file` (`--libc
std --strict`, the case's options, the clang arguments of the row) within 600 s.

Each side's lanes: `refused` with the side's error when it has no module; `compile` with the first
`error[` line when the module fails `daslang -compile-only` (with our module folders on our side,
none on the Rust side), `timeout` past that check's 120 s; else each lane run by
`converter/tiers.das`'s `run_tier` with the fixture as the program's argument and judged: `timeout`
past its limit, `exit` with the code and the first line naming an error, `output` with the first
line that differs from the expected text (numbered from 1, a missing line `(none)`), `pass`. The
JIT's `[I]` lines are not the program's output. The `aot` tier's host passes the program no
arguments, so a project that reads its fixture from its argument is `skipped` under `aot` with that
reason, never dropped. A lane's limit is 120 s for a run, 300 s for each `exe` or `aot` build step
and the run it ends with (`COMPARE_LIMITS`).

## The speed {#speed}

The bench unit prints the expected output and two more lines, `setup_us=<n>` (parse and load) and
`decode_us=<n>` (the timed loop). It is built natively and converted and translated as the unit is;
each side's lane whose verdict over the unit is `pass` is timed over `--samples` runs (five by
default), each its own process: the interpreter and the JIT run the module, `exe` its binary built
once. A run whose output without the two lines differs from the expected text, or that lacks them,
stops the cell with an error. A cell is `{setup, decode}`, each perf's cell shape (`time` the median
in seconds, `spread`, `samples`); a lane that does not pass is `{error: "the lane does not pass:
<status>"}`, a side whose bench unit does not convert or translate `{error: "bench: <reason>"}`. The
native cell is timed the same way. Each side is timed where its own lanes pass, whether or not the
other side's do.

## The code {#code}

Each side that has a module is measured as the quality comparison measures one (`measure_side`): its
`.das` and `.das.inc` files, their non-blank lines and the readability counters over the entry
module, `compile` when the counters' compile fails. The Rust side's runtime lines are its `c2da_`
declarations named with a prefix of `RUNTIME_PREFIXES` (`c2da_rt_`, `c2da_std_`); a single project's
run has no other Rust modules to find the fixed prelude from, so the prelude counts as program code.
`functions` holds `{key, name, ours, rust}` per C function of the row, found by `function_text`.
`scripts/run_criteria.sh` measures its own inputs and takes no single one, so the criteria are not
computed per project.

## The rendering {#rendering}

`compare_render.das`'s `projects_text` renders the section under `### Real projects`: the verdicts
table (per project and side, the native verdict and each lane's), one line per side and reason for
every lane that does not pass, the lanes sharing a reason named together, the bench table (the
native decode seconds, each lane's decode median over it, an error cell as the lane's status,
`refused` for a side with no bench module, else the error's first word), the code table (status,
files, lines, the Rust runtime's lines and each counter) and the functions side by side. A capture
without the section renders `No project is captured yet.` The list of where the Rust translator is
ahead names each project whose Rust side passes a lane ours does not.
