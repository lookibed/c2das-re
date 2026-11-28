// r09b: defined() produced by a macro expansion in #if (undefined behaviour; gcc and clang evaluate it)
#define S 1
#define D defined(S)
#if D
d_true
#endif
