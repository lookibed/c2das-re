# perf Architecture - the guarded samples

Companion to `ARCHITECTURE.md` in this folder: how a timed sample is started and how its failure
reads in a cell, for the perf harness and `compare/run.das` alike.

## 1. The guard

`measure` starts every sample through `guarded` (`perf_lanes.das`): `sh -c '"$@"; exit $?' sh prlimit --core=1 --
<argv>`. `prlimit` (util-linux; the fast tier's `env` gate checks it is on `PATH`) sets the core
file limit to one byte before it executes the program, so a sample that crashes writes no core:
a capture's crashes are findings in its cells, not dumps on the disk. The limit is 1, not 0,
because `/proc/sys/kernel/core_pattern` here is a pipe handler (WSL's `|/wsl-capture-crash`), and
the kernel hands a crash to a pipe handler whatever a limit of 0 says, while at a limit of 1 it
skips the pipe, and a file dump smaller than a page is never written either. `guarded` with an
address-space size adds `--as=<bytes>` to the same `prlimit`, the cap `compare/run.das --project`
gives its measured runs (`compare/ARCHITECTURE_PROJECTS.md`). The run an `exe` or `aot` build
ends with, the program's first, is guarded too (`lane_binary` hands `run_tier` the guard as the
wrapper of the program's command line), under the same cap. The guard runs before the program
times itself, so it never enters a cell; a timeout kills the whole process group, the shell and
the program in it.

## 2. A failed sample

daslib's `run_and_capture` reports a child killed by signal N as the exit code N, the same code
as a child exiting N, so a crash read bare is an exit code with whatever the program printed
first. The guard's shell waits for the program instead of becoming it, and a shell reports a
death by signal N as 128 + N. `exit_text` reads a code from 129 to 192 as `signal N (<name>)`,
the name for the signals 1 to 15 (`SIGNAL_NAMES`), and any other code as `exited <code>`. The
reading is ambiguous: a program that itself exits with a code from 129 to 192 (`exit(134)`) reads
as that signal (`signal 6 (ABRT)`), since the shell reports both alike; no kernel exits so.
`run_error` adds the first line of the output that is neither empty, nor an `info` line, nor the
shell's own report of the death (`shell_signal_line`: `Segmentation fault`, `Aborted`, `Bus error`
and the rest, with or without ` (core dumped)`), or `no output` when none is left: daslang's
report of an exception it cannot unwind starts with an empty line, and the shell prints its
report after everything the program printed, so it would otherwise name a silent crash.
`compare/projects.das`'s `error_line` skips the shell's report as well. A sample that exits 0
without the kernel's line is `exited 0` with that line.

## 3. The exclusive run

A capture runs as `heavy --exclusive` (the box's queue, owner rule 2026-11-06): the job waits for
every other job to end and for the CPU to be quiet (under 4 percent busy, twice over 5 s), runs
alone, and `/var/log/heavy-exclusive.log` keeps the busy share; a capture from a run that was not
exclusive, or that the log marks `NOT quiet`, is not recorded. The runners convert and build inside
the run today (the kernels' conversions, the exe and AOT builds), which the rule tolerates until a
build-only step exists (`docs/implementation_order.md`).
