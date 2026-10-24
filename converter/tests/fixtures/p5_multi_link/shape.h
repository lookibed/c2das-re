#ifndef SHAPE_H
#define SHAPE_H

struct point {
    int x;
    int y;
};

/* the record's first use comes before the enum its dimension names */
struct bag;
int bag_total(const struct bag *b);
enum { BAG_SLOTS = 2 };
struct bag {
    int item[BAG_SLOTS];
};

extern int calls;
int area(struct point a, struct point b);
int geo_bump(void);
int geo_bias(void);
int geo_flavor(void);
int is_even(unsigned n);
int is_odd(unsigned n);
int total(int n, ...);

static int header_bias = 3;

static inline int twice(int v) {
    return v * 2;
}

static inline int quad(int v) {
    return twice(twice(v));
}

static inline int biased(int v) {
    return v + header_bias;
}

#ifndef FLAVOR
#define FLAVOR 0
#endif

static inline int flavor(void) {
    return FLAVOR;
}

static inline int flavor_twice(void) {
    return flavor() * 2;
}

#endif
