#ifndef SHAPES_H
#define SHAPES_H

/* the program's types, which every module of it requires from sub/shapes_h.das */
struct point {
    int x;
    int y;
};

union number {
    int i;
    float f;
};

enum mode { MODE_ADD = 1, MODE_MUL = 2 };

typedef int (*binop)(int, int);

/* a function the header defines: a copy per module, one per cluster */
static int twice(int v) {
    return v * 2;
}

extern int solo_count;
int solo_apply(binop f, int a, int b);
int solo_sum(int n, ...);
const char *solo_name(void);
int ring_a(int n);
int ring_b(int n);
int ring_mul(int a, int b);
int *ring_cell(void);
int ring_words(void);

#endif
