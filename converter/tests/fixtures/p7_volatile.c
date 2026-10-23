/* P7.0: every access of a volatile object is one c_volatile_load or c_volatile_store: globals, a
   typedef, a field, an element, a pointer target, a local, compound stores, steps, a discarded read,
   a function pointer, the small and floating types and _Bool */
int printf(const char *, ...);
int vfp(void);
int vpointers(void);
typedef volatile int vint;
struct S { volatile int f; int g; };
static volatile int a = 3;
static vint b = 4;
static int x0 = 9;
static int * volatile p = &x0;
static volatile int arr[3] = {1, 2, 3};
static volatile double vd = 1.5;
static volatile unsigned char vc = 250;
static volatile _Bool vb = 1;
int f(volatile int *q, struct S *s) { return a + b + *p + arr[1] + *q + s->f + s->g; }
int main(void) {
    struct S s = {5, 6};
    volatile int loc = 7;
    int t = f(&loc, &s);
    a = 10; a += 5; a++; --a; b <<= 2; vc += 10; vd *= 2.0; vb = 0;
    s.f = a; arr[2]++;
    int u = (a = 4) + 4;
    struct S s2 = {1, 2};
    struct S *ps = &s2;
    ps->f += 3; ps->f++;
    t += ps->f;
    (void)a; t += vfp(); t += vpointers();
    loc--;
    printf("%d %d %d %d %d %d %g %d %d %d %d\n", t, a, b, s.f, arr[2], vc, vd, vb, u, loc, *p);
    return 0;
}
typedef int (*handler)(int);
static int twice(int v) { return v * 2; }
struct H { volatile handler hook; };
int vfp(void) { struct H h; h.hook = twice; volatile handler local = twice; local = h.hook; return local(3) + h.hook(4); }
/* a volatile pointer stepped and moved by a compound store, and a volatile _Bool's compound store */
static int cells[4] = {10, 20, 30, 40};
static int *volatile walker = cells;
static volatile _Bool seen = 0;
int vpointers(void) { walker++; walker += 2; walker--; walker -= 1; walker++; seen |= 1; seen &= 1; return *walker + seen; }
