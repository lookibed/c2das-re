/* P2.1 structs: a 16.16 fixed-point Mandelbrot over struct vectors passed and returned by
   value, the field access and the initializer lists of docs/lowering-examples.md "Structs" */
typedef int fixed_t;
typedef struct { fixed_t x, y; } vec_t;
static fixed_t fmul(fixed_t a, fixed_t b) { return (fixed_t) (((long long) a * b) >> 16); }
static vec_t vsq(vec_t z) { vec_t r = { fmul(z.x, z.x) - fmul(z.y, z.y), 2 * fmul(z.x, z.y) }; return r; }
static vec_t vadd(vec_t a, vec_t b) { vec_t r; r.x = a.x + b.x; r.y = a.y + b.y; return r; }
static int escape(vec_t c) {
    vec_t z = { 0, 0 };
    int i;
    for (i = 0; i < 48; i++) {
        z = vadd(vsq(z), c);
        if (fmul(z.x, z.x) + fmul(z.y, z.y) > (4 << 16)) return i;
    }
    return 48;
}
static volatile int side = 96;
static int result;
static void kernel_run(void) {
    int n = side;
    int sum = 0;
    int row, col;
    for (row = 0; row < n; row++) {
        for (col = 0; col < n; col++) {
            vec_t c = { -(2 << 16) + (3 << 16) / n * col, -(3 << 15) + (3 << 16) / n * row };
            sum += escape(c);
        }
    }
    result = sum;
}
static int kernel_check(void) { return result == 102833; }
