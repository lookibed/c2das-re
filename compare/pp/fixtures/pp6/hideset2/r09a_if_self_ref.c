// r09a: #if with a self-referential object-like macro (S stays painted, then counts as 0)
#define S S + 1
#if S == 0
s_is_zero
#else
s_nonzero
#endif
