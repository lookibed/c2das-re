#include <stdio.h>

/* an inner index run past its row into the next (Quake's `model.c`: `out->vecs[0][j]` for
   `j < 8` over `float vecs[2][4]`), C's undefined behaviour the native build tolerates; the
   sidecar lists the member under `flat_indexed`, so the inner index goes unchecked through the row */
typedef struct {
    float vecs[2][4];
    int flags;
} texinfo_t;

int main(void) {
    texinfo_t in, out;
    for (int j = 0; j < 8; j++) {
        in.vecs[0][j] = (float) j;
    }
    in.flags = 3;
    for (int j = 0; j < 8; j++) {
        out.vecs[0][j] = in.vecs[0][j] * 2;
    }
    out.flags = in.flags;
    printf("%g %g %g %d\n", out.vecs[1][3], out.vecs[0][2], in.vecs[1][0], out.flags);
    return 0;
}
