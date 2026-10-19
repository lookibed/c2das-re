#include <stdio.h>
/* which pointer parameters a copy makes `var`: a pointer read out of one or an address into
   one is copied, a non-pointer value read through one (`*s` of a `char *s`) is not */
struct S { int x; int y; };
struct Q { int *p; int k; };
static int sink(int c) { return c; }
static int say(const char *s) { int t = 0; while (*s) { t += sink(*s); s++; } return t; }
static int say2(const char *s) { return say(s); }
static void show(int *p, int n) { while (n--) { printf("%d\n", *p); p++; } }
static void outer(int *q) { show(q, 2); }
static int get(int v) { return v; }
static int walk(struct S *sp, int n) { int t = 0; while (n--) { t += get(sp->x); sp++; } return t; }
static int idx(int *p, int n) { int t = 0; while (n--) { t += get(p[0]); p += 1; } return t; }
static int first(int *p) { int *l[2] = {p, 0}; return *l[0]; }
static int field(int *p) { struct Q q = {p, 1}; return *q.p + q.k; }
static int *nxt(int *p) { return p++; }
static int pre(int *p) { int *q = ++p; *q = 5; return *q; }
static int *comma(int k, int *p) { return (k++, p); }
static int *row(int **pp) { return pp[1]; }
static int *arrow(struct Q *qp) { return qp->p; }
static int *addr_y(struct S *sp) { return &sp->y; }
int main(void) {
    struct S s[2] = {{1, 2}, {3, 4}};
    int a[2] = {5, 6};
    int *pa[2] = {a, a + 1};
    struct Q q = {a, 0};
    _Bool b = 1;
    int n = 3;
    int r1, r2, r3, r4;
    b <<= n;
    outer(a);
    r1 = say("hi");
    r2 = say2("yo");
    r3 = walk(s, 2);
    r4 = idx(a, 2);
    printf("%d %d %d %d\n", r1, r2, r3, r4);
    r1 = first(a);
    r2 = field(a);
    r3 = *nxt(a);
    r4 = pre(a);
    printf("%d %d %d %d\n", r1, r2, r3, r4);
    printf("%d %d %d %d %d\n", *comma(1, a), *row(pa), *arrow(&q), *addr_y(s), (int) b);
    return 0;
}
