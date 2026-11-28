/* macros in #include, #line, #if lines and _Pragma */
#define HDR "vers2.h"
#include HDR
#define str(s) #s
#define xstr(s) str(s)
#define V(n) vers ## n.h
#include xstr(V(2))
#define LN 50
#line LN
__LINE__
#define ONE 1
#if ONE
one_taken
#endif
#define EMPTYDEF
#if defined EMPTYDEF
defined_taken
#endif
_Pragma("foo \"bar\" \\x") after _Pragma("once") _Pragma ( "pack(push, 2)" ) x _Pragma("STDC FP_CONTRACT ON")
#define P(x) _Pragma(#x) y
P(message("hi")) z
#define EMPTY
EMPTY w
q EMPTY
r
