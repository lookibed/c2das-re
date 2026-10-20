#include <stdio.h>
#include <alloca.h>
#include <string.h>
/* P4.6 fixture: every data pointer parameter and every record parameter holding one is `var`,
   and every record parameter is copied on entry. Pointers a function only reads pass on to one
   that writes through them: directly, through `?:`, a sum, `*pp`, `pp[i]`, `->`, a record's
   field and a function value; a parameter returns as itself or as a record's field; a record
   parameter passes on, copies into a local, is written, and arrives from a call; a record
   parameter is C's copy even when the caller's object changes during the call, deep in a
   recursion and past das's default stack; a record holds its pointer in an array field or a
   nested record; a cast between function pointer types that spell one das type is no cast */
struct S { int *p; int x; };
struct H { int *q; };
struct P { int x; int y; };
union U { int *p; long v; };
struct W { union U u; int x; };

static void deep(int *p) { *p += 1; }
static void chain(int *p) { deep(p); }
static void pick(int *p, int *q, int c) { deep(c ? p : q); }
static void second(int *p) { deep(p + 1); }
static void through(int **pp) { deep(*pp); }
static void indexed(int **pp) { deep(pp[0]); }
static void arrow(struct H *hp) { deep(hp->q); }
static void field(struct S s) { deep(s.p); }
static void (*sink)(int *) = deep;
static void invoked(int *p) { sink(p); }

static const int *ident(const int *p) { return p; }
static int widen(const int *q) { return *ident(q) + *q; }
static int *fld(struct S s) { return s.p; }

static void bump_rec(struct S s) { *s.p += s.x; }
static void passed_on(struct S s) { bump_rec(s); }
static int copied(struct S s) { struct S t = s; t.x++; *t.p += t.x; return *s.p; }
static int written(struct S s) { s.x = 5; *s.p += s.x; return s.x; }
static struct S make(int *p) { struct S s = {p, 2}; return s; }
static int read_through(const struct S *sp) { struct S t = *sp; return *t.p; }
static void (*rec_sink)(struct S) = bump_rec;

static int alias_plain(struct P s, struct P *q) { q->x = 5; return s.x; }
static int alias_ptr(struct S s, struct S *q) { q->x = 5; *s.p += 1; return s.x; }

struct A { int *ps[2]; int k; };
struct N { struct H h; int k; };
static int arr_leaf(struct A a) { *a.ps[1] += a.k; return *a.ps[0]; }
static int arr_field(struct A a) { return arr_leaf(a); }
static int nested_leaf(struct N n) { *n.h.q += n.k; return *n.h.q; }
static int nested(struct N n) { return nested_leaf(n); }
static int renamed(struct S s, int s_in) { return *s.p + s_in; }

struct big { int i[1000]; };
static struct big gbig;
static int depth(struct big b, int n) { if (n == 0) return b.i[3]; return depth(b, n - 1) + 1; }
struct huge { int i[300000]; };
static struct huge ghuge;
static int huge_leaf(struct huge b) { return b.i[3]; }

typedef int (*reader_t)(int *);
typedef int (*byte_reader_t)(char *);
static int read_const(const int *p) { return *p; }

static int n_picks;
static int *next_pick(int *p) { n_picks++; return p; }
static void set9(int *p) { *p = 9; }
static int fill(void *p) { memset(p, 1, 4); return *(unsigned char *)p; }

int main(void) {
    int x = 0;
    int a[2] = {0, 0};
    int *px = &x;
    struct H h = {&x};
    struct S s = {&x, 2};
    chain(&x);
    pick(&x, &a[0], 1);
    second(a);
    through(&px);
    indexed(&px);
    arrow(&h);
    field(s);
    invoked(&x);
    printf("chains %d %d %d\n", x, a[0], a[1]);
    int w1 = widen(&x);
    int w2 = *fld(s);
    printf("returns %d %d\n", w1, w2);
    passed_on(s);
    int c1 = copied(s);
    int c2 = written(s);
    printf("records %d %d %d %d\n", x, c1, c2, s.x);
    bump_rec(make(&x));
    rec_sink(s);
    int m1 = read_through(&s);
    printf("made %d %d\n", x, m1);
    struct P pp = {1, 2};
    struct S ps = {&x, 1};
    int r1 = alias_plain(pp, &pp);
    int r2 = alias_ptr(ps, &ps);
    printf("alias %d %d %d %d\n", r1, pp.x, r2, ps.x);
    struct W w = {{next_pick(&a[0])}, n_picks};
    set9(w.u.p);
    int f1 = fill(alloca(4));
    struct A ar = {{&a[0], &a[1]}, 3};
    struct N nn = {{&a[1]}, 4};
    int a1 = arr_field(ar);
    int a2 = nested(nn);
    int a3 = renamed(s, 2);
    printf("deep %d %d %d %d %d\n", a1, a2, a3, a[0], a[1]);
    gbig.i[3] = 7;
    ghuge.i[3] = 9;
    int d1 = depth(gbig, 8);
    int d2 = huge_leaf(ghuge);
    reader_t same = (reader_t) read_const;
    byte_reader_t other = (byte_reader_t) read_const;
    int r3 = same(&x);
    int r4 = ((reader_t) other)(&x);
    printf("stack %d %d casts %d %d\n", d1, d2, r3, r4);
    printf("union %d %d %d\n", a[0], w.x, f1);
    return 0;
}
