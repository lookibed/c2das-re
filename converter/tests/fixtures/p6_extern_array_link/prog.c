#include <stdio.h>
#include "opts.h"

int main(void) {
    int count = 0;
    for (struct opt *o = opts; o->name; o++) {
        printf("%s=%d\n", o->name, o->value);
        count++;
    }
    opts[1].value = 3;
    table[0] = 1;
    printf("%d %d %d %d\n", total(5), (int) (slot(5) - slot(0)), opts[1].value, grid[1][2]);
    return count;
}
