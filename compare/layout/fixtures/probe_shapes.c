/* The records probes/test_layout.das lays out through clang (`c_shapes`, `UNNAMED_SHAPES`). */

struct P { int x; short y; };
struct M { char a; long long b; double c; };
struct I { char a; long long b; };
struct O { char c; struct I inner; short d; void (*cb)(int); char e; };
struct A { int id; int vals[4]; struct I inner; };
struct BC { _Bool b; char c; };
struct T2 { char a; short b; int c; char d; };
struct BF { unsigned a : 3; int b : 5; short e; };
struct HoldBF { struct BF bf; short y; };
struct CharBF { char c; struct BF bf; };
struct AC { unsigned a : 3; char c; };
struct OuterAC { char q; struct AC a; };

struct Pad20 { char a; int : 20; };
struct Zero0 { char a; int : 0; char b; };
struct ZeroBits { char c; char x : 3; long long : 0; char d; };
struct ZeroShort { char x : 3; short : 0; };
struct ZeroTail { char x : 3; long long : 0; };
struct ZeroPlain { char x : 3; char y; long long : 0; char d; };
struct ZeroTwice { char x : 3; int : 0; long long : 0; char d; };
struct ZeroNine { char c; unsigned a : 9; long long : 0; char d; };
