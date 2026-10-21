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
