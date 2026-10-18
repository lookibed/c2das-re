int printf(const char *, ...);
struct BF { unsigned a : 3; int b : 5; short e; };
struct Pad { unsigned lo : 3; unsigned : 2; unsigned mid : 4; int : 0; unsigned hi : 6; };
struct Mixed { char a : 3; int b : 5; long long wide : 40; _Bool flag : 1; int neg : 1; };
struct Holder { int id; struct BF bf; };
struct R { int a : 8; int b : 8; char c[2]; };
struct W { char x[3]; struct R r; };
struct T { int x; int : 0; int y; };
struct Full { unsigned long long all : 64; unsigned long long top : 7; _Bool on : 1; };
struct Narrow { short a : 3; char c; };
struct LL { long long q : 4; char d; char pad[6]; };
struct Names { int _1; int _bits9; unsigned f : 3; };
static struct BF g = { 9, -3, 7 };
static struct BF table[3] = { { 1, 2, 3 }, { .b = -1 }, { 7, 15, -2 } };
static int sum(struct BF s) { return s.a + s.b + s.e; }
static struct BF make(int v) { struct BF r = { v, v - 20, (short) v }; return r; }
static void bump(struct BF *p) { p->a++; ++p->b; p->e += 2; }
int main(void) {
    struct BF s = { 1, 2, 3 };
    s.a = 9;
    s.b = 16;
    printf("%u %d %d %d\n", s.a, s.b, s.e, (int) sizeof(struct BF));
    s.a += 6;
    s.b -= 1;
    s.a++;
    s.b--;
    int old = s.a++;
    int pre = --s.b;
    printf("%u %d %d %d\n", s.a, s.b, old, pre);
    struct Pad p = { 5, 9, 33 };
    p.mid |= 6;
    p.hi <<= 1;
    printf("%u %u %u %d\n", p.lo, p.mid, p.hi, (int) sizeof(struct Pad));
    struct Mixed m = { .wide = -5, .b = 3, .a = 6 };
    m.flag = 1;
    m.neg = 1;
    m.wide += 1LL << 30;
    printf("%d %d %lld %d %d %d\n", m.a, m.b, m.wide, m.flag, m.neg, (int) sizeof(struct Mixed));
    struct BF c = g;
    bump(&c);
    struct Holder h = { 4, { 2, -7, 11 } };
    h.bf.b += 3;
    printf("%d %d %d %d %d\n", sum(c), sum(g), sum(make(25)), h.bf.b + h.id, (int) sizeof(struct Holder));
    int total = 0;
    for (int i = 0; i < 3; i++) {
        total = total * 7 + sum(table[i]);
    }
    printf("%d %d\n", total, (int) sizeof table);
    struct W w = { { 1, 2, 3 }, { -4, 5, { 6, 7 } } };
    w.r.a += 9;
    struct T tt = { 1, 2 };
    struct Full f = { 0xfedcba9876543210ULL, 100, 1 };
    f.all++;
    f.top--;
    struct Narrow n = { -3, 9 };
    struct LL ll = { -2, 5, { 0 } };
    ll.q--;
    struct Names nm = { 1, 2, 5 };
    printf("%d %d %d %d %d\n", w.r.a, w.r.b + w.r.c[1], tt.y, (int) sizeof(struct W), (int) sizeof(struct T));
    printf("%llx %u %d %d %d %d %d\n", f.all, (unsigned) f.top, f.on, n.a + n.c, (int) ll.q + ll.d, nm._1 + nm._bits9 + nm.f, (int) sizeof(struct LL));
    return s.a + s.b;
}
