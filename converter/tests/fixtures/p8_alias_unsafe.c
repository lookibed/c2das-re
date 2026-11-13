/* P8.5: the punning shapes the JIT's typed aliasing model missed; each returns the bits it
   stored last, 1 and 3, natively and under every tier of the converted program */
#include <stdio.h>

/* two views of one float through void* parameters: a cast from void* is a pun to the model
   since lookibed/daScript#44 was fixed */
static float void_views(void *p, void *q) {
    float *f = p;
    unsigned *u = q;
    *f = 2.0f;
    *u = 0x3f800000u;
    return *f;
}

struct views {
    float *f;
    unsigned *u;
};

/* the views are made here, behind a void* record, so no caller learns of them */
static void make_views(void *rec, float *mem, int k) {
    struct views *v = rec;
    v->f = mem;
    v->u = (unsigned *)(mem + k);
}

/* no cast in this body: both views are loaded from the record */
static float record_views(struct views *v) {
    float *f = v->f;
    unsigned *u = v->u;
    *f = 2.0f;
    *u = 0x40400000u;
    return *f;
}

int main(int argc, char **argv) {
    float cells[4] = {0.0f, 0.0f, 0.0f, 0.0f};
    int k = argc - 1; /* 0 at run time, unknown to the compiler */
    struct views v;
    (void)argv;
    printf("%g\n", (double)void_views(&cells[0], &cells[k]));
    make_views(&v, cells, k);
    printf("%g\n", (double)record_views(&v));
    return 0;
}
