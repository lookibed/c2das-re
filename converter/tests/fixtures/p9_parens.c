#include <stdio.h>

/* a macro body's parentheses around a shift or a bitwise operator stay; around an argument,
   a unary or a comparison they go */
#define MASK1(n, p) ((~((~0u) << (n))) << (p))
#define TWICE(x) ((x) * 2)
#define IS(o, t) ((o) == (t))
#define VARIANT(t, v) ((t) | ((v) << 4))

int main(void) {
    int b = 4, a = 3, c = 5;
    unsigned u = 0xF0u;
    /* the author's parentheses around an operand stay, needed or not */
    int s = 1 << (b - 1);
    int t = (a + b) * c;
    int v = a + (b * c);
    int q = (a < b) ? (a + 1) : (b - 1);
    /* around a lone name, as an operand or not, and around a whole right-hand side, das needs none */
    int w = (a);
    int x = ((a + b));
    int r = (a) * (c);
    unsigned m = (u & MASK1(4, 4)) >> 4;
    int y = TWICE(a + 1);
    int k = IS(a, 3) && IS(b, 4);
    int z = VARIANT(3, 1) + 1;
    printf("%d %d %d %d %d %d %d %u %d %d %d\n", s, t, v, q, w, x, r, m, y, k, z);
    return 0;
}
