/* renamed past `c_volatile_load` and `c_label_end`, which the module spells for a volatile
   access and a label */
static int volatile_load(int x) {
    return x * 100;
}

static int label_end(void) {
    return 5;
}

volatile int vv = 4;

static int g(int n) {
    int r = 0;
    if (n) {
        goto out;
    }
    r = 10;
out:
    return r + label_end();
}

int c_run(void) {
    vv = vv + 1;
    return vv + volatile_load(2) + g(0) * 1000 + g(1) * 10000;
}
