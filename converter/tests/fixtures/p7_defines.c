/* P7.0k: a `#define` constant a function uses is a module `let` of its name */
#include <stdio.h>
#include <limits.h>

#define TNUMBER 3
#define makevariant(t, v) ((t) | ((v) << 4))
#define VNUMINT makevariant(TNUMBER, 0)
#define VNUMFLT makevariant(TNUMBER, 1)
#define MAXCALLS 200
#define match 7
#define HALF 0.5
#define GLOBAL_START 11

static int start = GLOBAL_START;

static int kind(int tt, unsigned calls) {
    if (tt == VNUMINT) return calls >= MAXCALLS ? 1 : 2;
    if (tt == VNUMFLT) return match;
    return makevariant(1, 2);
}

int main(void) {
    double h = HALF * 4;
    printf("%d %d %d %d %d %d\n", kind(3, 300), kind(3, 1), kind(19, 0), kind(0, 0), start, (int)h);
    return INT_MAX == 2147483647 ? 0 : 1;
}
