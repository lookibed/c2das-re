/* mutual recursion of two function-like macros */
#define a(x) b(x) c
#define b(x) a(x) d
a(1)
b(2)
