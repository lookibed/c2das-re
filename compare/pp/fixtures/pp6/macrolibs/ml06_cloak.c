/* Cloak: EVAL + DEFER/OBSTRUCT recursion (REPEAT, WHILE-style), the idiom h09 isolates */
#include "cloak.h"
#define M(i, _) i
EVAL(REPEAT(8, M, ~))
#define DECL(i, ty) ty v##i;
EVAL(REPEAT(5, DECL, int))
int b = EQUAL(3, 3), c = NOT_EQUAL(1, 2);
