/* P7.5 fixture: a record passed by value through `...` and read back by `va_arg` (c-testsuite
   00140, 00204): structs of several shapes and a union, a copy of the list (`va_copy`), a list
   forwarded to a function taking a `va_list`, a call through a pointer to a variadic function,
   and the member of a record a call returns (`f().a`, which clang wraps in `ExprWithCleanups`).
   Converted output must match the native build of this file. */
#include <stdarg.h>
#include <stdio.h>

struct s3 {
    char x[3];
};

struct pt {
    float a, b;
    double c;
};

union word {
    int i;
    unsigned char b[4];
};

struct pt origin = {1.5f, 2.5f, 3.25};

static struct pt get_pt(void) {
    return origin;
}

/* `n` records of the kinds the format names: `s` a struct s3, `p` a struct pt, `w` a union */
static int vsum(const char *kinds, va_list ap) {
    int total = 0;
    for (; *kinds; kinds++) {
        if (*kinds == 's') {
            struct s3 s = va_arg(ap, struct s3);
            printf("%.3s ", s.x);
            total += s.x[0];
        } else if (*kinds == 'p') {
            struct pt p = va_arg(ap, struct pt);
            printf("%.1f %.1f %.2f ", p.a, p.b, p.c);
            total += (int)(p.a + p.b + p.c);
        } else if (*kinds == 'w') {
            union word w = va_arg(ap, union word);
            total += w.b[0] + va_arg(ap, int);
        }
    }
    printf("\n");
    return total;
}

static int sum(const char *kinds, ...) {
    va_list ap, again;
    int first, second;
    va_start(ap, kinds);
    va_copy(again, ap);
    first = vsum(kinds, ap);
    second = vsum(kinds, again);
    va_end(again);
    va_end(ap);
    return first + second;
}

/* a record passed through `...` that the callee never reads */
static int skip(struct pt p, int n, ...) {
    return (int)p.a + n;
}

int main(void) {
    struct s3 abc = {{'a', 'b', 'c'}};
    struct s3 xyz = {{'x', 'y', 'z'}};
    struct pt q = {0.5f, 1.0f, 2.0};
    union word w;
    int (*fp)(const char *, ...) = sum;
    int total;
    w.i = 0;
    w.b[0] = 7;
    total = sum("sps", abc, q, xyz);
    total += sum("wp", w, 5, get_pt());
    total += fp("s", abc);
    total += skip(q, 1, q, abc, w);
    printf("%.1f %.2f %d\n", get_pt().a, get_pt().c, total);
    return total == 0;
}
