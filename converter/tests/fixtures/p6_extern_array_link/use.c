#include "opts.h"

static int *middle = &table[2];

int total(int n) {
    int s = *middle;
    for (int i = 0; i < n; i++) {
        s += table[i] + grid[i % 2][i % 3];
    }
    return s;
}

int *slot(int k) { return &table[k]; }
