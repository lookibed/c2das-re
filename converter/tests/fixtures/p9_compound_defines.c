/* P9.5: a `#define` constant whose body names other `#define` constants is a module `let` over
   their names, recursively, and a constant a function-like macro's body names is its name */
#include <stdio.h>

#define SIZE_OP 7
#define POS_OP 0
#define SIZE_A 8
#define POS_A (POS_OP + SIZE_OP)
#define POS_K (POS_A + SIZE_A)
#define MASK_A (~(~0u << SIZE_A))
#define GETARG_A(i) ((int)(((i) >> POS_A) & MASK_A))
#define ONE 1
#define TWO_ONES (ONE + ONE)
#define ONES_PLUS (ONE + ONE + 3)
#define MIX (POS_K + SIZE_OP + 1)
#define SUM 1 + 2
#define SUM_TIMES (SUM * 3)
#define ZERO() 0
#define AFTER_ZERO (ZERO() + 5)
#define BELOW_EOF (EOF - 1)
#define SPREAD \
    (POS_K * 2) /* a body on a continued line */
#define SPREAD_PLUS (SPREAD + 1)
#define START (POS_A + 1)

static int start = START;

static int decode(unsigned i) {
    return GETARG_A(i) + POS_K;
}

int main(void) {
    unsigned code = 0x1234u;
    printf("%d %d %d %d %d %d %d %d %d %d %d\n", decode(code), TWO_ONES, ONES_PLUS, MIX, SUM_TIMES, AFTER_ZERO, BELOW_EOF, SPREAD, SPREAD_PLUS, start, (int)MASK_A);
    return 0;
}
