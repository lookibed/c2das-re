/* metalang99: list recursion and arithmetic through ML99_EVAL */
#include <metalang99.h>
int s = ML99_EVAL(ML99_listFoldl(v(ML99_add), v(0), ML99_list(v(1, 2, 3, 4, 5))));
int fact5 = ML99_EVAL(ML99_mul(v(5), ML99_mul(v(4), ML99_mul(v(3), v(2)))));
#define F_IMPL(x) v(int field##x;)
#define F_ARITY 1
ML99_EVAL(ML99_listMapInPlace(v(F), ML99_list(v(a, b, c))))
int n = ML99_EVAL(ML99_listLen(ML99_list(v(1, 2, 3, 4, 5, 6, 7))));
