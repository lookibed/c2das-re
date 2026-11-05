/* --checks off (P7.0o): every converted function drops das's null and range checks. A
   well-defined run prints what the native build prints in both modes; with an argument the
   program indexes one past `a`, which the checked build stops with a panic and the unchecked
   one reads as C does, the field after the array. */
#include <stdio.h>
#include <stdlib.h>

struct S {
    int a[4];
    int b;
};

static int at(struct S *s, int i) {
    return s->a[i];
}

static int sum(int n) {
    int v[8];
    int k, total = 0;
    for (k = 0; k < 8; k++) {
        v[k] = k * n;
    }
    for (k = 0; k < 8; k++) {
        total += v[k];
    }
    return total;
}

int main(int argc, char **argv) {
    struct S s = {{1, 2, 3, 4}, 77};
    int i = argc > 1 ? atoi(argv[1]) : 3;
    printf("at %d = %d\n", i, at(&s, i));
    printf("sum %d\n", sum(3));
    return 0;
}
