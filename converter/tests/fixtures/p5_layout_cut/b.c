#include <stdarg.h>
#include "cut.h"

struct hidden {
    int secret;
};

static struct hidden kept = { 0 };

/* an object main.c reads: no cut can late-bind it */
int b_count = 4;

/* three call sites into a.c: the heavier edge, which stays a require */
int b_step(int n) {
    if (n <= 0) {
        return a_back(0);
    }
    return a_back(n) + a_back(n - 1) + b_step(n - 1);
}

int b_note(int n, ...) {
    va_list ap;
    int s = 0;
    va_start(ap, n);
    for (int i = 0; i < n; i++) {
        s += va_arg(ap, int);
    }
    va_end(ap);
    return s;
}

struct box b_make(int secret) {
    struct box b;
    kept.secret = secret;
    b.h = &kept;
    b.v = secret + 1;
    return b;
}

int b_open(struct box *b) {
    return b->h->secret + b->v;
}
