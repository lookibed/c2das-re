/* `assert` without `NDEBUG` (P8.4 (g)): the own <assert.h> spells one conditional expression over
   `__assert_fail`, with the expression's text, the file, the line and `__func__`; every assertion
   here holds, so both builds print the same lines */
#include <assert.h>
#include <stdio.h>

static int square(int v) {
    assert(v >= 0 && "a square of a negative is not asked for");
    return v * v;
}

int main(void) {
    int total = 0;
    for (int i = 0; i < 4; i++) {
        assert(i < 4);
        total += square(i);
    }
    assert(total == 14);
    printf("%s total %d\n", __func__, total);
    return 0;
}
