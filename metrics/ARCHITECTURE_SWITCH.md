# metrics Architecture - the switch census

Companion to `ARCHITECTURE.md` in this folder. The census counts the `switch` statements of the
C programs the project converts and sorts each by what a daslang form for it must carry. It reads
the C-IR (`docs/c-ir-spec.md`), where a `switch` is still C's own statement with its labels as
markers in the body, and never the emitted das: the emitter's choice between the if-chain, the
matched-flag loop and the goto table (`converter/ARCHITECTURE_EMITTER_CONTROL.md`) is not in what
is counted. It records no capture and has no ratchet: a run prints its tables.

## 1. File charters

- `switch_census.das` - the driver: `das metrics/switch_census.das -- [--filter <row>] [--jobs N]`
  from the repository root, on this box under `heavy --label switch-census --max 8G -- prlimit
  --as=3221225472:6442450944`. A program row (Lua's two programs, PureDOOM, each compare
  project) converts through `convert_input` of `readability_inputs.das` in a worker of its own,
  one at a time, and the worker reads every `.cir.json` the conversion wrote under
  `work/switch_census/<key>/`, so a program whose emission fails is still counted from its dump.
  A suite row (c-testsuite, gcc-torture) dumps every `.c` file of the suite's tests alone, with
  no sidecar, in eight workers that each take every eighth file. A worker writes `rows.tsv` (one
  line per switch, and for a suite one `file` line per file) and `failures.tsv`. `--reuse` prints
  the tables from the files already written; `--c <file>` prints the rows of one C file.
- `switch_census_count.das` - the counting: `census_tu` reads the switches of one translation
  unit (section 2), `switch_class` the class (section 3), `facts_line` and `read_facts_line` a
  row's line, `program_census` a row of the tables, `render_classes`, `render_features` and
  `render_sites` the tables. `census_c_file` dumps one C file under the `linux` dialect.
- `tests/test_switch_census.das` over `tests/fixtures/switch_census.c`, a C file with one function
  per counted fact.

The driver names, per program row, the functions that hold 1% or more of the self time in a
profile under `perf/profiles/` (the native, JIT and interpreter lanes together). A switch is hot
when its function is one of them, so a cold switch inside a hot function counts as hot.
doomgeneric has no profile and takes PureDOOM's names; wasm3 and quakegeneric have none and no
hot switch.

## 2. The facts of one switch

The body's statements at its own level are read as groups: a run of `case` and `default` labels
and the statements up to the next label. A nested switch is a row of its own, and its labels and
`break`s are not the outer one's.

- `cond` - the condition's kind below C's implicit conversions (an explicit cast is kept, so
  Lua's `GET_OPCODE` is its enum): `enum`, `bool`, `char` (a plain `char`, or an integer whose
  labels the source spells as character literals), `int` for every other integer, `other` for
  anything else, which C does not allow.
- `labels`, `values`, `lo`, `hi`, `density` - the labels at the body's level, the distinct case
  values among them, the smallest and largest, and the share of [lo, hi] they fill, in percent.
- `default_at` - `none`, or where the default's group stands: `first`, `middle`, `last`.
- `shared_labels` - labels that reach the next label with nothing done on the way: every label
  of a group past its first, and a group whose statements do nothing (`;`, `(void)0`).
- `real_falls` - groups, the last left out, that do something and whose end control can run
  past: the last statement reached is no `break`, `return`, `goto` or `continue`, no `if` leaving
  on both arms, no loop without a test and without a `break`, no switch that always leaves, no
  call of `NORETURN_CALLS`. The C-IR keeps no `noreturn` attribute, so a group ending in a
  program's own fatal call (`I_Error`, `luaD_throw`) counts as falling. `fall_line` is the line
  of the first such group's last statement.
- `falls_to_break` - groups that would count under `real_falls` but fall into a group that only
  breaks (`default: break;`), through groups that do nothing or to the body's end: the fall
  leaves the switch, as a `break` in its place would.
- `early_breaks` - `break`s of the switch that are not their group's last statement.
- `loop_breaks` - `break`s of a loop nested in the switch.
- `continues_out` - `continue`s that reach the loop around the switch.
- `goto_cross`, `labels_entered`, `goto_out` - gotos from one group to a C label in another;
  C labels in the body that a goto outside the switch names; gotos from the body to a label
  outside it.
- `decl_cross`, `decl_used_later` - declarations at the body's level with a label after them,
  and those of them a statement after that label names.
- `nested_labels` - labels of the switch below the body's level (Duff's device). Their values
  are not in `values`.
- `before_first` - statements before the first label.

## 3. The classes

`S4` is a condition that is no integer and no enum. `S3` is a switch with a goto between groups,
a label entered from outside, a declaration a later case names, or a nested label. `S2` is a
switch, not `S3`, with a real fall. `S1` is the rest: constants, groups that each leave or end
the switch, shared labels allowed. A fall to a `break`, an early `break`, a loop's `break`, a `continue` to the outer
loop, a goto out of the switch and a declaration no later case names do not change the class;
the feature table counts each.
