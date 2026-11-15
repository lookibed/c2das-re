/* switch_dispatch table: a dense switch is flat, a jump to one das label per case. A range every
   value of which is a case jumps by `goto _cond + base` past a bounds guard (`full`, with
   `default` in the middle `full_default`); a range with values no case holds jumps through a
   module-level table (`holes`: falling through, a goto into the neighbouring case, `default` in
   the middle; `no_default`; a negative low value `negative`; a `long`, an `unsigned` and an
   `unsigned long` subject; an enum; character labels). A switch inside another's case, one in a
   loop with `continue` and both `break`s, a declaration a later case reads, the same local name
   in two cases, every case returning, a dense switch in a small one's case (`in_small`), one a
   goto enters from outside and re-dispatches (`entered`), a range from INT_MIN (`from_min`),
   Duff's device, by its value and through a table (`duff_holes`), and the switches that keep the
   chain's forms: sparse, under 8 values, past int. main prints every result */
#include <limits.h>
#include <stdio.h>

static int full(int x) {
    int r = 0;
    switch (x) {
    case 3: r += 1;
    case 4: r += 10; break;
    case 5: case 6: r += 100; break;
    case 7: r += 1000; if (r > 500) break; r = -1; break;
    case 8: return -8;
    case 9: r += 9;
    case 10: r += 10000;
    }
    return r;
}

static int full_default(int x) {
    int r = 0;
    switch (x) {
    case 0: r = 1; break;
    case 1: r = 2;
    default: r += 500; break;
    case 2: r = 3; break;
    case 3: case 4: r = 4; break;
    case 5: r = 6; break;
    case 6: r = 7; break;
    case 7: r = 8;
    }
    return r;
}

static int holes(int op, int x) {
    int r = 0;
    switch (op) {
    case 2: r += 1;
    case 3: case 4: r += 10; break;
    case 5: r += 100; if (x) goto in7; break;
    default: r += 1000; break;
    case 7: r += 20;
    in7: r += 5; break;
    case 8: r += 7;
    case 9: r += 9; break;
    case 10: return -1;
    }
    return r;
}

static int no_default(int x) {
    int r = 1;
    switch (x) {
    case 10: r = 10; break;
    case 11: r = 11; break;
    case 13: r = 13; break;
    case 14: r = 14;
    case 15: r += 15; break;
    case 17: r = 17; break;
    case 18: r = 18; break;
    case 19: r = 19; break;
    }
    return r;
}

static int negative(int x) {
    int r = 0;
    switch (x) {
    case -4: r = 1; break;
    case -3: r = 2; break;
    case -2: r = 3;
    case -1: r += 4; break;
    case 1: r = 5; break;
    case 2: r = 6; break;
    case 3: r = 7; break;
    case 4: r = 8; break;
    default: r = 9;
    }
    return r;
}

static int negative_full(int x) {
    switch (x) {
    case -3: return 1;
    case -2: return 2;
    case -1: return 3;
    case 0: return 4;
    case 1: return 5;
    case 2: return 6;
    case 3: return 7;
    case 4: return 8;
    default: return 9;
    }
}

static int wide(long x) {
    int r = 0;
    switch (x) {
    case 20: r = 1; break;
    case 21: r = 2; break;
    case 22: r = 3; break;
    case 24: r = 4; break;
    case 25: r = 5; break;
    case 26: r = 6; break;
    case 27: r = 7; break;
    case 28: r = 8; break;
    default: r = -1;
    }
    return r;
}

static int low(unsigned x) {
    int r = 0;
    switch (x) {
    case 1: r = 1; break;
    case 2: r = 2; break;
    case 3: r = 3; break;
    case 5: r = 4; break;
    case 6: r = 5; break;
    case 7: r = 6; break;
    case 8: r = 7;
    case 9: r += 8; break;
    }
    return r;
}

static int wide_low(unsigned long x) {
    switch (x) {
    case 0: return 1;
    case 1: return 2;
    case 2: return 3;
    case 3: return 4;
    case 5: return 5;
    case 6: return 6;
    case 7: return 7;
    case 8: return 8;
    }
    return 0;
}

