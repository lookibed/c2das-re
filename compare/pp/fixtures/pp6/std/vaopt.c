/* __VA_OPT__ (C23, GNU) */
#define F(a, ...) f(a __VA_OPT__(,) __VA_ARGS__)
F(1) F(1,2) F(1,2,3) F(1,)
#define G(...) __VA_OPT__(x ## x) end
G() G(1)
#define H(x, ...) #__VA_OPT__(x ## x __VA_ARGS__)
H(a) H(a,b)
