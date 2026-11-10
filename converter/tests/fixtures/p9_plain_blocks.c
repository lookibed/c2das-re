#include <stdio.h>

/* a switch whose every case returns: no zero return after the chain */
static int *pick(int k, int *a, int *b) {
    switch (k) {
        case 0: return a;
        case 1: { return b; }
        default: return NULL;
    }
}

/* a loop whose body returns on every path: no zero return after it */
static int settle(int n) {
    for (;;) {
        n++;
        if (n > 3) {
            return n;
        } else {
            return -n;
        }
    }
}

/* a return inside an if of the loop body: das needs the zero return */
static int climb(int n) {
    for (;;) {
        if (n > 10) return n;
        n += 3;
    }
}

/* a break out of a loop whose body returns: das would accept the function without the zero
   return and fall off its end, so the zero return stays */
static int leave(int n) {
    for (;;) {
        if (n > 5) break;
        return 1;
    }
}

/* a block a goto stays inside keeps its braces: its label */
static int spin(int n) {
    int t = 0;
    {
again:
        t++;
        if (t < n) goto again;
    }
    return t;
}

int main(void) {
    int a = 1, b = 2, s = 0;
    {
        s += a;
        { s += b; }
    }
    /* a block that declares keeps its braces */
    {
        int t = s * 2;
        s += t;
    }
    int i;
    /* a for's scope block: gone without a declaration, kept for one */
    for (i = 1; i < 50; i *= 2) s += i;
    for (int j = 1; j < 50; j *= 3) s += j;
    printf("%d %d %d %d %d %d %d %d %d\n", *pick(0, &a, &b), *pick(1, &a, &b), pick(2, &a, &b) == NULL, settle(1), settle(5), climb(1), leave(0), spin(4), s);
    return 0;
}
