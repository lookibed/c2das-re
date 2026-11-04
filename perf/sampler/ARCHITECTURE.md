# perf/sampler Architecture

## 1. File charters

- `sampler.c` - a sampling profiler loaded with `LD_PRELOAD`: a `CLOCK_MONOTONIC` timer signals
  the loading thread every `SAMPLER_US` microseconds (default 250), the handler stores the
  interrupted RIP and the word at the stack top, and the file `SAMPLER_OUT.<pid>` gets the samples
  and every snapshot of `/proc/self/maps` (one at exit, one before each `dlclose`). Under
  `SAMPLER_GATE=clock` it records between the first and the second `clock()` call, the window
  Doom's host and the kernels time, and writes the file at the second: daslang's `c_exit` leaves
  through `_exit`, where no `atexit` handler runs. Build: `clang -O2 -fPIC -shared -o
  libsampler.so sampler.c -ldl -lrt`.
- `symbolize.sh` - names the samples offline: each PC's mapping gives its file offset, the
  file's `LOAD` segments (`readelf -lW`) its virtual address, `nm` its function (the JIT's cached
  `.dll` carries its symbols). Self samples per function; `--addr` per instruction of one
  function, `--lines` per source line (`addr2line`, a JIT `.dll` built under `--jit-debug`),
  `--callers` the stack-top word of a frameless leaf's samples (its caller), `--dso` one mapped
  file.

## 2. Why sampling here

The box has no `perf`, and daslang's instrumenting profiler prints nothing when a program leaves
through C `exit`. A timer signal on the monotonic clock samples a CPU-bound single-threaded run
at a finer period than the CPU-time timers, which expire on the scheduler tick.
