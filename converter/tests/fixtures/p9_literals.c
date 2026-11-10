#include <stdio.h>
#include <string.h>

/* an integer literal converted to a type das spells with a suffix is that literal; a type without
   one, a value past its range, a named constant and a character literal keep the conversion */
typedef unsigned char u8;
#define SHIFT 16

static double half(double d) { return d / 2; }

int main(void) {
    long a = 0, b = -1, c = 4096;
    unsigned long d = 1;
    unsigned u = 333772;
    u8 k = 7, ch = 'a';
    short s = 5;
    unsigned short us = 9;
    signed char sc = -3;
    double h = half(10);
    float f = 3;
    long sh = SHIFT;
    unsigned neg = -1;
    u8 wide = 300;
    const char *msg = "hello";
    size_t n = strlen(msg);
    long m = 3 * -2;
    long flip = -(long) -1;
    float exact = 16777216, past = 16777217;
    printf("%ld %ld %ld %lu %u %d %d %d %d %d %g %g %ld %u %d %d %ld %ld %.1f %.1f\n", a, b, c, d, u, k, ch, s, us, sc, h, f, sh, neg, wide, n > 4, m - -1, flip, exact, past);
    return 0;
}
