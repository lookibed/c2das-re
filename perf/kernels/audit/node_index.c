/* P7.0b lua's table: a node array reached as `&t->node[i]` (ltable.c `gnode`) and the array part as
   `&t->array[key - 1]` (luaH_getint), the masks of `lmod` on unsigned */
typedef struct Node { long long key; long long val; int next; } Node;
typedef struct Table { Node *node; long long *array; unsigned char lsizenode; unsigned alimit; } Table;
#define gnode(t, i) (&(t)->node[i])
#define lmod(s, size) ((int) ((s) & ((size) - 1)))
static volatile int rounds = 20000;
static Node nodes[64];
static long long arr[64];
static Table table;
static int result;
static long long probe(Table *t, int n) {
    long long acc = 0;
    for (int r = 0; r < n; r++) {
        for (unsigned h = 0; h < 64; h++) {
            Node *nd = gnode(t, lmod(h * 2654435761u, 1u << t->lsizenode));
            acc += nd->val ^ r;
            long long *slot = &t->array[(long long) h % t->alimit];
            acc += *slot;
        }
    }
    return acc;
}
static void kernel_run(void) {
    for (int k = 0; k < 64; k++) {
        nodes[k].key = k;
        nodes[k].val = 3 * k;
        arr[k] = k;
    }
    table.node = nodes;
    table.array = arr;
    table.lsizenode = 6;
    table.alimit = 64;
    result = (int) (probe(&table, rounds) & 0x7fffffff);
}
static int kernel_result(void) { return result; }
