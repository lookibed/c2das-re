/* P7.0e: a truth test through `__builtin_expect` and an integer widening is the test of the
   operand itself; a hint read as a number keeps its value */
int printf(const char *, ...);
#define l_likely(x) (__builtin_expect(((x) != 0), 1))
#define l_unlikely(x) __builtin_expect(((x) != 0), 0)
static int hits(int trap, long long wide, char c, int n) {
    int r = 0;
    if (l_unlikely(trap)) r += 1;
    if (l_likely(wide)) r += 10;
    while (l_likely(n > 0)) { r += 100; n--; }
    r += !l_unlikely(c) ? 1000 : 0;
    if (__builtin_expect((long) c, 1) && l_likely(trap)) r += 10000;
    if ((char) trap) r += 100000;
    return r;
}
int main(void) {
    long hint = __builtin_expect(7, 1);
    long truth = l_likely(3);
    printf("%d %d %d %ld %ld\n", hits(1, 0, 'a', 2), hits(0, 5, 0, 0), hits(256, 1, 1, 1), hint, truth);
    return 0;
}
