/* P7.0t: under switch_dispatch goto, a switch a goto from another case group re-dispatches, which
   the jump table refuses, is spelled open: switch_goto's VM loop (gotos into another case's block and
   into the middle of the last, a return before a case label), a returning `default` first and a
   return before the next case label, an enum with a default and holes, a continue of the loop
   around it, a goto from a nested switch's default to the outer one's, a sparse one, one case
   value, one past int, holes with no default in an open switch inside another, a switch a goto
   enters from outside; main prints every result */
#include <stdio.h>

static const unsigned char code[16] = { 0, 1, 2, 3, 4, 1, 0, 2, 3, 4, 0, 0, 1, 2, 4, 3 };
static int vm(int seed) {
    int acc = seed, pc = 0, n = 0;
    while (pc < 16) {
        switch (code[pc++]) {
        case 0:
            acc += 3;
            if (acc > 60000)
                return -1;
            break;
        case 1:
            acc ^= pc;
            goto l_call;
        case 2: {
          l_call: {
            acc = acc * 5 + 1;
            goto l_loop;
          }
        }
        case 3: {
          l_loop: {
            acc -= n;
            n++;
            break;
          }
        }
        case 4:
            if (acc & 1)
                acc >>= 1;
            else
                acc += 7;
          done:
            acc &= 0xffff;
            break;
        }
        if (acc == 12345)
            goto done;
    }
    return acc;
}

enum Shape { DOT = 1, LINE = 2, BOX = 4, RING = 5 };
static int shape(enum Shape s, int k) {
    int r = 0;
    switch (s) {
    case DOT: r = 1; if (k) goto boxed; break;
    case LINE: r = 2; break;
    case BOX: boxed: r += 40; break;
    case RING: r = 5; break;
    default: r = 99; break;
    }
    return r;
}

static int skip_odd(int n) {
    int r = 0;
    for (int i = 0; i < n; i++) {
        switch (i % 3) {
        case 0: r += 1; goto two;
        case 1: if (i & 1) continue; r += 10; break;
        case 2: two: r += 100; break;
        }
        r += 1000;
    }
    return r;
}

static int nested(int a, int b) {
    int r = 0;
    switch (a) {
    case 0: r = 1; break;
    case 1:
        switch (b) { case 0: r = 10; break; case 1: r = 11; break; default: goto dflt; }
        break;
    case 2: r = 3; break;
    default: dflt: r += 500; break;
    }
    return r;
}

static int sparse(int x) {
    int r = 0;
    switch (x) { case 1: r = 1; goto shared; case 50: shared: r += 5; break; case 900: r = 9; break; }
    return r;
}

static int single(int x) {
    int r = 0;
    switch (x) { case 7: r = 7; goto out; default: out: r += 2; break; }
    return r;
}

static int wide(long long x) {
    int r = 0;
    switch (x) { case 4000000000LL: r = 1; goto w; case 4000000001LL: w: r += 2; break; case 4000000002LL: r = 3; break; }
    return r;
}

static int twice(int a, int b) {
    int r = 0;
    switch (a) {
    case 0: r = 1; goto o3;
    case 2:
        switch (b) { case 0: r = 10; goto i2; case 2: i2: r += 20; break; case 3: r = 30; break; }
        break;
    case 3: o3: r += 300; break;
    }
    return r;
}

static int first_default(int x, int k) {
    int r = 0;
    switch (x) {
    default: return 9;
    case 0: if (k) return 100; r = 1; goto one;
    case 1: one: r += 10; break;
    case 2: r = 2; break;
    }
    return r;
}

static int entered(int x, int k) {
    int r = 0;
    if (k) goto inside;
    switch (x) { case 0: r = 1; goto inside; case 1: inside: r += 7; break; case 2: r = 3; break; }
    return r;
}

int main(void) {
    printf("%d %d %d %d\n", vm(0), vm(7), vm(1000), vm(59999));
    printf("%d %d %d %d %d %d\n", shape(DOT, 0), shape(DOT, 1), shape(LINE, 0), shape(BOX, 0), shape(RING, 0), shape((enum Shape)3, 0));
    printf("%d %d\n", skip_odd(7), skip_odd(10));
    printf("%d %d %d %d %d\n", nested(0, 0), nested(1, 1), nested(1, 5), nested(2, 0), nested(9, 0));
    printf("%d %d %d %d\n", sparse(1), sparse(50), sparse(900), sparse(3));
    printf("%d %d\n", single(7), single(1));
    printf("%d %d %d %d\n", wide(4000000000LL), wide(4000000001LL), wide(4000000002LL), wide(5));
    printf("%d %d %d %d %d %d\n", twice(0, 0), twice(1, 0), twice(2, 0), twice(2, 1), twice(2, 3), twice(3, 0));
    printf("%d %d %d %d %d\n", first_default(0, 0), first_default(0, 1), first_default(1, 0), first_default(2, 0), first_default(7, 0));
    printf("%d %d %d %d\n", entered(0, 0), entered(2, 0), entered(2, 1), entered(5, 0));
    return 0;
}
