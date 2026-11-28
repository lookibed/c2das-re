// r04: a macro undefined and redefined inside the arguments of a call of itself (gcc: the call uses the old definition)
#define f(x) <x>
f(1
#undef f
#define f 2
f)
f
