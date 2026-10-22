int printf(const char *, ...);

/* compound literals: a struct's as an initializer, an assignment's value and a call argument; an
   array's passed as a pointer; the address of a struct's; file-scope ones, whose storage is
   static (a union's, one taking the address of a zero-initialized global); one whose items have effects,
   evaluated left to right; a union's; a scalar's, an empty one included; ones under a
   conditional arm, one in a loop's condition; one in a loop, a fresh object per pass; one in a
   `for` increment, which the next pass reads (C11 6.8.5p5: it lives as long as the loop), plain,
   in a loop a `break` leaves and under a conditional arm; one under a case label, which the group
   a fallthrough reaches reads, and one in a group that breaks; under the arms of a `for` head, of
   `&&`, of a `void` conditional and of an `else if` condition; an array filled sparsely under an
   arm; an empty scalar's value; a record holding a union's list with effects in its items */
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

static void increment(int c) {
    int *p = 0;
    for (int i = 0; i < 3; p = (int[]){ i, i, i }, i++) {
        int big[3] = { 100, 200, 300 };
        if (p) {
            printf("increment %d %d\n", sum(p, 3), big[0]);
        }
    }
    p = 0;
    for (int i = 0; i < 4; p = (int[]){ i, 1, 1 }, i++) {
        int big[3] = { 100, 200, 300 };
        if (p) {
            printf("increment break %d %d\n", sum(p, 3), big[0]);
        }
        if (i == 2) {
            break;
        }
    }
    p = 0;
    for (int i = 0; i < 3; p = c ? (int[]){ i, 2, 2 } : (int[]){ 0, 0, i }, i++) {
        int big[3] = { 100, 200, 300 };
        if (p) {
            printf("increment arm %d %d\n", sum(p, 3), big[0]);
        }
    }
}

static void cases(int j) {
    int *q = 0;
    switch (j) {
    case 0:
        q = (int[]){ 1, 2, 3 };
    case 1: {
        int big[3] = { 100, 200, 300 };
        if (!q) {
            q = big;
        }
        printf("case %d %d\n", sum(q, 3), big[0]);
        break;
    }
    case 2:
        q = (int[]){ 4, 5, 6 };
        printf("case break %d\n", sum(q, 3));
        break;
    default:
        printf("case default\n");
    }
}

static void arms(int c) {
    int k = 0;
    int *seen = 0;
    for (; k < 3 && (seen = (k ? (int[]){ 5, k } : (int[]){ 6, k }))[0] > 0; k++) {
        int big[2] = { 100, 200 };
        printf("for head %d %d %d\n", seen[0], seen[1], big[0]);
    }
    int *kept = 0;
    if (c && (kept = (int[]){ 7, 8 })[0] > 0) {
        int big[2] = { 100, 200 };
        printf("and %d %d %d\n", kept[0], kept[1], big[0]);
    }
    int *armed = 0;
    c ? (void) (armed = (int[]){ 3, 4 }) : (void) 0;
    {
        int big[2] = { 100, 200 };
        printf("void arm %d %d\n", armed ? armed[1] : -1, big[0]);
    }
    int r = 0;
    if (c == 5) {
        r = 1;
    } else if ((c ? (int[]){ 5 } : (int[]){ 6 })[0] > 0) {
        r = 2;
    }
    int *sparse = c ? (int[40]){ [30] = 1 } : 0;
    printf("else if %d sparse %d %d\n", r, sparse ? sparse[30] : -1, sparse ? sparse[3] : -1);
    printf("empty %d\n", (int){} + 2);
}

static void union_effects(void) {
    order_n = 0;
    struct tagged t = (struct tagged){ note(5), { .i = note(6) } };
    printf("union effects %d %d %d %d\n", t.tag, t.n.i, order[0], order[1]);
}

int main(void) {
    struct_literals();
    array_literals();
    file_scope();
    effects();
    other_kinds(1);
    other_kinds(0);
    loop();
    increment(1);
    increment(0);
    for (int j = 0; j < 4; j++) {
        cases(j);
    }
    arms(1);
    arms(0);
    union_effects();
    return 0;
}
