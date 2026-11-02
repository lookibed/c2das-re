#ifndef G_H
#define G_H

/* g.h and h.h hold pointers to each other's records: two header nodes in one cycle */
struct H;

struct G {
    struct H *h;
    int v;
};

#endif
