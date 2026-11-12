/* function-like macro expansions the dumper marks, one shape per class */
#include <stdio.h>
#include "p9_fn_macros.h"

/* A: each parameter once */
#define ADD1(x) ((x) + 1)
#define FIELD(p) ((p)->v)
/* B: a parameter twice, never, or in one branch */
#define SQ(x) ((x) * (x))
#define FIRST(a, b) (a)
#define TONUM(c, n) (IS_INT(c) ? ((n) = (c)->v, 1) : 0)
/* C: a local of the caller, a type, a paste */
#define PLUS_LOCAL(x) ((x) + local)
#define CAST(t, e) ((t)(e))
#define GLUE(a, b) a##b
/* D: statements with no outward flow */
#define SETV(p, x) do { (p)->v = (x); } while (0)
#define SWAP(a, b) { int t_ = (a); (a) = (b); (b) = t_; }
/* nested: a body that is one call, calls side by side, a macro of itself */
#define TWICE(x) ADD1((x) * 2)
#define BOTH(x) (ADD1(x) + ADD1(x))
#define FOURTH(x) SQ(SQ(x))
/* a parameter the body calls: the rest of the body is followed */
#define APPLY(f, x) (f((x)) + ADD1(x))
/* an argument split by the body's precedence */
#define MUL2(x) x * 2

static int calls;

static int next(void) { return ++calls; }

static int twice(int v) { return 2 * v; }

int main(void) {
    struct cell c = {3, 5};
    struct cell *p = &c;
    int arr[4] = {1, 2, 3, 4};
    int local = 10;
    int i = 1, n = 0, j = 2, k = 7;
    int sum = ADD1(i) + FIELD(p) + SQ(i) + FIRST(i, 9) + TONUM(p, n);
    sum += PLUS_LOCAL(i) + CAST(int, 2.5) + GLUE(su, m);
    SETV(p, 6);
    SWAP(j, k);
    sum += TWICE(i) + BOTH(i) + FOURTH(i) + MUL2(i + 1) + IS_INT(p);
    /* effectful and faulting arguments */
    sum += SQ(next()) + ADD1(ADD1(i)) + FIRST(i, arr[3]) + FIRST(i, 8 / j) + FIRST(i, (*p).v);
    sum += APPLY(twice, i);
    printf("%d %d %d %d %d\n", sum, n, j, k, c.v);
    return 0;
}
