int printf(const char *, ...);
typedef struct GCObject { int marked; } GCObject;
typedef union { GCObject *gc; void *p; double n; long long i; } Value;
struct Point { int x, y; };
union Mix { struct Point pt; char bytes[12]; int i; };
union Half { short s; unsigned char c[2]; };
union Bits { float f; unsigned int u; };
struct Tagged { int tag; union Mix m; };
struct BF { unsigned a : 3; int b : 5; short e; };
union Wrap { struct BF bf; short s; };
enum { SLOTS = 3 };
union Slots { int slot[SLOTS]; char c; };
struct Shape { int kind; union { int side; double radius; }; struct { short w, h; }; };
union Ragged { char c[3]; short s; };
struct Dims { int slot[SLOTS]; };
union Nested { struct Dims dims; int i; };
union Out { union Half in; double d; };
struct Q { int n; unsigned char b[4]; };
struct HoldsHalf { int tag; union Half u; };
struct Order { int a; union Bits u; int b; };
struct Later { int *p; union Bits u; };
#define ANON union { int x; long long wide; }
struct P1 { ANON; };
struct P2 { int t; ANON; };
static union Bits gbits = { .u = 7 };
unsigned int *pbits = &gbits.u;
int big[1000] = { [5] = 1 };
int *pbig = &big[5];
int later_target;
struct Later later = { &later_target, { .u = 3 } };
static int counter;
static int side(void) { return ++counter; }
static int sum2(const unsigned char *p) { return p[0] + p[1]; }
static int decay_read(union Half h) { unsigned char *p = h.c; return p[0] + sum2(h.c); }
static int decay_field(struct HoldsHalf hh) { return sum2(hh.u.c); }
static int store_struct(struct Q q) { q.b[1] = 5; return q.b[1]; }
static int step_union(union Half h) { h.c[1]++; h.c[0] = 9; return h.c[0] + h.c[1]; }
static int read_struct(struct Q q) { return q.b[0] + sum2(q.b); }
static union Mix gmix = { .i = 0x01020304 };
static union Half ghalf;
struct Tagged gtags[2] = { { 1, { .i = 7 } }, { 2, { .pt = { 3, 4 } } } };
static Value make(double d) { Value v; v.n = d; return v; }
static long long bits_of(Value v) { return v.i; }
static int first_byte(union Mix m) { return m.bytes[0]; }
static void bump(int *p) { *p += 100; }
static void fill(union Half *h, int lo, int hi) { h->c[0] = lo; h->c[1] = hi; }
int main(void) {
    Value v = make(3.5);
    printf("%llx %llx %d\n", bits_of(v), bits_of(make(1.0)), (int) sizeof(Value));
    v.gc = 0;
    printf("%d\n", v.p == 0);
    union Mix m = { { 1, 2 } };
    m.pt.x = 7;
    m.pt.y += 2;
    m.i++;
    ++m.i;
    m.i *= 3;
    printf("%d %d %d %d\n", m.i, m.pt.y, first_byte(m), (int) sizeof(union Mix));
    bump(&m.i);
    printf("%d\n", m.i);
    union Mix copy = m;
    copy.bytes[1] = 1;
    printf("%d %d\n", m.i, copy.i);
    union Half h = { 0 };
    fill(&h, 1, 2);
    printf("%d %d %d\n", h.s, (int) sizeof h, ghalf.s);
    union Bits b;
    b.f = 1.0f;
    printf("%x\n", b.u);
    b.u = 0x40490fdb;
    printf("%.5f\n", b.f);
    struct Tagged t = { 5, { .i = 9 } };
    t.m.bytes[0] = 0x10;
    printf("%d %d\n", t.tag, t.m.i);
    printf("%d %d %d\n", gmix.bytes[0], gtags[0].m.i, gtags[1].m.pt.y);
    union Mix arr[2] = { { .i = 1 }, { .pt = { 5, 6 } } };
    union Mix *pm = &arr[1];
    pm->pt.x += 1;
    pm->i--;
    printf("%d %d %d\n", arr[0].i, pm->i, arr[1].pt.y);
    union Mix zero = {};
    printf("%d %d\n", zero.i, (int) __builtin_offsetof(union Mix, i));
    union Wrap w = { .s = -1 };
    w.bf.a = 2;
    printf("%d %d %d\n", w.s, w.bf.b, (int) sizeof(union Wrap));
    union Slots sl = { { 4, 5, 6 } };
    sl.c = 9;
    printf("%d %d %d\n", sl.slot[0], sl.slot[2], (int) sizeof sl);
    struct Shape sh = { 1, { .radius = 2.5 }, { 3, 4 } };
    sh.w += 1;
    printf("%d %.1f %d %d %d\n", sh.kind, sh.radius, sh.w, sh.h, (int) sizeof sh);
    sh.side = 6;
    printf("%d\n", sh.side);
    union Half hv = { .s = 0x0201 };
    struct Q q = { 1, { 1, 1, 1, 1 } };
    struct HoldsHalf hh = { 0, { .s = 0x0303 } };
    printf("%d %d %d %d\n", decay_read(hv), decay_field(hh), store_struct(q), step_union(hv));
    printf("%d %d %d %d %d\n", q.b[1], hv.c[1], hv.c[0], read_struct(q), hh.u.c[0]);
    printf("%u %d %d %u\n", *pbits, *pbig, *later.p, later.u.u);
    struct Order o1 = { side(), { .u = side() }, side() };
    int c = 0;
    struct Order o2 = { c++, { .u = c++ }, c++ };
    printf("%d %u %d / %d %u %d\n", o1.a, o1.u.u, o1.b, o2.a, o2.u.u, o2.b);
    union Out out = { .in = { .s = 5 } };
    union Bits sparse[40] = { [3] = { .u = 4 } };
    union Ragged rg = { { 1, 2, 3 } };
    union Nested ne = { .i = 8 };
    struct P1 p1;
    struct P2 p2;
    p1.x = 1;
    p2.wide = 2;
    printf("%d %u %d %d %d %d %d %d\n", out.in.s, sparse[3].u, rg.s, (int) sizeof rg, ne.dims.slot[0], (int) sizeof ne, p1.x, (int) p2.wide);
    return m.i == 127 ? 0 : 1;
}
