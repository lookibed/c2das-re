/* Cloak: REPEAT nested inside REPEAT, and REPEAT under a single EXPAND (partial evaluation) */
#include "cloak.h"
#define INNER(j, i) (i, j)
#define OUTER(i, _) EVAL(REPEAT(3, INNER, i))
EVAL(REPEAT(2, OUTER, ~))
#define M(i, _) i
EXPAND(REPEAT(3, M, ~))
EXPAND(EXPAND(REPEAT(3, M, ~)))
