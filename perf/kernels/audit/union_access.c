/* P7.0b lua's TValue and GCUnion: a tagged value whose payload is a union, an object reached by
   casting its common header to the union of every object type (lobject.h `gco2t`, lstate.h
   `cast_u`), read in a hot loop */
typedef struct GCObject { struct GCObject *next; unsigned char tt; unsigned char marked; } GCObject;
typedef union Value { GCObject *gc; long long i; double n; } Value;
typedef struct TValue { Value value_; unsigned char tt_; } TValue;
typedef struct Table { GCObject *next; unsigned char tt; unsigned char marked; int size; long long sum; } Table;
typedef struct Closure { GCObject *next; unsigned char tt; unsigned char marked; int nup; long long id; } Closure;
union GCUnion { GCObject gc; Table h; Closure cl; };
#define cast_u(o) ((union GCUnion *) (o))
#define gco2t(o) (&((cast_u(o))->h))
#define gco2cl(o) (&((cast_u(o))->cl))
static volatile int rounds = 20000;
static Table tables[8];
static Closure closures[8];
static TValue values[64];
static int result;
static long long walk(int n) {
    long long acc = 0;
    for (int r = 0; r < n; r++) {
        for (int k = 0; k < 64; k++) {
            TValue *v = &values[k];
            if (v->tt_ == 5) {
                acc += gco2t(v->value_.gc)->size;
            } else if (v->tt_ == 6) {
                acc += gco2cl(v->value_.gc)->id;
            } else {
                acc += v->value_.i ^ r;
            }
        }
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
            values[k].value_.gc = (GCObject *) &tables[k % 8];
            values[k].tt_ = 5;
        } else if (k % 3 == 1) {
            values[k].value_.gc = (GCObject *) &closures[k % 8];
            values[k].tt_ = 6;
        } else {
            values[k].value_.i = k;
            values[k].tt_ = 3;
        }
    }
    result = (int) (walk(rounds) & 0x7fffffff);
}
static int kernel_result(void) { return result; }
