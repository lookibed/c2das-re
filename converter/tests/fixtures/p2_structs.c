#include <stddef.h>
int printf(const char *, ...);
typedef struct { int fn; } thinker_t;
typedef struct { thinker_t thinker; int x, y; } mobj_t;
struct P { int a; short b; double d; };
typedef struct P P_t;
struct Node { int v; struct Node *next; };
static mobj_t g = { { 7 }, 1 };
static struct P gp = { .b = 2, .d = 1.5 };
static P_t scale(P_t p, int k) { p.a *= k; p.b = (short) (p.b * k); return p; }
static int sum(struct P p) { return p.a + p.b; }
static mobj_t make(int x) { mobj_t m = { { 3 }, x, x + 1 }; return m; }
static void bump(mobj_t *m) { m->x++; (*m).y += 2; }
int main(void) {
    mobj_t m = g;
    mobj_t *p = &m;
    P_t q = { 1, 2 };
    struct Node n2 = { 2, 0 };
    struct Node n1 = { 1, &n2 };
    bump(p);
    m.x = p->y + q.a + (int) sizeof(mobj_t) + (int) offsetof(mobj_t, x);
    thinker_t *th = &m.thinker;
    mobj_t *back = (mobj_t *) th;
    P_t s = scale(q, 3);
    printf("%d %d %d %d\n", back->x, (*p).y, q.a, s.a + s.b);
    printf("%d %d %g %d\n", sum(gp), gp.b, gp.d, sum(q));
    mobj_t k = make(10);
    printf("%d %d %d %d\n", k.thinker.fn, k.x, k.y, n1.next->v + n1.v);
    printf("%d %d %d\n", (int) offsetof(struct P, d), (int) sizeof(struct Node), (int) sizeof g);
    return m.x - 33;
}
