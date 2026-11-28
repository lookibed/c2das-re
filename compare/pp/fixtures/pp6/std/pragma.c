/* #pragma kept, _Pragma, #pragma in a macro, STDC pragmas, #line, #, #ident, null directive */
#pragma pack(push, 1)
struct S { char c; int i; };
#pragma pack(pop)
_Pragma("omp parallel for")
#define DO_PRAGMA(x) _Pragma(#x)
DO_PRAGMA(message("hello")) int after_pragma;
#pragma STDC FP_CONTRACT ON
#
#line 100
int l100 = __LINE__;
#line 200 "renamed.c"
int l200 = __LINE__; const char *f = __FILE__;
#define LN 300
#line LN
int l300 = __LINE__;
# 400 "gnu.c"
int l400 = __LINE__;
