/* P4.4 fixture: varargs - variadic definitions popping every argument class, a va_list
   parameter that pops the caller's list, va_copy walking on its own, two lists over one call,
   forwarding to vprintf, vsprintf and vsnprintf, a non-constant printf format, the default
   promotions (char, short, float, an enum) and sscanf. Converted output must match the native
   build of this file. The prototypes are spelled here, so the file converts under msvc too. */
#include <stdarg.h>

int printf(const char *, ...);
int vprintf(const char *, va_list);
int vsprintf(char *, const char *, va_list);
int vsnprintf(char *, __SIZE_TYPE__, const char *, va_list);
int sprintf(char *, const char *, ...);
int sscanf(const char *, const char *, ...);
int vsscanf(const char *, const char *, va_list);

enum color { RED, GREEN, BLUE };

/* every argument class through one walk the kinds string drives */
static double mix(const char *kinds, ...) {
    va_list ap;
    double acc = 0;
    int i;
    va_start(ap, kinds);
    for (i = 0; kinds[i]; i++) {
        if (kinds[i] == 'i') {
            acc += va_arg(ap, int);
        } else if (kinds[i] == 'd') {
            acc += va_arg(ap, double);
        } else if (kinds[i] == 'l') {
            acc += (double) va_arg(ap, long long);
        } else if (kinds[i] == 'u') {
            acc += va_arg(ap, unsigned int);
        } else if (kinds[i] == 's') {
            const char *s = va_arg(ap, const char *);
            while (*s) {
                acc += 1;
                s++;
            }
        } else if (kinds[i] == 'p') {
            int *p = va_arg(ap, int *);
            *p += 100;
        } else if (kinds[i] == 'e') {
            enum color c = va_arg(ap, enum color);
            acc += c == BLUE ? 1000 : 0;
        }
    }
    va_end(ap);
    return acc;
}

double sum(int n, ...) {
    va_list v;
    double total = 0;
    va_start(v, n);
    while (n-- > 0) {
        total += va_arg(v, double);
    }
    va_end(v);
    return total;
}

/* a va_list parameter: the pops advance the caller's list, as on linux */
static int take_two(va_list ap) {
    int a = va_arg(ap, int);
    return a * 10 + va_arg(ap, int);
}

/* a function type with a va_list position */
typedef int (*taker)(va_list);

static int pairs(int count, ...) {
    va_list ap;
    int first, rest;
    taker t = take_two;
    va_start(ap, count);
    first = t(ap);
    rest = va_arg(ap, int);
    va_end(ap);
    return first * 100 + rest + count;
}

/* a va_list parameter reassigned and passed on: still the caller's cursor, never a copy */
static int pop_one(va_list ap) {
    return va_arg(ap, int);
}

static int relay(va_list ap) {
    va_list mine;
    va_copy(mine, ap);
    va_copy(ap, mine);
    return pop_one(ap) * 10 + pop_one(mine);
}

static int relayed(int n, ...) {
    va_list ap;
    int r;
    va_start(ap, n);
    r = relay(ap);
    va_end(ap);
    return r + n;
}

/* va_arg items of an initializer holding a union are evaluated first, in order */
union num { int i; float f; };
struct tagged { int tag; union num u; };

static int tagged_sum(int n, ...) {
    va_list ap;
    va_start(ap, n);
    struct tagged t = { va_arg(ap, int), { va_arg(ap, int) } };
    va_end(ap);
    return t.tag * 100 + t.u.i + n;
}

/* a buffer parameter the printf family writes through */
static void put_number(char *buf, int v) {
    sprintf(buf, "<%d>", v);
}

/* vsscanf from a forwarded list */
static int scan_two(const char *src, const char *fmt, ...) {
    va_list ap;
    int n;
    va_start(ap, fmt);
    n = vsscanf(src, fmt, ap);
    va_end(ap);
    return n;
}

/* va_copy walks on its own; two lists over one call are independent */
static void copies(int n, ...) {
    va_list a, b, c;
    int i, sa = 0, sb = 0, sc = 0;
    va_start(a, n);
    va_start(c, n);
    sa += va_arg(a, int);
    va_copy(b, a);
    for (i = 1; i < n; i++) {
        sa += va_arg(a, int);
    }
    for (i = 1; i < n; i++) {
        sb += va_arg(b, int) * 2;
    }
    for (i = 0; i < n; i++) {
        sc += va_arg(c, int) * 3;
    }
    va_end(a);
    va_end(b);
    va_end(c);
    printf("copies %d %d %d\n", sa, sb, sc);
}

/* forwarding: the list goes on to the printf family */
static void vlog(const char *fmt, va_list ap) {
    printf("[log] ");
    vprintf(fmt, ap);
}

static void log_line(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vlog(fmt, ap);
    va_end(ap);
}

