// Function-like macros: the --fn-macros knob folds a macro into a [c_macro] def (fold)
// or spells its expansion at every site (expand).
#include <stdio.h>

#define SQUARE(x) ((x) * (x))
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define CLAMP(v, lo, hi) ((v) < (lo) ? (lo) : (v) > (hi) ? (hi) : (v))

int main(void)
{
    for (int i = -3; i <= 3; i++)
        printf("%d: square %d, max with 0 %d, clamped to [-1, 1] %d\n", i, SQUARE(i), MAX(i, 0), CLAMP(i, -1, 1));
    return 0;
}
