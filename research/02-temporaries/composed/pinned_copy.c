int printf(const char *, ...);
long clock(void);
#define C2DAS_CLOCKS_PER_SEC 1000000L
#define C2DAS_BUDGET (C2DAS_CLOCKS_PER_SEC / 2)

/* 02-temporaries: pinned postfix steps. `*d++ = *s++` copies (the F/P4.8 ledger family),
   `arr[k++].a++` (the index-with-effect family) and a discarded `(void)(cond || f())`. */
typedef struct Cell { int a; int b; } Cell;
static volatile int rounds = 2000;
static unsigned char src[256];
static unsigned char dst[256];
static Cell arr[256];
static int result;
static int fail_calls;
static int on_fail(int v) { fail_calls += v; return 0; }
static int copy_round(int n) {
    int acc = 0;
    for (int r = 0; r < n; r++) {
        const unsigned char *s = src;
        unsigned char *d = dst;
        while (s < src + 255 && (*d++ = *s++))
            ;
        int k = 0;
        while (k < 255) {
            arr[k++].a++;
            acc += arr[k - 1].a;
        }
        for (int i = 0; i < 255; i++)
            (void)(dst[i] == src[i] || on_fail(1));
        acc += dst[254] + k;
    }
    return acc;
}
static void kernel_run(void) {
    for (int k = 0; k < 256; k++) { src[k] = (unsigned char) (k + 1); arr[k].a = k; }
    result = copy_round(rounds) & 0x7fffffff;
}
static int kernel_result(void) { return result + fail_calls; }

int main(void) {
    long reps = 1;
    long total = 0;
    for (;;) {
        long start = clock();
        for (long i = 0; i < reps; i++) kernel_run();
        total = clock() - start;
        if (total >= C2DAS_BUDGET || reps >= 1000000000L) break;
        long next = total <= 0 ? 100 * reps : (long) ((double) reps * (double) C2DAS_BUDGET / (double) total * 1.2);
        if (next > 100 * reps) next = 100 * reps;
        if (next < reps + 1) next = reps + 1;
        reps = next;
    }
    printf("%.9f %ld %d\n", (double) total / (double) C2DAS_CLOCKS_PER_SEC / (double) reps, reps, kernel_result());
    return 0;
}
