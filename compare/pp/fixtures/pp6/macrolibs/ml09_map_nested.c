/* map-macro inside a function-like wrapper: the deferred recursion rescanned by an outer expansion */
#include "map.h"
#define WRAP(...) { __VA_ARGS__ }
#define ID(x) x
#define NEG(x) -x
int a[] = WRAP(MAP_LIST(NEG, 1, 2, 3));
int b[] = ID(WRAP(MAP_LIST(ID, MAP_LIST(NEG, 4, 5))));
