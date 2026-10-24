#include <stdio.h>
#include "shape.h"

static int counter = 1;

static int bump(void) {
    return ++counter;
}

/* locals named like the renamed static keep their own name */
static int scoped(int n) {
    int sum = counter;
    {
        int counter = n * 100;
        sum += counter;
    }
    for (int counter = 0; counter < 3; counter++) {
        sum += counter;
    }
    return sum + counter;
}

int calls;

int main(int argc, char **argv) {
    struct point a = {1, 2};
    struct point b = {4, 6};
    struct bag g = {{5, 7}};
    printf("%d\n", area(a, b));
    printf("%d %d\n", bump(), geo_bump());
    printf("%d\n", bump());
    printf("%d %d\n", is_even(10), is_odd(7));
    printf("%d\n", calls);
    header_bias += 10;
    printf("%d %d %d\n", header_bias, geo_bias(), biased(0));
    printf("%d %d\n", twice(21), quad(2));
    printf("%d %d %d\n", flavor(), geo_flavor(), flavor_twice());
    {
        /* a local spelled like the name parity.c's kept copy of `flavor` would take */
        int parity_flavor = 100;
        printf("%d\n", flavor() + parity_flavor);
    }
    printf("%d %d\n", bag_total(&g), scoped(2));
    printf("%d %d\n", total(3, 1, 2, 3), argc);
    return argv[argc] == 0 ? 0 : 1;
}
