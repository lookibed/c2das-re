#include <stdio.h>
#include <stdlib.h>

/* a flexible array member in the record's tail padding (wasm3's `M3FuncType`): the member at 14,
   the record 16 wide; das leaves the member out, keeps the size, and decays it at offset 14; the
   same for bytes right after a byte (`tagged`, the member at 5 of 8) */
typedef struct func_type {
    struct func_type *next;
    unsigned short num_rets;
    unsigned short num_args;
    unsigned short kind;
    unsigned short types[];
} func_type;

struct tagged {
    int n;
    char tag;
    char text[];
};

int main(void) {
    func_type *t = malloc(sizeof(func_type) + 4 * sizeof(unsigned short));
    t->next = NULL;
    t->num_rets = 1;
    t->num_args = 3;
    t->kind = 7;
    for (int i = 0; i < 4; i++) {
        t->types[i] = (unsigned short) (10 + i);
    }
    unsigned short *types = t->types;
    printf("%d %d %d %d %d\n", (int) sizeof(func_type), t->kind, t->types[0], types[3], (int) ((char *) types - (char *) t));
    free(t);
    struct tagged *g = malloc(sizeof(struct tagged) + 3);
    g->n = 2;
    g->tag = 'x';
    g->text[0] = 'o';
    g->text[1] = 'k';
    g->text[2] = 0;
    printf("%d %c %s %d\n", (int) sizeof(struct tagged), g->tag, g->text, (int) (g->text - (char *) g));
    free(g);
    return 0;
}
