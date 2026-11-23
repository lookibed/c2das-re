/* GNU keywords (P7.6): `__alignof__` is clang's value, `typeof` the type clang resolves,
   `__extension__` its operand. */
#include <stdio.h>
void func(void) __attribute__((aligned(256)));
void func(void) {}
struct S { char c; double d; };
typedef int aligned16 __attribute__((aligned(16)));
#define BOTH(a, b) (__alignof__(a) + __alignof__(b))
#define SWAP(a, b) do { __typeof__(a) _t = (a); (a) = (b); (b) = _t; } while (0)
#define WIDE(x) (__extension__ (long long) (x))
__extension__ typedef long long wide_t;
__extension__ static long long big = 1LL << 40;
static typeof(big) twice(typeof(int) n) {
    typeof(n * 2LL) r = n;
    return r * 2;
}
int main(void) {
    char c = 'x';
    struct S s = { 'a', 1.5 };
    int arr[3] = { 1, 2, 3 };
    printf("%d %d %d %d\n", (int)__alignof__(char), (int)__alignof__(double), (int)__alignof(struct S), (int)__alignof__(long long));
    printf("%d %d %d\n", (int)__alignof__(c), (int)__alignof__(s), (int)__alignof__(arr));
    printf("%d %d %d\n", (int)__alignof__(func), (int)__alignof__(aligned16), (int)__alignof__(int[4]));
    printf("%d\n", (int)BOTH(int, double));
    typeof(s) s2 = { 'b', 2.5 };
    __typeof__(arr[0]) *p = &arr[1];
    SWAP(s, s2);
    SWAP(arr[0], arr[2]);
    wide_t w = WIDE(arr[0]) * big;
    printf("%c %g %d %d %d %lld %lld\n", s.c, s.d, *p, arr[0], arr[2], w, twice(21));
    return __extension__ 0;
}
