static int index(int k, int n) {
    return k + n;
}

static int volatile_load(int x) {
    return x + 1;
}

static int label_end(void) {
    return 7;
}

static int dialect(void) {
    return 9;
}

int other(void) {
    return index(1, 1) + volatile_load(1) * 10 + label_end() * 100 + dialect() * 1000;
}
