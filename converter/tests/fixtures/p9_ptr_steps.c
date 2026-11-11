/* P9.9: a pointer step is das's `p++`/`p--`, a compound store of a pointer `p += n`/`p -= n`, on
   every lvalue kind and count type; a dereference is `*p`, parenthesized under a postfix */
#include <stdio.h>
#include <string.h>

struct S {
    int *p;
    int n;
};

union U {
    int *p;
    long bits;
};

static int g[32];
static char rows[3][4] = {"ab", "cde", "f"};

static long off(const int *p) {
    return (long)(p - g);
}

static void copy(char *dst, const char *src, int n) {
    while (n--) *dst++ = *src++;
}

int main(void) {
    for (int i = 0; i < 32; i++) {
        g[i] = i * 10;
    }
    int *p = &g[8];
    int n = 3;
    long l = -2;
    unsigned u = 5;
    unsigned long k = 2;
    p += n;
    p += k;
    p += u;
    p += l;
    p -= n + 1;
    p -= 2;
    p -= k;
    p++;
    --p;
    ++p;
    p--;
    int *before = p++;
    int *after = --p;
    printf("var %ld %ld %ld\n", off(p), off(before), off(after));

    struct S s = {g, 0};
    struct S *sp = &s;
    s.p += 4;
    s.p++;
    sp->p -= 1;
    sp->p++;
    int *arr[2] = {g, g};
    arr[1] += 6;
    arr[1]--;
    int *held = g;
    int **pp = &held;
    *pp += 3;
    (*pp)++;
    union U un;
    un.p = g;
    un.p += 7;
    un.p++;
    printf("lvalues %ld %ld %ld %ld\n", off(s.p), off(arr[1]), off(held), off(un.p));

    int *q = &g[9];
    *q = 40;
    (*q)++;
    *q += 2;
    int a = 86 / *q + 3 * *q - *q;
    int *r = &g[10];
    int b = *(r - 1) + **pp;
    int (*row)[4] = (int (*)[4])&g[12];
    printf("deref %d %d %d %d\n", *q, a, b, (*row)[2]);

    char src[] = "steps", dst[8] = {0};
    copy(dst, src, 6);
    const char *c = dst;
    int sum = 0;
    while (*c) sum += *c++;
    printf("copy %s %d\n", dst, sum);
    printf("rows %d %s\n", (int)strlen(*(&rows[1] - 1)), *(&rows[2] - 1));
    return 0;
}
