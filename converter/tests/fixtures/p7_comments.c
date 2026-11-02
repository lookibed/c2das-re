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

#if 0
it's prose an unbalanced apostrophe opens
#endif

/* the sign of n, in GNU style */
static int
sign_of(int n)
{
    int r;
    switch (n) {
    case 0:  /* zero */
        r = 0;
        break;
    default:  /* the rest */
        if (n > 0) {
            r = 1;  /* positive */
        } /* not positive */ else {
            r = -1;  /* negative */
        }
    }
    return r;  /* the sign */
}

int main(void) {
    const char *t = "not /* a comment */ here";
    // print it
    printf("%d %s %d %d\n", odd_sum(10), t, unused_global, sign_of(-4) + sign_of(0));
    return 0;
}
