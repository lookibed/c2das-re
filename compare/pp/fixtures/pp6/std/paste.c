/* # and ## edge cases */
#define STR(x) #x
#define XSTR(x) STR(x)
#define CAT(a,b) a##b
#define XCAT(a,b) CAT(a,b)
STR( a   +   b ) STR("q\n" 'c' "\\") STR(/* c */ x /* d */ y) STR() STR(a\b)
CAT(,) CAT(a,) CAT(,b) CAT(1,2) CAT(x,1) CAT(+,+) CAT(<,<=) CAT(.,.) CAT(1.,e5) CAT(0x,1F) CAT(L,"s") CAT(L,'c')
XCAT(CAT(a,b),CAT(c,d)) CAT(CAT(a,b),c)
#define HASH_HASH # ## #
#define MKSTR(a) # a
#define IN_BETWEEN(a) MKSTR(a)
#define JOIN(c, d) IN_BETWEEN(c HASH_HASH d)
JOIN(x, y)
#define E
#define P(a,b) a ## E ## b
P(1,2) P(,) 
#define VA(a,...) a ## __VA_ARGS__
VA(x) VA(x,) VA(x,1,2) VA(,1)
#define GVA(fmt, args...) f(fmt, ## args)
GVA("a") GVA("a", 1) GVA("a", 1, 2)
#define CVA(fmt, ...) f(fmt, ## __VA_ARGS__)
CVA("a") CVA("a", 1)
