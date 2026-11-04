# perf Architecture - the guarded samples

Companion to `ARCHITECTURE.md` in this folder: how a timed sample is started and how its failure
reads in a cell, for the perf harness and `compare/run.das` alike.

## 1. The guard

`measure` starts every sample through `guarded`: `sh -c '"$@"; exit $?' sh prlimit --core=0 --
<argv>`. `prlimit` (util-linux; the fast tier's `env` gate checks it is on `PATH`) sets the core
file limit to zero before it executes the program, so a sample that crashes writes no core file:
a capture's crashes are findings in its cells, not dumps on the disk. `guarded` with an
address-space size adds `--as=<bytes>` to the same `prlimit`, the cap `compare/run.das --project`
gives its measured runs (`compare/ARCHITECTURE_PROJECTS.md`). The guard runs before the program
times itself, so it never enters a cell; a timeout kills the whole process group, the shell and
the program in it.

## 2. A failed sample

daslib's `run_and_capture` reports a child killed by signal N as the exit code N, the same code
as a child exiting N, so a crash read bare is an exit code with whatever the program printed
first. The guard's shell waits for the program instead of becoming it, and a shell reports a
death by signal N as 128 + N. `exit_text` reads a code from 129 to 192 as `signal N (<name>)`,
the name for the signals 1 to 15 (`SIGNAL_NAMES`), and any other code as `exited <code>`; a
program that exits with a code above 128 itself reads as that signal, which no kernel does.
`run_error` adds the first line of the output that is neither empty nor an `info` line, or `no
output` when there is none: daslang's report of an exception it cannot unwind starts with an
empty line, and the shell reports the death (`Segmentation fault`) after everything the program
printed. A sample that exits 0 without the kernel's line is `exited 0` with that line.
