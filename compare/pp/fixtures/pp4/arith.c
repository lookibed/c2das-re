#define N 10
#define TWICE(x) ((x) * 2)
#if TWICE(N) == 20 && N % 3 == 1 && -7 / 2 == -3 && -7 % 2 == -1
int division_truncates;
#endif
#if (1 << 62) * 2 < 0 && 9223372036854775807 + 1 < 0
int wraps;
#endif
#if 0x10 + 010 + 0b10 == 26 && 1ULL << 63 > 0 && ~0u == 18446744073709551615u
int literals;
#endif
#if -1 >> 63 == -1 && (-9223372036854775807 - 1) / -1 < 0
int shifts;
#endif
#if 0 && 1 / 0
int never;
#elif 1 || 1 / 0
int short_circuit;
#endif
#if (2, 3) == 3 && 1 ? 2 : 3
int comma_in_parentheses;
#endif
#if UNDEFINED == 0 && !defined UNDEFINED && defined(N) && defined N
int names;
#endif
#if 1
# if 0
int a;
# elif 2 > 3
int b;
# elif N > 5
int c;
# else
int d;
# endif
#elif 1
int e;
#endif
#if __COUNTER__ == 0 && __COUNTER__ == 1
int counted = __COUNTER__;
#endif
#if 'ab' == 0x6162 && '\377' == 255 && 'abcd' == 0x61626364 && L'\xffffffff' < 0
int chars;
#endif
