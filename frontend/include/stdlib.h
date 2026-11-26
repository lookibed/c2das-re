/* <stdlib.h> of the own libc header set (frontend/include/ARCHITECTURE.md). */
#ifndef _STDLIB_H
#define _STDLIB_H

#include <stddef.h>
#include <alloca.h>

#define EXIT_FAILURE 1
#define EXIT_SUCCESS 0
#define RAND_MAX 2147483647

typedef int (*__compar_fn_t)(const void *, const void *);

double atof(const char *);
int atoi(const char *);
long atol(const char *);
double strtod(const char *, char **);
long strtol(const char *, char **, int);
unsigned long strtoul(const char *, char **, int);
long long strtoll(const char *, char **, int);
unsigned long long strtoull(const char *, char **, int);
int rand(void);
void srand(unsigned int);
void *malloc(size_t);
void *calloc(size_t, size_t);
void *realloc(void *, size_t);
void free(void *);
void abort(void);
void exit(int);
char *getenv(const char *);
int system(const char *);
void *bsearch(const void *, const void *, size_t, size_t, __compar_fn_t);
void qsort(void *, size_t, size_t, __compar_fn_t);
int abs(int);
long long llabs(long long);

#endif
