options gen2

module perf_compose public

require daslib/fio
require crt
require ../suites/suite_files.das

//! The C program of a kernel: the kernel file under `perf/kernels/` between the profile
//! prologue and epilogue. The harness builds and converts it; the readability metric converts it.

//! The profile protocol around a kernel: dastest's budget loop in C, timed by the CRT clock
//! the kernel's converted form also reaches, one line `<seconds per run> <runs> <result>` at
//! the end; the result is what the lanes are compared on.
def composed_source(kernel : string) : string {
    let prologue = "int printf(const char *, ...);\nlong clock(void);\n#define C2DAS_CLOCKS_PER_SEC {crt::CLOCKS_PER_SEC}L\n#define C2DAS_BUDGET (C2DAS_CLOCKS_PER_SEC / 2)\n\n"
    let epilogue = "\nint main(void) \{\n    long reps = 1;\n    long total = 0;\n    for (;;) \{\n        long start = clock();\n        for (long i = 0; i < reps; i++) kernel_run();\n        total = clock() - start;\n        if (total >= C2DAS_BUDGET || reps >= 1000000000L) break;\n        long next = total <= 0 ? 100 * reps : (long) ((double) reps * (double) C2DAS_BUDGET / (double) total * 1.2);\n        if (next > 100 * reps) next = 100 * reps;\n        if (next < reps + 1) next = reps + 1;\n        reps = next;\n    \}\n    printf(\"%.9f %ld %d\\n\", (double) total / (double) C2DAS_CLOCKS_PER_SEC / (double) reps, reps, kernel_result());\n    return 0;\n\}\n"
    return prologue + kernel + epilogue
}

//! The kernel `name` composed into `<work>/<name>.c`, `work` created; the path written.
def write_composed(name, work : string) : string {
    mkdir_rec(work)
    let c_path = path_join(work, "{name}.c")
    fwrite(c_path, composed_source(fread("{KERNELS}/{name}.c")))
    return c_path
}

//! The define the native build of a dasProfile-method program takes: it compiles the clock's C
//! body, which the conversion reaches as `crt::c_monotonic_ns` instead.
let METHOD_NATIVE_DEFINE = "-DC2DAS_NATIVE"

//! The dasProfile method around a kernel, its `profile.h` step for step: `kernel_run` never
//! inlined into the timing loop (`PROFILE_NOINLINE`), each run's result stored into a `volatile`
//! sink (`profile::keep`), the steady clock (CLOCK_MONOTONIC, what `std::chrono::steady_clock`
//! reads on linux; `crt::c_monotonic_ns` in the conversion), a 0.5 s budget in seconds, the count
//! regrown as `budget / per-run * 1.2`, at most a hundredfold and at least one more per round,
//! capped at 1e9; then the same one line as `composed_source`.
def composed_method_source(kernel : string) : string {
    let prologue = "int printf(const char *, ...);\nlong c_monotonic_ns(void);\n#ifdef C2DAS_NATIVE\n#include <time.h>\nlong c_monotonic_ns(void) \{\n    struct timespec ts;\n    clock_gettime(CLOCK_MONOTONIC, &ts);\n    return ts.tv_sec * 1000000000L + ts.tv_nsec;\n\}\n#endif\nstatic void kernel_run(void) __attribute__((noinline));\n\n"
    let epilogue = "\nstatic volatile int c2das_sink;\n\nint main(void) \{\n    const double budget = 0.5;\n    long n = 1;\n    double total = 0.0;\n    for (;;) \{\n        long t0 = c_monotonic_ns();\n        for (long i = 0; i < n; i++) \{\n            kernel_run();\n            c2das_sink = kernel_result();\n        \}\n        total = (double) (c_monotonic_ns() - t0) / 1e9;\n        if (total >= budget || n >= 1000000000L) break;\n        double per = total / (double) n > 1e-9 ? total / (double) n : 1e-9;\n        long next = (long) (budget / per * 1.2);\n        if (next > 100 * n) next = 100 * n;\n        if (next < n + 1) next = n + 1;\n        n = next < 1000000000L ? next : 1000000000L;\n    \}\n    printf(\"%.9f %ld %d\\n\", total / (double) n, n, kernel_result());\n    return 0;\n\}\n"
    return prologue + kernel + epilogue
}

//! The kernel `name` composed by the dasProfile method into `<work>/<name>.c`, `work` created.
def write_method_composed(name, work : string) : string {
    mkdir_rec(work)
    let c_path = path_join(work, "{name}.c")
    fwrite(c_path, composed_method_source(fread("{KERNELS}/{name}.c")))
    return c_path
}
