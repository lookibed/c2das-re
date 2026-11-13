#include <stdio.h>
#include "shape.h"

int area(struct pt *p);
extern int count;

int main(void) {
    struct pt q = { 2, 5 };
    int a = area(&q);
    printf("%d %d %d %d\n", a, SUM2(&q), SCALE(q.y), NOTED(q.x));
    printf("%d\n", count);
    return 0;
}
