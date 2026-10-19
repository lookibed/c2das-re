#include <stdio.h>
#include <stdint.h>
/* csmith's safe shift wrappers: C promotes a shift's count apart from its left side */
static int8_t safe_lshift_s8(int8_t left, unsigned int right) {
    return ((left < 0) || (right >= 32) || (left > (INT8_MAX >> right))) ? left : (left << right);
}
static int16_t safe_rshift_s16(int16_t left, unsigned int right) {
    return ((left < 0) || (right >= 32)) ? left : (left >> right);
}
static int64_t wide(int64_t v, int n) { return (v << n) >> (n / 2); }
static uint64_t narrow_count(uint64_t v, uint8_t n) { return v >> n; }
int main(void) {
    int a = 1000;
    long long b = 3;
    unsigned u = 7;
    int16_t s = -3;
    a <<= b;
    u >>= (char) 1;
    b <<= u;
    b >>= 1;
    printf("%d %d %d\n", safe_lshift_s8(5, 3u), safe_lshift_s8(100, 2u), safe_rshift_s16(300, 4u));
    printf("%lld %llu %d %u %lld %d\n", (long long) wide(-12345, 5) + (b << 2), (unsigned long long) narrow_count(0xFFFFFFFFFFFFull, 9), a, u, b, s << (uint8_t) 2);
    return 0;
}
