# ports Architecture: the run

Read `ARCHITECTURE.md` (this folder) first. This companion holds how a publish runs its programs.

## 1. A process per program {#apart}

A daslang context keeps every string it allocates until the process exits, and its heaps never
shrink, so the programs of one process add up: a compare project converts in the publisher's own
process (`ARCHITECTURE.md` section 5), and a publish of every program in one process grew past 10
GB of resident memory. A publish without `--program` therefore publishes each program in a process of its own
(`publish_apart`): the publisher runs itself again with its own arguments and `--program <name>
--results <file>` last (`perf/perf_lanes.das`'s `rerun_command`), a program at a time, in the
order `ARCHITECTURE.md` section 1 names them (Lua, the compare projects, PureDOOM). A program the publish skips (a
compare project under `--no-convert` or missing from the Rust checkout, PureDOOM without the
`doom/` harness) starts no process; the publisher logs why (`skip_reason`). The child shares the
publisher's stdout and stderr, so the log reads as one process's.

`--results` marks the child: it publishes the one program, its top-level README and with
`--commit` its commit, then writes its outcome to the file, a line `published` or `failed <why>`
each, and exits; it neither pushes nor writes the failure line of the top-level README. The
publisher reads each child's outcome back (a child that ended without one is a failure naming how
it ended, `process_ended`) and ends the publish as section 5 of `ARCHITECTURE.md` states: the
failures named in the top-level README and committed with `--commit`, then the push with
`--push`. A publish with `--program` runs that program in its own process, the publisher's.

## 2. A process per project variant {#variant-apart}

A compare project that refuses whole converts file by file, and both of its variants converted in
one process add up the same way: quakegeneric's two variants together need more than the 8 GB
scope a publish runs in. Each variant of a compare project therefore converts in a process of its own
(`convert_apart`): the publisher runs itself again with its own arguments and `--program <name>
--convert-variant <variant> --results <file>` last. The child reads the project's cases and the
variant file, converts into the variant's work folder (`compare/work/ports/<name>/<variant>/`,
`convert_project`), writes the conversion to the file as JSON and exits; the publisher reads it
back and publishes from the work folder as before. A child that wrote no conversion fails the
project's publish, naming how the child ended.
