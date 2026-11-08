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

static int calls;

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
    /* the forms that keep the crt call */
    unsigned char *r = memcpy(buf, "AB", 2);
    memcpy(counted((char *) buf), buf + 3, n);
    memset(buf, 7, n);
    show("crt", r, 8);
    printf("calls %d\n", calls);
    return 0;
}
