/* `__STDC_NO_VLA__` (C11 6.10.8.3): the converter lowers no variable-length array, so it predefines
   the macro an implementation without them defines, and a program that tests it (wasm3's
   `M3_HAS_VLA`) takes its fixed-size path; the native build keeps the VLA, both print the same */
#include <stdio.h>

#define MAX_ARGS 8

static int sum_squares(int n) {
#ifdef __STDC_NO_VLA__
    int squares[MAX_ARGS + 1];
#else
    int squares[n + 1];
#endif
    int total = 0;
    for (int i = 0; i <= n; i++) {
        squares[i] = i * i;
    }
    for (int i = 0; i <= n; i++) {
        total += squares[i];
    }
    return total;
}

int main(int argc, char **argv) {
    (void)argv;
    printf("%d\n", sum_squares(argc + 2));
    return 0;
}
