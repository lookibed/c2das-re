// Arrays and nested loops: the primes below 100.
#include <stdio.h>
#include <string.h>

#define LIMIT 100

int main(void)
{
    char composite[LIMIT];
    memset(composite, 0, sizeof composite);
    int count = 0;
    for (int i = 2; i < LIMIT; i++) {
        if (composite[i])
            continue;
        printf("%d ", i);
        count++;
        for (int j = i * i; j < LIMIT; j += i)
            composite[j] = 1;
    }
    printf("\n%d primes below %d\n", count, LIMIT);
    return 0;
}
