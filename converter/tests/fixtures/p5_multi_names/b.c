#include <ctype.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int counter = 2;

static int foo(void) {
    return 2;
}

#include "names.h"

extern int total;
extern int tick_total;

int a_all(void);
int a_get(void);

static int count = 9;

/* a record only this unit lays out, measured here */
struct small {
    int v;
};

int scale(void) {
    return 4;
}

/* a parameter named like this unit's renamed static */
static int bump(int counter) {
    return counter + 1;
}

/* a local static named like the external it hides */
static int tick(void) {
    static int total = 0;
    total++;
    return total;
}

double average(int n, ...) {
    va_list ap;
    double sum = 0.0;
    va_start(ap, n);
    for (int i = 0; i < n; i++) {
        sum += va_arg(ap, double);
    }
    va_end(ap);
    return sum / n;
}

/* reads a type the first unit never names, so its index moves in the link */
static unsigned long long sum_wide(int n, ...) {
    va_list ap;
    unsigned long long sum = 0;
    va_start(ap, n);
    for (int i = 0; i < n; i++) {
        sum += va_arg(ap, unsigned long long);
    }
    va_end(ap);
    return sum;
}

int main(void) {
    int shades[BLUE];
    shades[BLUE - 1] = GREEN;
    printf("%d %d %d\n", a_all(), a_get(), get() * 100 + wrap());
    printf("%d %d\n", abs(-5), (int)sqrt(16.0));
    printf("%d\n", (int)strlen("from libc"));
    srand(1);
    printf("%d\n", rand() == rand());
    printf("%d %d\n", (int)sizeof(struct small), bump(41));
    printf("%d\n", tick());
    printf("%d %d %d %d %d\n", tick(), total, scale(), count, tick_total);
    printf("%d %d %d\n", shades[BLUE - 1], (int)average(2, 1.5, 2.5), tolower('A'));
    printf("%d\n", (int)sum_wide(2, 3ull, 4ull));
    fflush(stdout);
    exit(counter == 2 ? 0 : 1);
}
