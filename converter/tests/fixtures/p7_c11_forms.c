// The C11 and GNU forms of P7.6's third slice: a generic selection, a pointer to an enum the
// unit never defines, a bitfield of enum type, an initializer of an anonymous member, and a
// statement expression an expression statement assigns or holds in a `void` conditional.
#include <stdio.h>

#define kind_of(x) _Generic((x), int: 1, long: 2, const char *: 3, char *: 4, default: 9)

static int twice(int n) { return 2 * n; }
static int thrice(int n) { return 3 * n; }

static int generics(void) {
    int i = 0;
    long l = 5;
    const char *s = "s";
    double d = 1.5;
    // the controlling expression is never evaluated
    int picked = _Generic(i++, int: twice, long: thrice)(7);
    printf("%d %d %d %d %d\n", kind_of(i), kind_of(l), kind_of(s), kind_of("lit"), kind_of(d));
    printf("%d %d %s\n", picked, i, _Generic(l + i, long: "long", int: "int"));
    // an lvalue stays one
    _Generic(l, long: i, default: picked) = 4;
    return i;
}

enum never *nowhere;
const enum never *nowhere_const;

static int incomplete(void) {
    int cell = 6;
    nowhere = (enum never *)&cell;
    nowhere_const = nowhere;
    return (nowhere == nowhere_const) + *(int *)nowhere;
}

enum code { LOW = 3, HIGH = 148, TOP };
enum sign { NEG = -2, POS = 1 };
struct node { struct node *next; enum code code : 8; unsigned flag : 1; enum sign sign : 3; };
union packed_code { enum code c : 4; int whole; };
static struct node root = { 0, TOP, 1, NEG };

static int classify(struct node *n) {
    switch ((enum code)n->code) {
    case TOP: return 1;
    case LOW: return 2;
    default: return 0;
    }
}

static void enum_bitfields(void) {
    struct node n = { &root, HIGH, 0, POS };
    union packed_code u = { LOW };
    enum code got;
    printf("%d %d %d %d\n", root.code, root.flag, root.sign, classify(&root));
    printf("%d %d %d\n", n.code, n.sign, classify(&n));
    n.code = TOP;
    n.sign = NEG;
    got = n.code;
    printf("%d %d %d %d\n", got == TOP, n.sign < 0, n.next->code, classify(&n));
    got = (n.code = LOW);
    n.code |= 4;
    printf("%d %d %d\n", got == LOW, n.code, (int)sizeof(struct node));
    u.c = (enum code)9;
    printf("%d %d\n", u.c, u.whole & 15);
}

typedef unsigned char u8;
union pair { struct { u8 a, b; }; unsigned short both; };
union pair braced = {{6, 5}};
union pair designated = {.b = 8, .a = 7};
struct tagged { int tag; union { int i; float f; }; };
struct tagged by_float = { .tag = 2, .f = 1.5f };

static void anonymous_members(void) {
    union pair local = {{1, 2}};
    printf("%d %d %d %d %d %d\n", braced.a, braced.b, designated.a, designated.b, local.a, local.b);
    printf("%d %g\n", by_float.tag, by_float.f);
}

static int blocks(int n) {
    int r = 0;
    r = ({ int k = n; while (k > 10) k -= 10; k; });
    (r > 5 ? (void)printf("high %d\n", r) : ({ int k = r; while (k < 6) k += 2; printf("low %d -> %d\n", r, k); }));
    (r = (({ int twice_r = 2 * r; twice_r + 1; })));
    return r;
}

int main(void) {
    printf("%d\n", generics());
    printf("%d\n", incomplete());
    enum_bitfields();
    anonymous_members();
    printf("%d %d\n", blocks(27), blocks(32));
    return 0;
}
