int printf(const char *, ...);
static int attempts;
static int try_lock(void) { return ++attempts >= 3; }
static int retry_fail(int err) {
    int n = 0;
    attempts = 0;
retry:
    if (!try_lock()) { n++; goto retry; }
    if (err) goto fail;
    return n;
fail:
    n = -n;
    return n - 100;
}
static int nested_exit(int limit) {
    int i, j, found = -1;
    for (i = 0; i < 5; i++) {
        for (j = 0; j < 5; j++) {
            if (i * j == limit) { found = i * 10 + j; goto done; }
        }
    }
done:
    return found;
}
static int into_block(int x) {
    int r = 0;
    if (x > 0) goto inside;
    r += 1;
    {
        r += 10;
    inside:
        r += 100;
    }
    return r;
}
static int over_declaration(int x) {
    int r = 1;
    if (x) goto skip;
    r = 2;
    {
        int unused = 7;
        r += unused;
    }
skip:
    return r;
}
static int backward(void) {
    int n = 0;
again:
    n += 2;
    if (n < 7) goto again;
    return n;
}
static int tail_label(int x) {
    if (x) goto end;
    x = 5;
end:
    return x;
}
int main(void) {
    printf("%d %d %d %d\n", retry_fail(0), retry_fail(1), nested_exit(6), nested_exit(99));
    printf("%d %d %d %d %d %d\n", into_block(1), into_block(0), over_declaration(1), over_declaration(0), backward(), tail_label(0));
    return tail_label(9) + into_block(0);
}
