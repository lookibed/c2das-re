#include "shapes.h"

/* with ring_a.c a cycle of calls: the two are one module of two fragments */
extern int a_value;

/* renamed ring_b_helper: ring_a.c's static of the name shares the module */
static int helper(int v) {
    return v * 3;
}

/* the address of the other fragment's global: ring_a.das.inc is included first */
int *b_ptr = &a_value;
int *b_list = (int[]){ 4, 5, 6 };
static const char *b_words[] = { "gamma", "" };

int ring_b(int n) {
    return n <= 0 ? helper(1) + twice(1) : ring_a(n - 1) * 2;
}

int *ring_cell(void) {
    return b_ptr;
}

int ring_words(void) {
    return b_words[0][0] + b_words[1][0] + b_list[2];
}
