// r11: __VA_OPT__ content with #, ## and a lone comma
#define F(a,...) <__VA_OPT__(#a a##a, __VA_ARGS__)>
F(x,1,2) F(y)
#define G(X, ...) f(0 __VA_OPT__(,) __VA_ARGS__)
G(a,b,c) G(a)
