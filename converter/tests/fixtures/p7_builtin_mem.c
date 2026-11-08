/* the program's own memcpy, memmove and memset as daslang's builtins: constant and run-time
   sizes, sizes of every width C widens to size_t, zero sizes with null pointers, overlapping
   moves both ways, a fill value truncated to its byte, a size with an effect, and the forms that
   keep the crt call (a used result, a pointer with an effect under the zero test, a fill of a
   run-time count) */
#include <stdio.h>
#include <string.h>

struct block {
    int coef[16];
    unsigned char flags[6];
};

#define FOUR (sizeof(int))
#define TWO ((size_t) 2)

static int calls;
static int sizes;

static size_t sized(size_t n) {
    sizes++;
    return n;
}

static char *counted(char *p) {
    calls++;
    return p;
}

static void show(const char *what, const unsigned char *p, int n) {
    printf("%s:", what);
    for (int i = 0; i < n; i++) {
        printf(" %d", p[i]);
    }
    printf("\n");
}

int main(void) {
    unsigned char buf[16];
    struct block b;
    int len = 3;
    unsigned ulen = 2u;
    long long wide = 2;
    size_t n = 5;
    size_t zero = 0;
    int izero = 0;
    for (int i = 0; i < 16; i++) {
        buf[i] = (unsigned char) (i + 1);
    }
    /* constant sizes: the call alone */
    memset(&b, 0, sizeof(b));
    memset(b.flags, -1, 3);
    memset(b.flags + 3, 'x' + 256, 2);
    show("fill", b.flags, 6);
    memcpy(b.coef, buf, 4 * sizeof(int));
    printf("copy %d %d\n", b.coef[0], b.coef[3]);
    /* run-time sizes, tested against zero */
    memmove(buf + 1, buf, n);
    show("move up", buf, 8);
    memmove(buf, buf + 2, n);
    show("move down", buf, 8);
    memcpy(buf, buf + 10, len);
    memcpy(buf + 4, buf + 12, ulen);
    memcpy(buf + 6, buf + 14, wide);
    show("copy widths", buf, 8);
    memcpy(NULL, NULL, zero);
    memmove(NULL, buf, zero);
    memcpy(buf, NULL, izero);
    __builtin_memcpy(buf + 8, buf, n);
    show("builtin", buf + 8, 6);
    /* a size with an effect, made once */
    memcpy(buf, buf + 1, n++);
    printf("n %d\n", (int) n);
    /* a block clear per step */
    int sum = 0;
    for (int k = 0; k < 4; k++) {
        memset(&b, k, sizeof(b));
        sum += b.flags[5] + (b.coef[2] & 0xff);
    }
    printf("sum %d\n", sum);
    /* a size from a call is made once, ahead of the test */
    memcpy(buf + 8, buf, sized(3));
    printf("sizes %d\n", sizes);
    /* a fill count C widened from `unsigned` or `long long`, a copy size of a lower precedence */
    unsigned m = 6u;
    memset(b.flags, 5, 3u);
    memset(b.flags + 3, 6, (long long) 2);
    memcpy(buf, buf + 4, m & 3u);
    show("widths", b.flags, 6);
    /* constant sizes through `+`, `_Alignof` and the macros */
    memcpy(b.flags, buf, sizeof(short) + 1);
    memcpy(buf + 10, buf, _Alignof(int));
    memcpy(buf + 2, buf + 12, FOUR);
    memcpy(buf + 6, buf, TWO);
    show("constants", buf, 16);
    /* sizes no constant holds: a cast to a byte, a product C wraps at 32 bits, an operand past int */
    unsigned char wide_src[48];
    unsigned char wide_dst[48];
    for (int i = 0; i < 48; i++) {
        wide_src[i] = (unsigned char) (3 * i);
        wide_dst[i] = 0;
    }
    memcpy(wide_dst, wide_src, (unsigned char) 300);
    memcpy(wide_dst, wide_src, 65536u * 65536u);
    memcpy(wide_dst, wide_src, 0x100000000ull * 0);
    show("wrapped", wide_dst + 40, 8);
    /* a volatile size is read once into the temporary */
    volatile size_t vn = 2;
    memcpy(buf, buf + 1, vn);
    show("volatile size", buf, 4);
    /* the forms that keep the crt call */
    memcpy(buf, buf + 1, 0);
    if (calls < 0) {
        memset(buf, 0, 0x80000000ull);
    }
    unsigned char *volatile vp = buf;
    memcpy(vp, buf + 1, n);
    memcpy(buf, counted((char *) buf + 2), n);

    unsigned char *r = memcpy(buf, "AB", 2);
    memcpy(counted((char *) buf), buf + 3, n);
    memset(buf, 7, n);
    show("crt", r, 8);
    printf("calls %d\n", calls);
    return 0;
}
