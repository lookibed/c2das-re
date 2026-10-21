/* P4.7a: parameters the body writes, under both --param-writes modes */
#include <stdio.h>

struct holder {
    int *p;
    int n;
};

/* a stepped int parameter */
static int count_down(int n) {
    int steps = 0;
    while (n-- > 0) {
        steps += 2;
    }
    return steps + n;
}

/* an assigned pointer parameter walking an array */
static int sum_walk(const int *p, int n) {
    int s = 0;
    const int *end = p + n;
    for (; p != end; p = p + 1) {
        s += *p;
    }
    return s;
}

static void set_to(int *where, int v) {
    *where = v;
}

/* the address of a parameter passed to a callee */
static int through_address(int x) {
    set_to(&x, x * 3);
    return x + 1;
}

static int read_at(int *q) {
    return *q;
}

/* a pointer parameter reassigned, then passed on */
static int reassigned(int *q, int k) {
    q = q + k;
    *q += 100;
    return read_at(q);
}

/* a by-value record parameter holding a pointer, its fields written */
static int record_param(struct holder h) {
    *h.p += h.n;
    h.n = 0;
    h.p = 0;
    return h.n;
}

/* a function value whose callee writes its parameter */
static int halve_until(int v) {
    int rounds = 0;
    while (v > 1) {
        v /= 2;
        rounds++;
    }
    return rounds * 10 + v;
}

static int apply(int (*fn)(int), int v) {
    v += 1;
    return fn(v);
}

/* an aliasing call: the record by value and a pointer to the same object */
static int aliased(struct holder a, struct holder *b) {
    b->n = 5;
    return a.n;
}

/* a scalar written through its own address and stepped, under the same name as a local */
static int shadowed(int v_in, int v) {
    int *pv = &v;
    *pv += v_in;
    v++;
    return v;
}

int main(void) {
    int arr[6] = {1, 2, 3, 4, 5, 6};
    int n = 4;
    int r = count_down(n);
    printf("%d %d\n", r, n);
    int *walk = arr;
    r = sum_walk(walk, 6);
    printf("%d %d\n", r, walk == arr);
    int x = 7;
    r = through_address(x);
    printf("%d %d\n", r, x);
    int *q = arr;
    r = reassigned(q, 2);
    printf("%d %d %d\n", r, arr[2], q == arr);
    struct holder h = {&arr[0], 9};
    r = record_param(h);
    printf("%d %d %d %d\n", r, arr[0], h.n, h.p == &arr[0]);
    int (*fn)(int) = halve_until;
    int v = 40;
    r = apply(fn, v);
    printf("%d %d\n", r, v);
    struct holder a = {&arr[1], 1};
    r = aliased(a, &a);
    printf("%d %d\n", r, a.n);
    printf("%d\n", shadowed(3, 4));
    return 0;
}
