/* the library half of p8_include_dirs, included by app/main.c through `-I../lib` */
#include "../shared/shared.h"

struct pair make_pair(int a, int b) {
    struct pair p;
    p.a = a;
    p.b = b;
    return p;
}

int pair_sum(const struct pair *p) {
    return p->a + p->b;
}
