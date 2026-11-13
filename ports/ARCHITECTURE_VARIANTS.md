# ports Architecture: the variants

Read `ARCHITECTURE.md` (this folder) first. This companion holds the two variants every published
program has and the files that set them: `variants/`, the variant files; `variants.das`, which reads
them and makes the sidecar a variant converts under; `ports_render.das`'s `render_variants`, the
table of both; `tests/test_variants.das`, the committed files
read and the refusals and sidecars over scratch files.

## 1. The variant files {#variant-files}

Every program the publisher knows (Lua with luac, each compare project, PureDOOM) has two variants,
`readable` and `fast` (`VARIANT_NAMES` of `variants.das`), each a file
`ports/variants/<program>.<variant>.json`. `readable` is the flag set with the highest criteria
total on the program (`metrics/ARCHITECTURE_CRITERIA.md`); `fast` the flag set with the best time
on the program's own workload, the JIT's when the tiers disagree. Both convert the same program:
a variant sets only knobs, never a fact of the program.

A knob is one of `VARIANT_KNOBS`, the sidecar keys that choose a spelling, a layout or das's checks
for the whole program (`layout`, `fn_macros`, `inline_helpers`, `switch_dispatch`, `checks`,
`past_end`, `param_writes`, `loops`, `first_member`, `solid_context`, `jit_whole_program`,
`strict_aliasing`, `forms_off`). Every other key of `SIDECAR_KEYS` is in `PROGRAM_KEYS` (defines, marshal records,
include folders and the like), which the program's own sidecar holds and no variant changes; a
sidecar key the converter adds is in exactly one of the two lists, which `tests/test_variants.das`
holds.

A variant file is a JSON object:

- `knobs`: an object of knobs, each `{value, reason, numbers}`: the value as the sidecar takes it,
  a one-line reason (required), and the numbers that chose it (`""` before a search).
- `results`: an object, the numbers the variant's search recorded for the tables (section 2).

`read_variant` refuses a file whose name is not `<program>.<variant>.json` with a variant of
`VARIANT_NAMES`, a file that is not a JSON object, a key outside `knobs` and `results`, a knob
outside `VARIANT_KNOBS`, a knob that is not an object, a member outside `value`, `reason` and
`numbers`, a knob without a value or a reason, a reason or numbers that is no string, and `results`
that is not as section 2 states. A knob's value is checked as the converter checks it: by the
sidecar it makes.

## 2. The results of a variant {#variant-results}

`results` holds what the variant's search measured, the numbers the ports tables show for the
variant; `{}` before a search. Each of its members is optional and carries its own provenance,
since the criteria run as a normal job and the timing as an exclusive one, at commits of their own
(`read_results`):

- `criteria`: `total`, the criteria total in percent; `row`, the row of
  `metrics/criteria_linux.json` the conversion is, when the capture holds one; `commit` and `date`,
  the c2das-re commit it was measured at and that commit's date; `command`, what reproduces it.
  `total`, `commit` and `date` are required.
- `speed`: `x_native`, per tier of `SPEED_TIERS` (`interp`, `jit`, `exe`, `aot`) the das time over
  the native build's, above 1 when slower (for PureDOOM the native frame rate over the das one),
  null or absent for a tier not measured or not running; `over`, what the ratio is over (the
  workloads and their mean); `commit`, `date`, `box` (`perf/boxes.das`) and `command`; `quiet`.
  Every member but `x_native`'s tiers is required, and `quiet` is true: a number is quoted only from
  a run under `heavy --exclusive` whose stderr said the machine was quiet.
- `lines`: `das`, the das lines of the converted tree, `luaV_execute`, the lines of Lua's
  interpreter loop (Lua only), and `commit`, the commit converted; `das` and `commit` are required.
  It is the search's record: the tables count the lines of the tree they publish.
- `notes`: one line, such as the tier whose best flag set differs from the variant's.

A ratio, a total or a count is a number above 0. `read_variant` refuses a member outside these, a
section that is no object, a required member missing, a number not above 0 (null only for a tier),
a string member that is no string, and `quiet` other than true.

## 3. The variants table {#variant-tables}

A program's README shows its variants side by side (`render_variants` of `ports_render.das`): a
line per variant's directory saying what it is for (`VARIANT_USES`: `readable` for reading and
changing the code, Boris and the weak-model add-a-feature check; `fast` for running), then one table,
a column per variant: every knob of `VARIANT_KNOBS` (`-` where the file sets none), the criteria
total, the das time over native per tier of `SPEED_TIERS`, the das lines of the tree published for
the variant and, for Lua, of `luaV_execute` there. A number comes from the variant's `results`
when the search recorded its section, a tier the section leaves out `not yet`; where the section
is missing it falls back to a capture the publisher hands with its label (`VariantColumn`), the
number marked `(N)` and the label listed under the table as not from a search of the variant;
without either it is `not yet`. Under the table each recorded section names its commit, date and
command, the speed its box and that the run was exclusive on a quiet machine, and the notes.

In Lua's README the das lines are those of the `lua` program's tree and `luaV_execute`'s are its
function there (compare's `function_text`). Its fallbacks: the criteria total of the `readable`
column is the row `lua/lua` of `metrics/criteria_linux.json`, the converter's default flags, and
the `fast` column has none, since no row measures its knobs; the speed of each column is the
directory's latest capture, per tier the geometric mean of the work time over native's
(`geomean_ratio`), its plain lanes for `readable` and its `-fast` lanes for `fast`, labelled with
the capture's time, box and commit.

## 4. The sidecar of a variant {#variant-sidecar}

A variant converts under its program's sidecar with its knobs set (`overlay_knobs`): each knob's key
takes its value, except `layout` over a program whose `layout` is an object (the source-cut layout's
cut), where the value goes into that object's `mode`. `variant_sidecar` writes the result where the
conversion reads it, the program sidecar's relative paths (`include_dirs`, `include_files`,
`program_root`, `layout.profile`) made absolute so it reads the same from there, and reads it back
with the converter's `read_sidecar`, so a value the converter refuses is refused naming the variant
and the key. `published_sidecar` is the same object with the paths as the program's sidecar writes
them: the sidecar a variant's directory in the clone holds.

## 5. The harnesses

Each harness converts under a variant file it is handed, its own program's only:

- `lua/run.das --variant <file>`: `lua/work/variants/<variant>/`, its sidecar `lua.c2das` there
  (`lua/ARCHITECTURE.md` section 1).
- `doom/run.das --variant <file>`: `doom/work/variants/<variant>/`, its sidecar `doom.c2das` and
  `--fps`'s capture there (`doom/ARCHITECTURE.md` section 1).
- `compare/run.das --project <name> --variant <file> --out <capture>`: our side of the project
  (`compare/ARCHITECTURE_PROJECTS.md`); `convert_project`, which the publisher and the criteria
  call, takes the variant as the project's `ours_variant`.
