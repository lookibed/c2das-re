/* P7.0f lua's first members: a register's value through `&(base + a)->val` on an array of stack
   slots (`s2v`) and an object's table or closure through `&((union GCUnion *) o)->h` (`gco2t`,
   `gco2cl`), in a hot loop whose sum a volatile sink takes each round */
typedef struct GCObject { struct GCObject *next; unsigned char tt; unsigned char marked; } GCObject;
typedef union Value { GCObject *gc; long long i; double n; } Value;
typedef struct TValue { Value value_; unsigned char tt_; } TValue;
typedef union StackValue { TValue val; struct { Value value_; unsigned char tt_; unsigned short delta; } tbclist; } StackValue;
typedef struct Table { GCObject *next; unsigned char tt; unsigned char marked; int size; } Table;
typedef struct Closure { GCObject *next; unsigned char tt; unsigned char marked; long long id; } Closure;
union GCUnion { GCObject gc; Table h; Closure cl; };
#define s2v(o) (&(o)->val)
#define gco2t(o) (&(((union GCUnion *) (o))->h))
#define gco2cl(o) (&(((union GCUnion *) (o))->cl))
static volatile int rounds = 20000;
static volatile long long sink;
static StackValue stack[64];
static Table tables[8];
static Closure closures[8];
static int result;
static long long walk(StackValue *base, int n) {
    long long acc = 0;
    for (int r = 0; r < n; r++) {
        for (int a = 0; a < 62; a++) {
            TValue *v = s2v(base + a);
            if (v->tt_ == 5) {
                acc += gco2t(v->value_.gc)->size;
            } else if (v->tt_ == 6) {
                acc += gco2cl(v->value_.gc)->id;
            } else {
                acc += (v->value_.i ^ r) + s2v(base + a + 1)->tt_;
            }
        }
        sink = acc;
    }
    return acc;
}
static void kernel_run(void) {
    for (int k = 0; k < 8; k++) {
        tables[k].tt = 5;
        tables[k].size = k + 1;
        closures[k].tt = 6;
        closures[k].id = 10 * k;
    }
    for (int k = 0; k < 64; k++) {
        if (k % 3 == 0) {
            stack[k].val.value_.gc = (GCObject *) &tables[k % 8];
            stack[k].val.tt_ = 5;
        } else if (k % 3 == 1) {
            stack[k].val.value_.gc = (GCObject *) &closures[k % 8];
            stack[k].val.tt_ = 6;
        } else {
            stack[k].val.value_.i = k;
            stack[k].val.tt_ = 3;
        }
    }
    result = (int) (walk(stack, rounds) & 0x7fffffff);
}
static int kernel_result(void) { return result; }
