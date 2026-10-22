/* the header half of p5_lua_shapes.c: macros that spell offsetof and an extern table the way
   lua's headers do */
#ifndef P5_LUA_SHAPES_H
#define P5_LUA_SHAPES_H

#include <stddef.h>

typedef struct cell0 { char tag; double payload; } cell0;
typedef struct cell { char tag; int count; double slots[2]; } cell;

/* lobject.h:489 `udatamemoffset`: two offsetof in one expansion of a header macro */
#define cell_offset(n) ((n) == 0 ? offsetof(cell0, payload) : offsetof(cell, slots) + sizeof(double) * (n))

/* lfunc.h:14 `sizeCclosure`: offsetof under a cast in a header macro */
#define cell_size(n) ((int) offsetof(cell, slots) + (int) sizeof(double) * (n))

/* luaconf.h:325 `LUAI_FUNC`, ltm.h:71 `LUAI_DDEC`: an extern table declared with an attribute */
#define SHAPES_FUNC __attribute__((visibility("internal"))) extern
#define SHAPES_DDEC(dec) SHAPES_FUNC dec
SHAPES_DDEC(const char *const shape_names[3];)

/* lua.h:157 `extern const char lua_ident[];`: an array of unknown length its definition completes */
extern const char shapes_ident[];

#endif
