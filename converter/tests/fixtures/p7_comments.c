/* P7.0j: the C comments land as `//` lines above the statement of their line */
#include <stdio.h>

static int unused_global = 3;  /* a global's comment stays behind */

/*
** sum of the odd numbers below n
** (a block comment over lines, right above the function)
*/
static int odd_sum(int n) {
    int s = 0;  /* the running sum */
    // walk every number
    for (int i = 0; i < n; i++) {
        if (i % 2 == 0) {
            continue;  /* skip the even ones */
        }
        /* add the odd one,
           over two lines */
        s += i;
    }
    return s;  // "a // inside" stays one comment
}

int main(void) {
    const char *t = "not /* a comment */ here";
    // print it
    printf("%d %s %d\n", odd_sum(10), t, unused_global);
    return 0;
}
