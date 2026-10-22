/* a program whose declarations live in a header beside it (P5.1): the record, the typedefs, the
   enum, the prototype, the extern object, the static function and the static table of
   p5_project_header.h convert with this file; <string.h> stays a system header, its strlen
   bound by name */
#include <stdio.h>
#include <string.h>
#include "p5_project_header.h"

int figures_made = 0;

int area(const figure *f) {
    int side = f->corner.x - f->corner.y;
    switch (f->kind) {
    case SQUARE:
        return side * side;
    case TRIANGLE:
        return side * side / 2;
    default:
        return SCALED(side) * side;
    }
}

static figure make(enum shape kind, int x, int y, const char *name) {
    figure f;
    f.kind = kind;
    f.corner.x = x;
    f.corner.y = y;
    f.name = name;
    figures_made++;
    return f;
}

int main(void) {
    figure all[3];
    int i, total = 0;
    all[0] = make(CIRCLE, 5, 1, "circle");
    all[1] = make(SQUARE, 7, 2, "square");
    all[2] = make(TRIANGLE, 9, 3, "triangle");
    for (i = 0; i < 3; i++) {
        int a = clamp(area(&all[i]), 0, 40);
        total += a * weights[i];
        printf("%s %d %d %d\n", all[i].name, (int) strlen(all[i].name), a, weights[i]);
    }
    printf("made %d total %d scale %d\n", figures_made, total, SCALED(1));
    return total % 7;
}
