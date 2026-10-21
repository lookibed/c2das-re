int printf(const char *, ...);

/* a block a goto enters declares a local named like a global: the later reads stay the global's */
int g = 40;
static int into_hiding_block(int skip) {
    int n = 0;
    if (skip) goto in;
    {
        int g = 3;
        n += g;
    in:
        n += 1;
    }
    return n * 100 + g;
}

/* a block a goto enters declares a local named like a later block's */
static int into_twin_block(int skip) {
    int n = 0;
    if (skip) goto in;
    {
        int t = 2;
        n += t;
    in:
        n += 10;
    }
    {
        int t = 5;
        n += t * 100;
    }
    return n;
}

/* a local declared under one case label and used under later ones */
static int case_local(int k) {
    int r = 0;
    switch (k) {
    case 0:;
        int v = 1;
        r += v;
    case 1:
        v = 7;
        r += v;
        break;
    case 2:
        v = 20;
        r += v * 2;
        break;
    default:
        r = -1;
    }
    return r;
}

static int case_local_chain(int k) {
    switch (k) {
    case 0:;
        int w = 5;
        return w;
    case 1:
        w = 6;
        return w * 2;
    default:
        return 0;
    }
}

union un { int i; float f; };

/* a later case's own block, and a `for`'s first clause, declare the name of a case-level
   local: the switch's stays where C declares it, while a use at the body's level under a later
   label still carries it */
static int case_twin(int k) {
    int r = 0;
    switch (k) {
    case 0:;
        union un u = {5};
        int v = 1;
        r = u.i + v;
        break;
    case 1: {
        union un u = {9};
        r = u.i * 2;
        break;
    }
    case 2:
        for (int v = 0; v < 3; v++) {
            r += v;
        }
        break;
    case 3:
        v = 7;
        r = v;
        break;
    default:
        r = -1;
    }
    return r;
}

struct cell { int a; unsigned bf : 5; unsigned top : 3; };

static int calls;
static int store[4];
static int *next(void) { calls++; return &store[calls & 3]; }
static int pick(int k) { calls++; return k; }
static struct cell cells[2];
static struct cell *cell_at(void) { calls++; return &cells[1]; }

/* a value-producing step of an lvalue whose index has an effect */
static void step_value(void) {
    struct cell arr[3] = {{0, 0, 0}, {0, 0, 0}, {0, 0, 0}};
    int k = 0;
    int v = arr[k++].a++;
    int w = ++arr[k++].a;
    printf("step %d %d %d %d %d %d\n", v, w, arr[0].a, arr[1].a, arr[2].a, k);
}

/* `++` and `op=` through a call */
static void through_call(void) {
    calls = 0;
    (*next())++;
    *next() += 5;
    int u = (*next())++;
    int x = ++*next();
    cell_at()->a += 3;
    int y = cell_at()->a++;
    int z = (cell_at()->a = 9);
    printf("arrow %d %d %d %d\n", y, z, cells[1].a, calls);
    printf("call %d %d %d %d %d %d %d\n", calls, store[0], store[1], store[2], store[3], u, x);
}

/* an assignment used as a value stores once and yields the stored value */
static void assign_value(void) {
    char src[6] = "abcd";
    char dst[6] = {0};
    char *d = dst;
    const char *s = src;
    int copied = 0;
    while ((*d++ = *s++)) {
        copied++;
    }
    printf("copy %d %s %d %d\n", copied, dst, (int) (d - dst), (int) (s - src));
    int p[3] = {0, 1, 2};
    int q[3] = {5, 0, 7};
    int *pp = p;
    int *qq = q;
    int hits = 0;
    if ((*pp++ = *qq++)) {
        hits++;
    }
    if ((*pp++ = *qq++)) {
        hits += 10;
    }
    printf("if %d %d %d %d %d\n", hits, p[0], p[1], (int) (pp - p), (int) (qq - q));
    int a[4] = {0, 0, 0, 0};
    int i = 0;
    int got = (a[i++] = 9);
    int got2 = (a[i++] = got + 1) * 2;
    calls = 0;
    int viaf = (*next() = 33);
    printf("value %d %d %d %d %d %d %d\n", got, got2, i, a[0], a[1], viaf, calls);
}

/* compound stores and steps of a bitfield and a small integer through an effectful index */
static void compound_effects(void) {
    struct cell cs[3] = {{0, 1, 0}, {0, 2, 0}, {0, 3, 0}};
    struct cell *p = cs;
    signed char bytes[3] = {10, 20, 30};
    calls = 0;
    p[pick(1)].bf += 5;
    p[pick(2)].top++;
    cs[pick(0)].bf -= 1;
    bytes[pick(1)] += 7;
    bytes[pick(2)]++;
    int n = 0;
    int bv = (p[n++].bf += 4);
    int *rows[2] = {&store[0], &store[2]};
    int *was = rows[pick(1)]++;
    _Bool flags[2] = {0, 0};
    flags[pick(1)] |= 2;
    printf("more %d %d %d %d\n", (int) (was - store), (int) (rows[1] - store), flags[0], flags[1]);
    printf("bits %d %u %u %u %u %d %d %d %d %d\n", calls, cs[0].bf, cs[1].bf, cs[2].bf, cs[2].top, bytes[1], bytes[2], bv, n, cs[0].bf);
}

static int gi;
static int *gp;
static int gi_to_one(void) { calls++; gi = 1; return 100; }
static int gi_to_zero(void) { calls++; gi = 0; return 100; }
static int gp_away(void) { calls++; gp = &store[0]; return 100; }

/* a pinned target spelled by a variable's own name, which a call later in the statement
   changes: the slot is the same whichever side runs first, so the shapes are determinate */
static void pinned_names(void) {
    int uc[4] = {0, 0, 0, 0};
    int q[4] = {1, 2, 3, 4};
    calls = 0;
    gi = 1;
    uc[++gi] += gi_to_one();
    *(gp = q + 1) += gp_away();
    int v = (uc[gi = 2] += gi_to_zero());
    printf("names %d %d %d %d %d %d %d\n", uc[0], uc[1], uc[2], uc[3], q[1], v, calls);
}

int main(void) {
    printf("goto %d %d %d %d %d\n", into_hiding_block(0), into_hiding_block(1), g, into_twin_block(0), into_twin_block(1));
    printf("switch %d %d %d %d %d %d\n", case_local(0), case_local(1), case_local(2), case_local(3), case_local_chain(0), case_local_chain(1));
    printf("twin %d %d %d %d %d\n", case_twin(0), case_twin(1), case_twin(2), case_twin(3), case_twin(4));
    step_value();
    through_call();
    assign_value();
    compound_effects();
    pinned_names();
    return 0;
}
