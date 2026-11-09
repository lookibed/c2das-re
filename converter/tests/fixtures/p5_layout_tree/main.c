#include <stdio.h>
#include "sub/shapes.h"

FILE *ring_stream(void);

/* the address of another module's global, set before main runs */
int *main_count = &solo_count;

/* a third `helper`, the entry module's own */
static int helper(int v) {
    return v - 1;
}

static int add(int a, int b) {
    return a + b;
}

/* the ring's depths are constants: daslang's optimizer folds the mutually recursive calls only
   once the globals they read hold their values (probe-findings F73) */
int main(int argc, char **argv) {
    union number u;
    struct point p = { 2, 3 };
    enum mode m = MODE_MUL;
    FILE *out = ring_stream();
    u.i = 0;
    u.f = 1.5f;
    solo_count += 10;
    *main_count += 1;
    fprintf(out, "%d %d %d %d\n", ring_a(3), ring_b(2), *ring_cell(), argv[argc] == 0);
    fprintf(out, "%d %d\n", solo_apply(add, p.x, p.y), solo_apply(ring_mul, p.x, p.y));
    printf("%d %d %d %d\n", solo_count, solo_sum(3, 1, 2, 3), helper((int) m), twice(4));
    printf("%d %s %d\n", u.i != 0, solo_name(), ring_words());
    return 0;
}
