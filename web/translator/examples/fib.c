// Recursion and a loop: the same Fibonacci two ways.
#include <stdio.h>

static int fib_rec(int n)
{
    return n < 2 ? n : fib_rec(n - 1) + fib_rec(n - 2);
}

static long long fib_loop(int n)
{
    long long a = 0, b = 1;
    for (int i = 0; i < n; i++) {
        long long t = a + b;
        a = b;
        b = t;
    }
    return a;
}

int main(void)
{
    for (int n = 0; n <= 20; n += 5)
        printf("fib(%d) = %d = %lld\n", n, fib_rec(n), fib_loop(n));
    return 0;
}
