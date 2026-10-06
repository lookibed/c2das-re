int printf(const char *, ...);
int next(void) { static int n = 0; return n++; }
int main(void) {
    int c, x, y;
    int a0 = 0;
    int k = 0;
    if ((c = next()) != 5) printf("c=%d\n", c);
    x = next();
    y = ++x;
    printf("%d %d\n", x, y);
    y = x++;
    printf("%d %d\n", x, y);
    y = x--;
    printf("%d %d\n", x, y);
    a0 = next() + k++;
    printf("%d %d\n", a0, k);
    x = (y = 7) + 1, k = x;
    printf("%d %d %d\n", x, y, k);
    x = next() ? next() : next();
    printf("%d\n", x);
    x = k ? (y = 1) : (y = 2);
    printf("%d %d\n", x, y);
    x = (k < 100 && next() > 0) ? 1 : 0;
    printf("%d %d\n", x, next());
    return 42;
}
