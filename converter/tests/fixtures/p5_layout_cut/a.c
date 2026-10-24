#include "cut.h"

/* two call sites into b.c: the lighter edge of the cycle, which the cut late-binds */
int a_run(int n) {
    return b_step(n) + b_note(3, n, 20, 300);
}

int a_back(int n) {
    return n * 2;
}
