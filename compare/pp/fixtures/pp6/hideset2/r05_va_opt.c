// r05: __VA_OPT__ around a self call, and a painted name inside __VA_OPT__
#define F(a, ...) a __VA_OPT__(F(a))
F(1, 2);
F(3);
#define G(...) __VA_OPT__(G)(__VA_ARGS__)
G(x)(y);
