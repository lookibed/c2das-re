/* The layout rules of frontend/c_layout.das, one record per case; frontend/tests/test_c_layout.das
   holds each record's numbers as clang 22 lays it out for x86_64-unknown-linux-gnu. */

enum E { E0, E1 };
typedef int int_a8 __attribute__((aligned(8)));
typedef int int_a1 __attribute__((aligned(1)));

struct Natural { char a; int b; char c; };
struct Tail { double d; char c; };
struct LongDouble { char c; long double x; };
struct Array { char c; short s[3]; };
struct Nested { char c; struct Natural n; };

struct Bits { unsigned a : 3; unsigned b : 5; unsigned c : 24; char d; };
struct Straddle { char c; int x : 30; };
struct CharBits { char a : 4; char b : 6; };
struct WideStraddle { int a : 30; long long b : 40; };
struct WideFits { int a : 20; long long b : 40; };
struct Bools { _Bool a : 1; _Bool b : 1; char c; };
struct EnumBits { enum E e : 2; char c; };

struct ZeroWidth { char a; int : 0; char b; };
struct ZeroAfterBits { char x : 3; long long : 0; char d; };
struct ZeroTail { char c; int : 0; };
struct Unnamed { char a; int : 20; };
struct UnnamedWide { char c; long long : 40; };
struct UnnamedOnly { int : 3; };

struct __attribute__((packed)) Packed { char a; int b; short c; };
struct PackedMember { char a; int b __attribute__((packed)); char c; };
struct __attribute__((packed)) PackedNested { char c; struct Natural n; };
struct __attribute__((packed)) PackedBits { char c; int x : 30; };
struct __attribute__((packed)) PackedZero { char a; int : 0; char b; };
struct __attribute__((packed)) PackedCharBits { char a : 3; char b : 7; };

struct __attribute__((aligned(16))) AlignedRecord { int a; };
struct AlignedMember { char a; int b __attribute__((aligned(8))); };
struct AlignedLower { char a; int b __attribute__((aligned(2))); };
struct __attribute__((packed)) PackedAligned { char a; int b __attribute__((aligned(2))); };
struct AlignedBits { char c; int x : 3 __attribute__((aligned(4))); };
struct TypedefAligned { char c; int_a8 x; };
struct TypedefLowered { char c; int_a1 x; };

#pragma pack(2)
struct Pack2 { char a; int b; char c; };
struct Pack2Bits { char a; int b : 20; int c; };
#pragma pack(1)
struct Pack1Aligned { char a; int b __attribute__((aligned(8))); };
struct __attribute__((aligned(8))) Pack1Record { char a; int b; };
struct Pack1Zero { char a; int : 0; char b; };
#pragma pack(2)
struct __attribute__((packed)) Pack2PackedBits { char c; int x : 20; };
struct Pack2AlignedBits { char c; int x : 3 __attribute__((aligned(4))); };
#pragma pack(4)
struct Pack4AlignedBits { char c; int x : 3 __attribute__((aligned(4))); };
#pragma pack()

union Union { char a; int b : 9; long double ld; };
union __attribute__((packed)) PackedUnion { char a; int b; };
union UnionBits { char a; int b : 9; };
union UnionUnnamed { char a; int : 9; };

struct Flexible { char c; double d[]; };
struct FlexibleChar { int n; char s[]; };
struct Empty {};
struct Anonymous { int x; union { char c; short s; }; struct { int y; } named; };
