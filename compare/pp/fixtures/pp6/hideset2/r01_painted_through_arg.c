// r01: a name painted inside its own expansion, passed through two argument layers and rescanned later, stays unexpanded
#define g(x) x
#define f(x) g(x)
#define h f(h)
h;
#define k(x) x
#define self k(self) self
self;