static int bounded(char *buf, __SIZE_TYPE__ size, const char *fmt, ...) {
    va_list ap;
    int n;
    va_start(ap, fmt);
    n = vsnprintf(buf, size, fmt, ap);
    va_end(ap);
    return n;
}

static int unbounded(char *buf, const char *fmt, ...) {
    va_list ap;
    int n;
    va_start(ap, fmt);
    n = vsprintf(buf, fmt, ap);
    va_end(ap);
    return n;
}

/* the default promotions: char and short arrive as int, float as double; reading them back
   at their own type is undefined in C and reads the promoted value */
static int promoted(int n, ...) {
    va_list ap;
    int total;
    double f;
    va_start(ap, n);
    total = (char) va_arg(ap, int);
    total += (short) va_arg(ap, int);
    f = va_arg(ap, double);
    va_end(ap);
    return total + (int) (f * 4);
}

/* va_arg inside a condition and skipped with a cast to void */
static int skip_then(int n, ...) {
    va_list ap;
    int i, ok;
    va_start(ap, n);
    for (i = 0; i < n; i++) {
        if (i % 2) {
            va_arg(ap, int);
        } else {
            (void) va_arg(ap, int);
        }
    }
    ok = va_arg(ap, int) == 7 || va_arg(ap, int) == 8;
    va_end(ap);
    return ok;
}

static int count_args(int n, ...) {
    return n;
}

/* defined below its caller */
static int late(int n, ...);

/* recursion, direct and mutual */
static int countdown(int n, ...) {
    return n > 0 ? n + countdown(n - 1) : 0;
}

static int pong(int n, ...);

static int ping(int n, ...) {
    return n > 0 ? 1 + pong(n - 1) : 0;
}

static int pong(int n, ...) {
    return n > 0 ? 10 + ping(n - 1) : 0;
}

/* two variadic functions calling a third */
static int shared_third(int n, ...);

static int first_caller(int n, ...) {
    return shared_third(1, n);
}

static int second_caller(int n, ...) {
    return shared_third(1, n * 2);
}

static int shared_third(int n, ...) {
    va_list ap;
    int v;
    va_start(ap, n);
    v = va_arg(ap, int);
    va_end(ap);
    return v + n;
}

/* a variadic function calling one defined below it */
static int outer(int n, ...) {
    va_list ap;
    int first;
    va_start(ap, n);
    first = va_arg(ap, int);
    va_end(ap);
    return late(2, first, n);
}

int main(void) {
    char buf[64];
    int x = 5, r;
    const char *fmt;
    int a = 0, b = 0, used = 0;
    double d = 0;
    char word[8];

    printf("mix %g\n", mix("idlus", 3, 2.5, 4000000000LL, 7u, "abcd"));
    printf("mix %g x=%d\n", mix("pe", &x, BLUE), x);
    printf("sum %g %g\n", sum(3, 1.5, 2.5, 3.0), sum(0));
    printf("pairs %d\n", pairs(1, 4, 2, 9));
    copies(3, 1, 2, 3);
    log_line("%s=%d\n", "answer", 42);
    r = bounded(buf, 6, "%d-%s", 12345, "tail");
    printf("bounded %d [%s]\n", r, buf);
    r = unbounded(buf, "<%c%c%5.2f>", 'o', 'k', 3.14159);
    printf("unbounded %d [%s]\n", r, buf);
    printf("promoted %d\n", promoted(0, (char) 'A', (short) -300, 1.25f));
    printf("skip %d %d\n", skip_then(2, 1, 2, 7, 0), skip_then(0, 3, 8));
    printf("zero %d late %d outer %d\n", count_args(4), late(2, 30, 12), outer(5, 37));
    printf("countdown %d ping %d\n", countdown(4), ping(5));
    printf("relayed %d tagged %d callers %d %d\n", relayed(1, 5, 6), tagged_sum(3, 4, 7), first_caller(10), second_caller(10));
    put_number(buf, 77);
    r = scan_two("8 9", "%d %d", &a, &b);
    printf("put %s scan %d %d %d\n", buf, r, a, b);
    fmt = x > 100 ? "big %d\n" : "small %d\n";
    printf(fmt, x);
    printf("sizeof %d\n", (int) sizeof(va_list));
    r = sscanf("  12,-7 2.5e1 hello", "%d,%d %lf %5s%n", &a, &b, &d, word, &used);
    printf("sscanf %d %d %d %g %s %d\n", r, a, b, d, word, used);
    r = sscanf("abc", "%d", &a);
    printf("sscanf %d %d\n", r, a);
    return 0;
}

static int late(int n, ...) {
    va_list ap;
    int total = 0;
    va_start(ap, n);
    while (n-- > 0) {
        total += va_arg(ap, int);
    }
    va_end(ap);
    return total;
}
