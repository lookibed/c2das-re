#include <stdio.h>
#include "h.h"

int a_run(int n);
int c_run(void);
int e_run(void);

int main(void) {
    struct H h = {0, 5};
    struct G g = {&h, 1};
    printf("%d %d %d %d\n", a_run(3), c_run(), e_run(), g.h->w);
    return 0;
}
