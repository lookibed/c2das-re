/* P8.5: the punning shapes the JIT's typed aliasing model keeps right; each writes a float, then
   the same bytes under another type, and reads the float back */
#include <stdio.h>
#include <string.h>

union fu {
    float f;
    unsigned u;
};

union val {
    double n;
    long long i;
    void *p;
};

/* a union member written under one type and read under another (C99 6.5.2.3) */
static float union_bits(union fu *a, union fu *b) {
    a->f = 2.0f;
    b->u = 0x3f800000u;
    return a->f;
}

/* the same over a Lua-style value: a double and a 64-bit integer */
static double value_bits(union val *a, union val *b) {
    a->n = 2.0;
    b->i = 0x3ff0000000000000ll;
    return a->n;
}

/* a typed pointer cast to another type */
static float cast_views(float *p, float *q) {
    unsigned *u = (unsigned *)q;
    *p = 2.0f;
    *u = 0x3f800000u;
    return *p;
}

/* a byte view, as C's character-type rule allows */
static float char_views(float *p, float *q) {
    unsigned char *b = (unsigned char *)q;
    *p = 2.0f;
    b[0] = 0x00;
    b[1] = 0x00;
    b[2] = 0x80;
    b[3] = 0x3f;
    return *p;
}

/* the bits copied in by memcpy */
static float memcpy_views(float *p, float *q) {
    unsigned bits = 0x3f800000u;
    *p = 2.0f;
    memcpy(q, &bits, sizeof bits);
    return *p;
}

/* two integer widths through void*: one class to the model, so the views alias */
static int width_views(void *p, void *q) {
    int *i = p;
    short *s = q;
    *i = 0x12345678;
    *s = 0x1111;
    return *i;
}

int main(int argc, char **argv) {
    float cells[2] = {0.0f, 0.0f};
    union fu us[2];
    union val vs[2];
    int words[2] = {0, 0};
    int k = argc - 1; /* 0 at run time, unknown to the compiler */
    (void)argv;
    printf("%g\n", (double)union_bits(&us[0], &us[k]));
    printf("%g\n", value_bits(&vs[0], &vs[k]));
    printf("%g\n", (double)cast_views(&cells[0], &cells[k]));
    printf("%g\n", (double)char_views(&cells[0], &cells[k]));
    printf("%g\n", (double)memcpy_views(&cells[0], &cells[k]));
    printf("%x\n", width_views(&words[0], &words[k]));
    return 0;
}
