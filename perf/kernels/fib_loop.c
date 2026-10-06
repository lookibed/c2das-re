/* dasProfile "fibonacci loop": the iterative Fibonacci number, wrapping in unsigned */
static int fibI(int n) {
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
static volatile int count = 6511134;
static void kernel_run(void) { result = fibI(count); }
static int kernel_check(void) { return result == 1781508648; }
