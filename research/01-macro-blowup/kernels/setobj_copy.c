/* research 01: setobj / setobj2s expanded in place at every use, as lvm.c's OP_MOVE and
   OP_GETTABUP copy a TValue: the io1/io2 block against a helper `def setobj` */
typedef union Value { long long i; double n; void *gc; } Value;
typedef struct TValue { Value value_; unsigned char tt_; } TValue;
typedef struct StackValue { TValue val; } StackValue;
#define s2v(o) (&(o)->val)
#define settt_(o,t) ((o)->tt_=(t))
#define setobj(L,obj1,obj2) \
    { TValue *io1=(obj1); const TValue *io2=(obj2); \
      io1->value_ = io2->value_; settt_(io1, io2->tt_); }
#define setobj2s(L,o1,o2) setobj(L,s2v(o1),o2)
#define setobjs2s(L,o1,o2) setobj(L,s2v(o1),s2v(o2))
#define ttisinteger(o) ((o)->tt_ == 3)
#define ivalue(o) ((o)->value_.i)
static volatile int rounds = 4000;
static StackValue stack[64];
static TValue konst[8];
static int result;
static long long shuffle(StackValue *base, TValue *k, int n) {
    long long acc = 0;
    for (int r = 0; r < n; r++) {
        for (int a = 1; a < 64; a++) {
            setobjs2s(0, base + a, base + a - 1);           /* OP_MOVE */
            setobj2s(0, base + (a & 7), k + (a & 7));       /* OP_LOADK */
            TValue *ra = s2v(base + a);
            if (ttisinteger(ra)) acc += ivalue(ra) + r;
        }
    }
    return acc;
}
static void kernel_run(void) {
    for (int a = 0; a < 64; a++) { stack[a].val.value_.i = a; stack[a].val.tt_ = (unsigned char) (a & 1 ? 3 : 19); }
    for (int a = 0; a < 8; a++) { konst[a].value_.i = a * 7; konst[a].tt_ = 3; }
    result = (int) (shuffle(stack, konst, rounds) & 0x7fffffff);
}
static int kernel_result(void) { return result; }
