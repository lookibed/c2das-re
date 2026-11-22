/* P7.5 fixture: declarator groups clang spells as written - a parenthesized pointer (`int
   (*const)`, a ParenType), a function returning a function pointer, a pointer to one and an
   array of those. Converted output must match the native build of this file. */
#include <stdio.h>

static int sub(int c, int b) {
    return c - b;
}

static int add(int c, int b) {
    return c + b;
}

/* `int (*(int, int))(int, int)`: a function returning a function pointer */
static int (*pick(int a, int b))(int c, int d) {
    if (a != b)
        return sub;
    return add;
}

static int (*pick_one(int which))(int, int) {
    return which ? add : sub;
}

/* `void (int (*const))`: a parameter written `int (* const x)` */
static void store(int (* const x), int v) {
    x[1] = v;
}

int main(void) {
    int cells[2] = {0, 0};
    int (*p) = cells;
    int (* (*choose)(int a, int b))(int c, int d) = pick;
    int (*(*table[2])(int))(int, int) = {pick_one, pick_one};
    store(p, 7);
    printf("%d %d\n", cells[1], (*(*choose)(0, 2))(2, 2));
    printf("%d %d\n", pick(1, 1)(3, 4), table[1](0)(9, 4));
    return (*choose)(5, 5)(1, 1) - 2;
}
