/* <stddef.h> of the own libc header set (frontend/include/ARCHITECTURE.md). */
#ifndef _STDDEF_H
#define _STDDEF_H

typedef __SIZE_TYPE__ size_t;
typedef __PTRDIFF_TYPE__ ptrdiff_t;
typedef __WCHAR_TYPE__ wchar_t;

#define NULL ((void*)0)
#define offsetof(t, d) __builtin_offsetof(t, d)

#endif
