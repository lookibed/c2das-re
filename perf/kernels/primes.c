/* dasProfile "primes loop": count the primes up to 14000 by trial division */
static int isprime(int n) {
    for (int i = 2; i < n; i++) {
        if (n % i == 0) return 0;
    }
    return 1;
}
static int primes(int n) {
    int count = 0;
    for (int i = 2; i != n + 1; ++i) {
        if (isprime(i)) ++count;
    }
    return count;
}
static int result;
static volatile int limit = 14000;
static void kernel_run(void) { result = primes(limit); }
static int kernel_check(void) { return result == 1652; }
