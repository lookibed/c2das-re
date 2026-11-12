/* function-like macros folded into [inline] defs, and the expansions that stay expanded */
#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>

struct node {
    int v;
    int len;
    struct node *next;
};

static int calls;
static int seen = 4;

static int next(void) { return ++calls; }

/* A: each parameter once, a body calling another macro, the arguments swapped */
#define ADD1(x) ((x) + 1)
#define SUB(a, b) ((a) - (b))
#define GETBITS(i, pos, size) (((i) >> (pos)) & ~((~0u) << (size)))
#define GETA(i) GETBITS(i, 3, 4)
#define OUTER(x) (ADD1(x) * 3)
/* B: a parameter twice, one never read, one read on one arm */
#define SQ(x) ((x) * (x))
#define KEEP(a, b) ((a) * 2 + 1)
#define PICK(c, a, b) ((c) ? (a) : (b))
/* one text per argument type: typed overloads */
#define TWICE(x) ((x) * 2)
/* D: a statement body, with a loop over a parameter */
#define SETV(p, x) do { (p)->v = (x); } while (0)
#define BUMP(p, n) do { int i_; for (i_ = 0; i_ < (n); i_++) (p)[i_] += 1; } while (0)
/* an expression statement */
#define SETLEN(o, t) ((o)->len = (t))
/* a field read through its load folds, a store into it stays expanded */
#define FLD(p) ((p)->v)
/* a pointer result, and the arm of a `?:` with a null arm */
#define NEXT(p) ((p)->next)
/* expanded: an argument read after the body's store, a caller's local, a return; a swap writes
   both locals through references, unless both are one */
#define ORD(p, x) ((p)->v = 1, (p)->v + (x))
#define PLUS_LOCAL(x) ((x) + local)
#define RET_IF(c) do { if (c) return 7; } while (0)
#define SWAP(a, b) { int t_ = (a); (a) = (b); (b) = t_; }
#define ADD2(a, b) ((a) + (b))
/* a caller's local the body writes: a reference parameter, unless another argument reads it */
#define TONUM(o, n) ((o)->len == 1 ? ((n) = (o)->v, 1) : ((o)->len == 2 ? ((n) = -(o)->v, 1) : 0))
#define INC(x) ((x)++)
#define BAD(a, b) ((a) = 1, (a) + (b))
/* a name das takes, and a macro defined twice */
#define length(p) ((p)->len + 0)
#define TAG(x) ((x) + 10)

static int ret_if(int c) {
    RET_IF(c);
    return 3;
}


/* a body action before an effectful argument: a declaration reading an argument or a global */
static int g1, cnt = 1;
int off = 100;
static int bump(void) { return ++cnt; }
#define DSEQ(a, b) do { int t_ = (a); g1 = t_ * 100 + (b); } while (0)
#define BEF(x) do { int c_ = cnt; g1 = c_ * 100 + (x); } while (0)
/* a faulting argument C evaluates after a body call that may exit */
static void check(int c) { if (!c) { printf("checked\n"); exit(3); } }
#define CHECKED(c, v) (check(c), (v))
/* a global named like a parameter, reached through an object-like macro */
#define OFF off
#define ADDOFF(off) ((off) + OFF)
#define ADDOFF2(x) ((x) + OFF)
/* a local declared in an inner block leaves scope: the later name is the caller's */
#define SCOPED(x) do { { int nn = (x); g1 += nn; } g1 += nn; } while (0)
/* never folded, a type argument, a compound literal, an argument's address */
#define ID(x) (x)
#define CASTI(t, e) ((t)(e) + 1)
#define FIRSTV(a) (((struct node){(a), 0, NULL}).v)
#define ADDR(x) (&(x))

static int review_cases(void) {
    int i = 5, j = 1, k = 3, nn = 40, n = 7, d = 0;
    volatile int vv = 4;
    DSEQ(i, ++i);
    printf("m %d", g1);
    DSEQ(j, j++);
    printf(" %d", g1);
    DSEQ(k, k = 10);
    printf(" %d", g1);
    BEF(bump());
    printf(" %d", g1);
    DSEQ(i, 3);
    printf(" %d", g1);
    BEF(7);
    printf(" %d\n", g1);
    g1 = 0;
    SCOPED(2);
    int *pi = ADDR(n);
    printf("n %d %d %d %d %d %d", ADDOFF(3), ADDOFF2(3), g1, ID(n), CASTI(int, 2.5), FIRSTV(n));
    printf(" %d %d\n", SQ(vv), *pi);
    printf("o %d\n", CHECKED(1, n + d));
    return CHECKED(d != 0, n / d);
}

int main(void) {
    struct node n2 = {20, 2, NULL};
    struct node n1 = {10, 1, &n2};
    struct node *p = &n1;
    int arr[4] = {1, 2, 3, 4};
    int *ap = arr;
    int local = 5;
    int i = 9, j = 2, k = 0;
    double d = 1.5;
    unsigned u = 0x1f8u;
    int sum = ADD1(i) + SUB(i, j) + SUB(j, i) + (int)GETA(u) + OUTER(j);
    printf("a %d\n", sum);
    sum = SQ(i) + SQ(n1.v) + SQ(i + j) + KEEP(i, 7) + KEEP(i, j) + PICK(k, i, j);
    printf("b %d\n", sum);
    /* faulting arguments read twice or on one arm: an element, a field through ->, a division */
    sum = SQ(arr[1]) + SQ(p->v) + SQ(i / j) + PICK(k, p->v, j) + KEEP(i, arr[2]);
    printf("c %d\n", sum);
    /* effectful arguments: one evaluated once folds, twice or beside another stays */
    sum = ADD1(next()) + SQ(next()) + ADD2(next(), next());
    printf("d %d %d\n", sum, calls);
    printf("e %d %d %d\n", TWICE(i), (int)TWICE(d), TWICE(i < j));
    SETV(p, 30);
    BUMP(ap, j);
    SETLEN(p, 6);
    printf("f %d %d %d %d %d\n", n1.v, arr[0], arr[1], arr[2], n1.len);
    FLD(p) = FLD(p) + 1;
    printf("g %d %d\n", FLD(p), NEXT(p) != NULL ? NEXT(p)->v : 0);
    struct node *q = k ? NEXT(p) : NULL;
    printf("h %d %d\n", q == NULL, ORD(p, p->v));
    sum = PLUS_LOCAL(i) + ret_if(k) + ret_if(1) + seen;
    SWAP(i, j);
    printf("i %d %d %d\n", sum, i, j);
    printf("j %d %d\n", length(p), TAG(i));
#undef TAG
#define TAG(x) ((x) + 20)
    printf("k %d\n", TAG(i));
    struct node t1 = {4, 1, NULL}, t2 = {6, 2, NULL};
    int m1 = 0, m2 = 0, m3 = 8;
    int ok = TONUM(&t1, m1) && TONUM(&t2, m2);
    INC(m3);
    int z = BAD(m3, m3);
    SWAP(m2, m2);
    printf("l %d %d %d %d %d\n", ok, m1, m2, m3, z);
    return review_cases();
}
