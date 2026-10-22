int printf(const char *, ...);

/* compound literals: a struct's as an initializer, an assignment's value and a call argument; an
   array's passed as a pointer; the address of a struct's; file-scope ones, whose storage is
   static (a union's, one taking the address of a zero-initialized global); one whose items have effects,
   evaluated left to right; a union's; a scalar's, an empty one included; ones under a
   conditional arm, one in a loop's condition; one in a loop, a fresh object per pass */
struct P { int x, y; };
union num { int i; float f; };
struct tagged { int tag; union num n; };

static struct P *origin = &(struct P){ 3, 4 };
static int *primes = (int[]){ 2, 3, 5, 7 };
static union num *shared = &(union num){ .i = 7 };
static int zeroed;
static int **zero_ref = (int *[]){ &zeroed, 0 };
static int order[4];
static int order_n;

static int sum(const int *a, int n) {
    int s = 0;
    for (int i = 0; i < n; i++) {
        s += a[i];
    }
    return s;
}

static int dot(struct P a, struct P b) { return a.x * b.x + a.y * b.y; }

static int len2(const struct P *p) { return p->x * p->x + p->y * p->y; }

static int note(int v) {
    order[order_n++] = v;
    return v;
}

static void struct_literals(void) {
    struct P p = (struct P){ 1, 2 };
    printf("init %d %d\n", p.x, p.y);
    p = (struct P){ .y = 9 };
    printf("assign %d %d\n", p.x, p.y);
    printf("arg %d\n", dot((struct P){ 2, 3 }, p));
    printf("address %d\n", len2(&(struct P){ 3, 4 }));
    struct P *q = &(struct P){ 5, 6 };
    q->x += 10;
    printf("through %d %d\n", q->x, q->y);
}

static void array_literals(void) {
    printf("array %d\n", sum((int[]){ 1, 2, 3 }, 3));
    int *w = (int[4]){ 1 };
    w[3] = 8;
    printf("partial %d %d %d %d\n", w[0], w[1], w[2], w[3]);
    printf("index %d\n", (int[]){ 10, 20, 30 }[1]);
}

static void file_scope(void) {
    printf("static %d %d %d %d %d\n", origin->x, origin->y, sum(primes, 4), shared->i, *zero_ref[0]);
    origin->x = 30;
    printf("kept %d\n", origin->x);
}

static void effects(void) {
    struct P p = (struct P){ note(1), note(2) };
    int *a = (int[]){ note(3), note(4) };
    printf("effects %d %d %d %d", p.x, p.y, a[0], a[1]);
    for (int i = 0; i < order_n; i++) {
        printf(" %d", order[i]);
    }
    printf("\n");
}

static void other_kinds(int c) {
    union num *u = &(union num){ .f = 1.5f };
    printf("union %d\n", (int) (u->f * 2));
    struct tagged t = (struct tagged){ 7, { .i = 9 } };
    printf("tagged %d %d\n", t.tag, t.n.i);
    int s = (int){ 5 } + (int){ 0 };
    int *ps = &(int){ 11 };
    printf("scalar %d %d\n", s, *ps);
    int *arm = c ? (int[]){ 1, 2 } : (int[]){ 3, 4 };
    printf("arm %d %d\n", arm[0], arm[1]);
    union num *pick = c ? &(union num){ .i = 3 } : &(union num){ .f = 2.0f };
    int *none = c ? &(int){} : 0;
    printf("arm union %d %d\n", c ? pick->i : (int) pick->f, none ? *none : -1);
}

static void loop(void) {
    int total = 0;
    for (int i = 0; i < 3; i++) {
        int *row = (int[]){ i, i * 10 };
        row[0] += 1;
        total += row[0] + row[1];
    }
    printf("loop %d\n", total);
    int k = 0;
    while (k < 2 && (k ? (int[]){ 5 } : (int[]){ 6 })[0] > 0) {
        k++;
    }
    printf("condition %d\n", k);
}

int main(void) {
    struct_literals();
    array_literals();
    file_scope();
    effects();
    other_kinds(1);
    other_kinds(0);
    loop();
    return 0;
}
