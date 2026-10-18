#include <alloca.h>
#include <string.h>
int printf(const char *, ...);
static int sum_bytes(const unsigned char *p, int n) {
    int s = 0, i;
    for (i = 0; i < n; i++) s += p[i];
    return s;
}
static int variable(int n) {
    unsigned char *buf = alloca(n);
    memset(buf, 3, n);
    buf[0] = 1;
    return sum_bytes(buf, n);
}
static int accumulate(int rounds) {
    char *keep[4];
    int i, total = 0;
    for (i = 0; i < rounds; i++) {
        char *t = alloca(8);
        strcpy(t, "ab");
        t[2] = (char) ('0' + i);
        t[3] = 0;
        keep[i] = t;
    }
    for (i = 0; i < rounds; i++) total += keep[i][2] - '0' + (int) strlen(keep[i]);
    return total;
}
static int recursive(int depth) {
    int *slot = __builtin_alloca(sizeof(int) * 4);
    slot[0] = depth;
    if (depth == 0) return slot[0];
    return slot[0] + recursive(depth - 1);
}
static int constant_size(void) {
    char *fixed = alloca(16);
    strcpy(fixed, "fixed");
    return (int) strlen(fixed);
}
int main(void) {
    printf("%d %d %d %d\n", variable(5), accumulate(4), recursive(10), constant_size());
    return variable(3) + constant_size();
}
