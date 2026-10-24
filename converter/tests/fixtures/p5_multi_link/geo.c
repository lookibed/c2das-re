#define FLAVOR 1
#include "shape.h"

static int counter = 100;

static int bump(void) {
    counter += 10;
    return counter;
}

int geo_bump(void) {
    return bump();
}

int area(struct point a, struct point b) {
    calls++;
    return (b.x - a.x) * (b.y - a.y);
}

int geo_bias(void) {
    return biased(header_bias) + twice(0);
}

int geo_flavor(void) {
    return flavor() * 10 + quad(1) + flavor_twice() * 100;
}

int bag_total(const struct bag *b) {
    int sum = 0;
    for (int i = 0; i < BAG_SLOTS; i++) {
        sum += b->item[i];
    }
    return sum;
}

int is_even(unsigned n) {
    return n == 0 ? 1 : is_odd(n - 1);
}
