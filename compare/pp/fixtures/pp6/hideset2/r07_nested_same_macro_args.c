// r07: nested invocations of one function-like macro, its own name inside its argument and through another macro
#define f(x) (x + f(x))
f(f(1));
#define g(x) h(x)
#define h(x) g(x) x
g(g(2));
#define p(x) x
p(p)(3);