enum Op { A, B, C, D, E, F, G, H, I, J };
static int ops(enum Op op, int acc) {
    switch (op) {
    case A: acc += 1; break;
    case B: acc += 2;
    case C: acc *= 3; break;
    case D: case E: acc -= 4; break;
    case F: acc ^= 5; break;
    case G: acc += 6; break;
    case H: acc += 7; break;
    case J: acc += 9; break;
    default: acc = -acc;
    }
    return acc;
}

static int op_names(enum Op op) {
    int r = 0;
    switch (op) {
    case A: r = 1; break;
    case B: r = 2; break;
    case C: r = 3; break;
    case D: r = 4; break;
    case E: r = 5; break;
    case F: r = 6; break;
    case G: r = 7; break;
    case H: r = 8; break;
    case I: r = 9; break;
    case J: r = 10; break;
    }
    return r;
}

static int letters(const char *s) {
    int r = 0;
    for (; *s; s++) {
        switch (*s) {
        case 'a': r += 1; break;
        case 'b': r += 2; break;
        case 'c': r += 3; break;
        case 'e': r += 5; break;
        case 'f': r += 6; break;
        case 'g': r += 7; break;
        case 'h': r += 8; break;
        case 'i': r += 9; break;
        default: r += 100;
        }
    }
    return r;
}

static int nested(int x, int y) {
    int r = 0;
    switch (x) {
    case 0: r += 1; break;
    case 1:
        switch (y) {
        case 0: r += 10;
        case 1: r += 100; break;
        case 2: case 3: r += 3; break;
        case 5: r += 5; break;
        case 6: r += 6; break;
        case 7: r += 7; break;
        case 8: r += 8; break;
        case 9: r += 9; break;
        default: goto two;
        }
        r += 20000;
    case 2: two: r += 1000; break;
    case 3: r += 3; break;
    case 4:
        switch (y) {
        case 1: r += 41; break;
        case 50: r += 42; break;
        }
        break;
    case 5: r += 5; break;
    case 6: r += 6; break;
    case 8: r += 8; break;
    default: r = -1;
    }
    return r;
}

static int looped(const unsigned char *code, int n) {
    int r = 0;
    for (int i = 0; i < n; i++) {
        switch (code[i]) {
        case 0: r += 1;
        case 1: r += 10; break;
        case 2: case 3: r += 100; continue;
        case 4: goto out;
        case 5:
            for (int k = 0; k < 4; k++) {
                if (k == 2)
                    break;
                r += 1000;
            }
            break;
        case 6: if (r & 1) break; r += 3; break;
        case 8: r -= 1; break;
        default: r += 50000;
        }
        r *= 2;
    }
out:
    return r;
}

static int scoped(int x) {
    int r = 0;
    switch (x) {
    case 1: r += 1; int carry = 5; r += carry;
    case 2: carry = x * 3; { int t = carry + 1; r += t; } break;
    case 3: { int t = 7; r += t; }
    case 4: r += 4; break;
    case 5: r += 50; int u = x + 1; r += u; break;
    case 6: r += 60; break;
    case 7: r += 70; break;
    case 9: r += 90; break;
    }
    {
        int u = r * 2;
        r = u + 1;
    }
    return r;
}

static int in_small(int x, int n) {
    int r = 0;
    for (int i = 0; i < n; i++) {
        switch (x) {
        case 1:
            switch (i) {
            case 0: r += 1;
            case 1: r += 2; break;
            case 2: r += 3; continue;
            case 4: r += 5; break;
            case 5: r += 6; break;
            case 6: if (r > 20) break; r += 7; break;
            case 7: r += 8; break;
            case 8: r += 9; break;
            default: r += 100;
            }
            r += 1000;
            break;
        case 2: r += 7; break;
        default: r -= 1;
        }
        r *= 2;
    }
    return r;
}

static int entered(int x, int k) {
    int r = 0;
    if (k)
        goto mid;
    switch (x) {
    case 0: r += 1; break;
    case 1: r += 2; break;
    case 2: r += 3;
    mid: r += 30; break;
    case 3: r += 4; break;
    case 4: r += 5; goto mid;
    case 5: r += 6; break;
    case 6: r += 7; break;
    case 8: r += 9; break;
    }
    return r;
}

