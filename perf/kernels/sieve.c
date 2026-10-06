/* P2.2 arrays: the sieve of Eratosthenes over a fixed byte array, indexed in both loops */
static volatile int limit = 1000000;
static unsigned char flags[1000001];
static int result;
static void kernel_run(void) {
    int n = limit;
    int i, k, count = 0;
    for (i = 0; i <= n; i++) flags[i] = 1;
    for (i = 2; i <= n; i++) {
        if (flags[i]) {
            for (k = i + i; k <= n; k += i) flags[k] = 0;
            count++;
        }
    }
    result = count;
}
static int kernel_result(void) { return result; }
