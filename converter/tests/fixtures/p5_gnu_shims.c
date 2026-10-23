/* The GNU extensions a run never observes and the builtins with a direct meaning: the dropped
   attributes, the asm barriers, the shim list and clang's answer to __builtin_constant_p (P5.1c,
   the skip audit). */
#include <stdio.h>
#include <stddef.h>
#include <limits.h>
#include "p5_gnu_shims.h"

typedef int alias_int __attribute__((may_alias));

/* mode: clang gives the declaration the type the mode names */
typedef int DI __attribute__((mode(DI)));
typedef unsigned int UQI __attribute__((mode(QI)));
typedef int SI __attribute__((mode(SI)));
struct moded {
    DI big;
    UQI small;
};
UQI moded_global __attribute__((mode(QI))) = 44;

static int twice(int x) __attribute__((noinline, const));
static int twice(int x) { return 2 * x; }

int counter __attribute__((weak, used)) = 5;
extern int weak_init __attribute__((weak)) = 3;
__attribute__((weak)) int weak_fn(void) { return 4; }

__attribute__((noreturn, cold)) static void stop(void) { __builtin_trap(); }
_Noreturn static void stop_c11(void) { __builtin_trap(); }
[[noreturn]] static void stop_c23(void) { __builtin_trap(); }

static int __attribute__((pure, warn_unused_result, nonnull)) first(const int *p) { return p[0]; }
static inline int __attribute__((always_inline, hot, nothrow, leaf)) hinted(int x) { return x + 1; }
static int __attribute__((deprecated, no_instrument_function, nodebug, unused)) quiet(int x) { return x - 1; }
static void *__attribute__((alloc_size(1), returns_nonnull, malloc)) grab(size_t n) { static char pool[64]; return n < sizeof pool ? pool : pool; }
static int __attribute__((format(printf, 1, 2), section(".text.shims"), visibility("hidden"))) say(const char *fmt, ...) { return fmt[0]; }
static inline __attribute__((gnu_inline)) int gnu_twice(int x) { return 2 * x; }

#define BARRIER __asm__ __volatile__("" : : : "memory")
#define TEMPLATED(s) __asm__ volatile(s ::: "memory")

static int bit_counts(void) {
    unsigned u = 0x00F0u;
    unsigned long lu = 0x0F00ul;
    unsigned long long w = 0x8000000000000000ull;
    printf("ffs %d %d %d %d\n", __builtin_ffs(0), __builtin_ffs(12), __builtin_ffsl(0l), __builtin_ffsll(1ll << 40));
    printf("ctz %d %d %d clz %d %d %d\n", __builtin_ctz(u), __builtin_ctzl(lu), __builtin_ctzll(w), __builtin_clz(u), __builtin_clzl(lu), __builtin_clzll(1ull));
    printf("popcount %d %d %d parity %d %d %d\n", __builtin_popcount(u), __builtin_popcountl(lu), __builtin_popcountll(w - 1), __builtin_parity(7u), __builtin_parityl(lu), __builtin_parityll(3ull));
    printf("clrsb %d %d %d %d %d\n", __builtin_clrsb(0), __builtin_clrsb(-1), __builtin_clrsb(1), __builtin_clrsbl(-2l), __builtin_clrsbll(LLONG_MAX));
    printf("bswap %x %x %llx\n", __builtin_bswap16(0x1234), __builtin_bswap32(0x12345678u), (unsigned long long)__builtin_bswap64(0x0102030405060708ull));
    return 0;
}

int glob = 3;
static const int kc = 5;
enum { E1 = 3 };
struct pair {
    int a;
    int b;
};
static int calls;
static int called(void) { calls++; return 4; }

/* clang's -O0 answer, which GCC's differs from on a const local and on `(1, 2)` */
static void constant_p(int x) {
    const int lc = 9;
    double d = 1.5;
    int i = 0;
    printf("constant_p %d %d %d %d %d %d %d %d %d %d\n", __builtin_constant_p(5), __builtin_constant_p(-5), __builtin_constant_p(1.5), __builtin_constant_p(E1), __builtin_constant_p(sizeof(int)), __builtin_constant_p(sizeof x), __builtin_constant_p(_Alignof(double)), __builtin_constant_p(offsetof(struct pair, b)), __builtin_constant_p(1 ? 2 : 3), __builtin_constant_p(!0));
    printf("constant_p %d %d %d %d %d %d %d %d %d %d\n", __builtin_constant_p("hi"), __builtin_constant_p((1234 + 45) & ~7), __builtin_constant_p(1 ? 2 : x), __builtin_constant_p(0 && x), __builtin_constant_p(1 || x), __builtin_constant_p(1 / 0), __builtin_constant_p(kc), __builtin_constant_p(lc), __builtin_constant_p(&glob), __builtin_constant_p("hi" + 1));
    printf("constant_p %d %d %d %d %d %d %d %d %d %d\n", __builtin_constant_p((void *)0), __builtin_constant_p((int)d), __builtin_constant_p(1.0 / 3), __builtin_constant_p(x * 0), __builtin_constant_p((1, 2)), __builtin_constant_p(-2147483647 - 1 - 1 > 0), __builtin_constant_p(1 << 40), __builtin_constant_p("hi"[0]), __builtin_constant_p(called), __builtin_constant_p(__builtin_constant_p(i++)));
    printf("constant_p %d %d %d %d %d %d i=%d calls=%d\n", __builtin_constant_p(x), __builtin_constant_p(called()), __builtin_constant_p(i++), __builtin_constant_p(&glob == 0), __builtin_constant_p(x ? 1 : 1), __builtin_constant_p(__builtin_choose_expr(1, 5, x)), i, calls);
}

int main(void) {
    alias_int a = 21;
    int arr[2] = {7, 8};
    int i = 0;
    struct moded m = {1ll << 40, 255};
    SI neg = -1;
    int narrow __attribute__((mode(HI))) = 70000;
    asm("");
    asm volatile("" ::: "memory");
    __asm__ __volatile__("" "" ::: "memory", "cc");
    BARRIER;
    TEMPLATED("");
    header_barrier();
    m.small++;
    printf("mode %d %d %d %d %lld %d %d %d %d\n", (int)sizeof(DI), (int)sizeof(UQI), (int)sizeof(SI), (int)sizeof(struct moded), (long long)m.big, m.small, neg, narrow, moded_global);
    __builtin_prefetch(&arr[i++]);
    __builtin_prefetch(&arr[0], 1, 3);
    printf("%d %d %d %d %d %d\n", twice(a), counter, first(arr), i, weak_init, weak_fn());
    printf("%d %d %d %d %d\n", hinted(1), quiet(1), grab(4) != NULL, say("x"), gnu_twice(3));
    switch (i) {
    case 1:
        i += 10;
        __attribute__((fallthrough));
    case 2:
        i += 100;
        [[fallthrough]];
    default:
        i += 1000;
    }
    printf("fallthrough %d\n", i);
    constant_p(i);
    printf("signbit %d %d %d %d\n", __builtin_signbit(-0.0) != 0, __builtin_signbit(1.5) != 0, __builtin_signbit(-2.0f) != 0, __builtin_signbitf(-1.0f) != 0);
    bit_counts();
    if (i > 5000) {
        __builtin_unreachable();
    }
    if (counter != 5) {
        stop();
    }
    if (counter == 6) {
        stop_c11();
    }
    if (counter == 7) {
        stop_c23();
    }
    return 0;
}
