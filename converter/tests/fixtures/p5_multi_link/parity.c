#include <stdarg.h>
#include "shape.h"

int is_odd(unsigned n) {
    return n == 0 ? 0 : is_even(n - 1);
}

int total(int n, ...) {
    va_list ap;
    int sum = 0;
    va_start(ap, n);
    for (int i = 0; i < n; i++) {
        sum += va_arg(ap, int);
    }
    va_end(ap);
    return sum + twice(n);
}
