int printf(const char *, ...);
enum E { E0, E1 };
struct S { int n; _Bool flag; };
struct F { unsigned v : 3; _Bool on : 1; };
static _Bool gflag = 1;
static _Bool garr[3] = { 0, 1, 1 };
static _Bool sparse[200] = { 1, [150] = 1 };
static int take(_Bool b) { return b ? 10 : 20; }
static _Bool g(int x) { return x > 1; }
static _Bool h(int x) { return x; }
static int count = 0;
static int tick(void) { count++; return count; }
int main(void) {
    int x = 7;
    _Bool b = x > 3;
    _Bool c = 5;
    b = !b;
    if (b) {
        x += 100;
    }
    while (c) {
        c = 0;
    }
    int i = b;
    double d = c;
    int arr[2] = { 40, 41 };
    _Bool *p = &b;
    *p = gflag;
    _Bool local[4] = { 0 };
    local[2] = b;
    struct S s = { 3, 1 };
    s.flag = i;
    struct S t = { .flag = x > 9 };
    b += 1;
    c |= 0;
    enum E e = b;
    _Bool hoisted = x > 50 ? b : (c = tick());
    printf("%d %d %d %g %d %d %d\n", b, c, i, d, b && c, b == c, b < c);
    printf("%d %d %d %d %d %d\n", b + c, arr[b], take(b), take(x > 9), take(x), g(x) + h(0));
    printf("%d %d %d %d %d %d %d\n", local[2], s.flag, t.flag, garr[1], sparse[150] + sparse[1], (int) e, hoisted);
    switch (b) {
    case 1:
        x += 1000;
        break;
    default:
        break;
    }
    struct F f = { 5, 1 };
    if (!f.on) {
        x = 0;
    }
    if (f.on) {
        x += f.v;
    }
    printf("%d %d %d\n", x, b ? 1 : 0, count);
    return b;
}
