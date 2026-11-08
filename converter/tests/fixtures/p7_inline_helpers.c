/* P7.0w: pure `static` helpers spelled as their expression at a direct call under
   `inline_helpers` - the clamp shape, `return <expr>` with C's conversions, an argument with an
   effect or read twice evaluated once, a helper calling a helper - and the calls kept where the
   expression cannot stand or the function is no pure helper; against native */
int printf(const char *, ...);
typedef unsigned char uint8_t;
enum Lim { LIM_LO = -8, LIM_HI = 8 };
static int counter;
static int g = 3;
static uint8_t clamp8(int n) {
    if (n > 255) {
        n = 255;
    } else if (n < 0) {
        n = 0;
    }
    return n;
}
static int clamp_lim(int v) {
    if (v > LIM_HI)
        v = LIM_HI;
    else if (v < LIM_LO)
        v = LIM_LO;
    else
        v = v * 2;
    return v;
}
static int fmul(int a, int b) { return (int) (((long long) a * b) >> 16); }
static int sq(int a) { return a * a; }
static int sum_sq(int a, int b) { return sq(a) + sq(b) + sq(a); }
static double half(double x) { return x / 2; }
static unsigned wrap_add(unsigned a, unsigned b) { return a + b; }
static int pick(int c, int a, int b) { return c ? a : b; }
static int ignore_second(int a, int b) { return a; }
static int both(int a, int b) { return a < b && b < 100; }
static int add(int a, int b) { return a + b; }
static int twice(int x) { return add(x, x); }
static unsigned char clampu(unsigned char n) {
    if (n > 200)
        n = 300;
    return n;
}
static short narrow(int a) { return a * 1000; }
/* no pure helper: its value is taken, it reads a global, it recurses, it takes a pointer */
static int taken(int a) { return a + 1; }
static int reads_global(int a) { return a + g; }
static int fact(int n) { return n <= 1 ? 1 : n * fact(n - 1); }
static int deref(const int *p) { return *p; }
static int next(void) { return ++counter; }
int main(void) {
    int (*fp)(int) = taken;
    int i = 300, s = 0, k = 2;
    uint8_t small = 200;
    uint8_t buf[4];
    buf[0] = clamp8(i);
    buf[1] = clamp8(-5 + i - 400);
    buf[2] = clamp8(next() * 100);
    buf[3] = clamp8(small);
    s += clamp_lim(k) + clamp_lim(k + 20) + clamp_lim(-k * 9);
    s += fmul(1 << 16, 3 << 16) + fmul(small, k << 16);
    s += sq(next()) + sum_sq(k, i) + sum_sq(k + 1, k - 1);
    s += pick(next(), 1, 2) + ignore_second(k, next()) + both(k, i);
    s += k > 1 ? sq(next()) : sq(k);
    s += k > 1 && sq(k) > 3;
    s += (int) half(i) + (int) half(small);
    s += (int) (wrap_add(4000000000u, 500000000u) % 1000u);
    s += fp(1) + taken(2) + reads_global(k) + fact(5) + deref(&k);
    clamp8(i);
    {
        /* an argument that is itself a call of the helper, directly or through another helper,
           next to a caller's local named like the helper's parameter */
        int a = 100;
        volatile int vv = 7;
        s += add(1, add(2, 3)) + add(1, twice(2)) + a;
        s += sq(k < i) + sq(vv) + clampu(small) + clampu(150) + narrow(i) + ignore_second(k, vv);
    }
    printf("%d %d %d %d %d %d\n", buf[0], buf[1], buf[2], buf[3], s, counter);
    return 0;
}
