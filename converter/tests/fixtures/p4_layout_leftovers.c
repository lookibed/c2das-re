int printf(const char *, ...);

/* a bitfield member of a union: a property pair over the storage, beside the plain members */
union Pun { volatile signed f0 : 8; volatile unsigned f1; };
union Only { const unsigned f0 : 2; };
union Wide { char c; long long f : 5; };
union Odd { char c[3]; unsigned f : 20; };
/* unnamed bitfield members are no members: their bits still count toward clang's size */
union Gap { char c; int : 12; };
union Zero { short a; int b; const unsigned : 0; int c; };
struct HoldsPun { int k; union Pun u; };
union Flag { _Bool b : 1; unsigned char raw; };
union __attribute__((packed)) PackedUnion { char c; unsigned f : 5; };

/* bitfields no naturally aligned unit covers clear of the plain fields take byte units (linux
   dialect): Cramped, Tail3, Lead3, Five, WideJoin, SplitJoin, ZeroSkip */
struct Cramped { const signed f0 : 16; unsigned f1 : 14; const signed char f2; unsigned f3 : 12; int f4; unsigned f5 : 19; volatile signed f6 : 30; volatile unsigned f7 : 27; };
struct Tail3 { unsigned f0 : 21; short f1; unsigned f2 : 30; unsigned f3 : 8; unsigned f4 : 13; signed f5 : 5; signed f6 : 18; signed char f7; };
struct Lead3 { unsigned f0 : 24; signed char f1; signed f2 : 20; long long f3; };
struct Five { char c; unsigned long long x : 40; };
struct WideJoin { unsigned char a : 3; unsigned long long b : 40; short s; };
struct SplitJoin { char c; unsigned a : 12; unsigned b : 12; unsigned char d : 7; unsigned e : 20; short s; };
struct ZeroSkip { char c; unsigned a : 9; int : 0; char d; };
/* records das's natural placement leaves short of clang's offsets or size take padding fields:
   a record holding one whose bitfield units align below clang (HoldBF, CharBF), a record whose
   units or unnamed bitfields end before clang's size (OnlyPad, Narrow, ZeroTail), a unit clang
   moves past a zero-width bitfield (FloorUnit) */
struct BF { unsigned a : 3; int b : 5; short e; };
struct HoldBF { struct BF bf; short y; };
struct CharBF { char c; struct BF bf; };
struct OnlyPad { char a; int : 20; };
struct Narrow { unsigned a : 3; char c; };
struct ZeroTail { short p0; unsigned : 0; };
struct ZeroMid { char c; int : 0; char d; };
struct FloorUnit { char c; long long : 0; unsigned a : 3; };
/* a zero-width bitfield right after a bitfield aligns the record by its declared type under
   msvc (ZeroAfterBits 16/8, linux 12/4); one after a plain field does not (ZeroAfterPlain 3/1,
   linux 9/1) */
struct ZeroAfterBits { char c; unsigned a : 9; long long : 0; char d; };
struct ZeroAfterPlain { char x : 3; char y; long long : 0; char d; };
struct HoldsNarrow { char k; struct Narrow n; short after; struct OnlyPad o[2]; };
/* a C field spelled like a padding field, in a record that does not pad */
struct PadName { int _pad0; int x; };
/* packed records the law places: every plain field sits at a multiple of its das alignment */
struct __attribute__((packed)) PackedBits { unsigned a : 3; char c; unsigned b : 20; };
struct __attribute__((packed)) Wide64 { char c; unsigned long long a : 64; };
#pragma pack(2)
struct Pack2 { short s; unsigned a : 3; short t; unsigned b : 20; };
#pragma pack()
/* a bitfield stepped and compound-stored through a pointer step and a field, in a struct and in
   a union */
struct BFPair { unsigned a : 5; unsigned b : 3; };
struct HoldsPair { int k; struct BFPair bf; };
union Small { unsigned s : 5; unsigned x; };
struct HoldsSmall { int k; union Small u; };
struct BFInts { int b : 5; unsigned long long w : 40; };
union IntPun { int s : 6; unsigned x; };
struct HoldsInts { int k; struct BFInts bf; union IntPun u; };
static struct HoldsPair pairs[4];
static struct HoldsSmall smalls[4];
static struct HoldsInts ints[4];

