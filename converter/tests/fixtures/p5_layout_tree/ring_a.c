#include <stdio.h>
#include "sub/shapes.h"

/* renamed ring_a_helper: ring_b.c's static of the name shares the module */
static int helper(int v) {
    return v * 2;
}

int a_value = 7;
struct point *a_corner = &(struct point){ 3, 4 };
static const char *a_words[] = { "alpha", "" };

int ring_a(int n) {
    return n <= 0 ? helper(1) + twice(2) : ring_b(n - 1) + a_corner->y + a_words[0][1] + a_words[1][0];
}

int ring_mul(int a, int b) {
    return a * b;
}

FILE *ring_stream(void) {
    return stdout;
}
