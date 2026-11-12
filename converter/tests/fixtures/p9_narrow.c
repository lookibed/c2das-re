/* P9.14: a narrow `==` against a literal in range compares narrow; an enum converts directly */
#include <stdio.h>

#define STATUS_OK 0

struct ts { unsigned char extra; signed char s; short h; unsigned short w; unsigned char bits : 3; };
enum dir { WEST = -1, NORTH, BIG = 300 };
enum mask { M_LOW = 1, M_HIGH = 0x80000000u };

/* storage operands against literals in their range, either side, a character among them */
static int narrow(const struct ts *t, const char *s) {
    int r = 0;
    if (t->extra == 0) r += 1;
    if (t->extra != 255) r += 2;
    if (0 == t->s) r += 4;
    if (t->s == -128) r += 8;
    if (t->h == -1) r += 16;
    if (t->w == 65535u) r += 32;
    if (*s == 'a') r += 64;
    if (s[1] == 0x80) r += 128;
    if (t->bits == 5) r += 256;
    if ((unsigned char)t->h == 5) r += 512;
    return r;
}

/* stays promoted: a literal outside the range, an ordering, mixed types */
static int wide(const struct ts *t, const char *s) {
    int r = 0;
    if (t->extra == 256) r += 1;
    if (t->extra == -1) r += 2;
    if (t->h == 65535) r += 4;
    if (s[1] == -128) r += 8;
    if (t->extra < 5) r += 16;
    if (t->extra == t->s) r += 32;
    if (t->s == (signed char)-1 + 0) r += 64;
    if (t->extra == STATUS_OK) r += 128;
    if ((long)t->s == -1u) r += 256;
    if (t->s == (long long)-1u) r += 512;
    if (t->h == (signed char)200) r += 1024;
    return r;
}

/* two values of one storage type */
static int same(const struct ts *a, const struct ts *b) {
    return (a->extra == b->extra) + 2 * (a->h != b->h);
}

/* an enum to every number type, a signed enum and one past INT_MAX */
static void enums(enum dir d, enum mask m) {
    printf("%u %lld %llu %u %d %.1f\n", (unsigned)d, (long long)d, (unsigned long long)d,
        (unsigned)(unsigned char)d, (int)(short)d, (double)d);
    printf("%u %lld %llu %.1f\n", (unsigned)m, (long long)m, (unsigned long long)m, (double)m);
    printf("%u %llu\n", 1u << NORTH + 3, 1ull << NORTH);
}

int main(void) {
    struct ts t = { 0, -128, -1, 65535, 5 };
    struct ts u = { 255, 0, 7, 0, 1 };
    struct ts v = { 1, -1, -56, 0, 0 };
    struct ts w = { 1, 0, 261, 0, 0 };
    const char s[3] = { 'a', (char)0x80, 0 };
    printf("%d %d %d %d\n", narrow(&t, s), narrow(&u, s + 1), wide(&t, s), wide(&u, s));
    printf("%d %d\n", same(&t, &t), same(&t, &u));
    printf("%d %d %d %d\n", wide(&v, s), wide(&w, s), narrow(&v, s), narrow(&w, s));
    enums(WEST, M_HIGH);
    enums(BIG, M_LOW);
    return 0;
}
