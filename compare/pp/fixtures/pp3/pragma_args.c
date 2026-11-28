/* _Pragma's operand is macro-expanded; in an argument it is done at the rescan, at its place */
#define STRINGIFY(a) #a
#define DIAG(x) _Pragma(STRINGIFY(GCC diagnostic x))
#define S "pack(1)"
#define WRAP(x) x
#define TWICE(x) x x
DIAG(push) int y1;
WRAP(struct A { char c; int i; }; _Pragma("pack(2)") struct B { char c; int i; };)
TWICE(_Pragma("pack(4)") int a;) int w;
WRAP(int b _Pragma(S) ;) int c;
_Pragma("pack()")
#if _Pragma("weak w2") 1
int in_if;
#endif

/* a disabled macro's name read in a call's arguments stays painted */
#define k(x) x
#define kk k(kk
#define m(a) k(m(a)
int kk 1);
int m(1));

/* a directive line between a function-like name and ( ends the lookahead */
#define g(x) [x]
int g
#define Q
(2);

/* __VA_OPT__ in a macro that is not variadic is empty; # drops a final unescaped backslash */
#define V(x) [__VA_OPT__(x) x]
#define W(x) #__VA_OPT__(x) x
int V(1) W(2);
#define q(x) #x
const char *bs = q(\);

