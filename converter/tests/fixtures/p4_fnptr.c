/* P4.3 fixture: function pointers - qsort and bsearch with converted comparators, a callback
   table, a function-pointer field called through `->`, casts between function pointer types,
   a union of function pointers stored through one member and called through another, zero
   function pointers, const function pointers and null tests. Converted output must match the
   native build of this file. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct Rec {
    int key;
    int tags[2];
};

/* a comparator that copies its parameters into typed locals */
static int cmp_int(const void *a, const void *b) {
    const int *x = a;
    const int *y = b;
    return *x - *y;
}

/* one that reads through casts, and never writes or copies a parameter */
static int cmp_desc(const void *a, const void *b) {
    return *(const int *)b - *(const int *)a;
}

static int cmp_rec(const void *a, const void *b) {
    const struct Rec *x = a, *y = b;
    return x->key < y->key ? -1 : x->key > y->key;
}

static int cmp_str(const void *a, const void *b) {
    return strcmp(*(char *const *)a, *(char *const *)b);
}

static int twice(int v) { return v * 2; }
static int square(int v) { return v * v; }
static int negate(int v) { return -v; }

static int (*ops[3])(int) = { twice, square, &negate };

struct Counter {
    int n;
    void (*step)(struct Counter *);
};

static void bump(struct Counter *c) { c->n += 3; }

/* a function pointer parameter, called with a pointer parameter the body also writes through */
static void apply_to(void (*f)(struct Counter *), struct Counter *c) {
    c->n++;
    f(c);
}

static int add3(int a, int b, int c) { return a + b + c; }

/* handlers of three arities in one union, stored through one member and called through another */
typedef void (*handler_v)();
typedef void (*handler_p1)(void *);
typedef void (*handler_p2)(void *, void *);
typedef union {
    handler_p1 h1;
    handler_v h0;
    handler_p2 h2;
} handler_t;

struct task {
    struct task *next;
    handler_t run;
};

struct unit {
    struct task task;
    int health;
};

struct gun {
    int ammo;
};

struct frame {
    int tics;
};

static void unit_tick(struct unit *u) { u->health -= 1; }
static void gun_fire(struct gun *g, struct frame *f) {
    g->ammo -= 1;
    f->tics = 4;
}

typedef struct {
    int sprite;
    handler_t action;
    int next;
} step_t;

static step_t steps[] = {
    { 1, { (handler_p1) gun_fire }, 1 },
    { 2, { 0 }, 0 },
};

/* an array of function pointers inside a union */
union Slots {
    void (*fns[2])(struct Counter *);
    long raw[2];
};

static int (*unset)(int);

/* zero function pointers: an array's fill, a sparse array, a record holding an array of them,
   and a function falling off its end */
typedef int (*ifn)(int);
static int inc(int v) { return v + 1; }
struct Table {
    int n;
    ifn f[2];
};
static struct Table table = { 1, { inc } };
static ifn get(int k) {
    if (k) {
        return inc;
    }
}

/* const function pointers: a member read through a const record, a const table, a const local */
struct cmd {
    const char *name;
    ifn fn;
};
static const struct cmd cmds[] = { { "inc", inc }, { "twice", twice } };
struct ops {
    ifn f;
};
static int run_ops(const struct ops *o) { return o->f(1); }
static double half(double d) { return d / 2; }
static double (* const halves[])(double) = { &half };

/* pointers passed down a chain of calls that never write through them */
struct Holder {
    const int *p;
};
static const int seven = 7;
static const int *const gp = &seven;
static int deep(const int *p) { return *p; }
static int leaf(const int *p) { return deep(p); }
static int mid(const int *p, const int *q, int c) { return leaf(c ? p : q); }
static int field(struct Holder s) { return leaf(s.p); }
static int global(void) { return leaf(gp); }

/* a function whose value is taken, writing through and stepping its parameter */
static void fill(int *p) {
    *p++ = 1;
    *p = 2;
}

/* function pointer parameters: one copied into a local, one reassigned and passed on; a
   function value has no pointee, so neither is `var` */
static int call_copy(ifn g, int v) {
    ifn h = g;
    return h(v);
}
static int call_default(ifn f, int v) {
    if (!f) {
        f = inc;
    }
    return call_copy(f, v);
}

/* a stepped parameter whose copy name the source already uses, as a parameter and as a local */
static void put(int *p, int p_in) {
    *p++ = p_in;
    *p = p_in + 1;
}
static int put_local(int *q) {
    int q_in = 4;
    *q++ = q_in;
    *q = q_in;
    return q_in;
}

