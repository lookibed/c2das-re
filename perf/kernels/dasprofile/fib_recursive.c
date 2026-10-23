/* dasProfile 436d58d tests/cpp/fib_recursive.cpp in C: the same function, parameter and noinline */
static volatile int depth = 31;

__attribute__((noinline)) int fibR(int n) {
    if (n < 2) return n;
    return fibR(n - 1) + fibR(n - 2);
}

static int result;
static void kernel_run(void) { result = fibR(depth); }
static int kernel_result(void) { return result; }
