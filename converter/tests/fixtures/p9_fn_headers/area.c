#include "shape.h"

int count;

int note(int v) {
    count++;
    return v;
}

#define BUMP(p) SETX(p, count + 4)

int area(struct pt *p) {
    BUMP(p);
    return SCALE(PX(p)) * p->y + NOTED(p->y);
}
