#ifndef A_H
#define A_H

/* `union B` is the first type the program meets, so b.h's node comes first; A points at it */
typedef union B B;

struct A {
    B *next;
    int v;
};

#endif
