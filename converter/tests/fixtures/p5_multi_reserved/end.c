#include <stdio.h>

/* renamed past `end_index`, the c_runtime helper a pointer into an array spells */
static int index(int k, int n) {
    return k * 100 + n;
}

int a[8] = {1, 2, 3, 4, 5, 6, 7, 8};

int c_run(void);
int c2das_run(void);
int other(void);

int main(void) {
    int k = 3;
    int *p = &a[k];
    printf("%d %d %d\n", *p, index(1, 2), other());
    printf("%d %d\n", c_run(), c2das_run());
    return 0;
}