static union Pun gpun = { -3 };
static struct Cramped gcramped = { -5, 1000, -7, 4000, 123456, 300000, -100000000, 100000000 };
static struct Cramped gcrampeds[2] = { { 1, 2, 3, 4, 5, 6, 7, 8 }, { -1, -2, -3, -4, -5, -6, -7, -8 } };
static struct HoldBF ghold = { { 5, -6, 7 }, 8 };
static struct Narrow gnarrow[3] = { { 1, 2 }, { 7, 255 }, { 0, 3 } };

static int read_pun(const union Pun *p) { return p->f0; }
static void bump_through(struct HoldsPair *p) { p[1].bf.a += 1; p[2].bf.a++; p[2].bf.b--; }
static void step_union(struct HoldsSmall *p) { p[2].u.s++; p[3].u.s--; }
static void store_through(struct HoldsInts *p) { p[2].bf.b += 3; p[2].bf.w += 5; p[3].bf.b -= 1; p[1].u.s += 4; p[1].u.s |= 2; p[3].bf.w <<= 2; }

int main(void) {
    union Pun a = { 0 };
    a.f1 = 0x12345678u;
    printf("%d %u\n", a.f0, a.f1);
    a.f0 = 511;
    printf("%d %u\n", a.f0, a.f1);
    a.f0++;
    a.f0 += 3;
    --a.f0;
    printf("%d %u %d %d\n", a.f0, a.f1, gpun.f0, read_pun(&a));
    union Only only = { 1 };
    union Odd odd;
    odd.f = 0xfffff;
    odd.c[0] = 1;
    printf("%u %u %d\n", only.f0, odd.f, (int) sizeof(union Odd));
    union Wide w;
    w.c = 0;
    w.f = -1;
    printf("%lld %d %d\n", (long long) w.f, w.c, (int) sizeof(union Wide));
    union Zero z;
    z.c = 4;
    printf("%d %d %d\n", z.b, (int) sizeof(union Gap), (int) sizeof(union Zero));
    struct HoldsPun in = { 1, { 9 } };
    in.u.f0 = -100;
    struct HoldsPun *pin = &in;
    pin->u.f0 -= 1;
    printf("%d %u\n", in.u.f0, in.u.f1);

    struct Cramped s = gcramped;
    s.f3 += 100;
    s.f1--;
    s.f6 = -s.f6;
    printf("%d %u %d %u %d %u %d %u\n", s.f0, s.f1, s.f2, s.f3, s.f4, s.f5, s.f6, s.f7);
    printf("%d %d %d %u\n", (int) sizeof(struct Cramped), gcrampeds[1].f0, gcrampeds[1].f2, gcrampeds[1].f3);
    struct Cramped local = { 7, 8, 9, 10, 11, 12, 13, 14 };
    struct Cramped *pc = &local;
    pc->f3 = pc->f3 * 3 + 1;
    printf("%u %d\n", local.f3, local.f2);
    struct Tail3 t3 = { 0x1fffff, -2, 0x3fffffff, 200, 8000, -16, -131072, -9 };
    t3.f6 += 1;
    printf("%u %d %u %u %u %d %d %d %d\n", t3.f0, t3.f1, t3.f2, t3.f3, t3.f4, t3.f5, t3.f6, t3.f7, (int) sizeof(struct Tail3));
    struct Lead3 l3 = { 0xabcdef, -1, -524288, 1LL << 40 };
    l3.f0 ^= 0xffffff;
    printf("%u %d %d %lld %d\n", l3.f0, l3.f1, l3.f2, l3.f3, (int) sizeof(struct Lead3));
    struct Five five = { 9, 0xffffffffffULL };
    five.x += 2;
    printf("%d %llu %d\n", five.c, (unsigned long long) five.x, (int) sizeof(struct Five));

    struct HoldBF h = ghold;
    h.bf.b = -16;
    h.y = 3;
    struct HoldBF harr[3];
    harr[2] = h;
    printf("%d %d %d %d %d\n", (int) sizeof(struct HoldBF), harr[2].bf.a, harr[2].bf.b, harr[2].y, (int) ((char *) &harr[2] - (char *) &harr[0]));
    struct CharBF cb = { 1, { 2, 3, 4 } };
    printf("%d %d %d\n", (int) sizeof(struct CharBF), cb.bf.e, (int) ((char *) &cb.bf - (char *) &cb));
    struct OnlyPad op = { 5 };
    printf("%d %d\n", (int) sizeof(struct OnlyPad), op.a);
    printf("%d %u %d\n", (int) sizeof gnarrow, gnarrow[1].a, gnarrow[1].c);

    union Flag flag;
    flag.raw = 0;
    flag.b = 1;
    printf("%d %d\n", flag.b, flag.raw);
    flag.raw = 2;
    printf("%d\n", flag.b);
    flag.b = 0;
    printf("%d %d\n", flag.b, flag.raw);
    union PackedUnion pu;
    pu.c = 0;
    pu.f = 21;
    printf("%d %d\n", (int) sizeof(union PackedUnion), pu.f);
    struct WideJoin wj = { 5, 77, 3 };
    wj.b += 1000;
    printf("%d %d %llu %d\n", (int) sizeof wj, wj.a, (unsigned long long) wj.b, wj.s);
    struct SplitJoin sj = { 1, 5, 4000, 100, 1000000, 9 };
    sj.e--;
    printf("%d %d %u %u %u %u %d\n", (int) sizeof sj, sj.c, sj.a, sj.b, sj.d, sj.e, sj.s);
    struct ZeroSkip zs = { 1, 300, 4 };
    struct ZeroTail zt = { 5 };
    struct ZeroMid zm = { 6, 7 };
    printf("%d %u %d %d %d %d %d %d\n", (int) sizeof zs, zs.a, zs.d, (int) sizeof zt, zt.p0, (int) sizeof zm, zm.c, zm.d);
    struct FloorUnit fu = { 2, 5 };
    fu.a += 1;
    printf("%d %d %u\n", (int) sizeof fu, fu.c, fu.a);
    struct ZeroAfterBits zb = { 1, 300, 4 };
    zb.a += 7;
    struct ZeroAfterPlain zp = { 3, 5, 6 };
    zp.x -= 1;
    printf("%d %d %u %d %d %d %d %d\n", (int) sizeof zb, zb.c, zb.a, zb.d, (int) sizeof zp, zp.x, zp.y, zp.d);
    struct HoldsNarrow hn[2] = { { 1, { 2, 3 }, 4, { { 5 }, { 6 } } }, { 7, { 6, 9 }, 10, { { 11 }, { 12 } } } };
    hn[1].n.a += 1;
    hn[1].after = -1;
    printf("%d %d %d %u %d %d %d\n", (int) sizeof(struct HoldsNarrow), (int) ((char *) &hn[1] - (char *) &hn[0]), (int) ((char *) &hn[1].after - (char *) &hn[1]), hn[1].n.a, hn[1].after, hn[1].o[1].a, (int) ((char *) &hn[1].o[1] - (char *) &hn[1]));
    struct PadName pn = { 3, 4 };
    printf("%d %d\n", pn._pad0, pn.x);
    struct PackedBits pb = { 5, 2, 1000000 };
    pb.b += 3;
    struct Pack2 p2 = { 1, 6, 2, 999999 };
    p2.b -= 9;
    printf("%d %u %d %u %d %d %u %d %u\n", (int) sizeof pb, pb.a, pb.c, pb.b, (int) sizeof p2, p2.s, p2.a, p2.t, p2.b);
    bump_through(pairs);
    step_union(smalls);
    printf("%u %u %u %u %u\n", pairs[1].bf.a, pairs[2].bf.a, pairs[2].bf.b, smalls[2].u.s, smalls[3].u.s);
    ints[3].bf.w = 0xffffffffffULL;
    store_through(ints);
    printf("%d %llu %d %llu %d %u\n", ints[2].bf.b, (unsigned long long) ints[2].bf.w, ints[3].bf.b, (unsigned long long) ints[3].bf.w, ints[1].u.s, ints[1].u.x);
    struct Wide64 w64 = { 3, 0xfedcba9876543210ULL };
    w64.a += 0x10;
    w64.c++;
    printf("%d %llx %d\n", (int) sizeof w64, (unsigned long long) w64.a, w64.c);
    return s.f0 + 5;
}
