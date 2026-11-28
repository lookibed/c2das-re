/* C11 6.10.3.4p4 EXAMPLE: whether the nested f is replaced is unspecified; clang and gcc agree */
#define f(a) a*g
#define g(a) f(a)
f(2)(9)
