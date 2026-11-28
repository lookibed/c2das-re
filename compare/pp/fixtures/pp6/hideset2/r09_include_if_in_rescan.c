// r09: #if with a self-referential macro; defined() through a macro
#define S S + 1
#if S == 0
s_is_zero
#else
s_nonzero
#endif
#define D defined(S)
#if D
d_true
#endif
