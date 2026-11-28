// r02: a function-like name at the end of an expansion, '(' from the source after the expansion ended
#define f(x) x+g
#define g(x) [x] f
f(1)(2)(3);
#define m(x) x m
m(1)(2);
#define obj fn
#define fn(x) <x obj>
obj(1)(2);
