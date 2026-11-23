#include <stdio.h>
#include <limits.h>

/* the three operand types are each their own: the exact result, cut to the result's type */
#define SHOW(op, a, b, T) do { T r = 0; int o = __builtin_##op##_overflow(a, b, &r); printf(#op " " #a " " #b " " #T " -> %d %lld\n", o, (long long) r); } while (0)

int main(void) {
    signed char sc = -128;
    unsigned char uc = 255;
    short sh = -32768;
    unsigned short us = 65535;
    SHOW(add, INT_MAX, 1, int);
    SHOW(add, INT_MAX, 1, long);
    SHOW(add, -1, 1u, unsigned);
    SHOW(sub, 0u, 1, int);
    SHOW(sub, 0u, 1, unsigned);
    SHOW(mul, sc, sc, signed char);
    SHOW(mul, sc, sc, short);
    SHOW(mul, uc, uc, unsigned char);
    SHOW(mul, us, us, unsigned short);
    SHOW(mul, us, us, int);
    SHOW(mul, sh, sh, int);
    SHOW(mul, ULLONG_MAX, ULLONG_MAX, unsigned long long);
    SHOW(mul, ULLONG_MAX, -1, long long);
    SHOW(mul, LLONG_MIN, -1, long long);
    SHOW(mul, LLONG_MIN, -1, unsigned long long);
    SHOW(mul, LLONG_MIN, ULLONG_MAX, long long);
    SHOW(add, ULLONG_MAX, ULLONG_MAX, unsigned long long);
    SHOW(add, LLONG_MIN, LLONG_MIN, long long);
    SHOW(sub, LLONG_MIN, 1, long long);
    SHOW(sub, 0, LLONG_MIN, long long);
    SHOW(sub, 0, ULLONG_MAX, long long);
    SHOW(sub, -1, ULLONG_MAX, long long);
    SHOW(add, 'a', sc, unsigned char);
    SHOW(add, uc, uc, signed char);
    SHOW(sub, sc, 1, signed char);
    SHOW(sub, us, sh, unsigned short);
    SHOW(mul, UINT_MAX, UINT_MAX, unsigned long long);
    SHOW(mul, UINT_MAX, UINT_MAX, long long);
    SHOW(mul, INT_MIN, INT_MIN, long long);
    SHOW(mul, 0x100000000LL, 0x100000000LL, unsigned long long);
    SHOW(mul, 0xFFFFFFFFLL, 0x100000001LL, unsigned long long);
    SHOW(mul, LLONG_MAX, 2, unsigned long long);
    SHOW(mul, -3, 5u, int);
    SHOW(mul, -3, 0u, unsigned);
    /* the typed spellings: clang converts the operands to the prototype's types */
    int r;
    long lr;
    unsigned long long ur;
    int o = __builtin_sadd_overflow(INT_MAX, 1, &r);
    printf("sadd %d %d\n", o, r);
    o = __builtin_smull_overflow(LONG_MAX, 2, &lr);
    printf("smull %d %ld\n", o, lr);
    o = __builtin_usubll_overflow(1, 2, &ur);
    printf("usubll %d %llu\n", o, ur);
    /* an operand is evaluated once, the result may be an operand, the flag is a condition */
    int n = 0;
    unsigned a = UINT_MAX - 1;
    if (__builtin_add_overflow(a, ++n, &a))
        printf("early\n");
    if (__builtin_add_overflow(a, ++n, &a))
        printf("wrapped %u %d\n", a, n);
    return 0;
}
