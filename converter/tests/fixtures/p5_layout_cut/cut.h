#ifndef CUT_H
#define CUT_H

/* b.c defines the record; the header reaches it through a pointer, so the header's types module
   owns it and no unit is required by the header */
struct hidden;

struct box {
    struct hidden *h;
    int v;
};

extern int b_count;
int a_run(int n);
int a_back(int n);
int b_step(int n);
int b_note(int n, ...);
struct box b_make(int secret);
int b_open(struct box *b);

#endif
