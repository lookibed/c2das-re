/* P7.5 fixture: declarator groups clang spells as written - a parenthesized pointer (`int
   (*const)`, a ParenType), a function returning a function pointer, a pointer to one and an
   array of those; a function returning a pointer to an array, a pointer to one, an array of those
   and a const pointer to an array. Converted output must match the native build of this file. */
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

static int rows[2][3] = {{1, 2, 3}, {4, 5, 6}};

/* `int (*(void))[3]`: a function returning a pointer to an array */
static int (*row0(void))[3] {
    return &rows[0];
}

static int (*row1(void))[3] {
    return &rows[1];
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
    int (*(*row_of)(void))[3] = row1;
    int (*(*row_table[2])(void))[3] = {row0, row1};
    int (*const last)[3] = &rows[1];
    store(p, 7);
    printf("%d %d %d %d\n", (*row0())[2], (*row_of())[0], (*row_table[0]())[1], (*last)[2]);
    printf("%d %d\n", cells[1], (*(*choose)(0, 2))(2, 2));
    printf("%d %d\n", pick(1, 1)(3, 4), table[1](0)(9, 4));
    return (*choose)(5, 5)(1, 1) - 2;
}
