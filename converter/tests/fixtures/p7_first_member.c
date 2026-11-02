/* P7.0f: the address of a member at offset 0 - a struct's first member, a union's member, nested
   first members, an array member's decay - under `first_member` addr and reinterpret, and the
   addresses no offset proves (a later member, a record held by value) */
int printf(const char *, ...);
typedef struct TValue { long long v; int tt; } TValue;
typedef union StackValue { TValue val; struct { TValue tv; unsigned short delta; } tbc; } StackValue;
typedef struct GCObject { struct GCObject *next; unsigned char tt; } GCObject;
typedef struct Table { struct GCObject *next; unsigned char tt; int size; } Table;
typedef union GCUnion { GCObject gc; Table h; } GCUnion;
typedef union Cell { int i; float f; } Cell;
typedef struct Inner { int b; int c; } Inner;
typedef struct Outer { Inner a; int d; } Outer;
typedef struct Row { int cells[4]; int sum; } Row;
typedef struct Fixed { const int k; volatile int v; } Fixed;
typedef struct Ticker { volatile int v; } Ticker;
static TValue *slot(StackValue *base, int a) { return &(base + a)->val; }
static Table *as_table(GCObject *o) { return &((GCUnion *) o)->h; }
static int *as_cell(int *ip) { return &((Cell *) ip)->i; }
static int *nested(Outer *p) { return &p->a.b; }
static int *deref_first(Outer *p) { return &(*p).a.b; }
static Inner *indexed(Outer *p, int i) { return &p[i].a; }
static int *later(Outer *p) { return &p->d; }
static int *later_nested(Outer *p) { return &p->a.c; }
static int *decayed(Row *r) { return r->cells; }
static const int *constant(const Fixed *f) { return &f->k; }
static volatile int *ticking(Ticker *t) { return &t->v; }
int main(void) {
    StackValue stack[3];
    for (int i = 0; i < 3; i++) { stack[i].val.v = 10 * i; stack[i].val.tt = i; }
    TValue *top = slot(stack, 2);
    Table t = { 0, 5, 42 };
    Table *h = as_table((GCObject *) &t);
    int raw = 7;
    *as_cell(&raw) += 1;
    Outer outs[2] = { { { 1, 2 }, 3 }, { { 4, 5 }, 6 } };
    *nested(&outs[0]) += 100;
    *deref_first(&outs[1]) += 200;
    Inner *second = indexed(outs, 1);
    *later(&outs[0]) += 30;
    *later_nested(&outs[1]) += 40;
    Outer held = { { 8, 9 }, 10 };
    int *kept = &held.a.b;
    *kept += 1;
    Inner *elem = &outs[1].a;
    Row row = { { 1, 2, 3, 4 }, 0 };
    int *cells = decayed(&row);
    for (int i = 0; i < 4; i++) row.sum += cells[i];
    Row *rp = &row;
    int (*all)[4] = &rp->cells;
    Fixed fx = { 11, 12 };
    Ticker tk = { 13 };
    *ticking(&tk) += 1;
    printf("%lld %d %d %d\n", top->v, top->tt, h->size, raw);
    printf("%d %d %d %d %d %d %d\n", outs[0].a.b, outs[1].a.b, second->c, outs[0].d, outs[1].a.c, held.a.b, elem->b);
    printf("%d %d %d %d\n", row.sum, (*all)[3], *constant(&fx), tk.v);
    return 0;
}
