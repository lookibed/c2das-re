/* P4.7 layout leftovers, under the linux dialect: read-modify-writes of bitfields in a record of
   naturally aligned units (Natural); in a record whose f3 takes a two-byte unit (Cramped), built
   each round from an initializer whose f3 word is spread into the unit's bytes; in a record that
   holds an underaligned bitfield record before a short and takes a padding field to reach
   clang's size (HoldBF); and in a union whose bitfield member puns with a plain one beside an
   unnamed bitfield (Pun) */
struct Natural { unsigned lo : 12; signed mid : 9; unsigned hi : 11; short tag; };
struct Cramped { signed f0 : 16; unsigned f1 : 14; signed char f2; unsigned f3 : 12; int f4; };
struct BF { unsigned a : 3; int b : 5; short e; };
struct HoldBF { struct BF bf; short y; };
union Pun { signed f0 : 8; unsigned : 12; unsigned f1; };
static volatile int rounds = 20000;
static int result;
static unsigned mix(int n) {
    struct Natural p[16] = { { 0 } };
    struct Cramped c[16] = { { 0 } };
    struct HoldBF h[16] = { { { 0 } } };
    union Pun u;
    unsigned sum = 0;
    int i;
    u.f1 = 0;
    for (i = 0; i < n; i++) {
        int k = i & 15;
        struct Cramped seed = { -3, 7, 5, (unsigned) i, k };
        p[k].lo += i;
        p[k].mid -= 3;
        p[k].hi ^= p[k].lo;
        c[k].f3 += p[k].hi + seed.f3;
        c[k].f0 = c[k].f0 + p[k].mid + seed.f0;
        c[k].f1 += c[k].f3 & 7;
        h[k].bf.a += 1;
        h[k].bf.b -= c[k].f1 & 3;
        h[k].y += h[k].bf.a;
        u.f0 = u.f0 + c[k].f0;
        u.f1 += (unsigned) k;
        sum = sum * 31 + (unsigned) (p[k].mid + c[k].f3 + u.f0 + h[k].bf.b + h[k].y) + c[k].f1;
    }
    return sum;
}
static void kernel_run(void) { result = (int) (mix(rounds) & 0x7fffffff); }
static int kernel_result(void) { return result; }
