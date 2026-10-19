#include <stdio.h>
#include <stdint.h>
/* csmith's block-local names: a local hiding one of an enclosing block or a parameter, discarded
   reads in nested blocks, and subscripts of a small integer type */
static int g[4] = {1, 2, 3, 4};
static int hide(int p) {
    int i = 10, total = 0;
    for (i = 0; i < 2; i++) {
        int i = 5;
        total += i;
        {
            int i = 7;
            total += i;
            g[0];
        }
        g[1];
    }
    {
        int p = 3;
        total += p;
    }
    for (int i = 1; i < 3; i++) {
        total += i * 100;
    }
    return total + i + p;
}
static int at(const int *p, char c) { return p[c]; }
int main(void) {
    int8_t k = 2;
    uint8_t m = 3;
    int16_t n = 1;
    int v = g[k] + g[m] + g[n];
    {
        int v = 100;
        printf("%d\n", v);
    }
    printf("%d %d %d\n", hide(1), v, at(g, (char) 3));
    return 0;
}
