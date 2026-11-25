/* <stdint.h> of the own libc header set (frontend/include/ARCHITECTURE.md). */
#ifndef _STDINT_H
#define _STDINT_H

typedef signed char int8_t;
typedef short int16_t;
typedef int int32_t;
typedef __INT64_TYPE__ int64_t;
typedef unsigned char uint8_t;
typedef unsigned short uint16_t;
typedef unsigned int uint32_t;
typedef unsigned __INT64_TYPE__ uint64_t;

typedef signed char int_least8_t;
typedef short int_least16_t;
typedef int int_least32_t;
typedef __INT64_TYPE__ int_least64_t;
typedef unsigned char uint_least8_t;
typedef unsigned short uint_least16_t;
typedef unsigned int uint_least32_t;
typedef unsigned __INT64_TYPE__ uint_least64_t;

typedef signed char int_fast8_t;
typedef __INT64_TYPE__ int_fast64_t;
typedef unsigned char uint_fast8_t;
typedef unsigned __INT64_TYPE__ uint_fast64_t;

typedef __INT64_TYPE__ intptr_t;
typedef unsigned __INT64_TYPE__ uintptr_t;
typedef __INT64_TYPE__ intmax_t;
typedef unsigned __INT64_TYPE__ uintmax_t;

#if __LONG_MAX__ > 2147483647L
typedef long int_fast16_t;
typedef long int_fast32_t;
typedef unsigned long uint_fast16_t;
typedef unsigned long uint_fast32_t;
#define INT_FAST16_MIN (-9223372036854775807L-1)
#define INT_FAST32_MIN (-9223372036854775807L-1)
#define INT_FAST16_MAX (9223372036854775807L)
#define INT_FAST32_MAX (9223372036854775807L)
#define UINT_FAST16_MAX (18446744073709551615UL)
#define UINT_FAST32_MAX (18446744073709551615UL)
#define INT64_C(c) c ## L
#define UINT64_C(c) c ## UL
#define INTMAX_C(c) c ## L
#define UINTMAX_C(c) c ## UL
#else
typedef short int_fast16_t;
typedef int int_fast32_t;
typedef unsigned short uint_fast16_t;
typedef unsigned int uint_fast32_t;
#define INT_FAST16_MIN (-32767-1)
#define INT_FAST32_MIN (-2147483647-1)
#define INT_FAST16_MAX (32767)
#define INT_FAST32_MAX (2147483647)
#define UINT_FAST16_MAX (65535)
#define UINT_FAST32_MAX (4294967295U)
#define INT64_C(c) c ## LL
#define UINT64_C(c) c ## ULL
#define INTMAX_C(c) c ## LL
#define UINTMAX_C(c) c ## ULL
#endif

#define INT8_C(c) c
#define INT16_C(c) c
#define INT32_C(c) c
#define UINT8_C(c) c
#define UINT16_C(c) c
#define UINT32_C(c) c ## U

#define INT8_MIN (-128)
#define INT16_MIN (-32767-1)
#define INT32_MIN (-2147483647-1)
#define INT64_MIN (-INT64_C(9223372036854775807)-1)
#define INT8_MAX (127)
#define INT16_MAX (32767)
#define INT32_MAX (2147483647)
#define INT64_MAX (INT64_C(9223372036854775807))
#define UINT8_MAX (255)
#define UINT16_MAX (65535)
#define UINT32_MAX (4294967295U)
#define UINT64_MAX (UINT64_C(18446744073709551615))

#define INT_LEAST8_MIN (-128)
#define INT_LEAST16_MIN (-32767-1)
#define INT_LEAST32_MIN (-2147483647-1)
#define INT_LEAST64_MIN (-INT64_C(9223372036854775807)-1)
#define INT_LEAST8_MAX (127)
#define INT_LEAST16_MAX (32767)
#define INT_LEAST32_MAX (2147483647)
#define INT_LEAST64_MAX (INT64_C(9223372036854775807))
#define UINT_LEAST8_MAX (255)
#define UINT_LEAST16_MAX (65535)
#define UINT_LEAST32_MAX (4294967295U)
#define UINT_LEAST64_MAX (UINT64_C(18446744073709551615))

#define INT_FAST8_MIN (-128)
#define INT_FAST64_MIN (-INT64_C(9223372036854775807)-1)
#define INT_FAST8_MAX (127)
#define INT_FAST64_MAX (INT64_C(9223372036854775807))
#define UINT_FAST8_MAX (255)
#define UINT_FAST64_MAX (UINT64_C(18446744073709551615))

#define INTPTR_MIN (-INT64_C(9223372036854775807)-1)
#define INTPTR_MAX (INT64_C(9223372036854775807))
#define UINTPTR_MAX (UINT64_C(18446744073709551615))
#define INTMAX_MIN (-INT64_C(9223372036854775807)-1)
#define INTMAX_MAX (INT64_C(9223372036854775807))
#define UINTMAX_MAX (UINT64_C(18446744073709551615))
#define PTRDIFF_MIN (-INT64_C(9223372036854775807)-1)
#define PTRDIFF_MAX (INT64_C(9223372036854775807))
#define SIZE_MAX (UINT64_C(18446744073709551615))
#define SIG_ATOMIC_MIN (-2147483647-1)
#define SIG_ATOMIC_MAX (2147483647)

#endif
