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
    for (unsigned long long z = 0; z < (unsigned long long) u; z++) total += (int) z * 7;
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
static int after_addressed(int b) {                                       /* kept's addressed j and b are its own */
    int total = 0;
    for (int j = 0; j < b; j++) total += j;
    return total;
}
struct box { int n; };
static int lim_calls = 0;
static int lim(void) { lim_calls++; return 4; }
static int bounds(struct box *b, int n) {
    int total = 0, j = 1;
    for (int i = 0; i < n - i; i++) total += i;                           /* the bound reads the counter */
    for (int i = 0; i < b->n; i++) { total += i; b->n--; }                /* a member bound */
    for (int i = 0; i < lim(); i++) total += i;                           /* a call bound */
    for (int i = j++; i < n; i++) total += i * 10;                        /* a start with an effect */
    return total * 100 + b->n * 10 + lim_calls + j;
}
static int trailing(int n) {
    int total = 0;
    int j;
    for (j = 0; j < n * 2; j++) { if (j == 7) break; total += j; }
    for (j = 0; j < n * 2; j++) { if (j == 3) return total + j * 1000; total += j; }
    for (j = 0; j < n; j++) { total += 5; break; }                        /* no increment after the jump */
    for (j = 0; j < n; j++) { total += 7; goto done; }
done:
    for (j = 0; j < n; j++) { total += j; return total * 10 + j; }
    return total;
}
static int both_return(int n) {                                           /* both arms leave: no increment */
    int j;
    for (j = 0; j < limit; j++) { if (j == n) return 1000 + j; else return 2000 + j; }
    return j;
}
static int nested_continue(int n) {                                       /* the inner loop's continue is its own */
    int total = 0, j, k;
    for (j = 0; j < n; j++) { for (k = 0; k < 3; k++) { if (k == 1) continue; total += k; } total += j; }
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
    int z = 2;
    x = x + z++;                                    /* an effect on the right */
    int *pz = &z;
    *pz = *pz + 4;
    return x + (int) y + (int) u + (int) d + a.sum + a.cells[1] + (int) a.mean + c + z;
}
/* a truth value on the right is the int C adds; a bitfield and a [c_union] member keep the plain store */
struct bits { unsigned a : 3, b : 5; unsigned c : 32; };
struct holds { int k; struct bits bf; };
union pun { int i; float f; };
static int truths(int a, int b) {
    int x = 1;
    double d = 0.5;
    x = x + (a < b); x = x | !a; x = x * (a && b); d = d + (a > b);
    x = x + *(int[]){7, 8};
    struct holds h[3] = {{0, {1, 2, 7}}, {0, {3, 4, 8}}, {0, {5, 6, 9}}};
    struct holds *p = h;
    p[2].bf.b = p[2].bf.b + 3;
    p[2].bf.c = p[2].bf.c + 3;
    union pun us[2] = {{1}, {2}};
    union pun *pu = us;
    pu[1].i = pu[1].i + 5;
    return x + (int) (d * 10) + p[2].bf.b + (int) p[2].bf.c + pu[1].i;
}
static int wraps(int a, int b, long long p, long long q) {
    int s = (int) ((unsigned) a + (unsigned) b);
    int t = (int) ((unsigned) a - (unsigned) b);
    long long w = (long long) ((unsigned long long) p + (unsigned long long) q);
    unsigned m = (unsigned) a * (unsigned) b;
    int cur = a;
    cur = (int) ((unsigned) cur + (unsigned) b);
    short s1 = 300, s2 = 400;
    short ss = s1 + s2;                             /* small: no wrapping pair */
    unsigned char c1 = 200, c2 = 100;
    unsigned char cs = c1 + c2;
    int tw = (int) ((unsigned) (a < b) + (unsigned) b);
    int tw2 = (int) ((unsigned) b - (unsigned) !a);
    return s + t + (int) (w >> 32) + (int) (m & 0xff) + cur + ss + cs + tw + tw2;
}
int main(void) {
    struct box bx = {9};
    printf("%d %d %d %d %d\n", ranges(6, 4, 3), kept(5), trailing(5), trailing(1), compound(4));
    printf("%d %d %d %d %d\n", bounds(&bx, 6), truths(1, 2), truths(0, 0), after_addressed(4), nested_continue(3));
    printf("%d %d\n", both_return(0), both_return(3));
    printf("%d\n", wraps(2147483647, 5, 9223372036854775807LL, 2));
    return 0;
}
