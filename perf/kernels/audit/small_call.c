/* P7.0b a small function called on every pass of a hot loop with pointer arguments, as the VM calls
   luaH_getint: the call's own cost under each tier, some keys outside the array part */
typedef struct Table { long long *array; unsigned alimit; } Table;
static volatile int rounds = 20000;
static long long arr[64];
static Table table;
static int result;
static long long *luaH_getint(Table *t, long long key) {
    if ((unsigned long long) key - 1u < t->alimit) return &t->array[key - 1];
    return 0;
}
static long long sum(Table *t, int n) {
    long long acc = 0;
    for (int r = 0; r < n; r++) {
        for (long long key = 1; key <= 64; key++) {
            long long *v = luaH_getint(t, (key + r) % 70);
            if (v) acc += *v;
        }
    }
    return acc;
}
static void kernel_run(void) {
    for (int k = 0; k < 64; k++) arr[k] = k;
    table.array = arr;
    table.alimit = 64;
    result = (int) (sum(&table, rounds) & 0x7fffffff);
}
static int kernel_result(void) { return result; }
