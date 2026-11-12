/* P9.23: more counting `for` loops are range loops - `<=` where `n + 1` cannot wrap, a bound over
   globals and members the body provably leaves alone - and the loops that must keep the while form */
int printf(const char *, ...);

static int count = 6;
static int lim = 4;
static int bytes_n = 3;
static int calls = 0;
struct box { int n; float f[8]; };
struct pair { int n; int k; };
union pun { int n; float f; };

static void shrink(void) { lim--; calls++; }
static int twice(int v) { calls++; return v * 2; }

/* a global no pointer reaches: a local store, an int store through a pointer, leave it alone */
static int globals(int *out) {
    int total = 0;
    for (int i = 0; i < count; i++) total += i;
    for (int i = 0; i < count; i++) out[i] = i * 3;
    for (int i = 0; i < count - 1; i++) total += out[i];
    return total;
}

/* a member bound: through a pointer with no store, of a local struct with a call */
static int members(struct box *b) {
    int total = 0;
    struct pair s = {5, 0};
    for (int i = 0; i < b->n; i++) total += i * 10;
    for (int i = 0; i < s.n; i++) total += twice(i);
    return total;
}

/* `<=`: a constant bound, a signed bound and a body that cannot end the run early, unsigned constant */
static int inclusive(int n, unsigned u) {
    int total = 0;
    for (int i = 0; i <= 10; i++) total += i;
    for (int i = 2; i <= n; i++) total += i * 100;
    for (unsigned v = 1u; v <= 9u; v++) total += (int) v;
    for (long long k = 0; k <= (long long) n; k++) total += (int) k;
    for (unsigned v = 0u; v <= u; v++) total += 1;                       /* unsigned, not constant */
    return total;
}

/* the loops that stay while */
static int kept(struct box *b, union pun *u, int big) {
    int total = 0, j;
    for (int i = 0; i < lim; i++) shrink();                              /* the callee writes the bound */
    unsigned char *cp = (unsigned char *) &bytes_n;
    for (int i = 0; i < bytes_n; i++) { total += i; cp[0] = 2; }        /* a char store into the bound */
    for (int i = 0; i <= big; i++) { if (i == 5) break; total += i; }    /* `<=` with a break, INT_MAX */
    for (int i = 0; i <= b->n; i++) total += twice(i);                  /* `<=` with a call, which may exit */
    for (j = 0; j <= 3; j++) total += j;                                 /* the counter read after */
    for (int i = 0; i < b->n; i++) b->f[i] = 0.5f;                       /* a float store, a member bound */
    for (int i = 0; i < b->n; i++) { total += i; b->n--; }               /* the body writes the bound */
    for (int i = 0; i < u->n; i++) { total += 1000; u->f = 0.0f; }       /* a union's other member */
    return total * 100 + j;
}

int main(void) {
    int out[8] = {0};
    struct box b = {5, {0}};
    union pun u = {3};
    printf("%d\n", globals(out));
    printf("%d\n", members(&b));
    printf("%d\n", inclusive(4, 3u));
    printf("%d\n", inclusive(-3, 0u));
    printf("%d\n", kept(&b, &u, 2147483647));
    printf("%d %d %d %d %d\n", lim, bytes_n, calls, b.n, (int) (b.f[4] * 10));
    return 0;
}
