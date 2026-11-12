/* P9.20 review: das inlines no call declared in a block with a label (error 30100); such a
   function keeps every expansion expanded, the others fold */
#include <stdio.h>

#define ALIGN_UP(x, a) (((x) + (a) - 1) & ~((a) - 1))

static int labeled(int n) {
    int r = 0;
again:
    n++;
    int v = ALIGN_UP(n, 8);
    r += v;
    if (r < 40)
        goto again;
    return r;
}

static int plain(int n) {
    n++;
    int v = ALIGN_UP(n, 8);
    return v;
}

int main(void) {
    printf("%d %d\n", labeled(3), plain(9));
    return 0;
}
