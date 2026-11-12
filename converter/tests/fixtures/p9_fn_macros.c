/* function-like macro expansions the dumper marks, one shape per class */
#include <stdio.h>
#include <stdarg.h>
#include <stddef.h>
#include <sys/param.h>
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
#define ADD(a, b) a + b
/* a body's other call with a constant argument, with and without parentheses; one macro called
   twice with the arguments swapped; an argument spelled like a body token through an object-like
   macro */
#define S4(x) (ADD1(x) + ADD1(0))
#define S3(x) ADD1(x) + ADD1(0)
#define SUB(a, b) ((a) - (b))
#define ANTI(x, y) (SUB(x, y) + SUB(y, x) * 2)
#define K 5
#define ADDK(x) ((x) + K)
/* system macros: a program macro calling one is followed no further */
#define BIGGER(a, b) (MAX(a, b) + 0)
/* one body calling another macro twice with arguments of its own text, and two bodies alike but
   for the constant they name */
#define BOTH2(x) (SQ(x + 1) - SQ(x + 2))
#define TAGV 3
#define TAGF 4
#define CHK(c, t) (TAG_OF(c) == (t))
#define IS_V(c) CHK(c, TAGV)
#define IS_F(c) CHK(c, TAGF)
#define EITHER(c) (IS_F(c) || IS_V(c))
/* calls whose every argument goes through a called parameter: nothing tells their nodes apart */
#define APPLY3(f, x) (ADD1(f(x)) + ADD1(f(0)))
/* parentheses around one call: the node of both, the outer first */
#define OUTP(x) (ADD1(x))

static int calls;

static int next(void) { return ++calls; }

static int twice(int v) { return 2 * v; }

/* va_start and va_end are a system header's: no mark */
static int first_of(int n, ...) {
    va_list ap;
    va_start(ap, n);
    int v = va_arg(ap, int);
    va_end(ap);
    return v;
}

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
    sum += S4(i) + S3(i) * 3 + ANTI(i, j);
    sum += ADDK(K) + MUL2(i + 1) + ADD(i ? 1 : 2, 3);
    sum += BIGGER(i, j) + (int)offsetof(struct cell, v) + OUTP(i) + first_of(1, 2);
    sum += BOTH2(i) + EITHER(p);
    sum += APPLY3(twice, i);
    printf("%d %d %d %d %d\n", sum, n, j, k, c.v);
    return 0;
}
