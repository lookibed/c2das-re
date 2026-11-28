/* #include through a macro, a computed header name, include_next, __has_include, #pragma once, include guards */
#define HDR "sub/a.h"
#include HDR
#define DIR sub
#define NAME b
#define STR2(x) #x
#define STR(x) STR2(x)
#define PATH(d,n) STR(d/n.h)
#include PATH(DIR,NAME)
#define ANGLE <sub/a.h>
#include ANGLE
#include "sub/once.h"
#include "sub/once.h"
#ifdef __has_include
# if __has_include("sub/a.h") && !__has_include("sub/missing.h")
int has_include_ok;
# endif
#endif
int after;
