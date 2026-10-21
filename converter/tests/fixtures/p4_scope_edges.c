int printf(const char *, ...);

static int calls;

/* an array member reached through an effectful index, and a pointer base with an effect */
struct S { int a[3]; };
static struct S ss[3];
static int g(void) { calls++; return calls; }
static int *slot(void) { calls++; return &ss[2].a[calls % 2]; }
static void arr_member(void) {
    calls = 0;
    ss[g()].a[1] += 5;
    ss[g()].a[2]++;
    int v = (ss[g() - 2].a[0] = 4);
    slot()[0] += 7;
    slot()[1]++;
    printf("member %d %d %d %d %d %d %d %d\n", calls, ss[1].a[1], ss[2].a[2], ss[1].a[0], v, ss[2].a[0], ss[2].a[1], ss[2].a[2]);
}

static int cells[4];
static signed char cb[4];
static int *nx(void) { calls++; return &cells[calls % 2]; }
static signed char *cp(void) { calls++; return &cb[calls % 2]; }
static void ptr_index(void) {
    calls = 0;
    cp()[1] += 7;
    int w = (nx()[0] = 9);
    int z = ++nx()[1];
    printf("index %d %d %d %d %d %d %d %d\n", calls, cb[0], cb[1], cb[2], w, z, cells[0], cells[1]);
}

/* a step in an `else if` condition, which the if lowering spells twice: the pins of the first
   spelling are gone by the second */
static int chain[4] = { 0, 5, 0, 0 };
static int *link(void) { calls++; return &chain[calls]; }
static void else_if(void) {
    calls = 0;
    int r = 0;
    if (calls == 7) r = 1;
    else if ((*link())++) r = 2;
    else r = 3;
    printf("elif %d %d %d %d\n", r, calls, chain[1], chain[2]);
}

/* a C variable spelled like an emitter temporary is not one: a call later in the statement
   changes it, so it is pinned */
int _t1;
static int uc[4];
static int t1_to_zero(void) { _t1 = 0; return 100; }
static void temp_named(void) {
    uc[_t1 = 2] += t1_to_zero();
    int v = (uc[_t1 = 3] += t1_to_zero());
    printf("tname %d %d %d %d %d\n", uc[0], uc[1], uc[2], uc[3], v);
}

/* a plain `=` statement through a call pins nothing */
static int *sink(void) { calls++; return &cells[3]; }
static void plain_store(void) {
    calls = 0;
    *sink() = 21;
    printf("plain %d %d\n", calls, cells[3]);
}

/* a carried declaration without an initializer, and one whose initializer is followed by the
   stores of a union inside it */
union un { int i; float f; };
struct holder { int a; union un u; };
static int carried_bare(int k) {
    int r = 0;
    switch (k) {
    case 0:;
        int v;
        v = 3;
        r = v;
    case 1:
        v = 4;
        r += v;
        break;
    default:
        r = -1;
    }
    return r;
}
static int carried_stores(int k) {
    int r = 0;
    switch (k) {
    case 0:;
        struct holder h = { 2, { 5 } };
        r = h.a + h.u.i;
    case 1:
        h.a = 7;
        r += h.a;
        break;
    default:
        r = -1;
    }
    return r;
}

/* a switch inside a loop carries its local too */
static int in_loop(int n) {
    int r = 0;
    for (int k = 0; k < n; k++) {
        switch (k) {
        case 0:;
            int v = 1;
            r += v;
        case 1:
            v = 7;
            r += v;
            break;
        default:
            r += 100;
        }
    }
    return r;
}

/* a use under `default` carries */
static int under_default(int k) {
    int r = 0;
    switch (k) {
    case 0:;
        int v = 2;
        r = v;
    default:
        v = 9;
        r += v;
    }
    return r;
}

/* what a later label resolves: a `for`'s first clause assigning the name carries it, one
   declaring it (alone or among others) binds its own, and a use inside a nested `if` carries */
static int for_assigns(int k) {
    int r = 0;
    switch (k) {
    case 0:;
        int v = 1;
        r = v;
    case 1:
        for (v = 5; r < 50; r += 10) ;
        break;
    default:
        r = -1;
    }
    return r;
}
static int for_declares(int k) {
    int r = 0;
    switch (k) {
    case 0:;
        union un u = {5};
        r = u.i;
        break;
    case 1:
        for (int u = 0; u < 3; u++) r += u;
        break;
    default:
        r = -1;
    }
    return r;
}
static int for_declares_two(int k) {
    int r = 0;
    switch (k) {
    case 0:;
        union un u = {5};
        r = u.i;
        break;
    case 1:
        for (int a = 1, u = 0; u < 3; u++) r += u + a;
        break;
    default:
        r = -1;
    }
    return r;
}
static int nested_use(int k) {
    int r = 0;
    switch (k) {
    case 0:;
        int v = 1;
        r = v;
    case 1:
        if (k < 5) {
            v = 7;
            r += v;
        }
        break;
    default:
        r = -1;
    }
    return r;
}

int main(void) {
    arr_member();
    ptr_index();
    else_if();
    temp_named();
    plain_store();
    printf("carried %d %d %d %d\n", carried_bare(0), carried_bare(1), carried_stores(0), carried_stores(1));
    printf("loop %d %d\n", in_loop(1), in_loop(3));
    printf("default %d %d\n", under_default(0), under_default(5));
    printf("for %d %d %d %d %d %d\n", for_assigns(0), for_assigns(1), for_declares(0), for_declares(1), for_declares_two(0), for_declares_two(1));
    printf("nested %d %d\n", nested_use(0), nested_use(1));
    return 0;
}
