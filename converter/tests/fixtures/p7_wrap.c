/* P7.0d: C's wrapping signed arithmetic through the unsigned twin with a narrower operand and the
   operators beyond `+` and `-` (lua's `intop`), past the type's range */
int printf(const char *, ...);
#define l_castS2U(i) ((unsigned long long) (i))
#define l_castU2S(i) ((long long) (i))
#define intop(op, v1, v2) l_castU2S(l_castS2U(v1) op l_castS2U(v2))
static long long regs[4] = {9223372036854775807LL, -3, 4294967297LL, 7};
static long long mixed(long long acc, int imm, unsigned u, short s, char c) {
    acc = intop(+, acc, imm);
    acc = intop(^, acc, intop(*, regs[0], 3));
    long long p = intop(*, regs[2], regs[2]);
    long long q = intop(-, p, u) + intop(&, regs[1], s) + intop(|, c, 1);
    unsigned w = (unsigned) imm * 2654435761u;
    int x = (int) ((unsigned) imm * 2654435761u) + (int) ((unsigned) s + 3u);
    return acc + q + w + x;
}
int main(void) {
    printf("%lld %lld\n", mixed(9223372036854775800LL, 100, 4000000000u, -5, 'a'), mixed(-1, -2147483647 - 1, 1u, 32767, 0));
    return 0;
}
