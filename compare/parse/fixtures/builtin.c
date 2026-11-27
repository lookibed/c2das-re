/* library functions clang knows as builtins: a redeclaration takes clang's own type (malloc's
   `__size_t`), a difference the oracle names; printf's agrees, and the declaration after them is
   compared as usual */
typedef unsigned long size_t;
void *malloc(size_t);
int printf(const char *, ...);
int after;
