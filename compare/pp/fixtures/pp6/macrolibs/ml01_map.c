/* map-macro: MAP and MAP_LIST over lists (EVAL + deferred recursion) */
#include "map.h"
#define STRING(x) char const *x##_string = #x;
MAP(STRING, foo, bar, baz)
#define PARAM(x) int x
void function(MAP_LIST(PARAM, foo, bar, baz));
#define CALL(x) putchar x;
MAP(CALL, ('a'), ('b'), ('c'))
