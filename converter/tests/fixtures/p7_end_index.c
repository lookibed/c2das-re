/* P7.0zb: `&a[k]` of an array - a constant index folded at emit time, a plain load as das's own
   index with the length as the one exception, any other index through `end_index` - and the
   address one past the end against native; with arguments, an index past the end or below zero panics */
int printf(const char *, ...);
enum Ch { CH0, CH1, CH2, CH3, CH_COUNT };
typedef struct Obj { int v; } Obj;
typedef struct Emu { Obj oam[4]; int k; unsigned char small; } Emu;
typedef struct Bits { unsigned lo : 3; unsigned hi : 5; } Bits;
typedef union Pick { int k; float f; } Pick;
static int a[4] = {1, 2, 3, 4};
static Emu g_emu = {{{10}, {20}, {30}, {40}}, 4, 2};
static int calls;
static int *at_int(int k) { return &a[k]; }
static int *at_uint(unsigned k) { return &a[k]; }
static int *at_long(long k) { return &a[k]; }
static int *at_ulong(unsigned long long k) { return &a[k]; }
static Obj *at_small(Emu *e) { return &e->oam[e->small]; }
static Obj *at_field(Emu *e) { return &e->oam[e->k]; }
static int *at_enum(void) { return &a[CH2]; }
static int *at_enum_end(void) { return &a[CH_COUNT]; }
static int *at_cast(void) { return &a[(unsigned char)3]; }
static int *at_wrapped(void) { return &a[(unsigned char)260]; }
static int *at_bool_cast(void) { return &a[(_Bool)4]; }
static int *at_enum_var(enum Ch c) { return &a[c]; }
static int *at_bitfield(Bits *b) { return &a[b->lo]; }
static int *at_union(Pick *p) { return &a[p->k]; }
static int *at_sum(int i, int j) { return &a[i + j]; }
static int *at_bool(_Bool b) { return &a[b]; }
static int *at_volatile(void) { volatile int vk = 4; return &a[vk]; }
static Emu *next_emu(void) { calls++; return &g_emu; }
static Obj *at_effect(int k) { return &next_emu()->oam[k]; }
static Obj *at_volatile_base(int k) { Emu *volatile vp = &g_emu; return &vp->oam[k]; }
static int span(const int *b, const int *e) { int s = 0; while (b != e) s += *b++; return s; }
int main(int argc, char **argv) {
    (void)argv;
    if (argc == 5) {
        return *at_long(5);
    }
    if (argc == 4) {
        return *at_uint(5u);
    }
    if (argc == 3) {
        return *at_int(-1);
    }
    if (argc == 2) {
        return *at_int(5);
    }
    printf("%d %d %d %d\n", (int)(at_int(4) - a), (int)(at_uint(4u) - a), (int)(at_long(4) - a), (int)(at_ulong(4u) - a));
    printf("%d %d %d %d\n", *at_int(0), *at_uint(3u), *at_long(1), *at_ulong(2u));
    printf("%d %d\n", at_small(&g_emu)->v, (int)(at_field(&g_emu) - g_emu.oam));
    printf("%d %d %d %d\n", *at_enum(), (int)(at_enum_end() - a), *at_cast(), (int)(at_wrapped() - a));
    printf("%d %d %d\n", (int)(at_sum(2, 2) - a), *at_bool(1), (int)(at_volatile() - a));
    printf("%d %d %d\n", (int)(at_effect(4) - g_emu.oam), calls, (int)(at_volatile_base(4) - g_emu.oam));
    Bits bits = {4, 1};
    Pick pick = {4};
    printf("%d %d %d %d %d\n", (int)(at_bool_cast() - a), (int)(at_enum_var(CH_COUNT) - a), *at_enum_var(CH1), (int)(at_bitfield(&bits) - a), (int)(at_union(&pick) - a));
    printf("%d %d\n", span(a, &a[g_emu.k]), (int)(&a[g_emu.k] - &a[1]));
    return 0;
}
