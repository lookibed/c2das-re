/* P99: P99_NARG, P99_FOR, P99_SEQ, P99_REPEAT */
#include "p99_for.h"
int n0 = P99_NARG(), n3 = P99_NARG(a, b, c);
#define SUMOP(NAME, I, X, Y) ((X) + (Y))
#define IDENT(NAME, X, I) X
int sum = P99_FOR(, 4, SUMOP, IDENT, 1, 2, 3, 4);
#define DECLARE(NAME, X, I) int X = I
P99_FOR(, 3, P00_SEP, DECLARE, p, q, r);
int z[] = { P99_DUPL(3, 7) };
