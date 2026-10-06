int printf(const char *, ...);
int main(void) {
    char b = 127;
    b = b + 1;
    unsigned char ub = 255;
    ub += 1;
    short s = 32767;
    s++;
    unsigned u = 3;
    int i = -1;
    long long m = i * 10LL;
    double d = 1.5;
    float f = 0.5f;
    d = d * f;
    printf("%d %u %d %d %lld %g\n", b, ub, s, i < u, m, d);
    printf("%d %d %d %d\n", -7 / 2, -7 % 2, -8 >> 1, (int)2.9);
    printf("%u %u %d\n", (unsigned)-1, u >> 1 | 2u, (int)(0x1FFFFFFFFLL));
    printf("%d %d %d %d\n", !i, !!i, i && u, i || 0);
    return (b == -128 && ub == 0) ? 42 : 1;
}
