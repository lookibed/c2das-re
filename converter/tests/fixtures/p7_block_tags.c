/* P7.5 fixture: a struct or union tag defined again in a block, hiding the outer definition
   (c-testsuite 00044, 00053). The inner record takes the first numbered tag the unit leaves
   free (`T1` is the program's own, so a hiding `T` is `T2`); an expression of the hidden type
   inside the block (`outer.x`, a call returning it, a pointer to it, a macro's argument) keeps
   the outer record, a tag a `for` declaration defines ends with the statement, and a file-scope
   record first reached inside the block names the file-scope tags. Converted
   output must match the native build of this file. */
#include <stdio.h>

struct T {
    int x;
    struct T *self;
};

struct T1 {
    char tag;
};

union V {
    int i;
    unsigned char b[4];
};

/* `struct B` is file scope though it nests in `struct A` */
struct A {
    struct B {
        short lo, hi;
    } b;
};

struct U;

/* a macro's argument of the hidden type keeps its record */
#define X_OF(s) ((s).x)

static struct T make(int x) {
    struct T t;
    t.x = x;
    t.self = 0;
    return t;
}

/* no declaration before `main` names `struct U`: its first use is inside the block */
static int via_u(void *p);

/* a function's name is no free tag: the second `struct S` is `S2` */
static int S1(void) {
    return 1;
}

static int siblings_one(void) {
    struct S {
        int a;
    } s = {3};
    return s.a;
}

static int siblings_two(void) {
    struct S {
        double d;
        int b;
    } s = {0.5, 4};
    return s.b + (int)(s.d * 2) + S1();
}

/* `struct W *` in a block before W's one definition names that definition */
static int ahead(void) {
    struct W *b = 0;
    return b == 0;
}

struct W {
    int k;
};

static int after(void) {
    struct W w = {4};
    struct W *b = &w;
    return b->k;
}

int main(void) {
    struct T outer = make(7);
    struct T *op = &outer;
    struct T1 one = {'k'};
    union V v;
    struct A a;
    int total = 0;
    v.i = 0;
    a.b.lo = 2;
    a.b.hi = 3;
    {
        /* a self-referential record hiding the file-scope `struct T` */
        struct T {
            double w;
            struct T *next;
        } inner = {1.5, 0};
        struct T list[2];
        union V {
            long long wide;
            char c;
        } w;
        struct B {
            char only;
        } b = {'q'};
        /* an expression is the first to reach `struct U` */
        int no_u = (struct U *)0 == 0;
        typedef struct T node_t;
        node_t *head = &list[0];
        list[0].w = 2.5;
        list[0].next = &inner;
        list[1] = inner;
        w.wide = 40;
        /* the hidden record through a variable, a pointer, a call and a member */
        total += outer.x + op->x + (int)(head->next->w * 2);
        outer = make(5);
        total += outer.x + X_OF(outer) + X_OF(*op);
        /* a compound literal of the hiding type */
        total += (int)((struct T){3.5, 0}).w;
        total += (int)sizeof(struct T) + (int)sizeof(outer) + (int)w.wide + b.only;
        total += a.b.lo + (int)sizeof(a.b) + (int)list[1].w + no_u;
        printf("inner %d %d %d\n", (int)sizeof(inner), (int)sizeof(union V), (int)sizeof(struct B));
        {
            struct T1 {
                int deep;
            } d = {9};
            total += d.deep + (int)sizeof(struct T1);
        }
    }
    /* a tag a `for` declaration defines ends with the statement */
    for (struct T { char c; } a = {1}; a.c; a.c = 0)
        total += a.c + (int)sizeof(struct T);
    total += one.tag + (int)sizeof(struct T) + (int)sizeof(union V) + v.i;
    printf("%d %d %d %d\n", total, siblings_one(), siblings_two(), ahead() + after());
    return via_u(0);
}

struct U {
    struct T *t;
    int n;
};

static int via_u(void *p) {
    struct U *u = p;
    struct U local;
    struct T t = make(3);
    local.t = &t;
    local.n = 1;
    if (u == 0)
        u = &local;
    return u->t->x + u->n - 4;
}
