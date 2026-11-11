/* P9.13: a conversion between types das spells alike is none; sizeof read as an int */
#include <stdio.h>
#include <string.h>

typedef unsigned char lu_byte;
struct rec { int a; char b[3]; };
struct ts { lu_byte extra; signed char s; short h; };

/* char and unsigned char are both uint8: lstring.c's `cast_byte(str[i])` */
static unsigned hash(const char *str, size_t l) {
    unsigned h = 7;
    for (; l > 0; l--)
        h ^= ((h << 5) + (h >> 2) + (lu_byte)(str[l - 1]));
    return h;
}

/* a char's byte past 0x7f: the same bits either way */
static int high_bytes(void) {
    const char s[3] = { (char)0x80, (char)0xff, 0 };
    lu_byte a = (lu_byte)s[0];
    unsigned b = (unsigned)(lu_byte)s[1];
    return a * 1000 + (int)b;
}

/* sizeof read as an int, and as a size_t */
static int sizes(void) {
    int n = sizeof(struct rec);
    int m = (int)sizeof(int) * 2;
    size_t z = sizeof(struct ts);
    return n * 100 + m * 10 + (int)z;
}

/* a widening that changes the das type stays: a negative int zero-extended through unsigned */
static unsigned long long widen(int i) {
    return (unsigned long long)(unsigned)i;
}

/* a narrow field compared and stored */
static int fields(struct ts *t) {
    t->extra = (lu_byte)(t->extra + 1);
    t->s = (signed char)(t->s - 1);
    return t->extra == 0 ? 1 : (int)t->s;
}

int main(void) {
    struct ts t = { 255, -128, -1 };
    printf("%u %d %d %llu\n", hash("hello", 5), high_bytes(), sizes(), widen(-2));
    printf("%d %d %d\n", fields(&t), (int)t.extra, (int)t.s);
    printf("%d\n", (int)strlen("abc") + (int)sizeof(t.h));
    return 0;
}
