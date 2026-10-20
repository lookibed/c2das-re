#include <stdio.h>
/* the pointer shapes csmith generates around pointer parameters: a pointer returned or copied
   out through `*pp` or a `?:` arm, compared across constness, and arrays of null pointers */
int sprintf(char *, const char *, ...);
static int g = 5;
static int h = 6;
static int *table[3] = {(void *) 0, (void *) 0, (void *) 0};
static int *rows[2][2] = {{(void *) 0, (void *) 0}, {&g, (void *) 0}};
static int *partial[2][2] = {{&g}};
static int *pass_back(int *p) { return p; }
static int *pick(int k, int *p, int *q) { return k ? p : q; }
static void keep(int **pp, int **out) { *out = *pp; }
static int via_alias(int *p) { int **l = 0; l = &p; return **l; }
static int chained(int *p) { int *l[2]; l[0] = (p = &g); return *l[0] + *p; }
static int same(const int *p, int *q) { return p == q; }
static int is_null(const int *p) { return (int *) 0 == p; }
static int write_either(char *b, char *e, int k) { return sprintf(k ? b : e, "%d", k * 7); }
int main(void) {
    int *out = 0;
    int *src = &h;
    int *local[2] = {(void *) 0, (void *) 0};
    char x[8] = "", y[8] = "";
    keep(&src, &out);
    local[1] = pick(1, &g, &h);
    printf("%d %d %d %d %d\n", *pass_back(&g), *pick(0, &g, &h), *out, same(&g, &g), same(&g, &h));
    printf("%d %d\n", partial[0][0] == &g, partial[1][1] == 0);
    printf("%d %d %d %d %d\n", is_null(table[1]), is_null(&g), rows[1][0] == &g, local[0] == 0, *local[1]);
    printf("%d %s%s %d %d\n", write_either(x, y, 1), x, y, via_alias(&h), chained(&h));
    return 0;
}
