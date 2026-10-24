#ifndef B_H
#define B_H

#include "a.h"

/* holds a.h's record by value: the two headers point at each other, one module, and a.h's
   fragment goes first, since [c_union] reads its members' records where it is declared */
union B {
    struct A a;
    long long wide;
};

#endif
