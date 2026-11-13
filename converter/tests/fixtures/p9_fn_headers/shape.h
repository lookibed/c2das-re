/* P9.22: header macros. PX, SCALE and SUM2 need only the header's record and constant: one public
   def in shape_h.das; SETX writes through its pointer, so its def's `p` is `var` and so is the `p` of
   area.c's BUMP, which passes its own on. NOTED calls a unit's function: a private def in each
   module using it. */
#ifndef SHAPE_H
#define SHAPE_H
#define FACTOR 3
struct pt {
    int x, y;
};
int note(int v);
#define PX(p) ((p)->x)
#define SCALE(v) ((v) * FACTOR)
#define NOTED(v) (note(v) + 1)
#define SUM2(p) (PX(p) + (p)->y)
#define SETX(p, v) ((p)->x = (v))
#endif
