/* P7.0b lua's wrapping integer arithmetic (lvm.c `intop`): a 64-bit signed add of an `int`
   immediate and a product, each through unsigned (`l_castU2S(l_castS2U(a) op l_castS2U(b))`) as
   OP_ADDI and OP_MUL do */
#define l_castS2U(i) ((unsigned long long) (i))
#define l_castU2S(i) ((long long) (i))
#define intop(op, v1, v2) l_castU2S(l_castS2U(v1) op l_castS2U(v2))
static volatile int rounds = 20000;
static long long regs[64];
static int result;
static long long arith(int n) {
    long long acc = 0;
    for (int r = 0; r < n; r++) {
        for (int k = 0; k < 64; k++) {
            int imm = k - 32;
            acc = intop(+, acc, imm);
            acc = intop(^, acc, intop(*, regs[k], 3));
        }
    }
    return acc;
}
static void kernel_run(void) {
    for (int k = 0; k < 64; k++) regs[k] = k * 1000003;
    result = (int) (arith(rounds) & 0x7fffffff);
}
static int kernel_result(void) { return result; }
