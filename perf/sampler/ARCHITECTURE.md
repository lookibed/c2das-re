# perf/sampler Architecture

## 1. File charters

- `sampler.c` - a sampling profiler loaded with `LD_PRELOAD`: a `CLOCK_MONOTONIC` timer signals
  the loading thread every `SAMPLER_US` microseconds (default 250), the handler stores the
  interrupted RIP and the word at the stack top, and the file `SAMPLER_OUT.<pid>` gets the samples
  (past `MAX_SAMPLES` counted as dropped) and every snapshot of `/proc/self/maps` (one when the
  file is written, one before each `dlclose`, which leave `MAPS_FINAL_RESERVE` of the
  `MAPS_BYTES` buffer to the last; a cut snapshot adds `# maps truncated` after `# maps`). The
  file is written once: at exit, in an interposed `_exit` or `_Exit` (daslang's `c_exit` leaves
  through `_exit`, where no `atexit` handler runs), or under `SAMPLER_GATE=clock`, which records
  between the first and the second `clock()` call, the window Doom's host and the kernels time, at
  the second; writing deletes the timer, so no signal interrupts what runs after. A forked child
  writes nothing. Build: `clang -O2 -fPIC -shared -o libsampler.so sampler.c -ldl -lrt`; the caps
  are `-D` overridable.
- `symbolize.sh` - names the samples offline: each PC's mapping gives its file offset, the
  file's `LOAD` segments (`readelf -lW`) its virtual address, `nm -S` its function (the JIT's cached
  `.dll` carries its symbols), `?` past a sized symbol's end (a static function of a stripped
  library); the last snapshot's mappings are tried first, so a range reused after a `dlclose`
  names the later file. Self samples per function; `--addr` per instruction of one
  function, `--lines` per source line (`addr2line`, a JIT `.dll` built under `--jit-debug`),
  `--callers` the stack-top word of a frameless leaf's samples (its caller), `--dso` one mapped
  file.

## 2. Why sampling here

The box has no `perf`, and daslang's instrumenting profiler prints nothing when a program leaves
through C `exit`. A timer signal on the monotonic clock samples a CPU-bound single-threaded run
at a finer period than the CPU-time timers, which expire on the scheduler tick.

## 3. The test

`perf/tests/test_sampler.das` builds the library with the pinned clang (`default_clang`) and the
build line of section 1, no script between, three times (as is, `MAX_SAMPLES=16`, a 2 KiB maps
buffer), the stand-in `perf/tests/sampler_stand_in.c` once per define its header names (`main`
timing `hot_caller` between two `clock()` calls, `hot_caller` calling `hot_leaf`, a loop in
registers that keeps no frame), and `sampler_stand_in_lib.c` stripped. It holds the file's format
and every way it is written or not: gated, ungated at exit, through `_exit` both ways, never when
the gate never opens or `SAMPLER_OUT` is empty or unset, once across a fork, the default and a
zero period sampling, dropped samples past the cap, a sleep after the window not interrupted, a
dlclosed library's PCs and the truncation marker; and `symbolize.sh`'s self samples (80% in
`hot_leaf`), `--callers` (80% in `hot_caller`), `--addr`, `--dso`, `--lines` over a `-gdwarf-4`
build, `?` past `lib_run`'s size and an unknown flag's exit 2. The sampler measures and gates
nothing: only the tests lane runs the test, and nothing in the fast tier builds or loads it.
