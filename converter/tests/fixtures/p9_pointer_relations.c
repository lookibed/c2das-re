int printf(const char *, ...);
typedef unsigned long uintptr_t;
static int cells[4] = { 1, 2, 3, 4 };
/* a relation of two addresses in a global initializer */
static int ordered = &cells[2] > &cells[1];
static int twice(int x) { return 2 * x; }
static int thrice(int x) { return 3 * x; }
int main(void) {
    int *p = &cells[3];
    int *q = cells;
    void *v = q;
    int (*f)(int) = twice;
    int (*g)(int) = thrice;
    printf("%d %d %d %d %d\n", p < q, p <= q, p >= q, p != q, q < p);
    printf("%d %d %d %d\n", p > v, v != p, v == q, v <= q);
    printf("%d %d %d %d\n", f <= f, f < f, g >= g, f != g);
    printf("%d %d\n", ordered, f(1) + g(1));
    /* a pointer sum cast to void * against a void *: the cast keeps the address */
    printf("%d %d\n", (void *) (p - 1) < v, (void *) (q + 1) >= v);
    /* a variable count, a cast over a sum on the right, and a cast from an integer, which stays */
    int n = 2;
    uintptr_t x = (uintptr_t) p;
    printf("%d %d %d\n", (void *) (q + n) < v, v < (void *) (q + n), (char *) x < (char *) p);
    return 0;
}
