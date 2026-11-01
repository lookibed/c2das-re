/* P7.0b lua's stack: registers reached as `base + i` on a `StackValue *` and the value's address
   taken (`s2v(base + GETARG_A(i))`), a register copy per step as OP_MOVE does */
typedef union Value { void *gc; long long i; double n; } Value;
typedef struct TValue { Value value_; unsigned char tt_; } TValue;
typedef union StackValue { TValue val; struct { Value value_; unsigned char tt_; unsigned short delta; } tbclist; } StackValue;
#define s2v(o) (&(o)->val)
static volatile int rounds = 20000;
static StackValue stack[64];
static int result;
static long long move(StackValue *base, int n) {
    long long acc = 0;
    for (int r = 0; r < n; r++) {
        for (int a = 0; a < 60; a++) {
            TValue *io1 = s2v(base + a + 1);
            const TValue *io2 = s2v(base + a);
            io1->value_ = io2->value_;
            io1->tt_ = io2->tt_;
            acc += s2v(base + a + 2)->value_.i;
        }
    }
    return acc;
}
static void kernel_run(void) {
    for (int k = 0; k < 64; k++) {
        stack[k].val.value_.i = k;
        stack[k].val.tt_ = 3;
    }
    result = (int) (move(stack, rounds) & 0x7fffffff);
}
static int kernel_result(void) { return result; }
