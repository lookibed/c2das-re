/* dasProfile 436d58d tests/cpp/fib_loop.cpp in C: the same function, parameter and noinline */
static volatile int count = 6511134;

__attribute__((noinline)) int fibI(int n) {
    int last = 1;
    int cur = 0;
    for (int i = 0; i < n; ++i) {
        int tmp = cur;
        cur = (int) ((unsigned) cur + (unsigned) last);
        last = tmp;
    }
    return cur;
}

static int result;
static void kernel_run(void) { result = fibI(count); }
static int kernel_result(void) { return result; }
