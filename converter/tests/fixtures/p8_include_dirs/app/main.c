/* a unit wider than its folder (P8.4 (a)): `lib.c` comes from a sibling folder through the
   sidecar's `include_dirs`, `shared.h` through a `../` path; the sidecar's `program_root`, the
   fixture's folder, makes both the program's */
#include <stdio.h>
#include "../shared/shared.h"
#include "lib.c"

int main(void) {
    struct pair p = make_pair(3, 4);
    printf("sum %d scaled %d\n", pair_sum(&p), SCALE(pair_sum(&p)));
    return pair_sum(&p) - 7;
}
