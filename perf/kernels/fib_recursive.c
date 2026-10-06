/* dasProfile "fibonacci recursive": the naive recursion to depth 31 */
static int fibR(int n) {
    if (n < 2) return n;
    return fibR(n - 1) + fibR(n - 2);
}
static int result;
static volatile int depth = 31;
static void kernel_run(void) { result = fibR(depth); }
static int kernel_result(void) { return result; }
