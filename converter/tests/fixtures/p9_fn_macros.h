/* function-like macros of a header: their definitions' file is the header's */
struct cell { int tag; int v; };
#define TAG_OF(c) ((c)->tag)
#define IS_INT(c) (TAG_OF(c) == 3)