static int from_min(int x) {
    switch (x) {
    case INT_MIN: return 1;
    case INT_MIN + 1: return 2;
    case INT_MIN + 2: return 3;
    case INT_MIN + 3: return 4;
    case INT_MIN + 5: return 5;
    case INT_MIN + 6: return 6;
    case INT_MIN + 7: return 7;
    case INT_MIN + 8: return 8;
    }
    return 0;
}

static int duff(int count) {
    int sum = 0, n = (count + 7) / 8;
    if (count <= 0)
        return 0;
    switch (count % 8) {
    case 0: do { sum += 1;
    case 7:      sum += 2;
    case 6:      sum += 3;
    case 5:      sum += 4;
    case 4:      sum += 5;
    case 3:      sum += 6;
    case 2:      sum += 7;
    case 1:      sum += 8;
            } while (--n > 0);
    }
    return sum;
}

static int duff4(int count) {
    int sum = 0, n = (count + 3) / 4;
    switch (count % 4) {
    case 0: do { sum += 1;
    case 3:      sum += 20;
    case 2:      sum += 300;
    case 1:      sum += 4000;
            } while (--n > 0);
    }
    return sum;
}

static int duff_holes(int count) {
    int sum = 0, n = 2;
    switch (count) {
    case 0: do { sum += 1;
    case 5:      sum += 20;
    case 3:      sum += 300;
    case 1:      sum += 4000;
            } while (--n > 0);
    }
    return sum;
}

static int sparse(int x) {
    switch (x) {
    case 1: return 1;
    case 10: return 2;
    case 100: return 3;
    case 1000: return 4;
    case 10000: return 5;
    case 100000: return 6;
    case 1000000: return 7;
    case 10000000: return 8;
    }
    return 0;
}

static int small(int x) {
    switch (x) {
    case 0: return 5;
    case 1: return 6;
    case 2: return 7;
    }
    return 0;
}

static int past_int(long x) {
    switch (x) {
    case 4000000000L: return 1;
    case 4000000001L: return 2;
    case 4000000002L: return 3;
    case 4000000003L: return 4;
    case 4000000004L: return 5;
    case 4000000005L: return 6;
    case 4000000006L: return 7;
    case 4000000007L: return 8;
    }
    return 0;
}

int main(void) {
    static const int probes[] = { -2147483647 - 1, -2147483647, -1000, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 100, 2147483646, 2147483647 };
    static const unsigned char code[] = { 0, 1, 2, 5, 6, 7, 3, 8, 9, 0, 6, 4, 1 };
    for (unsigned i = 0; i < sizeof probes / sizeof probes[0]; i++) {
        int x = probes[i];
        printf("%d: %d %d %d %d %d %d %d", x, full(x), full_default(x), holes(x, 0), holes(x, 1), no_default(x), negative(x), negative_full(x));
        printf(" %d %d %d %d %d %d", wide(x), wide(x + 4294967296L), wide(x - 4294967296L), low((unsigned) x), wide_low((unsigned long) x), wide_low((unsigned long) (long) x));
        printf(" %d %d %d %d %d %d", ops((enum Op) x, 100), op_names((enum Op) x), scoped(x), sparse(x), small(x), past_int(x + 4000000000L));
        printf(" %d %d %d %d %d %d\n", in_small(1, x > 12 ? 12 : x), in_small(x, 3), entered(x, 0), entered(x, 1), from_min(x), from_min((int) ((unsigned) x + 0x80000000u)));
    }
    for (int x = -1; x < 10; x++) {
        for (int y = -1; y < 11; y++)
            printf("%d ", nested(x, y));
        printf("\n");
    }
    printf("%d %d %d\n", letters("abcdefghij"), letters(""), letters("hd`"));
    for (int n = 0; n <= 13; n++)
        printf("%d ", looped(code, n));
    printf("\n");
    for (int n = -1; n < 20; n++)
        printf("%d/%d/%d ", duff(n), n > 0 ? duff4(n) : 0, duff_holes(n));
    printf("\n");
    return 0;
}
