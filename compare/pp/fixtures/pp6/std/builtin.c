/* __COUNTER__, __LINE__ across lines, defined from a macro, __FILE__, __INCLUDE_LEVEL__ */
int a = __COUNTER__, b = __COUNTER__;
#define C __COUNTER__
int c = C, d = C;
#define L __LINE__
int e = L,
    f = L;
#define LL(x) x __LINE__
int g = LL(
  1
);
#define HAS defined(FOO) && defined BAR
#define FOO
#define BAR
#if HAS
int has_both;
#endif
#undef BAR
#if HAS
int wrong;
#else
int has_not;
#endif
#if defined FOO && !defined(BAR) && (1 ? 2 : (1/0)) && -1 < 0u == 0 && (-1 >> 1) < 0 && 0x7fffffffffffffff + 0 > 0 && 'a' == 97 && '\377' < 0 == 0
int arith_ok;
#endif
#if 1 == 1L && 2u > -1 == 0 && (2 || 1/0) && !(0 && 1/0) && ~0u == 0xffffffffffffffffu
int arith2_ok;
#endif
#ifdef __INCLUDE_LEVEL__
int lvl = __INCLUDE_LEVEL__;
#endif
const char *file = __FILE__;
