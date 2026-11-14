#include <stdio.h>
#include <stdlib.h>

/* a statement macro taking a pointer (wasm3's `m3_Free`): folded, a `void *` argument beside typed
   ones would add a `void?` overload that makes every typed call ambiguous in das, so the sites
   passing a `void *` stay expanded and the typed ones share the def, whichever comes first */
#define RELEASE(P) do { free((void *) (P)); (P) = NULL; } while (0)

struct node {
    int value;
};

int main(void) {
    struct node *n = malloc(sizeof *n);
    int *counts = malloc(4 * sizeof *counts);
    void *raw = malloc(8);
    n->value = 5;
    counts[0] = 3;
    printf("%d %d\n", n->value, counts[0]);
    RELEASE(raw);
    RELEASE(n);
    RELEASE(counts);
    printf("%d %d %d\n", n == NULL, counts == NULL, raw == NULL);
    return 0;
}
