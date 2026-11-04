/* The program test_sampler.das runs under perf/sampler/sampler.c: main times hot_caller between
   two clock() calls, the window SAMPLER_GATE=clock records; hot_caller calls hot_leaf, a loop in
   registers that keeps no frame, so its samples' stack-top word is hot_caller's return address.
   Built with -DNO_CLOCK it never calls clock(): under the gate it records nothing. */
#include <stdio.h>
#include <time.h>

static volatile unsigned rounds = 300000000u;

__attribute__((noinline)) unsigned hot_leaf(unsigned n)
{
    unsigned x = 1;
    for (unsigned i = 0; i < n; i++)
        x = x * 1664525u + 1013904223u;
    return x;
}

__attribute__((noinline)) unsigned hot_caller(unsigned n)
{
    return hot_leaf(n) ^ 7u;
}

int main(void)
{
#ifdef NO_CLOCK
    printf("%u\n", hot_caller(rounds));
#else
    clock_t start = clock();
    unsigned r = hot_caller(rounds);
    printf("%u %ld\n", r, (long)(clock() - start));
#endif
    return 0;
}
