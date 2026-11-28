/* the names the preprocessor answers itself, under SOURCE_DATE_EPOCH */
#define f(x,y) x+y __LINE__
a f(1,
2) b __LINE__
f
(3,4) e __LINE__
#define id(x) x
id(__LINE__
__LINE__) __LINE__
#define L2 __LINE__
id(
L2
)
__COUNTER__ __COUNTER__ __INCLUDE_LEVEL__ __DATE__ __TIME__ __TIMESTAMP__
#include "builtins.h"
__FILE_NAME__
#line 100 "x\\y.c"
__LINE__ __FILE__ __FILE_NAME__
