/* P7.0: the range rewrite of a canonical counting `for`, the loops it leaves alone, the increment
   as the body's last statement, `x = x op y` as `x op= y`, and C's wrapping signed sum */
int printf(const char *, ...);
static int limit = 5;
static int bump(int *p) { return ++*p; }
static int ranges(int n, long long m, unsigned u) {
    int total = 0;
    for (int i = 0; i < n; i++) total += i;
    for (int i = 2; i < n + 3; ++i) { if (i == 3) continue; if (i == 6) break; total += i * 10; }
    for (long long k = 1; k < m; k += 1) total += (int) k;
    for (unsigned v = 0u; v < u; v++) total += (int) v * 100;
    for (int i = n; i < 2; i++) total += 1000;
    return total;
}
static int kept(int n) {
    int total = 0, i;
    for (int j = 0; j < n; j++) { if (j == 1) j++; total += j; }          /* the body writes j */
    for (int j = 0; j < limit; j++) total += j;                           /* a global bound */
    for (int j = 0; j < n; j++) { total += j; n -= 1; }                   /* the body writes n */
    for (int j = 0; j <= n; j++) total += j;                              /* not `<` */
    for (int j = 0; j < n; j += 2) total += j;                            /* not a step of one */
    for (i = 0; i < n; i++) total += i;                                   /* no declaration */
    for (int j = 0; j < n; j++) total += bump(&j);                        /* j's address taken */
    int b = 4;
    int *pb = &b;
    for (int j = 0; j < b; j++) { total += j; *pb = 2; }                  /* b's address taken */
    return total + i;
}
static int trailing(int n) {
    int total = 0;
    int j;
    for (j = 0; j < n * 2; j++) { if (j == 7) break; total += j; }
    for (j = 0; j < n * 2; j++) { if (j == 3) return total + j * 1000; total += j; }
    return total;
}
struct acc { int sum; double mean; int cells[3]; };
static int compound(int n) {
    int x = 1;
    long long y = 3;
    unsigned u = 7u;
    double d = 0.5;
    struct acc a = {0, 0.0, {0, 0, 0}};
    unsigned char c = 9;
    x = x + n; x = x - 2; x = x * 3; x = x & 0xff; x = x | 0x100; x = x ^ 1;
    y = y * 5; u = u + 3u; d = d * 4.0;
    a.sum = a.sum + x; a.cells[1] = a.cells[1] + 7; a.mean = a.mean + d;
    c = c + 1;                                      /* small: computes in int */
    x = n + x;                                      /* the variable on the right */
    x = x / 2;                                      /* not one of the six */
    return x + (int) y + (int) u + (int) d + a.sum + a.cells[1] + (int) a.mean + c;
}
static int wraps(int a, int b, long long p, long long q) {
    int s = (int) ((unsigned) a + (unsigned) b);
    int t = (int) ((unsigned) a - (unsigned) b);
    long long w = (long long) ((unsigned long long) p + (unsigned long long) q);
    unsigned m = (unsigned) a * (unsigned) b;
    int cur = a;
    cur = (int) ((unsigned) cur + (unsigned) b);
    return s + t + (int) (w >> 32) + (int) (m & 0xff) + cur;
}
int main(void) {
    printf("%d %d %d %d %d\n", ranges(6, 4, 3), kept(5), trailing(5), trailing(1), compound(4));
    printf("%d\n", wraps(2147483647, 5, 9223372036854775807LL, 2));
    return 0;
}
