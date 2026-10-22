#include <stdlib.h>

int printf(const char *, ...);

/* trailing arrays read past their declaration: a flexible array member (C99), allocated with
   room for its elements, filled, summed and decayed; and the C89 idiom of a fixed trailing array
   over a larger allocation (Doom's `columnofs[8]`), which the sidecar lists under `over_indexed`
   so its accesses take no range check */
struct samples {
    int n;
    int data[];
};

struct patch {
    short width;
    short height;
    int columnofs[8];
};

static int sum(const int *v, int n) {
    int s = 0;
    for (int i = 0; i < n; i++) {
        s += v[i];
    }
    return s;
}

static void flexible(int n) {
    struct samples *s = malloc(sizeof(struct samples) + n * sizeof(int));
    s->n = n;
    for (int i = 0; i < n; i++) {
        s->data[i] = i * i;
    }
    (*s).data[0] += 100;
    int *row = s->data;
    printf("flexible %d %d %d %d\n", (int) sizeof(struct samples), sum(s->data, s->n), row[n - 1], (*s).data[0]);
    free(s);
}

static void over_indexed(int width) {
    struct patch *p = malloc(sizeof(struct patch) + (width - 8) * sizeof(int));
    p->width = (short) width;
    p->height = 3;
    for (int x = 0; x < width; x++) {
        p->columnofs[x] = 1000 + x;
    }
    int *col = &p->columnofs[width - 1];
    printf("over %d %d %d %d\n", p->width, p->columnofs[2], p->columnofs[width - 2], *col);
    free(p);
}

int main(void) {
    flexible(5);
    over_indexed(12);
    return 0;
}
