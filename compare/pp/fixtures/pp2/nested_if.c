/* nested conditionals: skipped groups hold directives that only nest */
#if 0
#if 1
int no1;
#else
int no2;
#endif
#define HIDDEN 1
#error never seen
#bogus directive in a skipped group
#elif 1
int yes1;
#ifdef HIDDEN
int no3;
#elif 0
int no4;
#else
int yes2;
#endif
#elif 1
int no5;
#else
int no6;
#endif
#ifdef __linux__
int linux_side;
#endif
#ifndef __clang__
int not_clang;
#endif
int end_of_nested;