int main(void) {
    int arr[] = { 41, 7, 19, 3, 88, 3, 0, -5, 12, 61, 7, 30, 2, 9, 70, 15, 44, 1 };
    int n = (int) (sizeof arr / sizeof arr[0]);
    qsort(arr, n, sizeof(int), cmp_int);
    for (int i = 0; i < n; i++) {
        printf("%d ", arr[i]);
    }
    printf("\n");
    int key = 19;
    int *hit = bsearch(&key, arr, n, sizeof arr[0], cmp_int);
    key = 20;
    int *miss = bsearch(&key, arr, n, sizeof arr[0], cmp_int);
    printf("hit at %d, miss %d\n", (int) (hit - arr), miss == NULL);
    qsort(arr, 5, sizeof(int), cmp_desc);
    printf("desc head %d %d\n", arr[0], arr[4]);
    qsort(arr, 0, sizeof(int), cmp_int);
    qsort(arr, 1, sizeof(int), cmp_int);

    struct Rec recs[4] = { { 3, { 30, 31 } }, { 1, { 10, 11 } }, { 4, { 40, 41 } }, { 2, { 20, 21 } } };
    qsort(recs, 4, sizeof(struct Rec), cmp_rec);
    for (int i = 0; i < 4; i++) {
        printf("%d:%d,%d ", recs[i].key, recs[i].tags[0], recs[i].tags[1]);
    }
    printf("\n");

    char *words[] = { "pear", "apple", "fig", "banana" };
    qsort(words, 4, sizeof(char *), cmp_str);
    printf("%s %s %s %s\n", words[0], words[1], words[2], words[3]);

    int acc = 5;
    for (int i = 0; i < 3; i++) {
        acc = ops[i](acc) + (*ops[i])(1);
    }
    int (*local_ops[2])(int) = { square, twice };
    printf("ops %d %d\n", acc, local_ops[1](local_ops[0](3)));

    struct Counter c = { 0, bump };
    struct Counter *pc = &c;
    pc->step(pc);
    apply_to(c.step, pc);
    printf("counter %d\n", c.n);

    /* a cast to another function type and back is defined C */
    void (*erased)(void) = (void (*)(void)) add3;
    int (*restored)(int, int, int) = (int (*)(int, int, int)) erased;
    printf("restored %d, same %d\n", restored(1, 2, 3), restored == add3);
    /* pointer parameters of any pointee pass alike */
    int (*by_bytes)(const unsigned char *, const unsigned char *) = (int (*)(const unsigned char *, const unsigned char *)) cmp_int;
    int l = 9, r = 4;
    printf("by bytes %d\n", by_bytes((const unsigned char *) &l, (const unsigned char *) &r));

    struct unit un = { { NULL, { NULL } }, 10 };
    if (!un.task.run.h1) {
        printf("no task\n");
    }
    un.task.run.h1 = (handler_p1) unit_tick;
    if (un.task.run.h0 != NULL) {
        un.task.run.h1(&un);
    }
    struct gun gn = { 5 };
    struct frame fr = { 0 };
    for (int s = 0; s < 2; s++) {
        if (steps[s].action.h2) {
            steps[s].action.h2(&gn, &fr);
        } else {
            printf("step %d has no action\n", s);
        }
    }
    un.task.run.h0 = (handler_v) (-1);
    printf("health %d ammo %d tics %d removed %d\n", un.health, gn.ammo, fr.tics, un.task.run.h0 == (handler_v) (-1));
    printf("task %d step %d\n", (int) sizeof(struct task), (int) sizeof(step_t));

    union Slots sl;
    sl.fns[0] = bump;
    sl.fns[1] = 0;
    sl.fns[0](&c);
    printf("slots %d %d\n", c.n, sl.fns[1] == 0);

    ifn zeros[3] = { 0 };
    ifn sparse[3] = { [2] = inc };
    ifn pair2[2] = { inc, 0 };
    ifn (*getter)(int) = get;
    printf("zeros %d %d %d %d %d\n", zeros[1] == 0, sparse[0] == 0, sparse[2](1), pair2[1] == 0, table.f[1] == 0);
    printf("nested %d %d\n", getter(1)(5), table.f[0](table.n));

    struct ops o = { inc };
    int (*const cf)(int) = inc;
    printf("const %d %d %d %d %g\n", cmds[0].fn(5), cmds[1].fn(5), run_ops(&o), cf(2), halves[0](3.0));

    int a = 4, b = 5;
    struct Holder h = { &b };
    printf("chain %d %d %d\n", mid(&a, &b, 0), field(h), global());
    int pair[2] = { 0, 0 };
    void (*filler)(int *) = fill;
    filler(pair);
    printf("filled %d %d\n", pair[0], pair[1]);
    printf("defaults %d %d\n", call_default(0, 1), call_default(twice, 4));
    put(pair, 8);
    printf("put %d %d\n", pair[0], pair[1]);
    int got = put_local(pair);
    printf("put local %d %d %d\n", got, pair[0], pair[1]);

    printf("unset %d %d\n", unset == NULL, !unset);
    unset = negate;
    return unset(-7) == 7 ? 0 : 1;
}
