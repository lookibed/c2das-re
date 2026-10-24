int counter = 1;
int total = 50;
/* spelled like the name b.c's local static `total` of `tick` would take */
int tick_total = 60;

#include "names.h"

/* a static prototype, then the definition without `static`: one internal name */
static int helper(int v);

int foo(void) {
    return 1;
}

/* a file-scope static spelled like the local static `x` of `f` once hoisted */
static int f_x = 5;

static int f(void) {
    static int x = 7;
    x++;
    return x * 10 + f_x;
}

/* renamed `a_count`, which a local of this unit already declares */
static int count = 7;

/* statics named like libc functions another unit calls */
static int abs(int v) {
    return 99 + v;
}

static int strlen(const char *s) {
    (void)s;
    return 0;
}

static int rand(void) {
    return 7;
}

/* named like the das function a c_runtime piece spells for C's `exit`, which b.c calls */
static int c_exit(int v) {
    return v * 100;
}

/* named like a function the emitter maps to crt, which no other unit calls by this name */
static int toupper(int c) {
    return c + 1;
}

/* named like the other unit's external function */
static int scale = 3;

int a_all(void) {
    int a_count = 1;
    return count + a_count + helper(2) + f() + abs(-1) + strlen("x") + rand() + scale + toupper(0) + c_exit(1);
}

int a_get(void) {
    return get() * 100 + wrap();
}

int helper(int v) {
    return v * 2;
}
