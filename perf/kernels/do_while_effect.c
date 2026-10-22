/* P5.1 lua's `do { ... } while (--n > 0)` (lvm.c:638 copy2buff): the effect in the condition, an
   inner loop counting its argument down and an outer one counting the static's value down */
static volatile int rounds = 300000;
static int result;
static unsigned spin(unsigned x, int n) {
    do {
        x = x * 1103515245u + 12345u;
        x ^= x >> 7;
    } while (--n > 0);
    return x;
}
static void kernel_run(void) {
    int i = rounds;
    unsigned acc = 0;
    do {
        acc += spin(acc ^ (unsigned) i, (i & 7) + 1);
    } while (--i > 0);
    result = (int) (acc & 0x7fffffff);
}
static int kernel_result(void) { return result; }
