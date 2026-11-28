/* an include guard a macro produces is no guard: the second #include reads the header again */
#define NOT_DEFINED ! defined (guard)
#include "guard_macro.h"
#define guard
#undef NOT_DEFINED
#define NOT_DEFINED 1
#define VAR five
int main(void) { int five = 0;
#include "guard_macro.h"
return five; }
