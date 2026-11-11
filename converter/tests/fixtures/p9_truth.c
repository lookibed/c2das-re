/* P9.10: C's `!x` of a value that is no truth value is the inverted zero test (`x == 0`,
   `p == null`, `f == 0.0f`, `int(e) == 0`); a truth value read as an int is `int_of(c)` */
#include <stdio.h>

typedef enum { no, yes } boolean;
enum color { red, green };

struct line {
    int dx, dy;
};

static volatile int vol = 0;

static int side(const struct line *l) {
    if (!l->dx) {
        return l->dy > 0;
    }
    return l->dx < 0;
}

static int not_all(int a, unsigned u, const char *p, float f, double d, enum color c, char ch) {
    return !a + 2 * !u + 4 * !p + 8 * !f + 16 * !d + 32 * !c + 64 * !ch + 128 * !vol;
}

static int count_down(int n) {
    int k = 0;
    while (n--) {
        k++;
    }
    return k;
}

int main(void) {
    struct line l1 = {0, 3}, l2 = {0, -3}, l3 = {-2, 0};
    float zero = 0.0f;
    float nan = zero / zero;
    int x = 0;
    int a = 3, b = 5;
    x += a < b;
    x |= !(a < b);
    x += !!a * 10;
    boolean flag = a > b;
    boolean other = !a;
    _Bool t = a != 0;
    int from_bool = t;
    int sum = (a && b) + (a || 0) + (a == 3);
    printf("%d %d %d\n", side(&l1), side(&l2), side(&l3));
    printf("%d %d %d\n", not_all(0, 0u, NULL, 0.0f, 0.0, red, 0), not_all(1, 2u, "s", 0.5f, -1.0, green, 'c'), not_all(0, 1u, NULL, nan, nan, red, 0));
    printf("%d %d %d %d %d\n", x, flag, other, from_bool, sum);
    printf("%d %d\n", count_down(4), count_down(0));
    return !t;
}
