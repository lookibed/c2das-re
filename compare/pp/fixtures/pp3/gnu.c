/* GNU variadics as clang takes them under gnu17: the comma before ## __VA_ARGS__, name..., __VA_OPT__ */
#define EMPTY
#define F(...) [__VA_OPT__(x)]
F() F(EMPTY) F(a) F( )
#define G(a,...) g(a , ## __VA_ARGS__)
#define X 9
G(1) G(1,) G(1,X) G(1,EMPTY) G(1,2,3)
#define F2(...) f(0 , ## __VA_ARGS__)
F2() F2(1) F2(EMPTY)
#define H(a,args...) h(a, ##args)
H(1) H(1,2)
#define V(a, ...) v(a __VA_OPT__(,) __VA_ARGS__)
V(1) V(1,2) V(1,2,3) V(1,)
#define W(...) __VA_OPT__(x ## x) end
W() W(1)
#define S(x, ...) #__VA_OPT__(x ## x __VA_ARGS__)
S(a) S(a,b)
#define id(x) x
id(a
b c) d
#define z() Z
z() z( )
#define two(a,b) a+b
id() [two(,)]
