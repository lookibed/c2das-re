/* dasProfile 436d58d tests/cpp/primes.cpp in C: the same functions, parameter and noinline, its
   `bool` as `_Bool` */
static volatile int limit = 14000;

__attribute__((noinline)) _Bool isprime(int n) {
    for (int i = 2; i != n; ++i) {
        if (n % i == 0) return 0;
    }
    return 1;
}

__attribute__((noinline)) int primes(int n) {
    int count = 0;
    for (int i = 2; i != n + 1; ++i) {
        if (isprime(i)) ++count;
    }
    return count;
}

static int result;
static void kernel_run(void) { result = primes(limit); }
static int kernel_result(void) { return result; }
