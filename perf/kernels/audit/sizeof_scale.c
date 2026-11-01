/* P7.0b `sizeof` in a hot loop: element addresses computed from byte offsets scaled by the
   element's size, as lmem.c and lstring.c size their blocks */
typedef struct Pair { long long key; long long val; } Pair;
static volatile int rounds = 20000;
static Pair pairs[64];
static int result;
static long long scan(int n) {
    long long acc = 0;
    for (int r = 0; r < n; r++) {
        for (unsigned long k = 0; k < 64; k++) {
            const Pair *p = (const Pair *) ((const char *) pairs + k * sizeof(Pair));
            acc += (p->val ^ r) + (long long) (sizeof(long long) * k);
        }
    }
    return acc;
}
static void kernel_run(void) {
    for (int k = 0; k < 64; k++) pairs[k].val = k;
    result = (int) (scan(rounds) & 0x7fffffff);
}
static int kernel_result(void) { return result; }
