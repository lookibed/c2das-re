/* named causes explain only the type they name: a library builtin's redeclaration (clang's own
   type, `__size_t` and `restrict`), a redeclaration merged with the declaration before it; the
   names, places and every line after them are compared as usual */
typedef unsigned long size_t;
void *memcpy(void *, const void *, size_t);
int m(void);
int m() { return 0; }
int f(int a);
int f(int a);
int after;
