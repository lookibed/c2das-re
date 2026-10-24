#include <stdarg.h>
#include "shapes.h"

/* a module of its own: nothing here calls back into another file */
int solo_count = 5;

/* named like a static of every other file, and renamed in none: each module keeps its own */
static int helper(int v) {
    return v + 1000;
}

int solo_apply(binop f, int a, int b) {
    solo_count++;
    return f(a, b) + helper(0) - 1000 + twice(0);
}

int solo_sum(int n, ...) {
    va_list ap;
    int s = 0;
    va_start(ap, n);
    for (int i = 0; i < n; i++) {
        s += va_arg(ap, int);
    }
    va_end(ap);
    return s;
}

const char *solo_name(void) {
    return "solo";
}
