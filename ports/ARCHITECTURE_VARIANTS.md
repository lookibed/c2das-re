# ports Architecture: the variants

Read `ARCHITECTURE.md` (this folder) first. This companion holds the two variants every published
program has and the files that set them: `variants/`, the variant files; `variants.das`, which reads
them and makes the sidecar a variant converts under; `tests/test_variants.das`, the committed files
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
- `results`: an object, the numbers the variant's search recorded for the tables.

`read_variant` refuses a file whose name is not `<program>.<variant>.json` with a variant of
`VARIANT_NAMES`, a file that is not a JSON object, a key outside `knobs` and `results`, a knob
outside `VARIANT_KNOBS`, a knob that is not an object, a member outside `value`, `reason` and
`numbers`, a knob without a value or a reason, a reason or numbers that is no string, and `results`
that is no object. A knob's value is checked as the converter checks it: by the sidecar it makes.

## 2. The sidecar of a variant {#variant-sidecar}

A variant converts under its program's sidecar with its knobs set (`overlay_knobs`): each knob's key
takes its value, except `layout` over a program whose `layout` is an object (the source-cut layout's
cut), where the value goes into that object's `mode`. `variant_sidecar` writes the result where the
conversion reads it, the program sidecar's relative paths (`include_dirs`, `include_files`,
`program_root`, `layout.profile`) made absolute so it reads the same from there, and reads it back
with the converter's `read_sidecar`, so a value the converter refuses is refused naming the variant
and the key. `published_sidecar` is the same object with the paths as the program's sidecar writes
them: the sidecar a variant's directory in the clone holds.

## 3. The harnesses

Each harness converts under a variant file it is handed, its own program's only:

- `lua/run.das --variant <file>`: `lua/work/variants/<variant>/`, its sidecar `lua.c2das` there
  (`lua/ARCHITECTURE.md` section 1).
- `doom/run.das --variant <file>`: `doom/work/variants/<variant>/`, its sidecar `doom.c2das` and
  `--fps`'s capture there (`doom/ARCHITECTURE.md` section 1).
- `compare/run.das --project <name> --variant <file> --out <capture>`: our side of the project
  (`compare/ARCHITECTURE_PROJECTS.md`); `convert_project`, which the publisher and the criteria
  call, takes the variant as the project's `ours_variant`.
