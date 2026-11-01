/* braced scalar initializers (P8.4 (b)): `T *p = { NULL }` as wasm3 spells `m3Err_none`, and the
   same braces around an int, a double, an enum and a record's scalar members */
#include <stdio.h>
#include <stddef.h>

typedef const char *result_t;

static const result_t err_none = { NULL };
static const result_t err_fail = { "failed" };
static int counter = { 3 };

enum color { RED, GREEN, BLUE };

struct cell {
    int n;
    const char *name;
    double w;
};

static struct cell table[2] = { { { 1 }, { "one" }, { 0.5 } }, { { 2 }, { NULL }, { 1.5 } } };

static result_t check(int ok) {
    return ok ? err_none : err_fail;
}

int main(void) {
    enum color c = { BLUE };
    double half = { 0.5 };
    const char *msg = { NULL };
    result_t r = check(counter > 2);
    printf("none %d fail %s\n", r == NULL, check(0));
    printf("counter %d color %d half %.2f msg %d\n", counter, (int)c, half, msg == NULL);
    for (int i = 0; i < 2; i++) {
        printf("cell %d %s %.1f\n", table[i].n, table[i].name ? table[i].name : "(null)", table[i].w);
    }
    return 0;
}
