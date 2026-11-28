/* Prosser-style recursion and hide sets */
#define f(a) a*g
#define g(a) f(a)
f(2)(9)
#define AA BB
#define BB AA
AA BB
#define foo() bar
#define bar() foo
foo()()()()
#define obj(x) x obj
#define call(m) m(1)
call(obj) obj(2) (3)
#define NIL(xxx) xxx
#define G_0(arg) NIL(G_1)(arg)
#define G_1(arg) NIL(arg)
G_0(42)
#define EMPTY
#define DEFER(id) id EMPTY
#define EXPAND(...) __VA_ARGS__
#define A() 123
A EMPTY ()
DEFER(A)()
EXPAND(DEFER(A)())
#define h(x) x h
#define k(x) h(x)(k)
k(1)(2)
#define LEFT (
#define APPLY(m, x) m LEFT x )
APPLY(h, 5) EXPAND(APPLY(h, 5))
