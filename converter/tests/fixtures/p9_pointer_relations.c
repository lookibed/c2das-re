int printf(const char *, ...);
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
    return 0;
}
