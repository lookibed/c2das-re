/* The GNU extensions a run never observes and the builtins with a direct meaning: the dropped
   attributes, the asm barriers and the shim list (P5.1c, the skip audit). */
#include <stdio.h>

typedef int alias_int __attribute__((may_alias));

static int twice(int x) __attribute__((noinline, const));
static int twice(int x) { return 2 * x; }

int counter __attribute__((weak, used)) = 5;

__attribute__((noreturn, cold)) static void stop(void) { __builtin_trap(); }

static int __attribute__((pure, warn_unused_result, nonnull)) first(const int *p) { return p[0]; }

#define BARRIER __asm__ __volatile__("" : : : "memory")

static int bit_counts(void) {
    unsigned u = 0x00F0u;
    unsigned long long w = 0x8000000000000000ull;
    printf("ffs %d %d %d\n", __builtin_ffs(0), __builtin_ffs(12), __builtin_ffsll(1ll << 40));
    printf("ctz %d %d clz %d %d\n", __builtin_ctz(u), __builtin_ctzll(w), __builtin_clz(u), __builtin_clzll(1ull));
    printf("popcount %d %d parity %d %d\n", __builtin_popcount(u), __builtin_popcountll(w - 1), __builtin_parity(7u), __builtin_parityll(3ull));
    printf("clrsb %d %d %d\n", __builtin_clrsb(0), __builtin_clrsb(-1), __builtin_clrsb(1));
    printf("bswap %x %x %llx\n", __builtin_bswap16(0x1234), __builtin_bswap32(0x12345678u), (unsigned long long)__builtin_bswap64(0x0102030405060708ull));
    return 0;
}

int main(void) {
    alias_int a = 21;
    int arr[2] = {7, 8};
    int i = 0;
    asm("");
    asm volatile("" ::: "memory");
    BARRIER;
    __builtin_prefetch(&arr[i++]);
    __builtin_prefetch(&arr[0], 1, 3);
    printf("%d %d %d %d\n", twice(a), counter, first(arr), i);
    printf("constant_p %d %d %d %d %d\n", __builtin_constant_p(5), __builtin_constant_p(i), __builtin_constant_p("hi"), __builtin_constant_p((1234 + 45) & ~7), __builtin_constant_p(&arr[0]));
    printf("signbit %d %d %d\n", __builtin_signbit(-0.0) != 0, __builtin_signbit(1.5) != 0, __builtin_signbit(-2.0f) != 0);
    bit_counts();
    if (i > 5) {
        __builtin_unreachable();
    }
    if (counter != 5) {
        stop();
    }
    return 0;
}
