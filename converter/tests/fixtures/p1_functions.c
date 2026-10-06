int printf(const char *, ...);
void exit(int);
int g = 5;
static int counter;
static int bump(int by) { counter += by; return counter; }
int twice(int v) { v = v * 2; return v; }
double mix(int a, double b) { return a + b; }
void noop(void) { }
int main(void) {
    int v = 3;
    noop();
    printf("%d %d %d\n", twice(v), v, bump(2) + bump(3));
    printf("%g %d %lu\n", mix(1, 0.5), g, sizeof(int) + sizeof v);
    g += twice(g);
    printf("%d\n", g);
    exit(42);
    return 0;
}
