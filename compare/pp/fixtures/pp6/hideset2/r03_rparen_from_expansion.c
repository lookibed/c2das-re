// r03: the macro's ')' comes from another expansion; which macros stay disabled during the rescan
#define f(a) a h
#define h g(f
#define g(x) [x]
#define call f(1)
call );
#define R )
#define id(x) x
#define open id(id
open(2)) R;
