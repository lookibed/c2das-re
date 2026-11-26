/* The conversions census's fixture: one function per counted context, each holding the casts
   clang gives that context. */

typedef struct {
    int a;
    char b;
} pair_t;

enum color { RED, GREEN };

int printf(const char *format, ...);
int knr();
void *memset_like(void *to, int c, unsigned long n);

long g_long = 3;
double g_reals[2] = {1, 2.0f};
const char *g_text = "text";
int (*g_fn)(int, int);

static int add(int a, int b) {
    return a + b;
}

int binary(char c, short s, long l, unsigned u, float f, double d) {
    int r = c + s;
    long m = l * u;
    double x = f + d;
    int y = r < l;
    return y + (int)m + (int)x;
}

int shifts(char c, int r) {
    return r << c;
}

int unary(char c) {
    return -c;
}

void assigns(int r, long l, double x, _Bool b, int *p, void *v) {
    l = r;
    x = r;
    r = x;
    b = r;
    b = p;
    p = v;
    v = p;
    p = 0;
    r += l;
    x *= r;
}

long returns(int r) {
    return r;
}

void calls(char c, float f, short s) {
    printf("%d %f", c, f);
    knr(s, f);
    add(c, s);
    g_fn = add;
    g_fn(1, 2);
    memset_like(&c, 0, 1);
    __builtin_memset(&c, 0, 1);
}

int conditions(int *p, double d, char c) {
    if (p) {
        return 1;
    }
    while (d) {
        d = d - 1;
    }
    return c ? 2 : 3;
}

int switches(char c, enum color k) {
    switch (c) {
    case 'a':
        return 1;
    }
    switch (k) {
    case RED:
        return 2;
    default:
        return 3;
    }
}

int subscripts(int *a, char c, int m[2][2]) {
    return a[c] + m[c][0];
}

double arms(int t, int i, double d, int *p) {
    int *q = t ? p : 0;
    return (t ? i : d) + (q != 0);
}

pair_t copies(pair_t x) {
    pair_t y = x;
    pair_t z[2] = {x, {1, 'c'}};
    (void)z;
    return y;
}

const int *qualify(int *p) {
    return p;
}

char *decay_string(void) {
    char *s = "abc";
    s = (char *)s;
    return s + 1;
}

struct bits {
    unsigned low : 3;
    int whole;
};

typedef __builtin_va_list va_list;

static int kr(p)
int *p;
{
    return p != 0;
}

static long kr_long(n)
long n;
{
    return n;
}

int kr_call(char c) {
    return kr(0) + (int)kr_long(c);
}

int members(struct bits s, struct bits *ps) {
    return s.low + ps->whole;
}

int logic(char c, int t) {
    return (c && t) + !c;
}

long commas(int a, long b) {
    return (a, b);
}

int va_first(int n, ...) {
    va_list ap;
    __builtin_va_start(ap, n);
    char r = __builtin_va_arg(ap, int);
    __builtin_va_end(ap);
    return r;
}

long literal(void) {
    return ((struct bits){1, 'c'}).whole;
}

int loops(char c) {
    int s = 0;
    for (char i = 0; i < c; (void)(i += 1)) {
        s += i;
    }
    do {
        s--;
    } while (c);
    if (s) {
        s = 1;
    } else {
        s = c;
    }
    return s;
}

int counter(void) {
    static long count = 1;
    return count;
}
