/* P4.8 scope fidelity: a switch in a hot loop whose case-level local a later case assigns and
   reads, and a goto into a block whose local hides a same-named global; `g` has external
   linkage, so the converted global keeps its C name and the flattened local takes `g1` */
static volatile int rounds = 400000;
static int result;
int g = 40;
static int step(int op, int x) {
    switch (op & 3) {
    case 0:;
        int v = x * 3;
        return v + 1;
    case 1:
        v = x ^ 5;
        return v - 2;
    case 2:
        v = x >> 1;
        return v + g;
    default:
        return x + g;
    }
}
static int hidden(int k) {
    int acc = 0;
    if (k & 1) goto in;
    acc += g;
    {
        int g = k * 2;
    in:
        acc += k;
        g = acc + 1;
        acc += g;
    }
    return acc + g;
}
static void kernel_run(void) {
    int n = rounds;
    unsigned acc = 0;
    int i;
    for (i = 0; i < n; i++) {
        acc = acc * 33 + (unsigned) step(i, i & 1023);
        acc ^= (unsigned) hidden(i & 255);
    }
    result = (int) (acc & 0x7fffffff);
}
static int kernel_result(void) { return result; }
