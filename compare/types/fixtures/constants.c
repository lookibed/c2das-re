/* the constant forms: offsetof, alignments, type traits and __builtin_constant_p answers the pinned clang gives; all four agree */
#include <stddef.h>
struct S { char c; int i; double d; };
typedef struct { short s; long l; } T;
int arr4[offsetof(struct S, d)];
unsigned long og = offsetof(T, l) + _Alignof(struct S) + __alignof__(double) + __builtin_types_compatible_p(int, const int);
const int ci = 3;
static const double cd = 2.0;
int g;
int arr[4];
struct P { int a; } ps;
int f(void);
int t3(void) { return __builtin_constant_p(0 && g); }
int t4(void) { return __builtin_constant_p(1 || g); }
int t5(void) { return __builtin_constant_p(g * 0); }
int t6(void) { return __builtin_constant_p(1.5 * 2.0); }
int t7(void) { return __builtin_constant_p(0.0 / 0.0); }
int t8(void) { return __builtin_constant_p(1.0 / 0.0); }
int t9(void) { return __builtin_constant_p("hi"); }
int t10(void) { return __builtin_constant_p("hi"[1]); }
int t11(void) { return __builtin_constant_p(&g); }
int t12(void) { return __builtin_constant_p((void *)0); }
int t13(void) { return __builtin_constant_p((int *)4); }
int t14(void) { return __builtin_constant_p(arr); }
int t15(void) { return __builtin_constant_p(ps); }
int t16(void) { return __builtin_constant_p(sizeof g); }
int t17(void) { return __builtin_constant_p(g ? 1 : 1); }
int t18(void) { return __builtin_constant_p(1 ? 2 : g); }
int t20(void) { return __builtin_constant_p(2147483647 + 1); }
int t21(void) { return __builtin_constant_p(1 / 0); }
int t22(void) { return __builtin_constant_p(1 << 40); }
int t23(void) { return __builtin_constant_p(-1 << 2); }
int t24(void) { return __builtin_constant_p((char)300); }
int t25(void) { return __builtin_constant_p(f); }
int t26(void) { return __builtin_constant_p(1.0f); }
int t27(void) { return __builtin_constant_p((int)2.5); }
int t28(void) { return __builtin_constant_p(-2147483647 - 1 / -1); }
int t29(void) { return __builtin_constant_p((-2147483647 - 1) / -1); }
int t30(void) { return __builtin_constant_p(1u << 31 << 1); }
int t32(void) { return __builtin_constant_p(arr[1]); }
int t33(void) { return __builtin_constant_p(g = 1); }
int t34(void) { return __builtin_constant_p(1 < 2.0); }
int t35(void) { return __builtin_constant_p((_Bool)0.5); }
int main(void) { return t3() + t4() + t5(); }
