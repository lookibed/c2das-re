/* map-macro: user data and nested MAP over a longer list */
#include "map.h"
#define PRINT_STREAM(x, stream) fprintf(stream, "%d\n", x);
MAP_UD(PRINT_STREAM, stderr, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
#define INVOKE(x, fun) fun(x)
int arr[] = { MAP_LIST_UD(INVOKE, map, 1, 2, 3, 4, 5) };
#define SQ(x) ((x) * (x))
int sq[] = { MAP_LIST(SQ, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16) };
