/* The msvc layout rules of frontend/c_layout.das that rules.c does not show, one record per case;
   frontend/tests/test_c_layout.das holds each record's numbers as clang 22 lays it out for
   x86_64-pc-windows-msvc. __declspec needs the msvc triple, so this file is read under it alone. */

typedef int int_a8 __attribute__((aligned(8)));
typedef int int_a1 __attribute__((aligned(1)));
typedef int int_a2 __attribute__((aligned(2)));
typedef double double_a2 __attribute__((aligned(2)));

struct MixedSizes { char a : 3; int b : 5; char c : 2; };
struct SameSizeRun { int a : 3; unsigned b : 5; };
struct NoFit { int a : 30; int b : 5; };
struct UnnamedAligns { char c; int : 3; };
struct ZeroAfterPlain { char c; int : 0; char d; };
struct ZeroAfterBits { char a : 3; long long : 0; char d; };
struct ZeroTwice { char a : 3; int : 0; long long : 0; char d; };
struct OnlyZero { int : 0; };
union UnionBitsAlign { char a; int b : 9; };
union UnionZero { char a : 3; long long : 0; };

struct __declspec(align(16)) Declspec { int a; };
struct DeclspecMember { char c; __declspec(align(8)) int x; };
#pragma pack(1)
struct RequiredRecord { char c; struct Declspec d; };
struct RequiredTypedef { char c; int_a8 x; };
struct __attribute__((aligned(8))) RequiredRounding { char a; int b; };
struct HoldsRequired { char c; struct DeclspecMember m; };
#pragma pack()
struct Outer { char c; struct HoldsRequired h; };
#pragma pack(16)
struct Pack16 { char c; double d; };
#pragma pack()

struct __attribute__((packed)) PackedRequired { char a; int b __attribute__((aligned(4))); };
struct AlignedBits { char c; int x : 3 __attribute__((aligned(8))); };
struct __attribute__((packed)) PackedBits { char c; int x : 3; short y : 4; };

struct TypedefKeepsType { char c; int_a1 x; };
struct TypedefKeepsDouble { char c; double_a2 x; };
struct TypedefArray { char c; int_a1 x[2]; };
struct TypedefBits { char c; int_a1 x : 3; };
#pragma pack(1)
struct TypedefUnderPack { char c; int_a2 x; };
#pragma pack()
