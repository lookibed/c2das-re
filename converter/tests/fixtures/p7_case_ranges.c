/* GNU case ranges (P7.6): `case lo ... hi` is a pair of tests in the condition's type. */
#include <stdio.h>
enum E { A, B, C, D, F };
int chain(int x) {
    switch (x) {
    case 1 ... 5: return 10;
    case 7: case 9 ... 11: return 20;
    case 'a' ... 'f': return 30;
    case '0' ... 57: return 40;
    default: return 0;
    }
}
int fall(int x) {
    int r = 0;
    switch (x) {
    case -3 ... -1: r += 1;
    case 0: r += 2; break;
    case 4 ... 4: r += 100;
    default: r += 7; break;
    case 20 ... 29: case 40: r += 9;
    }
    return r;
}
int wide(unsigned long long v) {
    switch (v) {
    case 0 ... 9: return 1;
    case 1000000000000000000ULL ... 9999999999999999999ULL: return 19;
    case 10000000000000000000ULL ... 18446744073709551614ULL: return 20;
    case 18446744073709551615ULL: return 21;
    default: return 2;
    }
}
int uns(unsigned x) {
    switch (x) {
    case 0x80000000u ... 0xFFFFFFFFu: return 1;
    case 3 ... 2: return 9;
    default: return 0;
    }
}
int en(enum E e) {
    switch (e) {
    case B ... D: return 1;
    default: return 0;
    }
}
int open(int x, int y) {
    int r = 0;
    switch (x) {
    case 1:
        if (y) {
    case 5 ... 9:
            r += 2;
        }
        r += 1;
        break;
    case 12:
        r = 50;
    }
    return r;
}
int redispatch(int x) {
    int r = 0;
    switch (x) {
    case 1 ... 3: r += 1; goto tail;
    case 10: r += 5; break;
    default:
    tail: r += 100; break;
    }
    return r;
}
/* eight values and a range: dense but for the range, which no jump table holds */
int dense(int x) {
    switch (x) {
    case 0: return 100;
    case 1: return 101;
    case 2: return 102;
    case 3: return 103;
    case 4: return 104;
    case 5: return 105;
    case 6: return 106;
    case 7: return 107;
    case 8 ... 9: return 108;
    default: return -1;
    }
}
/* a range in the switch around one without and one with its own: each one's cases are its own */
int nested(int x, int y) {
    switch (x) {
    case 1 ... 2:
        switch (y) {
        case 1: return 11;
        default: return 12;
        }
    case 3 ... 4:
        switch (y) {
        case 0 ... 1: return 13;
        }
        return 15;
    case 5 ... 6: return 16;
    default: return 14;
    }
}
int main(void) {
    for (int i = -5; i < 45; i++) printf("%d:%d,%d ", i, chain(i), fall(i));
    printf("\n%d %d %d %d %d\n", chain('a'), chain('f'), chain('g'), chain('0'), chain('9'));
    for (int i = -1; i < 11; i++) printf("%d ", dense(i));
    printf("\n");
    for (int i = 0; i < 8; i++) printf("%d,%d ", nested(i, 1), nested(i, 2));
    printf("\n");
    printf("%d %d %d %d %d %d %d\n", wide(5), wide(10), wide(1000000000000000000ULL), wide(999999999999999999ULL), wide(9999999999999999999ULL), wide(10000000000000000000ULL), wide(18446744073709551615ULL));
    printf("%d %d %d %d\n", uns(0x7FFFFFFFu), uns(0x80000000u), uns(0xFFFFFFFFu), uns(2));
    printf("%d %d %d %d\n", en(A), en(B), en(D), en(F));
    for (int i = 0; i < 14; i++) printf("%d,%d ", open(i, 0), open(i, 1));
    printf("\n");
    for (int i = 0; i < 12; i++) printf("%d ", redispatch(i));
    printf("\n");
    return 0;
}
